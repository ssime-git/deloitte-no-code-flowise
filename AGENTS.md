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

#### fileLoader (v2.0)
- anchors: `textSplitter` (TextSplitter) — do NOT include in inputParams
- params: `file`, `usage`, `legacyBuild`, `pointerName`, `metadata`, `omitMetadataKeys`
- runtime caveat: `inputs.file` must exist in `flowData` even before the first upload. Use `""` as default value when importing flows via DB insert, otherwise Flowise can crash at runtime with `TypeError: Cannot read properties of undefined (reading 'startsWith')` in `File_DocumentLoaders.init`

#### bufferMemory (v2)
- anchors: none
- params: `sessionId`, `memoryKey`

#### conversationChain
- anchors: `model` (BaseChatModel), `memory` (BaseMemory, optional)
- params: `systemMessagePrompt` (string)

#### toolAgent (v2)
- anchors: `tools` (Tool, list), `memory` (BaseChatMemory, optional), `model` (BaseChatModel), `chatPromptTemplate` (ChatPromptTemplate, optional), `inputModeration` (Moderation, optional, list)
- params: `systemMessage` (string, additionalParams), `maxIterations` (number, optional, additionalParams), `enableDetailedStreaming` (boolean, optional, additionalParams)
- baseClasses: `AgentExecutor`, `BaseChain`, `Runnable`
- requires a model with function/tool calling support (ChatOpenAI, ChatAnthropic, etc.)

#### calculator (v1)
- anchors: none
- params: none
- baseClasses: `Calculator`, `Tool`, `StructuredTool`, `Runnable`

#### currentDateTime (v1)
- anchors: none
- params: none
- baseClasses: `CurrentDateTime`, `Tool`

#### retrieverTool (v3)
- anchors: `retriever` (BaseRetriever)
- params: `name` (string), `description` (string), `returnSourceDocuments` (boolean, optional), `retrieverToolMetadataFilter` (json, optional, additionalParams)
- baseClasses: `RetrieverTool`, `DynamicTool`, `Tool`, `StructuredTool`, `Runnable`
- the `name` and `description` fields are exposed to the LLM — clear descriptions are critical for correct tool selection
- `returnSourceDocuments: true` adds source metadata to the prediction response under `sourceDocuments`

#### customMCP (v1.1)
- anchors: none
- params: `mcpServerConfig` (code), `mcpActions` (asyncMultiOptions, refresh=true)
- baseClasses: `Tool`
- for remote MCP over HTTP, use a config object with no `command`, for example:
  - `{"url": "http://mcp-server:8000/mcp"}`
- when `command` is absent, Flowise treats the MCP server as remote HTTP transport
- selected actions are stored in `inputs.mcpActions` and must be present in imported flow JSON
- for FastMCP streamable HTTP, the canonical endpoint path is `/mcp`, not `/health`

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

### Chat uploads in Flowise

Flowise supports two file upload modes in chatflows:
- **RAG file uploads**: uploaded files are upserted to a compatible vector store
- **Full file uploads**: uploaded files are parsed by `fileLoader` and injected directly into the chat flow

For **Full file uploads** on Flowise 3.1.2:
- `chatbotConfig` must contain `fullFileUpload.status = true`
- the chatflow must include a `fileLoader` node
- if both full uploads and RAG uploads are enabled, full uploads take precedence

For J2 with **In-Memory Vector Store**:
- a `fileLoader` node can be connected to `memoryVectorStore.document` for learner testing
- `folderFiles` and `fileLoader` can coexist on the same `document` input
- after import, verify both startup upsert and normal prediction, because `fileLoader` can break both paths if its `inputs.file` default is missing

### MCP tools in J5

For `J5 - Agent MCP`:
- start the stack with profile `mcp`
- in the local training stack, Flowise must run with:
  - `HTTP_SECURITY_CHECK=false`
  - `CUSTOM_MCP_SECURITY_CHECK=false`
  otherwise `Custom MCP` cannot reach the private Docker network host `mcp-server`
- the Flowise `Custom MCP` node should point to `http://mcp-server:8000/mcp`
- use governed actions only:
  - `get_audit_scope`
  - `aggregate_preprocessed_dsn_like`
  - `get_exception_investigation_case`
  - `search_documentary_sources`
