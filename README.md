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

Pour les journées agents :

```bash
make from-scratch-j4   # agent simple + agent RAG
make from-scratch-j5   # agent MCP (avec profil mcp)
make from-scratch-j6   # multi-agent supervisé (avec profil mcp)
```

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
make from-scratch-j4   # reset complet + import + smoke tests J4
make from-scratch-j5   # reset complet + import + smoke tests J5 (profil mcp)
make from-scratch-j6   # reset complet + import + smoke tests J6 (profil mcp)
make smoke-j2          # smoke tests J2 sur stack déjà lancée
make smoke-j4          # smoke tests J4
make smoke-j5          # smoke tests J5
make smoke-j6          # smoke test J6 jusqu'au point de validation humaine
make test-j2           # question URSSAF
make test-j2-nir       # question NIR fictif
make test-j4           # agent simple - calcul
make test-j4-date      # agent simple - date
make test-j4-rag       # agent RAG - recherche
make test-j4-rag-combo # agent RAG - recherche + calcul
make test-j5-scope     # agent MCP - périmètre gouverné
make test-j5-aggregate # agent MCP - vue agrégée
make test-j5-case      # agent MCP - dossier d'exception
make test-j6           # multi-agent jusqu'au Human Input
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

**J4 - Agent Simple** : *"Calcule le montant de la CSG sur un salaire brut de 3200 euros. Le taux de CSG deductible est 6.8%."*

**J4 - Agent RAG** : *"Quels sont les seuils URSSAF a verifier dans un audit paie ? Cite tes sources."*

**J5 - Agent MCP** : *"Quel est le perimetre de donnees auditables disponible via tes outils ? Reponds sans inventer de lignes brutes."*

**J6 - Multi-Agent Supervised** : *"Un salarie presente une variation de brut de 18 pourcent et lexception EXC_URSSAF_AMOUNT_INCONSISTENT. Prepare une alerte daudit DSN exploitable par un auditeur."*

## Arrêter et relancer from scratch

Arrêter proprement la stack en cours :

```bash
make down
```

Repartir de zéro avec une stack entièrement recréée :

```bash
make from-scratch-j2   # stack standard + reset complet + import + smoke tests J2
make from-scratch-j5   # idem avec profil MCP
make from-scratch-j6   # idem avec profil MCP + smoke test J6
```

Si tu veux uniquement réinitialiser sans lancer un scénario pédagogique précis :

```bash
make reset         # avec confirmation
make force-reset   # force
./reset.sh         # équivalent shell
./reset.sh -f      # équivalent shell
```

Ces commandes arrêtent la stack, suppriment les volumes PostgreSQL et Flowise, nettoient `project/`, puis redémarrent l’environnement proprement.

## Structure

```
├── docker-compose.yml    # postgres, flowise, init, mcp-server
├── .env                  # Variables d'environnement
├── init/
│   ├── import-flows.sh   # Bootstrap user + API key + import flows
│   └── flows/            # Flows J1/J2/J4/J5/J6
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

Expose un endpoint MCP `streamable-http` sur le port `8001`.

Healthcheck :

```bash
curl http://localhost:8001/health
```

## Flows disponibles

- `J1 - Simple Chat`
- `J2 - RAG Chat`
- `J4 - Agent Simple`
- `J4 - Agent RAG`
- `J5 - Agent MCP`
- `J6 - Multi-Agent Supervised`

## Limite moteur Flowise 3.1.2 — J6

`buildAgentflow.js` réinitialise `loopCounts = new Map()` à chaque reprise après `HumanInput`. Le compteur `maxLoopCount` repart donc à zéro après chaque Proceed/Reject : il ne bloque jamais une boucle infinie au niveau moteur.

**Contournement appliqué dans le flow JSON :**
- `startPersistState: true` → l'état (`final_report`, `next`) survit à la pause `HumanInput` ; DirectReply affiche le bon rapport après Proceed.
- `loopAgentflow_2.loopUpdateState` remet `next = ""` et `final_report = ""` après chaque rejet → le Superviseur ne choisit pas FINISH avec l'ancien rapport rejeté.
- Prompt Superviseur durci : interdit FINISH si un rejet humain récent est présent dans la conversation.

`make smoke-j6` valide l'arrivée au `Human Input`. La clôture complète (Proceed → rapport final affiché) est désormais stable.
