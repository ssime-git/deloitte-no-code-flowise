# Déploiement AWS — 1 AMI bakée, N instances (1 par apprenant)

Stratégie : **bake une AMI une fois**, puis **lancer N instances isolées** (une par
apprenant). Isolation totale, reset = `terminate` + relaunch, 100% AWS CLI depuis ton poste.

Chaque instance démarre la stack complète (profil `mcp`, donc J2→J6) et **importe les
flows au premier boot**.

## Prérequis (local)

- `aws` CLI configuré : `aws configure` puis `aws sts get-caller-identity` doit répondre.
- Une keypair EC2 (optionnelle, pour SSH/debug).
- Droits IAM : `ec2:*` (run/describe/create-image/terminate/security-group), `ssm:GetParameters`.

## 1. Configuration

```bash
cd deploy/aws
cp config.env.example config.env
# Édite config.env : AWS_REGION, KEY_NAME, secrets (OPENAI_GATEWAY_API_KEY, ANTHROPIC_API_KEY),
# FLOWISE_PASSWORD, COUNT (17), INSTANCE_TYPE...
```

`config.env` contient des **secrets** → il est gitignoré, ne le commit jamais.

## 2. Bake l'AMI (une fois, ~10-15 min)

```bash
./bake.sh
```

Ce script :
1. résout la dernière AMI Ubuntu via SSM (pas de hardcode),
2. crée le security group `flowise-training-sg` (ports 22 + 3000) si `SG_ID` est vide,
3. lance une instance temporaire qui installe Docker, clone le repo, écrit `.env`,
   **pull les images + build `mcp-server`**, puis `poweroff` (jamais `make up`),
4. `create-image` sur l'instance arrêtée → AMI cohérente,
5. termine l'instance de bake.

L'`AMI_ID` est mémorisé dans `deploy/aws/.state`.

> Important : on ne fait **jamais** `make up` au bake, sinon les volumes Postgres/Flowise
> seraient bakés dans l'AMI et les 17 apprenants partageraient le même état.

## 3. Lancer la flotte

```bash
./launch.sh           # lance COUNT instances depuis l'AMI bakée
```

Chaque instance exécute au premier boot `docker compose --profile mcp up -d`.
Compter ~60-90 s après l'état `running` pour que Flowise migre la base et importe les flows.

## 4. Distribuer les accès

```bash
./access.sh           # tableau apprenant → URL → user → password (+ access.csv)
```

Exemple :

```
LEARNER     INSTANCE             URL                           USER                PASSWORD
apprenant-01  i-0abc...          http://54.12.34.56:3000       admin@local.dev     <ton password>
...
```

Login Flowise : `admin@local.dev` / `FLOWISE_PASSWORD` (partagé, identique sur les 17).

## 5. Reset d'une instance cassée

L'isolation permet un reset trivial sans toucher les autres :

```bash
aws ec2 terminate-instances --instance-ids i-0abc...    # puis relancer 1 instance
# ou, en SSH sur l'instance : cd deloitte-no-code-flowise && make force-reset
```

## 6. Fin de formation — tout éteindre

```bash
./teardown.sh           # terminate les instances taggées
./teardown.sh --all     # + deregister l'AMI et supprime ses snapshots (stop des coûts de stockage)
```

## Notes & arbitrages

- **Profil mcp** : nécessaire pour J5 (Agent MCP) et J6 (multi-agent). Le port MCP (8001)
  reste **interne** au réseau Docker — pas besoin de l'exposer.
- **Sizing** : `t3.medium` (4 Go) suffit en mono-utilisateur mais c'est juste ;
  `t3.large` (8 Go) est plus confortable (~+13 $ sur la journée pour 17 instances).
- **Sécurité** : restreins `SSH_CIDR` à ton IP. Flowise est servi en **HTTP** sur :3000
  (pas de TLS) — acceptable pour une formation éphémère.
- **Secrets dans l'AMI** : les clés API sont dans le `.env` baké → garde l'AMI **privée**.
- **Coût** : pense à `terminate` (pas `stop`) et à `--all` pour ne pas payer le stockage AMI/snapshots.

## Fichiers

| Fichier | Rôle |
|---------|------|
| `config.env.example` | Modèle de configuration (copier en `config.env`) |
| `lib.sh` | Helpers partagés (AWS wrapper, résolution AMI SSM, SG, state) |
| `bake.sh` | Crée l'AMI de formation |
| `launch.sh` | Lance les N instances |
| `access.sh` | Tableau d'accès + `access.csv` |
| `teardown.sh` | Termine la flotte (+ option AMI/snapshots) |
