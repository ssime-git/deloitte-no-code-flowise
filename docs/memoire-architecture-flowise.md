# Mémoire : Adoption de Flowise comme outil unique pour la formation IA no-code

## Date
2026-05-20

## Programme de formation supporté
`../deloitte-ia-nocode/docs/programme-formation-ia-audit-v2.md`  
Formation 7 jours : conception d'un assistant d'audit paie/DSN no-code

## Décision
Adopter **Flowise** comme outil unique couvrant l'intégralité du programme 7 jours, en remplacement de l'architecture duale **Open WebUI (J1-J2) + n8n (J3-J7)**.

## Problème résolu
L'architecture précédente nécessitait deux outils (Open WebUI pour le chat/RAG, n8n pour les workflows/agents/MCP). Cela imposait un changement d'interface à J3 et complexifiait la progression pédagogique.

Flowise couvre seul :
- Chat LLM et prompting (J1)
- Comparaison de modèles et réglages (J2)
- Pipeline RAG visuel et fiabilité (J3)
- Agents et agent RAG (J4)
- MCP et accès contrôlé aux données (J5)
- Multi-agents + HITL (J6)
- Projet final (J7)

## Contraintes
- Public : auditeurs non-développeurs, zéro code
- RGPD : doit tourner en local / privé
- Pédagogie : doit montrer le mécanisme (pas boîte noire)
- Faible coût API
- Si possible outil unique pour les 7 jours
- Utilisation de MCP et API pour connecter des systèmes externes (CRM, ERP, etc.)

## Version Flowise
**`flowiseai/flowise:3.1.2`** (avril 2026) — version stable après correctifs de sécurité CVE-2026-41264, CVE-2026-41265, CVE-2026-41279.

## Architecture cible

```
┌──────────────────────────────────────────────┐
│  docker-compose                               │
│                                                │
│  ┌──────────┐  ┌──────────┐  ┌────────────┐ │
│  │ Flowise  │  │ Postgres │  │ MCP Server │ │
│  │ :3000    │  │ :5432    │  │ :8001      │ │
│  └────┬─────┘  └──────────┘  └────────────┘ │
│       │             │                          │
│       │   données   │                          │
│  ┌────▼─────────────▼────────────────────┐    │
│  │  Volumes partagés                       │    │
│  │  - ./data/     (DSN like fictif)        │    │
│  │  - ./corpus/   (documents RAG)          │    │
│  │  - ./project/  (exercices apprenants)   │    │
│  └─────────────────────────────────────────┘    │
└──────────────────────────────────────────────┘
```

