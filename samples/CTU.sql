USE [CEC_Custom]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- ==========================================================================================
-- Author:       Jagadeesh
-- Create date:  8/23/2026
-- Description:  ProcessPotentialGroupForStudents (CTU ONLINE - AD Early Student Attrition Cancel)
-- Modification Details:
-- Date         Modified By   UserStory  Description
---------------------------------------------------------------
-- 8/23/2026         #333064:   Initial Version
-- 2026-10-15:  CTU evaluation-day, LDA window, reassignment guard, and removal filtering update
--              (aligned to AIU logic). Verify deployment in INT/UAT before PROD.
-- 2026-10-28: Separate exact-day removal parameter; cache student/reporting fields.
-- ==========================================================================================
CREATE OR ALTER PROCEDURE [svcs].[ProcessPotentialGroupForStudents]
(
      @SyCampusID    AS INT = 6
    , @DateAddedDays INT    = 7  -- Calendar Day 8 evaluation (term start = Day 1)
    , @LDADate       INT    = 6  -- Number of eligible LDA calendar days, inclusive of term start
    , @GroupRemovalDaysAfterTermStart INT = 7 -- Removal on calendar Day 7    -- 
)
AS
BEGIN
    SET NOCOUNT ON;
    SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

    DECLARE @ProcessDate DATETIME = GETDATE();
    DECLARE @PotentialGroupID INT = 24058;  -- CTU ONLINE - AD Early Student Attrition Cancel

    -- Capture campus/student reporting fields once for both processing paths.
    SELECT ST.SyStudentID, ST.SyCampusID, ST.LastName, ST.FirstName,
           SC.Descrip AS CampusName
    INTO #CampusStudents
    FROM C2000.dbo.SyStudent ST WITH (NOLOCK)
    LEFT JOIN C2000.dbo.SyCampus SC WITH (NOLOCK)
        ON SC.SyCampusID = ST.SyCampusID
    WHERE ST.SyCampusID = @SyCampusID;

    CREATE UNIQUE CLUSTERED INDEX IX_CampusStudents_StudentID
        ON #CampusStudents (SyStudentID);

    -- One lookup for the configured group's reporting label.
    SELECT SG.SyGroupsID, SG.Descrip AS GroupName
    INTO #GroupDetails
    FROM C2000.dbo.SyGroups SG WITH (NOLOCK)
    WHERE SG.SyGroupsID = @PotentialGroupID;

    -- Shared current-term lookup for assignment and removal.
    SELECT CT.AdTermID, CT.StartDate, CT.EndDate
    INTO #CurrentTerms
    FROM C2000.dbo.AdTerm CT WITH (NOLOCK)
    WHERE CT.EndDate >= @ProcessDate
      AND CT.StartDate <= @ProcessDate
      AND CT.Active = 1;

    CREATE CLUSTERED INDEX IX_CurrentTerms_AdTermID ON #CurrentTerms(AdTermID);

    -- Active membership snapshot used to exclude already-active students and identify removals.
    SELECT DISTINCT G.SyStudentID
    INTO #ActiveGroupStudents
    FROM C2000.dbo.syStudGrp G WITH (NOLOCK)
    WHERE G.SyGroupsID = @PotentialGroupID
      AND G.Active = 1;

    CREATE UNIQUE CLUSTERED INDEX IX_ActiveGroupStudents_StudentID
        ON #ActiveGroupStudents(SyStudentID);

    CREATE TABLE #AssignedStudents
    (
          SyStudentID       INT
        , AdEnrollID        INT
        , AdTermID          INT
        , SyCampusID        INT
        , LDA               DATETIME
        , TermStartDate     DATETIME
        , GroupID           INT
        , ProcessDateTime   DATETIME
        , CampusName        NVARCHAR(MAX)
        , ProgramName       NVARCHAR(MAX)
        , GroupName         NVARCHAR(MAX)
        , StudentLastName   NVARCHAR(MAX)
        , StudentFirstName  NVARCHAR(MAX)
    );

    CREATE TABLE #RemovedStudents
    (
          SyStudentID       INT
        , AdEnrollID        INT
        , AdTermID          INT
        , SyCampusID        INT
        , LDA               DATETIME
        , TermStartDate     DATETIME
        , SchoolStatusID    INT
        , GroupID           INT
        , ProcessDateTime   DATETIME
    );

    BEGIN TRY
        BEGIN TRANSACTION;

        -- ======================================================================
        -- ASSIGNMENT PROCESS
        -- ----------------------------------------------------------------------
        -- Eligible degree levels: Undergraduate, Graduate, Doctoral, NDS.
        -- LDA must be posted on calendar Days 1 through 6.
        -- Evaluated on calendar Day 8 (term start + 7 days, default).
        -- Previous-enrollment exclusions: Withdraw, Graduate, Dismissal,
        --   Pending Graduate, NDS Withdraw, NDS Complete.
        -- ======================================================================
        BEGIN
            ;WITH CurrentEnrollment AS
            (
                SELECT
                      E.AdEnrollID
                    , E.SyStudentID
                    , E.SySchoolStatusID
                    , E.LDA
                    , E.AdProgramVersionID
                    , ROW_NUMBER() OVER
                      (
                          PARTITION BY E.SyStudentID
                          ORDER BY T.Hierarchy, E.GradDate DESC
                      ) AS RN
                FROM C2000.dbo.AdEnroll E WITH (NOLOCK)
                INNER JOIN C2000.dbo.SySchoolStatus SSS WITH (NOLOCK)
                    ON SSS.SySchoolStatusID = E.SySchoolStatusID
                INNER JOIN C2000.dbo.SyStatus T WITH (NOLOCK)
                    ON T.SyStatusID = SSS.SyStatusID
                INNER JOIN #CampusStudents ST
                    ON ST.SyStudentID = E.SyStudentID
                WHERE ST.SyCampusID = @SyCampusID
                    AND NOT EXISTS
                    (
                        SELECT 1
                        FROM #ActiveGroupStudents AG
                        WHERE AG.SyStudentID = E.SyStudentID
                    )
            ),
            EnrollmentTerms AS -- current enrollment + current term
            (
                SELECT DISTINCT
                      CE.SyStudentID
                    , CE.AdEnrollID
                    , CE.SySchoolStatusID
                    , CE.LDA
                    , CE.AdProgramVersionID
                    , ES.AdTermID
                    , CT.StartDate AS TermStartDate
                    , CT.EndDate AS TermEndDate
                FROM CurrentEnrollment CE
                INNER JOIN C2000.dbo.AdEnrollSched ES WITH (NOLOCK) ON ES.AdEnrollID = CE.AdEnrollID
                INNER JOIN #CurrentTerms CT ON CT.AdTermID = ES.AdTermID
                WHERE CE.RN = 1
                    -- Prevent re-assignment for the same enrollment/term/group.
                    AND NOT EXISTS
                    (
                        SELECT 1
                        FROM VirtualCampus.svcs.Student_Grp_Audit GA WITH (NOLOCK)
                        WHERE GA.AdEnrollID = CE.AdEnrollID
                            AND GA.TermID = ES.AdTermID
                            AND GA.GroupID = @PotentialGroupID
                    )
            ),
            EligibleStudents AS
            (
                SELECT DISTINCT
                      ET.SyStudentID
                    , ET.AdEnrollID
                    , ET.AdTermID
                    , ST.SyCampusID
                    , ST.CampusName
                    , ST.LastName AS StudentLastName
                    , ST.FirstName AS StudentFirstName
                    , PV.Descrip AS ProgramName
                    , ET.LDA
                    , ET.TermStartDate
                    , ET.SySchoolStatusID
                FROM EnrollmentTerms ET
                INNER JOIN #CampusStudents ST ON ST.SyStudentID = ET.SyStudentID
                INNER JOIN c2000.dbo.AdProgramVersion PV WITH (NOLOCK) ON ET.AdProgramVersionID = PV.AdProgramVersionID
                INNER JOIN c2000.dbo.AdProgram AP WITH (NOLOCK) ON PV.AdProgramID = AP.AdProgramID
                INNER JOIN C2000.dbo.AdDegree AD WITH (NOLOCK) ON AD.AdDegreeID = PV.AdDegreeID
                    AND AD.Code IN ('NDS','BD','MD','DD','AD') -- CTU production degree eligibility
                WHERE ST.SyCampusID = @SyCampusID
                    AND ET.LDA IS NOT NULL
                    -- Evaluate on Day 8; LDA must land on Days 1 through 6.
                    AND DATEDIFF(DAY, ET.TermStartDate, @ProcessDate) = @DateAddedDays
                    AND DATEDIFF(DAY, ET.TermStartDate, ET.LDA) BETWEEN 0 AND @LDADate - 1
                    -- Any previous enrollment with one of these statuses excludes the student.
                    AND NOT EXISTS
                    (
                        SELECT 1
                        FROM C2000.dbo.AdEnroll PREV_E WITH (NOLOCK)
                        INNER JOIN C2000.dbo.SySchoolStatus PREV_SSS WITH (NOLOCK)
                            ON PREV_SSS.SySchoolStatusID = PREV_E.SySchoolStatusID
                        WHERE PREV_E.SyStudentID = ET.SyStudentID
                            AND PREV_E.AdEnrollID <> ET.AdEnrollID
                            AND PREV_SSS.Descrip IN
                            (
                                  'Withdraw'
                                , 'Graduate'
                                , 'Dismissal'
                                , 'Pending Graduate'
                                , 'NDS Withdraw'
                                , 'NDS Complete'
                            )
                    )
            )
            INSERT INTO #AssignedStudents
            (
                  SyStudentID
                , AdEnrollID
                , AdTermID
                , SyCampusID
                , LDA
                , TermStartDate
                , GroupID
                , ProcessDateTime
                , CampusName
                , ProgramName
                , GroupName
                , StudentLastName
                , StudentFirstName
            )
            SELECT DISTINCT
                  ES.SyStudentID
                , ES.AdEnrollID
                , ES.AdTermID
                , ES.SyCampusID
                , ES.LDA
                , ES.TermStartDate
                , @PotentialGroupID
                , @ProcessDate
                , ES.CampusName
                , ES.ProgramName
                , GD.GroupName
                , ES.StudentLastName
                , ES.StudentFirstName
            FROM EligibleStudents ES
            LEFT JOIN #GroupDetails GD
                ON GD.SyGroupsID = @PotentialGroupID;

            -- Audit reads #AssignedStudents and inserts only new audit rows.
            EXEC [VirtualCampus].[svcs].[ProcessPotentialStudentGroupAudit]
                  @ActionType = 'ASSIGN'
                , @ProcessDate = @ProcessDate
                , @ModifiedByUserID = 1;

            INSERT INTO C2000.dbo.syStudGrp
            (
                  SyStudentID
                , SyGroupsID
                , Active
                , UserIDOn
                , EffectiveDate
                , DateAdded
                , DateLstMod
                , SyCampusID
            )
            SELECT DISTINCT
                  A.SyStudentID
                , A.GroupID
                , 1                 -- Active
                , 1                 -- TBD: UserIDOn
                , @ProcessDate      -- EffectiveDate
                , @ProcessDate      -- DateAdded
                , @ProcessDate      -- DateLstMod
                , A.SyCampusID
            FROM #AssignedStudents A;
        END;

        -- ======================================================================
        -- REMOVAL PROCESS
        -- ----------------------------------------------------------------------
        -- Evaluate ONLY on term start + @GroupRemovalDaysAfterTermStart.
        -- Default 7 means calendar Day 8; later runs do not catch up.
        -- Student must already be ACTIVE in the initial membership snapshot.
        -- Remove if LDA falls EXACTLY on calendar Day 8 (default offset 7),
        -- OR current school status is
        --   Cancel, NDS Cancel, Withdraw, or NDS Withdraw.
        -- ======================================================================
        BEGIN
            ;WITH CurrentEnrollment AS
            (
                SELECT
                      E.AdEnrollID
                    , E.SyStudentID
                    , E.SySchoolStatusID
                    , ST.SyCampusID
                    , E.LDA
                    , SSS.Descrip AS StatusDescrip
                    , ROW_NUMBER() OVER
                      (
                          PARTITION BY E.SyStudentID
                          ORDER BY T.Hierarchy, E.GradDate DESC
                      ) AS RN
                FROM C2000.dbo.AdEnroll E WITH (NOLOCK)
                INNER JOIN C2000.dbo.SySchoolStatus SSS WITH (NOLOCK)
                    ON SSS.SySchoolStatusID = E.SySchoolStatusID
                INNER JOIN C2000.dbo.SyStatus T WITH (NOLOCK)
                    ON T.SyStatusID = SSS.SyStatusID
                INNER JOIN #CampusStudents ST
                    ON ST.SyStudentID = E.SyStudentID
                INNER JOIN #ActiveGroupStudents AG
                    ON AG.SyStudentID = E.SyStudentID
                WHERE ST.SyCampusID = @SyCampusID
            ),
            EnrollmentTerms AS
            (
                SELECT DISTINCT
                      CE.SyStudentID
                    , CE.AdEnrollID
                    , CE.SySchoolStatusID
                    , CE.SyCampusID
                    , CE.LDA
                    , ES.AdTermID
                    , CT.StartDate AS TermStartDate
                    , CT.EndDate AS TermEndDate
                FROM CurrentEnrollment CE
                INNER JOIN C2000.dbo.AdEnrollSched ES WITH (NOLOCK)
                    ON ES.AdEnrollID = CE.AdEnrollID
                INNER JOIN #CurrentTerms CT
                    ON CT.AdTermID = ES.AdTermID
                WHERE CE.RN = 1
                    AND DATEDIFF(DAY, CT.StartDate, @ProcessDate) = @GroupRemovalDaysAfterTermStart
                    AND
                    (
                        (
                            CE.LDA IS NOT NULL
                            AND DATEDIFF(DAY, CT.StartDate, CE.LDA) = @GroupRemovalDaysAfterTermStart
                        )
                        OR CE.StatusDescrip IN
                        (
                              'Cancel'
                            , 'NDS Cancel'
                            , 'Withdraw'
                            , 'NDS Withdraw'
                        )
                    )
            )
            INSERT INTO #RemovedStudents
            (
                  SyStudentID
                , AdEnrollID
                , AdTermID
                , SyCampusID
                , LDA
                , TermStartDate
                , SchoolStatusID
                , GroupID
                , ProcessDateTime
            )
            SELECT DISTINCT
                  ET.SyStudentID
                , ET.AdEnrollID
                , ET.AdTermID
                , ET.SyCampusID
                , ET.LDA
                , ET.TermStartDate
                , ET.SySchoolStatusID
                , @PotentialGroupID
                , @ProcessDate
            FROM EnrollmentTerms ET;

            -- Audit reads #RemovedStudents and stamps DateRemoved on matches.
            EXEC [VirtualCampus].[svcs].[ProcessPotentialStudentGroupAudit]
                  @ActionType = 'REMOVE'
                , @ProcessDate = @ProcessDate
                , @ModifiedByUserID = 1;

            UPDATE G
            SET
                  G.DateOff = @ProcessDate
                , G.Active = 0
                , G.DateLstMod = @ProcessDate
                , G.UserIDOff = 1  -- TBD: SyStaffId
            FROM C2000.dbo.syStudGrp G
            INNER JOIN #RemovedStudents R ON R.SyStudentID = G.SyStudentID
            WHERE G.SyGroupsID = @PotentialGroupID
                AND G.Active = 1;
        END;

        COMMIT TRANSACTION;

        /* Reporting fields were captured during assignment; no source-table re-joins. */
        SELECT
              'ASSIGNED' AS ActionType
            , A.SyCampusID AS CampusID
            , A.CampusName
            , A.ProgramName
            , A.GroupName
            , A.SyStudentID
            , A.StudentLastName
            , A.StudentFirstName
            , A.AdEnrollID
            , A.TermStartDate AS CurrentTermStartDate
            , A.AdTermID AS AdTermId
            , A.LDA AS LDADate
            , A.ProcessDateTime AS ProcessRunDateTime
        FROM #AssignedStudents A
        ORDER BY A.SyStudentID;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO

-- Calling-code example only; intentionally commented to avoid processing at deployment:
-- EXEC [svcs].[ProcessPotentialGroupForStudents]
--      @SyCampusID = 6,
--      @DateAddedDays = 7,
--      @LDADate = 6,
--      @GroupRemovalDaysAfterTermStart = 6;
