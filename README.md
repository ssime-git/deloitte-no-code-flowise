# Deloitte No-Code Flowise

Stack pédagogique Flowise 3.1.2 + PostgreSQL pour la formation Liora.

## Prérequis

- Docker + Docker Compose v2
- Git

## Quick start

```bash
git clone https://github.com/ssime-git/deloitte-no-code-flowise.git
cd deloitte-no-code-flowise
make from-scratch-j2
```

Une seule commande. Elle remet la stack à zéro, redémarre PostgreSQL + Flowise, bootstrappe automatiquement l'utilisateur admin, l'API key et les flows J1/J2, puis exécute les smoke tests principaux du flow J2.

Pour un simple démarrage sans reset complet :

```bash
make up
```

Vérifier :
```bash
curl http://localhost:3000/api/v1/ping
# → pong
```

L'API key générée est visible dans les logs :
```bash
docker logs deloitte-no-code-flowise-init-1 | grep "API key:"
```

## Commandes utiles

```bash
make from-scratch-j2   # reset complet + import + smoke tests J2
make smoke-j2          # smoke tests J2 sur stack déjà lancée
make test-j2           # question URSSAF
make test-j2-nir       # question NIR fictif
make api-key           # affiche l'API key bootstrappee
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
make reset         # avec confirmation
make force-reset   # force
./reset.sh         # équivalent shell
./reset.sh -f      # équivalent shell
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
