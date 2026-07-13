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

`teardown.sh` ne couvre ni la VM instructeur (non taguée — la terminer par son ID),
ni le keypair, ni le security group. Nettoyage complet :

```bash
aws ec2 terminate-instances --instance-ids <id-vm-instructeur>
aws ec2 delete-key-pair --key-name flowise-training-key
aws ec2 delete-security-group --group-name flowise-training-sg   # après terminaison effective des VMs
rm -f flowise-training-key.pem access.csv .state                  # artefacts locaux périmés
```

## 7. Accès HTTPS via gateway (réseaux d'entreprise qui bloquent HTTP:3000)

Certains réseaux d'entreprise (proxy/filtrage) bloquent l'accès direct en HTTP sur un
port non-standard (3000) ou par IP nue. Solution : une VM séparée (« instructeur »,
hors flotte des 17) fait office de **gateway HTTPS**, et route chaque apprenant vers
sa VM par nom d'hôte — sans toucher aux 17 VMs de formation.

Architecture :
- La VM instructeur tourne Caddy (profil Compose `https`), qui obtient automatiquement
  un certificat Let's Encrypt par nom d'hôte via [sslip.io](https://sslip.io) (DNS
  gratuit qui résout `<n'importe-quoi>.<ip-avec-tirets>.sslip.io` vers cette IP — donc
  aucun DNS à demander à un admin).
- Un bloc Caddy par apprenant : `learnerNN.<ip-instructeur-avec-tirets>.sslip.io` →
  `reverse_proxy <ip-publique-vm-apprenant>:3000`.
- Les 17 VMs de formation restent strictement inchangées (HTTP:3000, comme avant).

Prérequis one-shot sur la VM instructeur : ouvrir 80/443 sur son security group,
ajouter `DOMAIN=<ip-instructeur-avec-tirets>.sslip.io` dans son `.env`, puis
`docker compose --profile mcp --profile https up -d caddy`. Renseigner ensuite
`INSTRUCTOR_IP` dans `config.env` (voir §8 pour la recréation complète).

Régénérer le mapping (après un reset/relaunch qui change des IPs, ou pour rafraîchir
la liste) :

```bash
./gateway.sh
```

Le script : liste les instances running via `describe-instances`, régénère le
`Caddyfile` de la VM instructeur (un bloc par apprenant), le pousse par `scp`, et
recharge Caddy à chaud (`caddy reload`, zéro downtime). Il affiche ensuite les URLs
`https://learnerNN.<domaine-instructeur>` à distribuer.

Limites à connaître :
- **Point de défaillance unique** : si la VM instructeur tombe, les 17 accès HTTPS
  tombent avec elle (les apprenants restent joignables en direct via
  `http://<ip>:3000`, cf. `access.sh`).
- **sslip.io** est un service tiers gratuit ; en cas de blocage par un filtre
  strict (catégorie "anonymizer/dynamic-DNS"), passer à un vrai sous-domaine
  (1 enregistrement DNS de type A vers l'IP de la VM instructeur suffit — aucune
  config TLS côté admin, Caddy gère le certificat automatiquement).

## 8. Tout recréer de zéro (après nettoyage complet)

État de départ supposé : **rien n'existe sur AWS** (pas d'instance, pas d'AMI, pas de
keypair `flowise-training-key`, pas de SG `flowise-training-sg` — c'est l'état laissé
par le §6). Tout se recrée depuis ce repo :

```bash
cd deploy/aws

# 1. Config + credentials
cp config.env.example config.env
# Renseigner : credentials AWS (ou AWS_PROFILE), OPENAI_GATEWAY_API_KEY,
# ANTHROPIC_API_KEY, FLOWISE_PASSWORD, COUNT. Mettre à jour TAG_VALUE
# (ex: flowise-j2027) pour ne pas collisionner avec une ancienne session.

# 2. Keypair (recréée car supprimée au nettoyage)
make -C ../.. deploy-key        # crée le keypair + .pem local + MAJ config.env

# 3. AMI (le SG flowise-training-sg est recréé automatiquement par bake.sh)
make -C ../.. deploy-bake       # ~20 min

# 4. Flotte + accès
make -C ../.. deploy-launch COUNT=17
make -C ../.. deploy-access    # access.csv régénéré
```

Si l'accès HTTPS (§7) est nécessaire, la VM instructeur est à recréer **à la main**
(elle n'est pas scriptée) :

1. Lancer 1 instance Ubuntu depuis l'AMI bakée (ou une Ubuntu vierge + `setup.sh`),
   SG avec ports 22, 80 et 443 ouverts.
2. Sur la VM : ajouter `DOMAIN=<ip-avec-tirets>.sslip.io` dans le `.env` du repo, puis
   `docker compose --profile mcp --profile https up -d caddy`.
3. En local : renseigner `INSTRUCTOR_IP=<ip publique>` dans `config.env`
   (requis par `gateway.sh` — plus aucune IP n'est hardcodée), puis `./gateway.sh`.

## Notes & arbitrages

- **Profil mcp** : nécessaire pour J5 (Agent MCP) et J6 (multi-agent). Le port MCP (8001)
  reste **interne** au réseau Docker — pas besoin de l'exposer.
- **Sizing** : `t3.medium` (4 Go) suffit en mono-utilisateur mais c'est juste ;
  `t3.large` (8 Go) est plus confortable (~+13 $ sur la journée pour 17 instances).
- **Sécurité** : restreins `SSH_CIDR` à ton IP. Par défaut Flowise est servi en **HTTP**
  sur :3000 (pas de TLS) — acceptable pour une formation éphémère, mais bloqué par
  certains réseaux d'entreprise ; voir §7 pour l'alternative HTTPS via gateway.
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
| `gateway.sh` | Régénère et pousse le Caddyfile de la gateway HTTPS (§7) |
| `teardown.sh` | Termine la flotte (+ option AMI/snapshots) |
