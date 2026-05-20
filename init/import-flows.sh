#!/bin/bash
set -euo pipefail

FLOWISE_URL="${FLOWISE_URL:-http://flowise:3000}"
FLOWS_DIR="/init/flows"

POSTGRES_HOST="${POSTGRES_HOST:-postgres}"
POSTGRES_DB="${POSTGRES_DB:-flowise}"
POSTGRES_USER="${POSTGRES_USER:-flowise}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD}"

ADMIN_EMAIL="admin@local.dev"
ADMIN_PASSWORD="changeme_admin_password"
ADMIN_NAME="Admin"

log()  { echo "[import-flows] $(date -u '+%H:%M:%S') $*"; }
error() { echo "[import-flows] ERROR: $*" >&2; }

# ---- Wait for Flowise ----
log "Waiting for Flowise at $FLOWISE_URL..."
for i in $(seq 1 60); do
  if curl -sf "${FLOWISE_URL}/api/v1/ping" > /dev/null 2>&1; then
    log "Flowise is ready."
    break
  fi
  if [ "$i" -eq 60 ]; then
    error "Flowise did not become ready within 120 seconds."
    exit 1
  fi
  sleep 2
done

# ---- Bootstrap: admin user, workspace, API key ----
log "Bootstrapping admin user and API key..."

BOOTSTRAP_OUT=$(python3 <<-'PYEOF'
import uuid, secrets, hashlib, base64, subprocess, json, os, sys

host = os.environ['POSTGRES_HOST']
db   = os.environ['POSTGRES_DB']
user = os.environ['POSTGRES_USER']
pw   = os.environ.get('POSTGRES_PASSWORD', '')
ADMIN_EMAIL = "admin@local.dev"
ADMIN_NAME  = "Admin"

def psql(sql):
    env = os.environ.copy()
    env['PGPASSWORD'] = pw
    r = subprocess.run(
        ['psql', '-h', host, '-U', user, '-d', db, '-t', '-A', '-c', sql],
        capture_output=True, text=True, env=env)
    if r.returncode != 0 and 'already exists' not in r.stderr and 'duplicate key' not in r.stderr:
        print(f"PSQL_ERR: {r.stderr.strip()}", file=sys.stderr)
        sys.exit(1 if 'ERROR' in r.stderr.upper() else 0)
    return r.stdout.strip()

# Check if admin user already exists
existing = psql(f"SELECT id FROM \"user\" WHERE email='{ADMIN_EMAIL}'")
if existing:
    ws = psql(f"SELECT wu.\"workspaceId\" FROM workspace_user wu JOIN \"user\" u ON u.id=wu.\"userId\" WHERE u.email='{ADMIN_EMAIL}' LIMIT 1")
    ak = psql(f"SELECT \"apiKey\" FROM apikey WHERE \"keyName\"='admin-key' LIMIT 1")
    print(f"EXISTS=1")
    print(f"WORKSPACE_ID={ws}")
    print(f"API_KEY={ak}")
    sys.exit(0)

PASSWORD_HASH = "$2a$10$.ovJgFwQxkOD7kmprvgESO.dbk796zCT9qSFZNhmhgvCxo5rKfDe2"

# Get roles
owner_role = psql("SELECT id FROM role WHERE name='owner'")
ws_role    = psql("SELECT id FROM role WHERE name='personal workspace'")

user_id = str(uuid.uuid4())
org_id  = str(uuid.uuid4())
ws_id   = str(uuid.uuid4())

# User (column is 'credential' in 3.x, not 'password')
psql(f"INSERT INTO \"user\" (id, email, credential, name, status, \"createdDate\", \"updatedDate\", \"createdBy\", \"updatedBy\") VALUES ('{user_id}', '{ADMIN_EMAIL}', '{PASSWORD_HASH}', '{ADMIN_NAME}', 'ACTIVE', NOW(), NOW(), '{user_id}', '{user_id}')")

# Organization
psql(f"INSERT INTO organization (id, name, \"createdDate\", \"updatedDate\", \"createdBy\", \"updatedBy\") VALUES ('{org_id}', 'Default', NOW(), NOW(), '{user_id}', '{user_id}')")

# Organization user
psql(f"INSERT INTO organization_user (\"organizationId\", \"userId\", \"roleId\", status, \"createdDate\", \"updatedDate\", \"createdBy\", \"updatedBy\") VALUES ('{org_id}', '{user_id}', '{owner_role}', 'active', NOW(), NOW(), '{user_id}', '{user_id}')")

# Workspace
psql(f"INSERT INTO workspace (id, name, \"organizationId\", \"createdDate\", \"updatedDate\", \"createdBy\", \"updatedBy\") VALUES ('{ws_id}', 'Default Workspace', '{org_id}', NOW(), NOW(), '{user_id}', '{user_id}')")

# Workspace user
psql(f"INSERT INTO workspace_user (\"workspaceId\", \"userId\", \"roleId\", status, \"lastLogin\", \"createdDate\", \"updatedDate\", \"createdBy\", \"updatedBy\") VALUES ('{ws_id}', '{user_id}', '{ws_role}', 'active', NOW(), NOW(), NOW(), '{user_id}', '{user_id}')")

# API key (Flowise format: base64url key + scrypt hash)
raw_key = secrets.token_bytes(32)
api_key = base64.urlsafe_b64encode(raw_key).decode().rstrip('=')
salt = secrets.token_bytes(8).hex()
secret_hash = hashlib.scrypt(api_key.encode(), salt=salt.encode(), n=16384, r=8, p=1, dklen=64).hex() + '.' + salt
key_id = str(uuid.uuid4())
perms = json.dumps([
    "chatflows:view","chatflows:create","chatflows:update","chatflows:duplicate",
    "chatflows:delete","chatflows:export","chatflows:import","chatflows:config","chatflows:domains",
    "agentflows:view","agentflows:create","agentflows:update","agentflows:duplicate",
    "agentflows:delete","agentflows:export","agentflows:import","agentflows:config","agentflows:domains",
    "tools:view","tools:create","tools:update","tools:delete","tools:export",
    "assistants:view","assistants:create","assistants:update","assistants:delete",
    "credentials:view","credentials:create","credentials:update","credentials:delete","credentials:share",
    "variables:view","variables:create","variables:update","variables:delete",
    "apikeys:view","apikeys:create","apikeys:delete",
    "documentStores:view","documentStores:create","documentStores:update","documentStores:delete",
    "documentStores:add-loader","documentStores:delete-loader","documentStores:preview-process","documentStores:upsert-config",
    "datasets:view","datasets:create","datasets:update","datasets:delete",
    "evaluators:view","evaluators:create","evaluators:update","evaluators:delete",
    "evaluations:view","evaluations:create","evaluations:update","evaluations:delete","evaluations:run",
    "templates:marketplace","templates:custom","templates:custom-delete","templates:toolexport","templates:flowexport","templates:custom-share",
    "workspace:export","workspace:import",
    "executions:view","executions:delete"
])
psql(f"INSERT INTO apikey (id, \"apiKey\", \"apiSecret\", \"keyName\", \"updatedDate\", \"workspaceId\", permissions) VALUES ('{key_id}', '{api_key}', '{secret_hash}', 'admin-key', NOW(), '{ws_id}', '{perms}'::jsonb)")

print(f"EXISTS=0")
print(f"WORKSPACE_ID={ws_id}")
print(f"API_KEY={api_key}")
PYEOF
)

