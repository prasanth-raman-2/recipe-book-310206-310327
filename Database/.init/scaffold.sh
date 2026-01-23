#!/usr/bin/env bash
set -euo pipefail
WORKSPACE="/home/kavia/workspace/code-generation/recipe-book-310206-310327/Database"
cd "$WORKSPACE"
mkdir -p "$WORKSPACE/app" "$WORKSPACE/tests"
# app/main.py - create only if missing
if [ ! -f "$WORKSPACE/app/main.py" ]; then
  cat > "$WORKSPACE/app/main.py" <<'PY'
from fastapi import FastAPI
app = FastAPI()

@app.get('/health')
def health():
    return {'status': 'ok'}
PY
fi
# start.sh - create only if missing to preserve custom scripts
if [ ! -f "$WORKSPACE/start.sh" ]; then
  cat > "$WORKSPACE/start.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
WORKSPACE="/home/kavia/workspace/code-generation/recipe-book-310206-310327/Database"
"$WORKSPACE/.venv/bin/uvicorn" app.main:app --host 0.0.0.0 --port 8000 "$@"
SH
  chmod +x "$WORKSPACE/start.sh"
fi
# Minimal requirements.txt - create only if missing
REQ_FILE="$WORKSPACE/requirements.txt"
if [ ! -f "$REQ_FILE" ]; then
  cat > "$REQ_FILE" <<'RQ'
fastapi
uvicorn
pytest
requests
# Optional DB client: add one of: psycopg2-binary OR mysqlclient OR pymongo
# Optional: add sqlmodel or sqlalchemy if an ORM is desired
# Optional: add python-dotenv if you want .env loading
RQ
fi
# .env example - create only if missing
if [ ! -f "$WORKSPACE/.env.example" ]; then
  cat > "$WORKSPACE/.env.example" <<'ENV'
# Example DATABASE_URL; change as needed or use container env vars
DATABASE_URL=postgresql://user:pass@localhost:5432/dbname
ENV
fi
# Short README hint - create only if missing
README_SNIPPET="$WORKSPACE/README.setup.txt"
if [ ! -f "$README_SNIPPET" ]; then
  cat > "$README_SNIPPET" <<'TXT'
Order to run scripts:
1) env-001 (create venv and persist PATH)
2) deps-001 (install dependencies into venv)
3) test-001 (run pytest smoke tests)
4) validation-001 (start server and validate /health)

Notes:
- If you want the automation to include an extra DB client, set REQUIREMENTS_DB to one of: psycopg2-binary, mysqlclient, pymongo before running deps-001. Automation will NOT edit your requirements.txt in-place; it will create a merged requirements.autogen.txt for installs.
- To request python-dotenv be installed, set REQUIREMENTS_ENV=python-dotenv before running deps-001.
- Pin versions in requirements.txt for reproducible installs before CI.
- Run ./start.sh --reload for development (omit --reload in CI).
TXT
fi

# stamp file to mark scaffold step completed idempotently
STAMP="$WORKSPACE/.init_scaffold_stamp"
if [ ! -f "$STAMP" ]; then
  date -u +"%Y-%m-%dT%H:%M:%SZ" > "$STAMP"
fi
