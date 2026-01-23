#!/usr/bin/env bash
set -euo pipefail
WORKSPACE="/home/kavia/workspace/code-generation/recipe-book-310206-310327/Database"
cd "$WORKSPACE"
PIP="$WORKSPACE/.venv/bin/pip"
PY="$WORKSPACE/.venv/bin/python"
REQ_BASE="$WORKSPACE/requirements.txt"
AUTOGEN_REQ="$WORKSPACE/requirements.autogen.txt"
STAMP="$WORKSPACE/.venv_installed"
LOGFILE=$(mktemp -t pip-log-XXXX)
# Ensure requirements.txt exists
if [ ! -f "$REQ_BASE" ]; then
  echo "requirements.txt missing in workspace ($REQ_BASE)" >&2
  exit 2
fi
# build autogen requirements file to avoid editing developer file
cp "$REQ_BASE" "$AUTOGEN_REQ"
# append optional extras requested by automation
if [ -n "${REQUIREMENTS_DB:-}" ]; then
  if ! grep -Fqx "${REQUIREMENTS_DB}" "$AUTOGEN_REQ" 2>/dev/null; then
    printf '%s\n' "${REQUIREMENTS_DB}" >>"$AUTOGEN_REQ"
  fi
fi
if [ -n "${REQUIREMENTS_ENV:-}" ]; then
  if ! grep -Fqx "${REQUIREMENTS_ENV}" "$AUTOGEN_REQ" 2>/dev/null; then
    printf '%s\n' "${REQUIREMENTS_ENV}" >>"$AUTOGEN_REQ"
  fi
fi
# Ensure uvicorn present in autogen (env expects uvicorn in venv)
if ! grep -E '(^|\s)uvicorn(==|>=|<=|\s|$)' "$AUTOGEN_REQ" >/dev/null 2>&1; then
  printf 'uvicorn\n' >>"$AUTOGEN_REQ"
fi
# If mysqlclient requested, ensure system headers for building wheels
if grep -E '(^|\s)mysqlclient(==|>=|<=|\s|$)' "$AUTOGEN_REQ" >/dev/null 2>&1 || [ "${REQUIREMENTS_DB:-}" = "mysqlclient" ]; then
  sudo apt-get update -q >/dev/null
  sudo apt-get install -yq python3-dev default-libmysqlclient-dev >/dev/null || { echo "Failed to install system deps for mysqlclient" >&2; exit 4; }
fi
# Skip install if stamp exists
if [ -f "$STAMP" ]; then
  # stamp present: assume installed
  exit 0
fi
# Install requirements into venv; send output to logfile
if [ ! -x "$PIP" ]; then
  echo "pip binary not found at $PIP - ensure .venv exists and env step ran" >&2
  rm -f "$AUTOGEN_REQ" "$LOGFILE" || true
  exit 3
fi
"$PIP" --disable-pip-version-check install --upgrade -r "$AUTOGEN_REQ" --no-cache-dir >"$LOGFILE" 2>&1 || {
  echo "pip install failed; tail of log:" >&2; tail -n 200 "$LOGFILE" >&2 || true; rm -f "$AUTOGEN_REQ"; exit 5
}
# stamp successful install
date -u +%s >"$STAMP"
# Validate imports: mapping package names to import modules
if [ ! -x "$PY" ]; then
  echo "python binary not found at $PY - ensure .venv exists and env step ran" >&2
  rm -f "$AUTOGEN_REQ" "$LOGFILE" || true
  exit 3
fi
"$PY" - <<'PY'
import sys,re
missing=[]
for pkg in ('fastapi','uvicorn','pytest','requests'):
    try:
        __import__(pkg)
    except Exception as e:
        missing.append(pkg+':'+str(e))
try:
    with open('requirements.autogen.txt') as f:
        raw=[l.split('#',1)[0].strip() for l in f if l.strip()]
except Exception:
    raw=[]
mapped=set()
for r in raw:
    base=re.split('[=<>]', r)[0].strip()
    if not base:
        continue
    if base=='psycopg2-binary':
        mapped.add('psycopg2')
    elif base=='mysqlclient':
        mapped.add('MySQLdb')
    elif base=='pymongo':
        mapped.add('pymongo')
    elif base in ('sqlmodel','sqlalchemy'):
        mapped.add(base)
    else:
        mapped.add(base)
for cand in mapped:
    try:
        __import__(cand)
    except Exception as e:
        missing.append(cand+':'+str(e))
if missing:
    print('Missing or failing imports:', file=sys.stderr)
    for m in missing:
        print(m, file=sys.stderr)
    sys.exit(6)
print('dependencies OK')
PY
# cleanup
rm -f "$AUTOGEN_REQ" || true
rm -f "$LOGFILE" || true
