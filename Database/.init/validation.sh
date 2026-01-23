#!/usr/bin/env bash
set -euo pipefail
WORKSPACE="/home/kavia/workspace/code-generation/recipe-book-310206-310327/Database"
cd "$WORKSPACE"
UVICORN="$WORKSPACE/.venv/bin/uvicorn"
PY="$WORKSPACE/.venv/bin/python"
PIP="$WORKSPACE/.venv/bin/pip"
REQ="$WORKSPACE/requirements.txt"
LOGFILE=$(mktemp -t uvicorn-log-XXXX) || LOGFILE="/tmp/uvicorn-log-$$.log"
PIPLOG=$(mktemp -t pip-log-XXXX) || PIPLOG="/tmp/pip-log-$$.log"
STAMP="$WORKSPACE/.venv_installed"
# Validate requirements.txt present
if [ ! -f "$REQ" ]; then
  echo "requirements.txt missing for validation" >&2
  exit 2
fi
# Install if no stamp (merge autogen to ensure uvicorn present) -- idempotent
if [ ! -f "$STAMP" ]; then
  export REQUIREMENTS_DB="${REQUIREMENTS_DB:-}"
  export REQUIREMENTS_ENV="${REQUIREMENTS_ENV:-}"
  # Create autogen merged requirements
  cp "$REQ" "$WORKSPACE/requirements.autogen.txt"
  if [ -n "${REQUIREMENTS_DB:-}" ] && ! grep -Fqx "${REQUIREMENTS_DB}" "$WORKSPACE/requirements.autogen.txt" 2>/dev/null; then
    printf '%s\n' "${REQUIREMENTS_DB}" >>"$WORKSPACE/requirements.autogen.txt"
  fi
  if [ -n "${REQUIREMENTS_ENV:-}" ] && ! grep -Fqx "${REQUIREMENTS_ENV}" "$WORKSPACE/requirements.autogen.txt" 2>/dev/null; then
    printf '%s\n' "${REQUIREMENTS_ENV}" >>"$WORKSPACE/requirements.autogen.txt"
  fi
  if ! grep -E '(^|\s)uvicorn(==|>=|<=|\s|$)' "$WORKSPACE/requirements.autogen.txt" >/dev/null 2>&1; then
    printf 'uvicorn\n' >>"$WORKSPACE/requirements.autogen.txt"
  fi
  # Use venv pip if available, otherwise try system pip
  if [ ! -x "$PIP" ]; then
    PIP=$(command -v pip3 || command -v pip || true)
    if [ -z "$PIP" ]; then
      echo "pip not found" >&2
      rm -f "$WORKSPACE/requirements.autogen.txt"
      exit 3
    fi
  fi
  "$PIP" --disable-pip-version-check install --upgrade -r "$WORKSPACE/requirements.autogen.txt" --no-cache-dir >"$PIPLOG" 2>&1 || {
    echo "Dependency install failed; tail of pip log:" >&2
    tail -n 200 "$PIPLOG" >&2 || true
    rm -f "$WORKSPACE/requirements.autogen.txt"
    exit 8
  }
  date -u +%s >"$STAMP"
  rm -f "$WORKSPACE/requirements.autogen.txt"
fi
# Locate uvicorn binary (prefer venv)
if [ ! -x "$UVICORN" ]; then
  UVICORN=$(command -v uvicorn || true)
  if [ -z "$UVICORN" ]; then
    echo "uvicorn not available" >&2
    exit 9
  fi
fi
# Start server in background in a new session and capture PID
setsid "$UVICORN" app.main:app --host 0.0.0.0 --port 8000 >"$LOGFILE" 2>&1 &
UV_PID=$!
# capture PGID explicitly
sleep 0.2
PGID=$(ps -o pgid= -p "$UV_PID" | tr -d ' ' || true)
if [ -z "$PGID" ]; then
  PGID="$UV_PID"
fi
_cleanup(){
  # Terminate entire process group first, fallback to PID
  if ps -p "$UV_PID" >/dev/null 2>&1; then
    kill -TERM -"$PGID" >/dev/null 2>&1 || kill -TERM "$UV_PID" >/dev/null 2>&1 || true
    sleep 1
  fi
}
trap _cleanup EXIT
# Wait for startup with timeout
timeout=20
BODY=""
while [ $timeout -gt 0 ]; do
  HTTP_RAW=$(curl -sS -m 3 -w "\n%{http_code}" http://127.0.0.1:8000/health) || true
  if [ -n "$HTTP_RAW" ]; then
    BODY=$(echo "$HTTP_RAW" | sed '$d')
    CODE=$(echo "$HTTP_RAW" | tail -n1)
    if [ "$CODE" = "200" ]; then
      break
    fi
  fi
  sleep 1
  timeout=$((timeout-1))
done
if [ "$timeout" -le 0 ]; then
  echo "Server did not become ready in time. Log excerpt:" >&2
  tail -n 200 "$LOGFILE" >&2 || true
  exit 10
fi
# Validate JSON using venv python (fallback to system python3)
if [ ! -x "$PY" ]; then
  PY=$(command -v python3 || command -v python || true)
  if [ -z "$PY" ]; then
    echo "python not available for validation" >&2
    exit 12
  fi
fi
VALID=$($PY - <<'PY'
import sys, json
body=sys.stdin.read()
try:
    data=json.loads(body)
except Exception:
    sys.exit(2)
if data=={"status":"ok"}:
    print('ok')
else:
    print('unexpected:'+json.dumps(data))
    sys.exit(3)
PY
<<<"$BODY")
if [ "$VALID" != "ok" ]; then
  echo "Validation failed: $VALID" >&2
  echo "Server log excerpt:" >&2
  tail -n 200 "$LOGFILE" >&2 || true
  exit 11
fi
# Evidence
echo "health endpoint status: 200"
echo "health endpoint body: $BODY"
# cleanup handled by trap
rm -f "$LOGFILE" "$PIPLOG" || true
