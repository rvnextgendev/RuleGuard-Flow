  
/*  
=======================================================================================================================================  
    Following actions are done by this procedure  
        1.  Delete the OEM_MASTER table data for this manufacturer  
        2.  Get the latest Price Effective date from the  
            Oem_Standard_Historical_Status  table  
        3.  Insert the data for the latest price-effective-date into the  
            OEM_Master table.  
        4.  Insert other the parts which are not in the OEM_Master table  
            for the latest price effective date.  
        5.  Update the D_PED table with latest PRICE_Effective date  
      
    Date        Developer           Description  
    -----------------------------------------------------------------------------------------------------------------------------------  
    11/16/2007  Rema Amirthamma     New  
    02/06/2007  STremaine           Added Functionality for an OEM Previous table  
    08/10/2017  Jim Fisher          Added filter to skip PVG processing based on the values  
                                    of @Manufacturer_Id and @Country_Id using table Filter_by_Manufacturer_and_Country  
    08/15/2017  Jim Fisher          Changed to reflect renaming OEM_Master to OEM_Master_Unfiltered  
    08/30/2017  Todd Jackson        Applied stored procedure template with standard transaction handling and error handling.  
    04/13/2018  Jim Fisher          Added call to [dbo].[USP_ApplyTechFormatToAddedParts]  
 07/09/2025  David Smith         Added processing for new GM_Patent_Trademark_Indicator column  
  
========================================================================================================================================  
EXEC [usp_Oem_Insert_Oem_Master]    
    @Manufacturer_Id = 98,   
    @Country_Id      = 40;  
  
EXEC [usp_Oem_Insert_Oem_Master]   
    @Manufacturer_Id = 1,   
    @Country_Id      = 40;  
*/  
  
CREATE PROCEDURE [dbo].[usp_Oem_Insert_Oem_Master]  
  
   @Manufacturer_Id INT,   
   @Country_Id      INT  
  
