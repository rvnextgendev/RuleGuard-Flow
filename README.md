# RuleGuard Flow

An Angular + FastAPI visual workflow for the RuleGuard AI POC. Inspect C#/SQL changes, trace baseline rule differences, request an optional LLM explanation, and record a human review decision.

## Quick start — Docker (recommended)

Requirements: Git and Docker Desktop running with Linux containers.

```bash
git clone https://github.com/rvnextgendev/RuleGuard-Flow.git
cd RuleGuard-Flow
cp .env.example .env
docker compose up --build
```

Windows PowerShell: use `Copy-Item .env.example .env` instead of `cp`.

- Visual workflow: http://localhost:8000
- Original Streamlit screens: http://localhost:8501
- API documentation: http://localhost:8000/docs

The default sample analysis works without an LLM. To use local Ollama:

```bash
docker compose --profile local-llm up -d --build
docker compose exec ollama ollama pull qwen2.5:3b
```

Then enable **Ask configured LLM** in the visual interface. The first model download can take time. For Groq set `LLM_PROVIDER=groq` and `GROQ_API_KEY` in `.env`, then recreate the services. Existing OpenAI and compatible-provider environment settings in `app/llm.py` remain supported; add them to `.env` if needed. Never commit `.env`.

## Demo walkthrough

1. Select **Payment validation removed** or **Removal period: 8 to 7 days**.
2. Open **Edit / upload code** to inspect or replace original and changed C#/SQL. An empty changed input represents removal of all source content.
3. Click **Run analysis**. The backend executes Load Code → Extract Rules → Compare Rules → Explain Impact → Business Review → Save Decision.
4. Click each node to inspect its actual output. The backend records every node transition. The UI presents those real events in order at 650 ms intervals so fast steps remain visible; this presentation does not slow backend execution. Groq/LLM steps remain running while awaiting the provider.
5. Read Compare Rules for added/removed/modified baseline evidence and the full unified source diff.
6. Enter a reviewer name and meaningful comments, then approve or reject.
7. Open **Execution history** to revisit the stored evidence and decision.

## What is reused from RuleGuard-AI

Copied from source commit `b6a4d4176392a427848bdec4b42f3290980b6f8d`:

- `app/engine.py`: four deterministic PAY patterns, draft Markdown discovery and staged Git review.
- `app/discovery_ai.py`: LangGraph candidate discovery with exact evidence validation.
- `app/llm.py`: Ollama/Groq/OpenAI/compatible provider support (default changed to Ollama).
- `app/ui.py`: original Streamlit discovery, rule management and developer review screens.
- `app/approval.py`, `install-hook.py`, samples, approved baseline, and GitHub business approval workflow.

The visual API imports the inherited patterns, analyzes submitted text without modifying sample files, and saves each run in SQLite. Flow can now save explicitly selected baseline rule proposals to Markdown after preview. It does not promote AI drafts or approve GitHub deployments. Use Classic Streamlit for the inherited AI draft approval flow. Container data for Flow lives in a named volume; classic drafts/approvals live under the mounted `rules` folder.

## Local development / debugging

Use Python 3.11+ and Node 22.12+ (or a compatible Angular 20 Node version).

```bash
python -m venv .venv
# Windows: .venv\Scripts\activate
# macOS/Linux: source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env
python -m uvicorn backend.main:app --reload --port 8000
```

In a second terminal:

```bash
cd frontend
npm ci
npm start
```

Open http://localhost:4200. Angular proxies `/api` to port 8000. For the classic UI, in another activated Python terminal run `python -m streamlit run app/ui.py`. VS Code launch configurations are included for API and Streamlit.

To serve the compiled frontend from FastAPI:

```bash
cd frontend
npm run build
cd ..
python -m uvicorn backend.main:app --port 8000
```

## Checks

```bash
python -m pytest -q
cd frontend
npm ci
npm run build
```

The CI workflow runs backend regression tests, inherited guard checks and the Angular production build. The inherited `RuleGuard Business Approval` workflow also remains available. Configure the `business-rule-exception` GitHub Environment with required reviewers and protect `main` with its `merge-gate` check to make GitHub approvals enforceable. Settings are not created by application code.

## API

| Method | Path | Purpose |
|---|---|---|
| GET | `/api/health` | Service health |
| GET | `/api/samples` | Three editable demo scenarios |
| POST | `/api/runs` | Submit filename, before, after, use_ai |
| GET | `/api/runs` | Last 50 saved runs |
| GET | `/api/runs/{id}` | Full input, node results and decision |
| POST | `/api/runs/{id}/decision` | Approve/reject with reviewer and comments |

## Scope and limitations

This is a local single-user POC, not a full n8n automation engine. It has a fixed six-step workflow, no arbitrary node editing, and no authentication. Reviewer names are self-entered. Keep it local until authentication and authorization are implemented. No GitHub token is needed to use the local UI.

Pattern coverage is limited to four inherited payment rules plus an explicit removal-day assignment candidate. Arbitrary changes are shown in the diff but are not guaranteed to be interpreted. Regex patterns can match comments and cannot prove behavior. SQL samples are analyzed as text and never executed. AI-discovered rules in the classic UI remain advisory; AI does not approve or enforce rules.

