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
4. Click each node to inspect its actual output. Fast deterministic runs may complete between polling intervals; the UI does not add artificial delays.
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

The visual API imports the inherited patterns, analyzes submitted text without modifying sample files, and saves each run in SQLite. Visual decisions do not promote Markdown drafts or approve GitHub deployments. Use Classic Streamlit for the inherited draft approval flow. Container data for Flow lives in a named volume; classic drafts/approvals live under the mounted `rules` folder.

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