- the pedagogical goal is not raw data access, but controlled exposure:
  - scope
  - aggregation
  - sanitized exception dossier
  - targeted documentary lookup

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
| `mcp-health` | Healthcheck for the MCP server on port 8001 |
| `psql` | Open PostgreSQL shell |
| `wait-init` | Wait until init finished bootstrap and flows are visible via API |
| `test-j1` | Test J1 prediction |
| `test-j2` | Test J2 prediction |
| `test-j2-nir` | Test J2 with the fictitious NIR question |
| `smoke-j2` | Run the main J2 smoke tests on a running stack |
| `reset-smoke-j2` | Force reset, reimport everything, then run J2 smoke tests |
| `from-scratch-j2` | Simple alias for `reset-smoke-j2` |
| `test-j4` | Test J4 prediction — agent calls calculator (CSG question) |
| `test-j4-date` | Test J4 prediction — agent calls CurrentDateTime (DSN period question) |
| `test-j4-rag` | Test J4 prediction — agent RAG searches the corpus |
| `test-j4-rag-combo` | Test J4 prediction — agent RAG combines retrieval + calculation |
| `smoke-j4` | Run the main J4 smoke tests on a running stack (agent simple + agent RAG) |
| `reset-smoke-j4` | Force reset, reimport everything, then run J4 smoke tests |
| `from-scratch-j4` | Simple alias for `reset-smoke-j4` |
| `test-j5-scope` | Test J5 prediction — MCP scope and governed perimeter |
| `test-j5-aggregate` | Test J5 prediction — MCP aggregated DSN-like view |
| `test-j5-case` | Test J5 prediction — MCP exception investigation dossier |
| `smoke-j5` | Run the main J5 smoke tests on a running stack with MCP |
| `reset-smoke-j5` | Force reset with profile `mcp`, reimport everything, then run J5 smoke tests |
| `from-scratch-j5` | Simple alias for `reset-smoke-j5` |
| `docs` | List training docs |

### Recommended operator path

For a full reproducible setup from scratch, prefer:

```bash
make from-scratch-j2
```

For the MCP day, prefer:

```bash
make from-scratch-j5
```

This target:
1. resets the stack and volumes
2. restarts Flowise + PostgreSQL
3. waits for init bootstrap completion
4. verifies imported chatflows through the API
5. runs the main J2 smoke tests

`from-scratch-j5` does the same, but starts the stack with `COMPOSE_PROFILE=mcp` so that the `mcp-server` container is available for the `Custom MCP` tool.

## AgentFlow V2 execution/resume pitfalls

### Human Input resume and persistent state

For `AgentFlow V2`, `Human Input` resumes are tied to the previous execution in the same session.

Important runtime behavior observed on Flowise 3.1.2:
- `startPersistState: true` on `startAgentflow` is required if the flow must preserve `$flow.state` across a `Human Input` pause/resume.
- Without it, values such as `final_report` can be lost on resume, causing empty direct replies or an unintended restart path.
- On resume, Flowise reloads the last stored state from the previous execution data, then continues from the stopped node.

### Loop count limitation across Human Input resumes

In Flowise 3.1.2, `buildAgentflow.js` recreates `loopCounts = new Map()` when an execution is resumed after `Human Input`.

Consequence:
- `maxLoopCount` only protects loops within a single uninterrupted execution.
- It does **not** reliably protect a loop that goes through repeated `Human Input` proceed/reject resumes, because the counter restarts after each resume.

For guarded review/revision flows like J6:
- do not rely on `maxLoopCount` alone for cross-resume protection
- prefer an explicit persistent state field such as `revision_count`
- update that state in `loopUpdateState` or worker outputs, and make the supervisor prompt respect it

### Updating AGENTFLOW JSON through the API

For `PUT /api/v1/chatflows/:id` on Flowise 3.1.2:
- `flowData` must be sent as a **JSON string**, not as an object
- reusing the payload shape returned by `GET /api/v1/chatflows/:id` is safest
- sending `flowData` as an object can trigger `500` with `"[object Object]" is not valid JSON`

## AgentFlow V2 pitfalls

### Importable is not enough

For Flowise `AgentFlow V2`, a flow JSON can be:
- importable
- executable

while still being **wrong for the UI**.

Typical symptoms:
- `Node version ... outdated`
- missing or partially empty config panel
- node parameters not editable in the right sidebar

This already happened in this repo on `J6 - Multi-Agent Supervised`.

### Rule for manual AgentFlow edits

Do not consider an `AGENTFLOW` node correct just because the flow runs.

When editing `AgentFlow V2` JSON manually:
- verify the **exact installed node version**
- mirror the **full native `inputParams` schema**
- preserve the real UI metadata, especially:
  - `array`
  - `show`
  - `hide`
  - `optional`
  - `acceptVariable`
  - `acceptNodeOutputAsVariable`
  - `loadMethod`
  - `loadConfig`
  - `placeholder`
  - `default`
- preserve companion `inputs` values expected by those params

For `CHATFLOW`, reduced schemas can sometimes work.

For `AGENTFLOW`, prefer the **full native node schema**.

### AgentFlow versions validated against Flowise 3.1.2

Observed node versions:
- `startAgentflow` = `1.1`
- `llmAgentflow` = `1.1`
- `conditionAgentflow` = `1.0`
- `agentAgentflow` = `3.2`
- `loopAgentflow` = `1.2`
- `humanInputAgentflow` = `1.0`
- `directReplyAgentflow` = `1.0`

If these are mismatched in imported JSON, expect `outdated` warnings.

### Success criteria for AgentFlow work

Do not claim an AgentFlow is fully correct unless all three are true:
1. the flow imports
2. the flow runs
3. the nodes remain editable in the Flowise UI without `outdated` warnings

If `3` fails, the JSON still needs alignment.

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