- **Flowise** stocke flows, credentials et configs dans PostgreSQL (pas de SQLite en prod)
- **Vector store** : Chroma intégré (fichier local, zéro infrastructure)
- **MCP Server** : serveur Python Dockerisé, à mettre à jour vers Streamable HTTP (cf. [#MCP-Transport](#mcp-transport))
- **PostgreSQL** : base partagée pour Flowise + éventuels outils MCP
- **Build** : tout service Python utilise `uv` dans son Dockerfile (copie statique de `uv` via `ghcr.io/astral-sh/uv`) — pas de `pip` à chaud
- **Run** : tout service tourne dans Docker Compose — pas de binaire local, pas d'install système

## Spécifications Docker Compose

```yaml
services:
  postgres:
    image: postgres:16-alpine
    restart: unless-stopped
    networks: [training_net]
    volumes:
      - pgdata:/var/lib/postgresql/data
    environment:
      POSTGRES_DB: ${POSTGRES_DB:-flowise}
      POSTGRES_USER: ${POSTGRES_USER:-flowise}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER:-flowise} -d ${POSTGRES_DB:-flowise}"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 30s

  flowise:
    image: flowiseai/flowise:3.1.2
    restart: unless-stopped
    networks: [training_net]
    depends_on:
      postgres:
        condition: service_healthy
    ports:
      - "${FLOWISE_PORT:-3000}:3000"
    extra_hosts:
      - "host.docker.internal:host-gateway"
    volumes:
      - flowise_data:/root/.flowise
      - ./data:/data:ro
      - ./corpus:/corpus:ro
      - ./project:/project:ro
    environment:
      PORT: 3000
      DATABASE_TYPE: postgres
      DATABASE_PORT: 5432
      DATABASE_HOST: postgres
      DATABASE_NAME: ${POSTGRES_DB:-flowise}
      DATABASE_USER: ${POSTGRES_USER:-flowise}
      DATABASE_PASSWORD: ${POSTGRES_PASSWORD}
      FLOWISE_USERNAME: ${FLOWISE_USERNAME:-admin}
      FLOWISE_PASSWORD: ${FLOWISE_PASSWORD}
      DEBUG: ${DEBUG:-false}
      LOG_LEVEL: ${LOG_LEVEL:-info}
      APIKEY_PATH: /root/.flowise/apikeys
      SECRETKEY_PATH: /root/.flowise
      GENERIC_TIMEZONE: ${TIMEZONE:-Europe/Paris}

  mcp-server:
    build: ./mcp-server
    restart: unless-stopped
    profiles: [mcp]
    networks: [training_net]
    depends_on:
      postgres:
        condition: service_healthy
    ports:
      - "${MCP_SERVER_PORT:-8001}:8000"
    extra_hosts:
      - "host.docker.internal:host-gateway"
    volumes:
      - ./data:/data:ro
      - ./corpus:/corpus:ro
    environment:
      POSTGRES_HOST: postgres
      POSTGRES_DB: ${POSTGRES_DB:-flowise}
      POSTGRES_USER: ${POSTGRES_USER:-flowise}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      DATA_DIR: /data
      CORPUS_DIR: /corpus
      FASTMCP_HOST: 0.0.0.0
      FASTMCP_PORT: "8000"
      OPENAI_BASE_URL: ${OPENAI_GATEWAY_BASE_URL:-https://ai-gateway.liora.tech/v1}
      OPENAI_API_KEY: ${OPENAI_GATEWAY_API_KEY:-}

volumes:
  pgdata:
  flowise_data:

networks:
  training_net:
    driver: bridge
```

Le service `mcp-server` est optionnel (profil `mcp`). Pour un démarrage minimal (Flowise + Postgres seul) :

```bash
docker compose up -d postgres flowise
```

Tous les services sont exclusivement déployés via Docker Compose. Les dépendances Python sont installées par `uv` dans les Dockerfiles (pas de `pip` système, pas de venv local).

## MCP Transport

Le MCP Server (`./mcp-server/server.py`) utilise `mcp.sse_app()` (transport SSE legacy). Flowise 3.1.2 attend du **Streamable HTTP**. Mise à jour nécessaire :

1. `requirements.txt` : `mcp[cli]>=1.27.1`
2. `server.py` : `mcp.sse_app()` → `mcp.streamable_http_app()`

Corrigé avant intégration J6.

## Planning final jour par jour

| Jour | Sujet | Dans Flowise |
|------|-------|-------------|
| J1 | Introduction à l'IA et prompting de base | Interface chat intégrée. Prompt simple, rôle/contexte/tâche/format, premières limites, premiers cas audit |
| J2 | Psychologie des modèles et prompting avancé | Multi-modèles (OpenAI/Claude/Gemini/Ollama), température/tokens, prompt système, few-shot, comparaison de réponses, confidentialité appliquée |
| J3 | RAG, fiabilité, citations | Pipeline visuel : Document Loader → Text Splitter → Embeddings → Vector Store. Comparaison avec/sans RAG. `sourceDocuments`, double check, cas limites |
| J4 | Agents avec Flowise | Agent node, system prompt agentique, tools, mémoire, différence chat vs agent. Construction d'un agent simple puis d'un agent RAG |
| J5 | MCP et accès contrôlé aux données | MCP Stdio + Streamable HTTP nodes. SQL Agent PostgreSQL. Requêtes ciblées, filtrage, agrégation, exposition d'outils plutôt qu'envoi brut |
| J6 | Systèmes multi-agents et validation humaine | AgentFlow V2, Supervisor, outils partagés, Human Input node, distribution des rôles, point d'arrêt de validation |
| J7 | Projet final | Assemblage complet : ingestion, contrôle, assistance documentaire, validation humaine, rapport, grille de fiabilité |

## Roadmap des flows pédagogiques

L'objectif est de faire progresser les apprenants dans Flowise sans changer d'outil ni de paradigme visuel. Chaque flow sert de support de démo, de manipulation et de reconstruction partielle ou complète.

| Flow | Jour | Rôle pédagogique | Contenu attendu |
|---|---|---|---|
| Flow 1 | J1-J2 | Chat d'acculturation et prompting | Chat simple, changement de modèle, température, prompt system, few-shot, tests de confidentialité |
| Flow 2 | J3 | Assistant documentaire RAG | Corpus DSN, ingestion dossier + upload manuel, embeddings, vector store, retrieval, réponse sourcée, tests de fiabilité |
| Flow 3 | J4 | Introduction aux agents | Agent simple avec prompt agentique, outils ciblés, mémoire, explication du cycle agentique |
| Flow 4 | J4 | Agent RAG | Agent branché sur la base documentaire J3 pour comparer QA chain vs agent RAG |
| Flow 5 | J5 | Agent connecté via MCP | Appels outillés vers vues de données, filtres, agrégations, requêtes contrôlées |
| Flow 6 | J6 | Multi-agent supervisé | Plusieurs agents spécialisés, orchestration, validation humaine, restitution consolidée |
| Flow 7 | J7 | Prototype final | Flow complet assemblant les briques utiles au cas d'usage d'audit |

## Progression pédagogique retenue

La progression finale suit une logique de maturité d'usage plutôt qu'une logique d'inventaire des concepts :

1. parler correctement à un modèle
2. comprendre que tous les modèles ne répondent pas pareil
3. fiabiliser les réponses avec une base documentaire
4. passer du chat à l'agent
5. connecter l'agent à des outils et données de façon contrôlée
6. faire collaborer plusieurs agents sous supervision humaine
7. assembler un prototype métier cohérent

Cette progression rend le passage au `Flow 3` plus naturel : les apprenants ont déjà vu le prompt, les réglages de modèle et le RAG avant d'aborder la logique agentique.

## Constats

### Forces
- **Outil unique** : progression linéaire J1→J7, pas de changement d'interface
- **Pipeline RAG visuel** : montre chunk → embed → retrieve → generate, idéal pour la pédagogie
- **Agents natifs** plus riches que n8n (ReAct, Tool, OpenAI Assistant, Supervisor)
- **MCP natif** : Stdio + HTTP prêts à l'emploi
- **Extensible via API** : API REST complète (création de chatflows, upsert vector, prédiction)
- **Éditeur drag-and-drop** : aucune ligne de code pour les apprenants

### Limites
- **Pas de connecteurs CRM/ERP natifs** — rattrapé via HTTP Request + MCP
- **Workflow automation moins riche que n8n** (400 connecteurs vs API/MCP)
- **Pas de scheduler intégré** (triggers temporels limités)
- **Citations RAG** dans le champ `sourceDocuments` de l'API, pas sous forme de numéros cliquables dans l'UI
- **Sécurité** : historique de CVE critiques sandbox Python (patché en 3.1.0)

### Risques
- **Version 3.1.2** : correctifs sécurité appliqués, mais les agents CSV/Airtable restent des surfaces d'attaque potentielles
- **Formation en local** : aucune exposition publique → risque neutralisé

## Artefacts

| Fichier | Rôle |
|---|---|
| `init/import-flows.sh` | Importe les flows `.json` de `init/flows/` dans Flowise au démarrage |
| `init/flows/README.md` | Instructions pour placer les exports JSON |
| `reset.sh` | Réinitialise la stack (volumes + `project/`) entre sessions |
| `mcp-server/server.py` | MCP Server, transport Streamable HTTP |
| `mcp-server/requirements.txt` | `mcp[cli]>=1.27.1` |

### Import des flows démo

```bash
docker compose --profile init up -d
```

### Reset entre sessions

```bash
./reset.sh          # demande confirmation
./reset.sh -f       # force
COMPOSE_PROFILE=mcp ./reset.sh  # avec MCP Server
```

## Décisions résolues

| Question | Décision |
|---|---|
| Vector store | Chroma intégré (fichier local, zéro infra) |
| MCP Server conserver ? | Oui, upgrade Streamable HTTP fait |
| Mode apprenant | Espace partagé, un seul Flowise |
| Mode RGPD (Gateway Liora) | OK pour la démo, mentionné dans les slides |
| Volume écriture J7 | Export UI + PostgreSQL suffit |
| Import flows démo | Script créé : `init/import-flows.sh` |
| Reset entre sessions | Script créé : `reset.sh` |
