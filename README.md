# Deloitte No-Code Flowise

Stack pédagogique Flowise 3.1.2 + PostgreSQL pour la formation Liora.

## Prérequis

- Docker + Docker Compose v2
- Git

## Quick start

```bash
git clone https://github.com/ssime-git/deloitte-no-code-flowise.git
cd deloitte-no-code-flowise
docker compose up -d
```

Une seule commande. Le conteneur `init` bootstrappe automatiquement l'utilisateur admin, l'API key et les flows J1/J2.

Vérifier :
```bash
curl http://localhost:3000/api/v1/ping
# → pong
```

L'API key générée est visible dans les logs :
```bash
docker logs deloitte-no-code-flowise-init-1 | grep "API key:"
```

## Connexion

| Info | Valeur |
|------|--------|
| URL | http://localhost:3000 |
| Email | admin@local.dev |
| Mot de passe | changeme_admin_password |

## Prompts de test

**J1 - Simple Chat** : *"Que peux-tu faire ?"*

**J2 - RAG Chat** : *"Quels sont les points de contrôle URSSAF et leurs seuils de tolérance ?"*

## Reset

```bash
./reset.sh         # avec confirmation
./reset.sh -f      # force
```

Arrête la stack, supprime les volumes PG et Flowise, nettoie `project/`, redémarre.

## Structure

```
├── docker-compose.yml    # postgres, flowise, init, mcp-server
├── .env                  # Variables d'environnement
├── init/
│   ├── import-flows.sh   # Bootstrap user + API key + import flows
│   └── flows/            # Flows J1-Simple-Chat, J2-RAG-Chat
├── data/                 # Données montées (RAG corpus)
├── corpus/               # Corpus de documents
├── project/              # Projets étudiants
├── mcp-server/           # Serveur MCP Python (profil mcp)
└── reset.sh              # Reset complet
```

## Architecture

```
Client ──▶ Flowise (3000) ──▶ PostgreSQL
               │
          init (bootstrap user, API key, flows)
```

## MCP Server

```bash
docker compose --profile mcp up -d
```

Expose un endpoint SSE sur le port 8001.
