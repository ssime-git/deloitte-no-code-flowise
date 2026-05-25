# Deloitte No-Code Flowise

Stack pédagogique Flowise 3.1.2 + PostgreSQL pour la formation Liora.

## Prérequis

- Git
- VM Ubuntu 22.04+ ou Debian 12+ avec accès internet
- Accès `sudo` (l'installation de Docker et des paquets le nécessite)

---

## 1. Première installation (VM vierge)

```bash
# 1. Cloner le dépôt
git clone https://github.com/ssime-git/deloitte-no-code-flowise.git
cd deloitte-no-code-flowise

# 2. Rendre le script exécutable et installer les dépendances
chmod +x setup.sh
./setup.sh

# 3. Configurer la clé API OpenAI
#    Éditer le fichier .env et renseigner OPENAI_GATEWAY_API_KEY
nano .env

# 4. Démarrer la stack
make up
```

> ⏳ Le premier démarrage dure 1-2 minutes (téléchargement des images Docker, bootstrap de l'utilisateur et import des flows).

### Vérifier que tout fonctionne

```bash
make ping          # → pong (Flowise est en ligne)
make api-key       # affiche la clé API générée automatiquement
```

### Lancer les tests

```bash
make test-j1       # test de base : "Bonjour, qui es-tu ?"
make test-j2       # test RAG : questions URSSAF
```

---

## 2. Utilisation courante (stack déjà déployée)

```bash
make from-scratch-j2   # reset complet + import + smoke tests J2
make from-scratch-j4   # reset complet + import + smoke tests J4
make from-scratch-j5   # reset complet + import + smoke tests J5 (profil MCP)
make from-scratch-j6   # reset complet + import + smoke test J6 (profil MCP)

make up                # simple démarrage sans reset
make down              # arrêt propre
make status            # état des conteneurs
```

Si la stack est déjà déployée et que tu veux juste revérifier :

```bash
make smoke-j2          # smoke tests J2 complets
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
