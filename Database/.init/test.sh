#!/usr/bin/env bash
set -euo pipefail
WORKSPACE="/home/kavia/workspace/code-generation/recipe-book-310206-310327/Database"
cd "$WORKSPACE"
TEST_FILE="$WORKSPACE/tests/test_smoke.py"
# create tests dir if missing
mkdir -p "$WORKSPACE/tests"
if [ ! -f "$TEST_FILE" ]; then
  cat > "$TEST_FILE" <<'PY'
from fastapi.testclient import TestClient
from app.main import app

client = TestClient(app)

def test_health():
    r = client.get('/health')
    assert r.status_code == 200
    assert r.json() == {'status': 'ok'}
PY
fi
# Ensure venv pytest exists and is executable
VENV_PYTEST="$WORKSPACE/.venv/bin/pytest"
if [ ! -x "$VENV_PYTEST" ]; then
  echo "Error: pytest not found at $VENV_PYTEST. Ensure env and deps steps ran." >&2
  exit 6
fi
# Run pytest using venv pytest; fail fast with exit code 7 on test failures
"$VENV_PYTEST" -q tests || { echo "pytest failed" >&2; exit 7; }
