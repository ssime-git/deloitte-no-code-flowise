# Deloitte No-Code Flowise — Agent Knowledge

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

After login, the JWT token in the cookie is verified by passport-jwt middleware. However, the API key check middleware requires an API key for all non-whitelisted routes. To make API calls:

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

## Flow structure rules

### Config panel rendering

Flowise stores node configuration split into three fields in `flowData`:

- **`inputAnchors`**: connection-type inputs (type=`BaseChatModel`, `Embeddings`, `TextSplitter`, `BaseRetriever`, `BaseMemory`, etc.)
- **`inputParams`**: form fields rendered in the right config panel (type=`string`, `number`, `boolean`, `asyncOptions`, `options`, `json`, etc.)
- **`inputs`**: actual values for both anchors and params

When importing flows via DB insert (`INSERT INTO chat_flow`), Flowise does **not** auto-populate `inputAnchors` or `inputParams`. These must be correctly pre-populated in the JSON, otherwise:
- `inputParams = []` → clicking the node shows a blank config panel
- `textSplitter` in both `inputAnchors` AND `inputParams` → rendering conflict
- Missing anchor definitions → edge won't appear in canvas

### Component definitions (flowise-components v3.1.2)

Key node versions and their input structure:

#### chatOpenAI (v8.3)
- anchors: `cache` (BaseCache)
- params: `modelName`, `temperature`, `streaming`, `allowImageUploads`, `reasoning`, `maxTokens`, `topP`, `frequencyPenalty`, `presencePenalty`, `timeout`

#### openAIEmbeddings (v4)
- anchors: none
- params: `modelName`, `stripNewLines`, `batchSize`, `timeout`

#### memoryVectorStore (v1.0)
- anchors: `embeddings` (Embeddings), `document` (Document, list, optional)
- params: `topK` (number)

#### conversationalRetrievalQAChain (v3)
- anchors: `model` (BaseChatModel), `vectorStoreRetriever` (BaseRetriever), `memory` (BaseMemory, optional)
- params: `returnSourceDocuments` (boolean), `rephrasePrompt` (string), `responsePrompt` (string)

#### folderFiles (v4.0)
- anchors: `textSplitter` (TextSplitter) — do NOT include in inputParams
- params: `folderPath`, `recursive`, `pdfUsage`, `pointerName`, `metadata`, `omitMetadataKeys`

#### bufferMemory (v2)
- anchors: none
- params: `sessionId`, `memoryKey`

#### conversationChain
- anchors: `model` (BaseChatModel), `memory` (BaseMemory, optional)
- params: `systemMessagePrompt` (string)

### Version mismatch issue

When a node's `version` in flowData doesn't match the installed component version, Flowise shows "Node version X outdated Update to latest version Y" in the UI. More critically, this can cause:
- Edges to disappear from canvas (output anchor format changed between versions)
- PUT API endpoint may strip non-standard inputs during node rebuild

Example: `folderFiles` was v1 in flow data but v4 installed. The v1 `outputAnchors` had nested `options` objects; v4 has a flat format. Caused the edge to not render.

### Edge format

Flowise stores edges with `source`, `target`, `sourceHandle`, `targetHandle`, and optional `id`. The `sourceHandle`/`targetHandle` format must match the `id` of the corresponding output/input anchor. Handle IDs follow the pattern:
- Source: `{nodeId}-output-{nodeName}-{outputName}-{BaseClass1}|{BaseClass2}`
- Target: `{nodeId}-input-{inputName}-{Type}`

### Upsert behavior for In-Memory Vector Store

The upsert endpoint (`POST /api/v1/vector/upsert/:chatflowId`) runs the component's `vectorStoreMethods.upsert` but creates an ephemeral vector store. On prediction, the `init` method creates a fresh vector store from the `document` input (folderFiles output). This means:
- Upsert is not strictly needed for In-Memory (each prediction loads from scratch)
- But upsert is still required by the init script to verify the document loader works
- For persistent vector stores (Chroma, Pinecone, etc.), upsert is essential

## Makefile targets

| Target | Description |
|--------|-------------|
| `up` | Start all services |
| `down` | Stop all services |
| `reset` | Reset stack (with confirmation) |
| `force-reset` | Reset without confirmation |
| `status` | Container status |
| `logs-flowise` | Tail Flowise logs |
| `logs-init` | Show init bootstrap logs |
| `api-key` | Get generated API key |
| `ping` | Healthcheck |
| `psql` | Open PostgreSQL shell |
| `test-j1` | Test J1 prediction |
| `test-j2` | Test J2 prediction |
| `docs` | List training docs |

## Stack layout

```
docker-compose.yml
├── postgres:16-alpine
├── flowise:3.1.2
├── mcp-server (profile: mcp)
└── init (alpine, runs once)

init/import-flows.sh:
  1. Wait for Flowise ping
  2. Bootstrap: user + org + workspace + API key
  3. Create OpenAI credential via API
  4. Import flows via INSERT INTO chat_flow
  5. Upsert J2 vector store

Volume mounts:
  ./data → /data (read-only)
  ./corpus → /corpus (read-only)
  ./project → /project (read-only)
```
