# btca (better-context)

btca is installed globally and configured to get up-to-date Flowise documentation from source code.

## Usage

```bash
# Ask a question about Flowise
btca ask -r flowise -q "your question"

# Add a new resource
btca add https://github.com/owner/repo --name resource-name

# Check status
btca status
```

## Configuration

btca uses the local LiteLLM proxy for LLM calls. Config is in `btca.config.jsonc`:

- provider: `openai-compat`
- model: `claude-haiku-4-5`
- baseURL: `http://localhost:4000/v1`
- searchPaths: `packages/api-documentation`, `packages/server`, `packages/ui/src/api`

This config is **independent of btca's npm package updates** - updates to btca (via `npm update -g btca`) will NOT break the config. If a future btca version changes its config schema, check https://docs.btca.dev/guides/configuration and update `btca.config.jsonc` accordingly.

## How to re-add a resource with search paths (if needed)

```bash
btca remove flowise
btca add https://github.com/FlowiseAI/Flowise --name flowise --search-path packages/api-documentation --search-path packages/server --search-path packages/ui/src/api
```

## Interacting with Flowise 3.1.2

### Auth model

Flowise 3.1.2 requires authentication for all API routes except `/api/v1/ping` and `/api/v1/version`.

Two auth methods:

1. **API Key** (recommended for scripts): pass `Authorization: Bearer <key>` header. Keys are stored in PostgreSQL `apikey` table with scrypt-hashed secrets.

2. **JWT + session** (browser): `POST /api/v1/auth/login` with `{email, password}` sets cookies (JWT token + refreshToken + session). Sessions are Express-session based, backed by the database.

Note: `FLOWISE_USERNAME`/`FLOWISE_PASSWORD` env vars do NOT create users automatically in 3.1.2. Admin user must be inserted into the `user` table with a bcrypt-hashed password, along with organization, workspace, and role records.

### Login flow

```
POST /api/v1/auth/login
Body: { "email": "...", "password": "..." }
→ Sets cookies: token (JWT), refreshToken, connect.sid (session)
```

### API access flow

After login, the JWT token in the cookie is verified by passport-jwt middleware. However, the API key check middleware (`dist/index.js:184`) requires an API key for all non-whitelisted routes. To make API calls:

- **From scripts**: create an API key in the `apikey` table, use it in `Authorization: Bearer` header
- **From init container**: the import script writes flows directly to PostgreSQL

### Key technical details

- **Password hashing**: bcrypt with 10 salt rounds
- **API key generation**: `crypto.randomBytes(32).toString('base64url')` for key, `crypto.scryptSync(key, salt, 64)` for secret hash (format: `hash.salt`)
- **Auth middleware order**: session → passport → auth routes (`/api/v1/auth/*`) → API key middleware → routes router (`/api/v1/*`)
- **Identity platforms**: OPEN_SOURCE, ENTERPRISE, CLOUD. Without `FLOWISE_EE_LICENSE_KEY`, defaults to OPEN_SOURCE

### Database tables

| Table | Purpose |
|-------|---------|
| `user` | Users (email, password hash, status) |
| `organization` | Organizations |
| `organization_user` | User-org membership (with role) |
| `workspace` | Workspaces (belongs to org) |
| `workspace_user` | User-workspace membership |
| `chat_flow` | Flow definitions |
| `apikey` | API keys (apiKey, apiSecret with scrypt hash, permissions) |
| `role` | Roles (owner, member, personal workspace) with permission JSON |

### Init container flow

The `init` container runs `import-flows.sh` on startup to:
1. Wait for Flowise via healthcheck on `/api/v1/ping`
2. Bootstrap admin user, workspace, and API key in PostgreSQL
3. Import flow definitions (JSON exports) directly via PostgreSQL insert

It connects to PostgreSQL directly for all operations.

### Reset procedure

`reset.sh` stops the stack, removes Docker volumes (`pgdata`, `flowise_data`), and restarts clean. On next startup:
1. Flowise creates DB tables via TypeORM migrations
2. Init container creates admin user + bootstraps everything
3. All flows are imported

This ensures a reproducible state for each training session.

## Auth quick reference

### API Key (scripts)

```bash
API_KEY="$(docker logs deloitte-no-code-flowise-init-1 2>/dev/null | grep 'API key:' | tail -1 | awk '{print $NF}')"

curl -H "Authorization: Bearer $API_KEY" http://localhost:3000/api/v1/chatflows
```

### Login + cookies (browser)

```bash
curl -c cookies.txt -X POST http://localhost:3000/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@local.dev","password":"changeme_admin_password"}'

curl -b cookies.txt http://localhost:3000/api/v1/chatflows
```

### Créer une API Key manuellement (DB)

```bash
docker exec -i deloitte-no-code-flowise-postgres-1 psql -U flowise -d flowise <<'SQL'
INSERT INTO apikey (id, "apiKey", "apiSecret", "keyName", "updatedDate", "workspaceId", permissions)
VALUES (gen_random_uuid(), '<cle>', '<hash.salt>', 'admin-key', NOW(), '<workspace-id>',
        '["chatflows:view","chatflows:create","chatflows:update","chatflows:delete"]'::jsonb);
SQL
```

### Endpoints principaux

| Endpoint | Méthode | Auth |
|----------|---------|------|
| `/api/v1/ping` | GET | Non |
| `/api/v1/version` | GET | Non |
| `/api/v1/auth/login` | POST | Non |
| `/api/v1/chatflows` | GET | API Key |
| `/api/v1/chatflows/:id` | GET | API Key |
| `/api/v1/prediction/:id` | POST | API Key |

### Prédiction

```bash
curl -X POST "http://localhost:3000/api/v1/prediction/<flow-id>" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"question": "Bonjour, qui es-tu ?"}'
```

### Troubleshooting

Login 401 → vérifier l'utilisateur en base :
```bash
docker exec -i deloitte-no-code-flowise-postgres-1 psql -U flowise -d flowise \
  -c "SELECT email, status FROM \"user\";"
```

API 403 Forbidden → vérifier les permissions de l'API key :
```bash
docker exec -i deloitte-no-code-flowise-postgres-1 psql -U flowise -d flowise \
  -c "SELECT \"keyName\", permissions FROM apikey;"
```
