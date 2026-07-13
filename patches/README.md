# Patches Flowise 3.1.2

Correctifs appliqués à chaud dans le conteneur Flowise via `make patch-flowise`
(idempotent : détecte les fichiers déjà patchés, sauvegarde un `.bak`, redémarre
le conteneur seulement si nécessaire). À relancer après chaque recréation du
conteneur (`make reset`, pull d'image).

## buildAgentflow.js

Cible : `/usr/local/lib/node_modules/flowise/dist/utils/buildAgentflow.js`

Deux bugs corrigés (impact : J6 multi-agent supervisé, Human-in-the-Loop) :

1. **Routage HumanInput** : les nœuds `humanInputAgentflow` utilisent des
   handles nommés (`output-proceed` / `output-reject`) alors que le moteur ne
   résolvait que les handles indexés (`-output-0/1`). Les branches
   approuver/rejeter n'étaient jamais suivies.
2. **Race condition INPROGRESS → STOPPED** : l'événement SSE part avant le
   commit DB ; la reprise après validation humaine lisait un état obsolète.
   Corrigé par une boucle de retry.

## jina-embeddings.js

Cibles (les deux copies de `@langchain/community`) :
- `flowise/node_modules/@langchain/community/dist/embeddings/jina.js`
- `flowise/node_modules/flowise-components/node_modules/@langchain/community/dist/embeddings/jina.js`

Bug : l'upsert vectoriel avec Jina restait bloqué en statut `UPSERTING`.
Upstream envoie tous les batches en parallèle (`Promise.all`) alors que l'API
Jina limite à 2 requêtes simultanées → erreur « Concurrency limit 2/2 » avalée
silencieusement. Le patch :

1. envoie les batches **séquentiellement** ;
2. ajoute un vrai retry avec backoff sur les erreurs de rate/concurrency
   (le `embeddingWithRetry` upstream ne retentait jamais).

Alternative sans patch : passer les embeddings par la gateway OpenAI
(config learner07).
