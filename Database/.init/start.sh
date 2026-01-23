#!/usr/bin/env bash
set -euo pipefail
WORKSPACE="/home/kavia/workspace/code-generation/recipe-book-310206-310327/Database"
cd "$WORKSPACE"
UVICORN_BIN="$WORKSPACE/.venv/bin/uvicorn"
# fallback to system uvicorn if venv one missing
if [ ! -x "$UVICORN_BIN" ]; then
  UVICORN_BIN=$(command -v uvicorn || true)
  if [ -z "$UVICORN_BIN" ]; then
    echo "uvicorn not found" >&2
    exit 2
  fi
fi
# Start uvicorn in a new session (no --reload in CI)
setsid "$UVICORN_BIN" app.main:app --host 0.0.0.0 --port 8000 > >(stdbuf -oL cat) 2>&1 &
echo $!
