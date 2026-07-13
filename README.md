# Deloitte No-Code Flowise

Stack pédagogique Flowise 3.1.2 + PostgreSQL pour la formation Liora.

## Sommaire

- [Prérequis](#prérequis)
- [1. Première installation (VM vierge)](#1-première-installation-vm-vierge)
- [2. Utilisation courante (stack déjà déployée)](#2-utilisation-courante-stack-déjà-déployée)
  - [Commandes utiles](#commandes-utiles) · [Connexion](#connexion) · [Prompts de test](#prompts-de-test) · [Arrêter et relancer from scratch](#arrêter-et-relancer-from-scratch)
- [3. Déploiement fleet AWS](#3-déploiement-fleet-aws-17-instances-pour-la-formation)
- [Structure](#structure) · [Architecture](#architecture) · [MCP Server](#mcp-server)
- [Flows disponibles](#flows-disponibles)
- [Limite moteur Flowise 3.1.2 — J6](#limite-moteur-flowise-312--j6)

Docs liées : [patches Flowise](patches/README.md) · [flows importés](init/flows/README.md) · [déploiement AWS](deploy/aws/README.md) · [TP jour par jour](docs/courses/)

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

# 4. Tout démarrer (stack + attente import des flows + patches Flowise)
make all
```

> ⏳ Le premier démarrage dure 1-2 minutes (téléchargement des images Docker, bootstrap de l'utilisateur et import des flows). Les patches appliqués par `make all` sont détaillés dans [patches/README.md](patches/README.md).

### Vérifier que tout fonctionne

```bash
make ping          # → pong (Flowise est en ligne)
make api-key       # affiche la clé API générée automatiquement
```

### Lancer les tests

```bash
make test-j2       # test de base : "Bonjour, qui es-tu ?"
make test-j3       # test RAG : questions URSSAF
```

Liste complète des tests par jour : [Commandes utiles](#commandes-utiles). Identifiants UI : [Connexion](#connexion).

---

## 2. Utilisation courante (stack déjà déployée)

```bash
make from-scratch-j3   # reset complet + import + smoke tests J3
make from-scratch-j4   # reset complet + import + smoke tests J4
make from-scratch-j5   # reset complet + import + smoke tests J5 (profil MCP)
make from-scratch-j6   # reset complet + import + smoke test J6 (profil MCP)

make all               # up + attente import flows + patches Flowise
make up                # simple démarrage sans reset ni patches
make down              # arrêt propre
make status            # état des conteneurs
```

Si la stack est déjà déployée et que tu veux juste revérifier :

```bash
make smoke-j3          # smoke tests J3 complets
```

Les questions envoyées par chaque `test-*` sont listées dans [Prompts de test](#prompts-de-test).

## Commandes utiles

```bash
make from-scratch-j3   # reset complet + import + smoke tests J3
make from-scratch-j4   # reset complet + import + smoke tests J4
make from-scratch-j5   # reset complet + import + smoke tests J5 (profil mcp)
make from-scratch-j6   # reset complet + import + smoke tests J6 (profil mcp)
make smoke-j3          # smoke tests J3 sur stack déjà lancée
make smoke-j4          # smoke tests J4
make smoke-j5          # smoke tests J5
make smoke-j6          # smoke test J6 jusqu'au point de validation humaine
make test-j3           # question URSSAF
make test-j3-nir       # question NIR fictif
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

**J2 - Simple Chat** : *"Que peux-tu faire ?"*

**J3 - RAG Chat** : *"Quels sont les points de contrôle URSSAF et leurs seuils de tolérance ?"*

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
make from-scratch-j3   # stack standard + reset complet + import + smoke tests J3
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

---

## 3. Déploiement fleet AWS (17 instances pour la formation)

> Prérequis : AWS CLI configuré avec des credentials valides, accès à EC2 en `eu-west-3`.

### Setup initial

```bash
cp deploy/aws/config.env.example deploy/aws/config.env
# Éditer config.env : renseigner ANTHROPIC_API_KEY, OPENAI_GATEWAY_API_KEY, FLOWISE_PASSWORD
```

`config.env` est gitignored — ne jamais commiter ce fichier.

### Étape 0 : créer la clé SSH (une seule fois)

```bash
make deploy-key
```

Crée le keypair EC2 `flowise-training-key` si `KEY_NAME` est vide dans `config.env`, sauvegarde le `.pem` localement (`deploy/aws/flowise-training-key.pem`, chmod 600) et met à jour `config.env` automatiquement.

> Si la clé existe déjà sur AWS et que le `.pem` est présent, cette commande ne fait rien.

### Workflow complet

```bash
# ── Étape 1 : valider le stack localement ────────────────────────────────────
make smoke-j3          # RAG Chat
make smoke-j4          # Agent Simple + Agent RAG
make smoke-j5          # Agent MCP
make smoke-j6          # Multi-Agent (attend Human Input — comportement normal)

# ── Étape 2 : créer la clé SSH si pas encore fait ────────────────────────────
make deploy-key        # idempotent — ne recrée pas si déjà présente

# ── Étape 3 : tester sur une VM fraîche ──────────────────────────────────────
make deploy-test       # ~12 min — Ubuntu vierge → install → smoke → prompt terminate
# SSH de debug possible : ssh -i deploy/aws/flowise-training-key.pem ubuntu@<IP>

# ── Étape 4 : bake l'AMI ─────────────────────────────────────────────────────
make deploy-bake       # ~20 min — clone repo + pull images + snapshot

# ── Étape 5 : 1 VM de validation avec les collègues ──────────────────────────
make deploy-launch COUNT=1   # Lance 1 instance depuis l'AMI (~90 s de boot)
make deploy-access           # Affiche URL + login à partager avec les collègues

# Les collègues testent : J2 → J6, ~15-30 min
# Si OK → étape 6. Sinon → make deploy-teardown, corriger, rebake.

# ── Étape 6 : déploiement fleet ───────────────────────────────────────────────
make deploy-teardown         # Termine la VM de validation
make deploy-launch COUNT=17  # Lance les 17 instances (~3 min)
make deploy-access           # Tableau complet URLs + login/password → access.csv

# ── Après la formation ────────────────────────────────────────────────────────
make deploy-teardown   # Termine toutes les instances
```

### Accès HTTPS (réseaux d'entreprise bloquant HTTP:3000)

Si les VMs sont inaccessibles depuis un réseau filtré (proxy d'entreprise, port 3000
non-standard, IP nue) : une VM instructeur séparée sert de gateway HTTPS (Caddy +
certificats Let's Encrypt automatiques via sslip.io) et route chaque apprenant vers sa
VM par nom d'hôte, sans toucher aux 17 VMs de formation.

```bash
make deploy-gateway    # régénère et pousse le Caddyfile de la gateway (après un reset/relaunch)
```

Détails complets (architecture, prérequis one-shot, limites) : voir [`deploy/aws/README.md`](deploy/aws/README.md#7-accès-https-via-gateway-réseaux-dentreprise-qui-bloquent-http3000).

### Terminer une instance spécifique

```bash
make deploy-terminate-vm ID=i-xxxxxxxxxxxx
```

Utile pour supprimer une VM de test sans passer par `deploy-teardown` (qui termine **toutes** les instances tagguées).

### Ce que fait chaque script

| Commande | Durée | Description |
|----------|-------|-------------|
| `deploy-key` | ~5 s | Crée keypair EC2 si absent, sauvegarde `.pem`, met à jour `config.env` |
| `deploy-terminate-vm ID=i-xxx` | ~5 s | Termine une instance spécifique |
| `deploy-test` | ~12 min | VM Ubuntu fraîche → install → `make up` → vérifie flows → prompt terminate |
| `deploy-bake` | ~20 min | VM tempo → install → pre-pull images → poweroff → snapshot AMI |
| `deploy-launch` | ~3 min | Lance N EC2 depuis l'AMI, chaque boot démarre le stack |
| `deploy-access` | ~5 s | Récupère les IPs et génère le tableau d'accès |
| `deploy-gateway` | ~10 s | Régénère et pousse le Caddyfile de la gateway HTTPS (VM instructeur) |
| `deploy-teardown` | ~10 s | Termine toutes les instances tagguées `training=flowise-j2026` |

### Ressources AWS créées

- Security group `flowise-training-sg` (créé automatiquement si absent) : ports 22 et 3000
- 1 AMI privée `flowise-training-YYYYMMDD-HHMMSS`
- 17 instances `t3.medium` (2 vCPU / 4 GB RAM), volume 30 GB gp3

### Coût estimé

| Ressource | Coût/h | 8h formation |
|-----------|--------|--------------|
| 17 × t3.medium | $0.0416/h | ~$5.70 |
| 17 × 30 GB gp3 | $0.002/h | ~$0.27 |
| AMI (snapshot) | ~$0.05/GB | <$1 |
| **Total** | | **~$7 / journée** |

---

## Structure

```
├── docker-compose.yml    # postgres, flowise, init, mcp-server
├── .env                  # Variables d'environnement
├── init/
│   ├── import-flows.sh   # Bootstrap user + API key + import flows
│   └── flows/            # Flows J2/J3/J4/J5/J6
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

Expose un endpoint MCP `streamable-http` sur le port `8001` (code dans [`mcp-server/`](mcp-server/)). Utilisé par le flow `J5 - Agent MCP` — voir [Flows disponibles](#flows-disponibles).

Healthcheck :

```bash
curl http://localhost:8001/health
```

## Flows disponibles

Importés automatiquement au démarrage depuis [`init/flows/`](init/flows/README.md) ; chaque flow a son TP dans [`docs/courses/`](docs/courses/).

- `J2 - Simple Chat` — [TP](docs/courses/tp_j2_simple_chat.md)
- `J3 - RAG Chat` — [TP](docs/courses/tp_j3_rag_chat.md)
- `J4 - Agent Simple` — [TP](docs/courses/tp_j4_agent_simple.md)
- `J4 - Agent RAG` — [TP](docs/courses/tp_j4_agent_rag.md)
- `J5 - Agent MCP` — [TP](docs/courses/tp_j5_agent_mcp.md)
- `J6 - Multi-Agent Supervised` — [TP](docs/courses/tp_j6_multi_agent_supervise.md)

Les prompts de démo correspondants : [Prompts de test](#prompts-de-test).

## Limite moteur Flowise 3.1.2 — J6

`buildAgentflow.js` réinitialise `loopCounts = new Map()` à chaque reprise après `HumanInput`. Le compteur `maxLoopCount` repart donc à zéro après chaque Proceed/Reject : il ne bloque jamais une boucle infinie au niveau moteur.

**Contournement appliqué dans le flow JSON :**
- `startPersistState: true` → l'état (`final_report`, `next`) survit à la pause `HumanInput` ; DirectReply affiche le bon rapport après Proceed.
- `loopAgentflow_2.loopUpdateState` remet `next = ""` et `final_report = ""` après chaque rejet → le Superviseur ne choisit pas FINISH avec l'ancien rapport rejeté.
- Prompt Superviseur durci : interdit FINISH si un rejet humain récent est présent dans la conversation.

`make smoke-j6` valide l'arrivée au `Human Input`. La clôture complète (Proceed → rapport final affiché) est désormais stable.

Les bugs moteur corrigés à chaud (routage HumanInput, race INPROGRESS, embeddings Jina) sont documentés dans [patches/README.md](patches/README.md) et appliqués par `make patch-flowise` (inclus dans `make all`).