AS  
BEGIN -- PROCEDURE  
      
    ---------------------------------------------------------------------------------------------------------------------  
    BEGIN   -- Standard declare/start block (from template)  
      
        -- SQL 2000-2005 - Does not allow variable assignment during DECLARE statements.  
        DECLARE @defaultSuccessCode     INT;  
        DECLARE @checkpoint             INT;  
        DECLARE @storedProcedureName    NVARCHAR(128);  
        DECLARE @databaseName           NVARCHAR(128);  
        SET @defaultSuccessCode         = 0;  
        SET @checkpoint                 = 0;  
        SET @storedProcedureName        = OBJECT_NAME(@@PROCID);  
        SET @databaseName               = DB_NAME();  
  
        /*  
        -- SQL 2008 and above - Allows variable assignment during DECLARE statements.  
        DECLARE @defaultSuccessCode     INT = 0;  
        DECLARE @checkpoint             INT = 0;  
        DECLARE @storedProcedureName    NVARCHAR(128)   = OBJECT_NAME(@@PROCID);  
        DECLARE @databaseName           NVARCHAR(128)   = DB_NAME();  
        */  
        SET NOCOUNT ON;  
  
    END     -- Standard declare/start block (from template)  
    ---------------------------------------------------------------------------------------------------------------------  
  
  
    DECLARE @Is_Active_for_Pvg BIT;  
    SET @Is_Active_for_Pvg = CASE   
                        WHEN EXISTS(SELECT 1  
                                  FROM Filter_by_Manufacturer_and_Country  
                                  WHERE Manufacturer_Id = @Manufacturer_Id  
                                  AND Country_Id = @Country_Id  
                                  AND Export_Pvg = 1  
                                )  
                        THEN 1  
                        ELSE 0  
                        END;  
  
  
  
    --Transactions ARE needed -> because there ARE truncates, deletes, inserts, or updates  
    BEGIN TRANSACTION  
  
 BEGIN TRY  
  
        SET @checkpoint = 1;  
  
        -------------------------------------------------------------------------------------------  
        --> > > CUSTOM CODE STARTS HERE < < <----------------------------------------------------------  
        -------------------------------------------------------------------------------------------  
  
  
  
        DECLARE @ran_Successfully BIT;  
        SET @ran_Successfully = 1;  
  
        DECLARE @Price_Effective_Date NVARCHAR(20)  
        DECLARE @Two_Files VARCHAR(5)  
         
        -- DOES THE OEM USE TWO FILES  
        SELECT @Two_Files = CASE  
                                WHEN @Manufacturer_Id =  10 AND @Country_Id = 40 THEN 'TRUE'  
                                ELSE 'FALSE'  
                                END  
  
        -- =========================================================  
        -- Store Old Values  
        -- In oem-master-previous table  
        -- =========================================================  
  
  
        SET @checkpoint = 2;  
  
        DELETE FROM Oem_Master_Previous  
            WHERE Mfg_Id = @Manufacturer_Id  
            AND Country_Id = @Country_Id  
  
        INSERT INTO Oem_Master_Previous  
            (  
                    File_Id,                Revision,   
                    Mfg_Id,                 Country_Id,   
                    Ped,                    Part_Id,   
                    Orig_Part_Number,       Part_Number,   
                    Formatted_Part_Number,  Formatted_Tech_Super_Number,   
                    Orig_Super_Number,      Super_Number,   
                    Formatted_Super_Number, Formatted_Tech_Part_Number,   
                    Status_Code,  
     GM_Patent_Trademark_Indicator,  
     Approx_Flag,   
                    Core_Flag,              Part_Desc,   
                    Price,                  Price_Net_Core,      
                    Pr_Type_Id,             Notes,           Time_Inserted  
            )  
            SELECT  
                    File_Id,                Revision,   
                    Mfg_Id,                 Country_Id,   
                    Ped,                    Part_Id,   
                    Orig_Part_Number,       Part_Number,   
                    Formatted_Part_Number,  Formatted_Tech_Super_Number,   
                    Orig_Super_Number,      Super_Number,   
                    Formatted_Super_Number, Formatted_Tech_Part_Number,   
                    Status_Code,  
     GM_Patent_Trademark_Indicator,  
     Approx_Flag,   
                    Core_Flag,              Part_Desc,   
                    Price,                  Price_Net_Core,      
                    Pr_Type_Id,             Notes,           Time_Inserted  
            FROM    OEM_Master_Unfiltered Oem_Master  
            WHERE   Mfg_Id = @Manufacturer_Id  
                    AND Country_Id = @Country_Id;  
  
        -- =========================================================  
        PRINT '1.Delete the values for the manufacturer from the oem-master table'  
        -- =========================================================  
        DELETE FROM Oem_Master_Unfiltered  
            WHERE Mfg_Id = @Manufacturer_Id  
                AND Country_Id = @Country_Id  
  
        -- =========================================================  
        PRINT '2.Get the latest price effective date for the manufacturer'  
        -- =========================================================  
        SELECT @Price_Effective_Date = MAX(Ped)  
            FROM  Oem_Standard_Historical_Status  
            WHERE Mfg_Id = @Manufacturer_Id  
                AND Country_Id = @Country_Id;  
        -- =========================================================  
  
        PRINT 'MAXPARTS '  
  
        ---------------------------------------------------------------------------------------- MaxDate  
        TRUNCATE TABLE MaxParts_Temp;  
  
        IF @TWO_FILES = 'TRUE'  
        BEGIN  
  
            -- NON PACN RECORDS  
            INSERT INTO MaxParts_Temp  
              (       Part_Number, MaxDate, Category  
                )  
                SELECT  Part_Number = RTRIM(LTRIM(Part_Number)),   
                        MaxDate = MAX(Ped),   
                        Category = ''  
                FROM    Oem_Standard_Historical  
                WHERE   CAST(Price as VARCHAR(10)) <> '0000000'   
                        AND Mfg_Id = 10  
                        AND Country_Id = 40  
                GROUP BY RTRIM(LTRIM(Part_Number));  
  
            --PACN RECORDS  
            INSERT INTO MaxParts_Temp  
                (       Part_Number, MaxDate, Category  
                )  
                SELECT  Part_Number = RTRIM(LTRIM(Part_Number)),   
                        MaxDate = MAX(Ped),   
                        Category = 'PACN'  
                FROM    Oem_Standard_Historical  
                WHERE   CAST(price as VARCHAR(10)) = '0000000'   
                        AND Mfg_Id = 10  
                        AND Country_Id = 40  
                GROUP BY RTRIM(LTRIM(Part_Number));  
  
        END --IF @Two_Files = 'TRUE'  
        ELSE  
        BEGIN  
  
            INSERT INTO MaxParts_Temp  
                (       Part_Number, MaxDate, Category  
                )  
                SELECT  Part_Number = RTRIM(LTRIM(Part_Number)),   
                        MaxDate = MAX(Ped),   
                        Category = ''  
                FROM    Oem_Standard_Historical  
                GROUP BY RTRIM(LTRIM(Part_Number)), Mfg_Id, Country_Id  
                HAVING  (Mfg_Id = @Manufacturer_Id)  
                        AND (Country_Id = @Country_Id);  
  
        END --ELSE  
  
        ---------------------------------------------------------------------------------------- HISTORY  
  
        PRINT 'PVG TABLE '  
        --- PVG TABLE  
  
        TRUNCATE TABLE Pvg_Table  
  
        /*  
            Vario, Stefanie  
            1.  The "SELECT" statements similar to the following should be done outside the transaction to prevent blocking for other users while this process is running:   
                   IF EXISTS(SELECT 1 FROM Filter_by_Manufacturer_and_Country  
                                WHERE Manufacturer_Id = @Manufacturer_Id  
                                AND Country_Id = @Country_Id  
                                AND Export_PVG = 1  
                        )  
  
            2.  Same for creating the temp tables.  They should be done outside the transaction.    Processing of the temp tables should also be done outside of the transaction.      
        */  
  
        -- jpf 08/10/2017  
        -- skip if not flagged for PVG export  
        IF @Is_Active_for_Pvg = 1  
        BEGIN  
  
            INSERT INTO Pvg_Table  
            (           [File_Id], [Mfg_Id], [Country_Id], [Ped], [Revision],  
                        [Part_Description], [Price], [Core_Flag], [Price_Net_Core],   
                        [Promotion_Code], [Status], [Manuf_Code], [Flag], [Notes],  
                        [Orig_Part_Number],   
                        [Part_Number],   
                        [Tech_Number],   
                        [Orig_Super_Number],   
                        [Super_Number],  
                GM_Patent_Trademark_Indicator  
            )  
            SELECT      [File_Id], [Mfg_Id], [Country_Id], [Ped], [Revision],  
                        [Part_Description], [Price], [Core_Flag], [Price_Net_Core],   
                        [Promotion_Code], [Status], [Manuf_Code], [Flag], [Notes],  
                        [Orig_Part_Number]  = RTRIM(LTRIM([Orig_Part_Number])),   
                        [Part_Number]       = RTRIM(LTRIM(oh.[Part_Number])),   
                        [Tech_Number]       = RTRIM(LTRIM(oh.[Tech_Number])),   
                        [Orig_Super_Number] = RTRIM(LTRIM([Orig_Super_Number])),   
                        [Super_Number]      = RTRIM(LTRIM([Super_Number])),  
                GM_Patent_Trademark_Indicator  
            FROM        Oem_Standard_Historical oh  
            WHERE       Mfg_Id = @Manufacturer_Id  
                        AND Country_Id = @Country_Id  
  
        END --IF EXISTS(SELECT 1  
  
          
        PRINT 'HISTORY TEMP TABLE '  
  
        IF OBJECT_ID('tempdb..#History_Temp') IS NOT NULL  
            DROP TABLE #History_Temp  
  
        CREATE TABLE #History_Temp   
        (  
            File_Id             INT NOT NULL,   
            Mfg_Id              INT NOT NULL,   
            Country_Id          INT NOT NULL,   
            Ped                 SMALLDATETIME NOT NULL,   
            Revision            INT NOT NULL,   
            Orig_Part_Number    VARCHAR(50) NOT NULL,   
            Part_Number         VARCHAR(50) NOT NULL,   
            Tech_Number         VARCHAR(50) NULL,   
            Part_Description    VARCHAR(50) NOT NULL,   
            Price               VARCHAR(50) NOT NULL,   
            Core_Flag           VARCHAR(50) NOT NULL,   
            Price_Net_Core      VARCHAR(15) NULL,   
            Promotion_Code      VARCHAR(50) NOT NULL,   
            Status              VARCHAR(50) NOT NULL,   
            Orig_Super_Number   VARCHAR(50) NOT NULL,   
            Super_Number        VARCHAR(50) NOT NULL,   
            Manuf_Code          VARCHAR(50) NOT NULL,   
            Flag                VARCHAR(50) NULL,   
            Notes               VARCHAR(255) NULL,  
            GM_Patent_Trademark_Indicator VARCHAR(1)  
        );  
  
        BEGIN --fetch data from PVG_TABLE or from Oem_Standard_Historical if PVG_TABLE is empty  
          
            IF @Is_Active_for_Pvg = 1  
            BEGIN  
  
                -- fetch data from PVG_TABLE which is already filtered  
                INSERT INTO #History_Temp   
                (  
                        File_Id, Mfg_Id, Country_Id, Ped, Revision,   
                        Part_Description, Price, Core_Flag, Price_Net_Core,   
                        Promotion_Code, Status, Manuf_Code, Flag, Notes,   
                        Orig_Part_Number,   
                        Part_Number,   
                        Tech_Number,   
                        Orig_Super_Number,   
                        Super_Number,  
                        GM_Patent_Trademark_Indicator  
  
                )  
                SELECT  File_Id, Mfg_Id, Country_Id, Ped, Revision,   
                        Part_Description, Price, Core_Flag, Price_Net_Core,   
                        Promotion_Code, Status, Manuf_Code, Flag, Notes,   
                        Orig_Part_Number    = RTRIM(LTRIM(Orig_Part_Number)),   
                        Part_Number         = RTRIM(LTRIM(oh.Part_Number)),   
                        Tech_Number         = RTRIM(LTRIM(oh.Tech_Number)),   
                        Orig_Super_Number   = RTRIM(LTRIM(Orig_Super_Number)),   
                        Super_Number       = RTRIM(LTRIM(Super_Number)),  
                        GM_Patent_Trademark_Indicator  
                FROM    Pvg_Table oh  
                        INNER JOIN MaxParts_Temp tt  
                            ON RTRIM(LTRIM(oh.Part_Number)) = tt.Part_Number  
                            AND oh.Ped = tt.Maxdate;  
  
            END --IF EXISTS(SELECT 1  
            ELSE  
            BEGIN  
  
  
                -- fetch data from directly from Oem_Standard_Historical since PVG_TABLE is empty  
                PRINT 'BEFORE -- '  
                INSERT INTO #History_Temp   
                (  
                        File_Id, Mfg_Id, Country_Id, Ped, Revision,   
                        Part_Description, Price, Core_Flag, Price_Net_Core,   
                        Promotion_Code, Status, Manuf_Code, Flag, Notes,   
                        Orig_Part_Number,   
                        Part_Number,   
                        Tech_Number,   
                        Orig_Super_Number,   
                        Super_Number,  
                        GM_Patent_Trademark_Indicator  
                )  
                SELECT  File_Id, Mfg_Id, Country_Id, Ped, Revision,   
                        Part_Description, Price, Core_Flag, Price_Net_Core,   
                        Promotion_Code, Status, Manuf_Code, Flag, Notes,   
                        Orig_Part_Number    = RTRIM(LTRIM(Orig_Part_Number)),   
                        Part_Number         = RTRIM(LTRIM(oh.Part_Number)),   
                        Tech_Number         = RTRIM(LTRIM(oh.Tech_Number)),   
                        Orig_Super_Number   = RTRIM(LTRIM(Orig_Super_Number)),   
                        Super_Number       = RTRIM(LTRIM(Super_Number)),  
                        GM_Patent_Trademark_Indicator  
                FROM    Oem_Standard_Historical oh  
                        INNER JOIN MaxParts_Temp tt  
                            ON RTRIM(LTRIM(oh.Part_Number)) = tt.Part_Number  
                            AND oh.Ped = tt.Maxdate  
                WHERE   oh.Mfg_Id = @Manufacturer_Id  
                        AND oh.Country_Id = @Country_Id;  
  
            END -- ELSE NOT EXISTS(SELECT 1  
  
        END --fetch data from Pvg_Table or from Oem_Standard_Historical if Pvg_Table is empty  
  
        ---------------------------------------------------------- OEM MASTER - START  
        PRINT 'OEM MASTER TABLE '  
  
        IF @Two_Files = 'TRUE'  
        BEGIN  
  
            
            SELECT      MAX(File_Id) AS File_Id,  
                        Part_Number  
                INTO    #History_FileId  
                FROM    #History_Temp  
                GROUP BY Part_Number;  
  
            SELECT      ht.Part_Number,  
                        Status,  
                        Orig_Super_Number,  
                        Super_Number  
                INTO    #History_Status  
                FROM    #History_Temp ht  
                        INNER JOIN #History_FileId hf   
                            ON ht.Part_Number = hf.Part_Number  
                            AND ht.File_Id = hf.File_Id;  
  
            INSERT INTO [OEM_Master_Unfiltered]  
                (        File_Id, Revision, Mfg_Id, Country_Id, Ped, Part_Id,                           
               Status_Code, Approx_Flag, Core_Flag, Part_Desc,                           
               Price_Net_Core, Pr_Type_Id, Notes, Time_Inserted,  
                         Orig_Part_Number,  
                         Part_Number,  
                         Formatted_Part_Number,  
                         Formatted_Tech_Super_Number,  
                         Orig_Super_Number,  
                         Super_Number,  
                         Formatted_Super_Number,  
                         Formatted_Tech_Part_Number,  
                         Price,  
                         GM_Patent_Trademark_Indicator  
                )  
                SELECT  MAX(File_Id), Revision, Mfg_Id, Country_Id, MAX(Ped), NULL,                          
                MAX(hs.Status), MAX(Promotion_Code), MAX(Core_Flag), MAX(RTRIM(LTRIM(Part_Description))),  
                        MAX(Price_Net_Core), NULL, Notes, GETDATE(),  
                  
                RTRIM(LTRIM(Orig_Part_Number)),  
                        RTRIM(LTRIM(ht.Part_Number)),  
                        NULL,  
                        NULL,  
                        MAX(RTRIM(LTRIM(hs.Orig_Super_Number))),  
                        MAX(RTRIM(LTRIM(hs.Super_Number))),  
                        NULL,  
                        RTRIM(LTRIM(Tech_Number)),  
                          
                MAX(CONVERT(MONEY,  
                                    CASE  
                                        WHEN CHARINDEX('/', Price) > 0  
                                        THEN(CONVERT(MONEY, SUBSTRING(Price, 1, CHARINDEX('/', Price)-1)))/(CONVERT(MONEY, SUBSTRING(Price, CHARINDEX('/', Price)+1, LEN(Price)-CHARINDEX('/', Price))))  
                                        ELSE Price  
                                    END)),  
                GM_Patent_Trademark_Indicator  
                FROM    #History_Temp ht  
                INNER JOIN #History_Status hs   
                  ON ht.Part_Number = hs.Part_Number  
GROUP BY Revision,  
                        Mfg_Id,  
                        Country_Id,  
                        RTRIM(LTRIM(Orig_Part_Number)),  
                        RTRIM(LTRIM(ht.Part_Number)),  
                        RTRIM(LTRIM(ht.Tech_Number)),  
                        Notes,  
                        GM_Patent_Trademark_Indicator;  
  
        END -- IF @Two_Files = 'TRUE'  
  
        ELSE -- NOT (@Two_Files = 'TRUE')  
        BEGIN  
  
            INSERT INTO [Oem_Master_Unfiltered]  
                (           File_Id,                    Revision,   
                            Mfg_Id,                     Country_Id,   
                            Ped,                        Part_Id,   
                            Orig_Part_Number,           Part_Number,   
                            Formatted_Part_Number,      Formatted_Tech_Super_Number,  
                            Orig_Super_Number,          Super_Number,   
                            Formatted_Super_Number,     Formatted_Tech_Part_Number,   
                            Status_Code,                Approx_Flag,   
                            Core_Flag,                  Part_Desc,   
                            Price,                      Price_Net_Core,      
                            Pr_Type_Id,                 Notes,             
                            Time_Inserted  
                )  
                SELECT      File_Id = MAX(File_Id),     Revision,   
                            Mfg_Id,                     Country_Id,   
                            Ped = MAX(Ped),             Part_Id = NULL,   
                            Orig_Part_Number            = RTRIM(LTRIM(Orig_Part_Number)),      
                            Part_Number                 = RTRIM(LTRIM(Part_Number)),  
                            Formatted_Part_Number       = NULL,         
                            Formatted_Tech_Super_Number = NULL,   
                            Orig_Super_Number           = MAX(RTRIM(LTRIM(Orig_Super_Number))),   
                            Super_Number                = MAX(RTRIM(LTRIM(Super_Number))),  
                            Formatted_Super_Number      = NULL,   
                            Formatted_Tech_Part_Number  = RTRIM(LTRIM(Tech_Number)),   
                            Status_Code                 = MAX(Status),   
                            Approx_Flag                 = MAX(Promotion_Code),   
                            Core_Flag                   = MAX(Core_Flag),   
                            Part_Desc                   = MAX(RTRIM(LTRIM(Part_Description))),   
                            Price                       = MAX(CONVERT(MONEY,   
                                                            CASE WHEN CHARINDEX('/', Price) > 0   
                                                            THEN (CONVERT(MONEY, SUBSTRING(Price, 1, CHARINDEX('/', PRICE) - 1)))   
                                                               / (CONVERT(MONEY, SUBSTRING(Price, CHARINDEX('/', Price) + 1, LEN(Price) - CHARINDEX('/', Price))))   
                                                            ELSE Price   
                                                            END)),   
                            Price_Net_Core              = MAX(Price_Net_Core),   
                            Pr_Type_Id                  = NULL,            
                            Notes,   
                            Time_Inserted               = GETDATE()  
                                      
                FROM        #History_Temp  
                GROUP BY    Revision,   
                            Mfg_Id,   
                            Country_Id,   
                            RTRIM(LTRIM(Orig_Part_Number)),   
                            RTRIM(LTRIM(Part_Number)),   
                            RTRIM(LTRIM(Tech_Number)), Notes  
  
        END --ELSE NOT (@Two_Files = 'TRUE')  
  
        ---------------------------------------------------------- OEM MASTER - END  
  
  
        --------------------------------------------------------------------------------- CREATE PVG FILE  
  
        PRINT 'PVG_1 '  
  
        DECLARE @Manufacturer AS INT;  
        DECLARE @Country AS INT;  
  
        SELECT  @Manufacturer = @Manufacturer_Id;  
        SELECT  @Country = @Country_Id;  
  
        --------------------------------------------------------------- STEP ONE  
        -- GET DATA FROM MOST RECENT PED FILE  
  
        DECLARE @Recent_Ped AS DATETIME;  
        SELECT  @Recent_Ped =  (SELECT TOP 1 Ped FROM Oem_Master_Unfiltered Oem_Master  
                                    WHERE Mfg_Id = @Manufacturer  
                                    AND Country_Id = @Country  
                                    ORDER BY Ped DESC);  
  
        TRUNCATE TABLE BuildPVG_StepOne  
  
        -- skip if not flagged for PVG export  
        IF @Is_Active_for_Pvg = 1  
        BEGIN --IF @Is_Active_for_Pvg = 1  
  
            INSERT INTO BuildPvg_StepOne  
                (       Part_Id, Manuf_Name, Part_Number, Part_Description,   
                Price, Status, Super_Number, Price_Effective_Date,   
                CountryCode, Manufacturer_Id, Manufacturer_Country_Code  
                )  
                SELECT  Oem_Master.Part_ID as Part_Id,   
                        RTRIM(Vw_Oem_Manufacturer_List.manuf_name) AS Manuf_Name,   
                        RTRIM(LTRIM(Oem_Master.Part_Number)) AS Part_Number,   
                        RTRIM(LTRIM(Oem_Master.Part_Desc)) AS Part_Description,   
                        RTRIM(LTRIM(Oem_Master.Price)) AS Price,   
                        RTRIM(LTRIM(Oem_Master.Status_code)) AS Status,   
                        RTRIM(LTRIM(Oem_Master.Super_Number)) AS Super_Number,   
                        Oem_Master.Ped as Price_Effective_Date,   
                        RTRIM(LTRIM(A_CountryCode.CountryCode)) AS CountryCode,   
                        Oem_Source_File_Log.Manufacturer_Id,   
                        Oem_Source_File_Log.Manufacturer_Country_Code  
                FROM    Oem_Source_File_Log   
                        INNER JOIN    A_CountryCode   
                  ON Oem_Source_File_Log.Manufacturer_Country_Code = A_CountryCode.CountryId   
                        INNER JOIN Vw_Oem_Manufacturer_List   
                  ON Oem_Source_File_Log.Manufacturer_Id = Vw_Oem_Manufacturer_List.Manufacturer_Id   
                RIGHT OUTER JOIN Oem_Master_Unfiltered OEM_MASTER      
                  ON Oem_Source_File_Log.File_Id = Oem_Master.File_Id  
                WHERE   EXISTS(SELECT TOP 1 1   
                      FROM    OEM_Master_Unfiltered om1  
                      WHERE   om1.File_Id = Oem_Master.File_Id   
                            AND Mfg_Id = @Manufacturer  
                            AND Country_Id = @Country  
                            AND Oem_Master.Ped =  @Recent_Ped  
                    )  
                AND Oem_Master.Mfg_Id = @Manufacturer  
                AND Oem_Master.Country_Id = @Country  
                ORDER BY Part_Number;  
  
        END --IF @Is_Active_for_Pvg = 1  
        --------------------------------------------------------------- STEP TWO  
        -- GET HISTORY OF PARTS  
        PRINT 'PVG_2 '  
        TRUNCATE TABLE BuildPVG_StepTwo  
  
        -- skip if not flagged for PVG export  
        IF @Is_Active_for_Pvg = 1  
        BEGIN  
  
            INSERT INTO BuildPvg_StepTwo  
          (         Ped, Part_Number, Price, Status  
          )  
                SELECT      Ped, Part_Number, Price, Status  
            FROM      Pvg_Table  
  
        END -- IF @Is_Active_for_Pvg = 1  
  
        --------------------------------------------------------------- STEP THREE  
        -- GET THE LAST PRICE CHANGE  
        TRUNCATE TABLE BuildPVG_StepThree_PRE  
  
        -- skip if not flagged for PVG export  
        IF @Is_Active_for_Pvg = 1  
        BEGIN -- IF @Is_Active_for_Pvg = 1  
  
            INSERT INTO BuildPvg_StepThree_Pre  
          (   Manuf_Name, CountryCode, Part_Number, Part_Description,   
Price, Status, Super_Number,   
            Price_Effective_Date  
          )  
                SELECT  One.Manuf_Name, One.CountryCode, One.Part_Number, One.Part_Description,   
                        One.Price, One.Status, One.Super_Number,   
                Price_Effective_Date = CASE WHEN ISNULL(Two.Ped, 0) = 0 THEN One.Price_Effective_Date  
                                ELSE Two.Ped  
                                END  
                FROM    BuildPvg_StepOne One  
                LEFT JOIN BuildPvg_StepTwo Two  
                  ON RTRIM(LTRIM(One.Part_Number)) = RTRIM(LTRIM(Two.Part_Number))  
                  AND RTRIM(LTRIM(one.Price)) = RTRIM(LTRIM(two.Price));  
  
        END --IF @Is_Active_for_Pvg = 1  
  
  
        PRINT 'PVG_3 '  
        TRUNCATE TABLE BuildPvg_StepThree  
  
        -- skip if not flagged for PVG export  
        IF @Is_Active_for_Pvg = 1  
        BEGIN  
  
            INSERT INTO BuildPvg_StepThree  
        (      Manuf_Name, CountryCode, Part_Number, Part_Description,   
            Price, Price_Effective_Date, Status, Super_Number  
        )  
            SELECT         Manuf_Name, CountryCode, Part_Number, Part_Description,   
                  Price, MIN(Price_Effective_Date), Status, Super_Number  
          FROM      BuildPvg_StepThree_Pre  
          GROUP BY      Manuf_Name, Part_Number, Part_Description, Price, Status, Super_Number, CountryCode;  
  
        END --IF @Is_Active_for_Pvg = 1  
  
        DELETE  
            FROM OEM_Master_Unfiltered  
            WHERE RTRIM(LTRIM(Part_Number)) = '';  
  
  
        PRINT 'DONE '  
  
        IF OBJECT_ID('tempdb..#History_Temp') IS NOT NULL  
            DROP TABLE #History_Temp;  
  
  
  
  
        -------------------------------------------------------------------------------------------  
        --> > > CUSTOM CODE ENDS HERE < < <------------------------------------------------------------  
        -------------------------------------------------------------------------------------------  
  
        SET @checkpoint = @defaultSuccessCode  
          
        --Transactions ARE needed -> because there ARE truncates, deletes, inserts, or updates  
        IF @@TRANCOUNT > 0 AND @@Error = 0  
            COMMIT TRANSACTION    
  
        -- apply the tech formats to the "ADDED" parts  
        EXEC [dbo].[USP_ApplyTechFormatToAddedParts] @manufacturer_id, @country_Id  
  
  
    END TRY  
  
    ---------------------------------------------------------------------------------------------------------------------  
    BEGIN CATCH  
        BEGIN   -- Standard error-handling block (from template)  
  
            IF @@TRANCOUNT > 0 AND @@Error <> 0  
                ROLLBACK TRANSACTION  
  
            -- SQL 2000-2005 - Does not allow variable assignment during DECLARE statements.  
            DECLARE @ErrorNumber    INT;  
            DECLARE @ErrorMessage   NVARCHAR(4000);  
            DECLARE @ErrorProcedure NVARCHAR(4000);  
            DECLARE @ErrorLine      INT;  
            SET @ErrorNumber        = ERROR_NUMBER();  
            SET @ErrorMessage       = ERROR_MESSAGE();  
            SET @ErrorProcedure     = ERROR_PROCEDURE();  
            SET @ErrorLine          = ERROR_LINE();  
  
            /*  
            -- SQL 2008 and above - Allows variable assignment during DECLARE statements.  
            DECLARE @ErrorNumber    INT             = ERROR_NUMBER();  
            DECLARE @ErrorMessage   NVARCHAR(4000)  = ERROR_MESSAGE();   
            DECLARE @ErrorProcedure NVARCHAR(4000)  = ERROR_PROCEDURE();  
            DECLARE @ErrorLine      INT             = ERROR_LINE();  
            */  
  
            EXEC Log_Error;  
  
            RAISERROR ('  
  
ERROR %d:  %s  
  
    Procedure       : [%s] in [%s] on [%s]  
    Checkpoint      : %d  
  
    EXEC [%s]  
        @Manufacturer_ID    = %d,  
        @Country_Id         = %d  
',  
            16, 2,  
            @ErrorNumber, @ErrorMessage,  
            @StoredProcedureName, @DatabaseName, @@SERVERNAME,  
            @checkpoint,  
     @ErrorProcedure,  
  
            -- Add parameters here  
            @Manufacturer_ID, @Country_Id  
            )  
  
        END     -- Standard error-handling block (from template)  
  
        SET @ran_Successfully = 0;  
  
    END CATCH;  
  
    SELECT PED = CASE   
                    WHEN @ran_Successfully = 1 THEN @Price_Effective_Date   
                    ELSE ''  
                    END;  
  
    RETURN @checkpoint;  
  
END -- PROCEDURE  