echo "$BOOTSTRAP_OUT" | grep -v "^$"

WORKSPACE_ID=$(echo "$BOOTSTRAP_OUT" | grep "^WORKSPACE_ID=" | cut -d= -f2)
API_KEY=$(echo "$BOOTSTRAP_OUT" | grep "^API_KEY=" | cut -d= -f2)
EXISTS=$(echo "$BOOTSTRAP_OUT" | grep "^EXISTS=" | cut -d= -f2)

if [ "$EXISTS" = "1" ]; then
    log "Admin user already exists."
else
    log "Admin user created. API key: $API_KEY"
fi
log "Workspace ID: $WORKSPACE_ID"

if [ -n "$API_KEY" ]; then
    log "API key: $API_KEY"
fi

# ---- Import flows ----
export WORKSPACE_ID
export POSTGRES_HOST POSTGRES_DB POSTGRES_USER POSTGRES_PASSWORD
if [ ! -d "$FLOWS_DIR" ]; then
    log "Flows directory $FLOWS_DIR does not exist. Nothing to import."
    exit 0
fi

shopt -s nullglob
FLOW_FILES=("$FLOWS_DIR"/*.json)
shopt -u nullglob

if [ ${#FLOW_FILES[@]} -eq 0 ]; then
    log "No .json files found in $FLOWS_DIR. Nothing to import."
    exit 0
fi

python3 <<-'PYEOF'
import json, os, uuid, subprocess, sys

host = os.environ['POSTGRES_HOST']
db   = os.environ['POSTGRES_DB']
user = os.environ['POSTGRES_USER']
pw   = os.environ.get('POSTGRES_PASSWORD', '')
ws_id = os.environ.get('WORKSPACE_ID', '')
flows_dir = '/init/flows'

def psql(sql):
    env = os.environ.copy()
    env['PGPASSWORD'] = pw
    r = subprocess.run(
        ['psql', '-h', host, '-U', user, '-d', db, '-t', '-A', '-c', sql],
        capture_output=True, text=True, env=env)
    return r.stdout.strip()

existing = set()
for row in psql(f"SELECT name FROM chat_flow WHERE \"workspaceId\"='{ws_id}'").split('\n'):
    if row:
        existing.add(row)

has_error = False

for fname in sorted(os.listdir(flows_dir)):
    if not fname.endswith('.json'):
        continue
    fpath = os.path.join(flows_dir, fname)
    with open(fpath) as f:
        data = json.load(f)
    flow_name = data.get('name', '')
    if not flow_name:
        print(f"[import-flows] ERROR: No name in {fname}. Skipping.")
        has_error = True
        continue

    if flow_name in existing:
        print(f"[import-flows] SKIP: flow '{flow_name}' already exists ({fname})")
        continue

    flow_data = data.get('flowData', json.dumps(data))
    flow_id = str(uuid.uuid4())

    # Use random delimiter for dollar-quoting to avoid clashes with JSON content
    delim = f"FLOWDATA_{uuid.uuid4().hex[:12]}"
    sql = f"""INSERT INTO chat_flow (id, name, "flowData", type, "workspaceId", "createdDate", "updatedDate")
VALUES ('{flow_id}', '{flow_name.replace(chr(39), chr(39)+chr(39))}',
        ${delim}${flow_data}$${delim}$,
        'CHATFLOW', '{ws_id}', NOW(), NOW())"""
    psql(sql)
    print(f"[import-flows] OK: flow '{flow_name}' imported ({fname})")

if has_error:
    sys.exit(1)
PYEOF

log "All flows imported successfully."
exit 0