Run records persist across restarts, but in-flight background execution does not resume after a process crash. Start a new run after an interruption. Use one API worker for this POC. Simultaneous decisions within that worker are guarded; a decision cannot be overwritten. A failed LLM call retains deterministic results with a visible warning. Real model connectivity requires a running provider and was not assumed by the offline tests.

Future extensions: durable job queue, authenticated reviewer identities, GitHub PR ingestion and commit-bound decisions, richer language parsers, configurable nodes, and streaming status updates.

## Test enriched context with Groq

1. Pull the latest `main`.
2. Edit `.env` (copy `.env.example` only if `.env` does not exist):

```env
LLM_PROVIDER=groq
GROQ_API_KEY=your_actual_key_here
GROQ_MODEL=llama-3.3-70b-versatile
```

3. Run `docker compose up -d --build --force-recreate` and open http://localhost:8000.
4. Select **Removal period: 8 to 7 days**. In **Business context**, enter: `The removal period changes from eight to seven days after term start. Identify the changed behavior and recommend boundary tests.`
5. Check **Ask configured LLM (groq)**, then click **Run analysis**.
6. Click **Explain Impact**. Success shows `mode: llm-advisory`, `provider: groq`, the explanation and context size metadata. `mode: deterministic` plus a warning means the LLM call failed; deterministic output is not a Groq response. Check your key, model access, provider quota, and server logs/configuration.

The prompt includes original and changed code (up to 12,000 characters each), business context (6,000), approved Markdown rules (8,000), detected changes (6,000), and diff (8,000). Smaller files are included completely. Oversized sections have explicit truncation metadata. Rules are read from `rules/approved` at execution time; Docker Flow mounts that folder writable so selected approvals persist locally. No retrieval of other repository files or external documents occurs. Groq receives the included content when enabled. Keys stay in server environment configuration and are never returned by the config API.

### Visible workflow execution

Run Analysis now highlights each running node, colors completed connections, automatically selects the current node, and shows a timestamped execution log. Business Review pauses until a decision is recorded. History shows the saved event log. Fast backend steps are presented from recorded events; displayed timestamps reflect actual server execution, not animation time.


## Save approved rules from Flow (UI 1.3)

1. Run a fresh analysis. Older runs have no saved rule proposals; re-run them to generate previews.
2. At Business Review, inspect **Rule file changes**, expand the proposed Markdown and current approved version, and select the individual changes to save. Nothing is preselected.
3. Enter reviewer and comments. Click **Approve & save selected rules**.
4. Click **Save Decision** to see `saved_files` and content hashes.

For the 8 → 7 day sample, select `TERM-REMOVAL` and open `rules/approved/TERM-REMOVAL.md` in your local checkout after approving. It records the explicit assignment as evidence; the pattern does not establish the full business requirement.

- New/modified selected rules create or update `rules/approved/<id>.md`.
- Previous versions are preserved under `rules/archived/<run-id>/<id>.previous.md`.
- Selected removals create `<id>.retired.md` in that archive folder and remove the active approved file. Retiring a rule intentionally removes it from baseline enforcement.
- Unselected rules and rejected proposals do not change files. **Approve review only** explicitly records a decision without saving rules.
- A rule changed since proposal generation returns a conflict; run analysis again and review the new proposal.
- Save failures leave the decision pending; handled write/DB failures restore prior files.

Markdown includes reviewer, comments, timestamp, source evidence, run ID and previous content hash. SQLite retains the decision, selected IDs, saved paths and new hashes. The Docker bind mount is writable; files survive container replacement. No GitHub commit/PR is created automatically. Commit approved/archived files yourself to share them.

This remains a single-worker local POC. The in-process lock coordinates Flow decisions, not external editors or Classic Streamlit. Avoid simultaneous manual/Classic writes during approval. File and SQLite updates are not a crash-atomic distributed transaction; abrupt process/machine failure during a save needs inspection of the saved files and run history. New rule IDs are documented but only the inherited PAY patterns are enforced by the existing Git guard.


## Uploaded source comparison (UI 1.4)

Upload the original file on the left and its changed version on the right. The interface displays uploaded filenames and character counts. Enable **Compare both sources with LLM**, then run analysis. The Compare Rules step sends both versions and context to the configured model and requests structured added/removed/modified behavior findings. Explain Impact displays the returned summary without a second model request.

The **Source comparison** panel shows before/after evidence and source line numbers for accepted advisory findings. The server rejects findings with missing, invented, unchanged, or incorrectly paired evidence. Evidence matching cannot establish semantic correctness: manually review the interpretations. Invalid JSON, provider failures or rate limits produce a visible warning and preserve the baseline results and text diff. No live provider success is implied by fallback output.

The existing 12,000-character limit per source remains. Larger files show a partial-comparison warning; split a large procedure or review the full text diff. The raw text diff always compares all submitted text. LLM findings are advisory and do not generate approved Markdown proposals; only the existing baseline proposals support file approval in this version. Generic AI-to-rule promotion remains a separate extension.

### Demo PR causes Flow unit-test failures

Flow's built-in scenarios are defined in `backend/demo_samples.py`. They intentionally do not read the mutable `samples/PaymentService.cs` or `samples/CapturePayment.sql` files. Those repository files remain inputs for the GitHub/pre-commit business guard, so deleting the payment validation during a PR demo still flags PAY-001 and requires configured environment approval. The UI's original/changed scenario pair and its tests remain repeatable while the demo branch changes the guard samples.
