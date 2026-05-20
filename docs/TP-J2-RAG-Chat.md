# TP J2 — Chat RAG avec Flowise

## Objectif

Comprendre le fonctionnement d'un pipeline RAG (Retrieval-Augmented Generation) dans Flowise : chargement de documents, vectorisation, recherche contextuelle et génération de réponse.

## Durée

~1h15

## Avant de commencer

La stack doit être opérationnelle avec le flow J2 importé et les documents upsertés :

```bash
make up
make api-key
```

Vérifier que J2 répond sur le corpus pédagogique :

```bash
make test-j2
```

Connecté sur http://localhost:3000 avec les identifiants admin.

---

## 1. Explorer le flow J2 (15 min)

Ouvrir **J2 - RAG Chat** et observer les 5 nœuds :

| Nœud | Rôle |
|------|------|
| **ChatOpenAI** | Modèle de langage (GPT-4.1 nano) |
| **OpenAI Embeddings** | Convertit le texte en vecteurs (text-embedding-3-small) |
| **In-Memory Vector Store** | Stocke les vecteurs et fait la recherche par similarité |
| **Conversational Retrieval QA Chain** | Chaîne RAG qui combine la question + le contexte récupéré |
| **Folder with Files** | Charge les documents depuis `/corpus/pedagogical/` |

### Questions

1. Quel est le rôle du nœud **Embeddings** ?
2. Quelle est la valeur de `topK` sur le vector store ? Que contrôle-t-elle ?
3. Pourquoi `Return Source Documents` est-il activé sur la chaîne RAG ?

<details>
<summary>Réponses</summary>
1. Convertir les documents texte en vecteurs numériques pour la recherche sémantique.<br>
2. `topK = 4` — nombre de documents les plus pertinents à récupérer.<br>
3. Pour que la réponse inclue les sources utilisées (traçabilité).
</details>

---

## 2. Tester le RAG (10 min)

Cliquer sur **Chat** et poser les questions :

- *"Quels sont les seuils d'écart pour les contrôles URSSAF ?"*
- *"Comment traiter un NIR fictif dans un workflow d'audit ?"*
- *"Que faire quand un salarié a une date de sortie mais un statut ACTIF ?"*

Observer que :
- Les réponses citent des règles précises (URSSAF-CTRL-001, PAYROLL-STATUS-001, etc.)
- Les réponses sont sourcées par les documents du corpus
- Le modèle ne répond pas à partir de sa connaissance générale mais du contexte fourni

---

## 3. Inspecter les documents chargés (10 min)

```bash
# Lister les fichiers du corpus pédagogique
ls -la corpus/pedagogical/

# Voir le contenu d'un fichier source
cat corpus/pedagogical/note_urssaf_controles_base_taux.md
```

1. Combien de documents sont dans le corpus ?
2. Quel format de fichier est utilisé ?
3. Les documents sont-ils compatibles avec le loader **Folder with Files** ?

<details>
<summary>Réponses</summary>
1. 6 fichiers `.md`<br>
2. Markdown (`.md`)<br>
3. Oui — le Folder loader supporte nativement `.md`, `.txt`, `.pdf`, `.csv`, `.docx`, etc.
</details>

---

## 4. Tester l'upsert (10 min)

L'**upsert** est le processus qui charge les documents dans le vector store :

```bash
# Récupérer l'ID du flow J2
API_KEY=$(make api-key 2>/dev/null | tail -1)
J2_ID=$(curl -s -H "Authorization: Bearer $API_KEY" http://localhost:3000/api/v1/chatflows | \
  python3 -c "import json,sys; print([f['id'] for f in json.load(sys.stdin) if 'RAG' in f['name']][0])")

# Déclencher un nouvel upsert
curl -X POST "http://localhost:3000/api/v1/vector/upsert/$J2_ID" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"question":""}'
```

1. Que retourne l'API ?
2. Pourquoi l'upsert est-il nécessaire après un reset ?

---

## 5. Modifier topK (10 min)

Le paramètre `topK` contrôle le nombre de documents récupérés.

1. Cliquer sur le nœud **In-Memory Vector Store**
2. Modifier `topK` :
   - Mettre à `1` → le LLM aura très peu de contexte
   - Sauvegarder et tester la même question URSSAF
3. Remettre `topK` à `4`
4. Mettre à `10` → plus de contexte mais plus de tokens consommés

---

## 6. Ajouter un nouveau document au corpus (15 min)

1. Créer un fichier dans `corpus/pedagogical/` :

```bash
cat > corpus/pedagogical/note_test_regles.md << 'EOF'
# Règles de Test pour la Formation

Source ID: TEST-001
Version: 1.0
Date: 2026-05-20
Status: Pédagogique

## Règle TEST-001

Un salaire brut ne peut pas être négatif.
EOF
```

2. Relancer l'upsert pour charger le nouveau document :

```bash
API_KEY=$(make api-key 2>/dev/null | tail -1)
J2_ID=$(curl -s -H "Authorization: Bearer $API_KEY" http://localhost:3000/api/v1/chatflows | \
  python3 -c "import json,sys; print([f['id'] for f in json.load(sys.stdin) if 'RAG' in f['name']][0])")
curl -X POST "http://localhost:3000/api/v1/vector/upsert/$J2_ID" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"question":""}'
```

3. Tester : *"Quelle est la règle concernant les salaires bruts négatifs ?"*
4. Vérifier que le nouveau document est utilisé dans la réponse

---

## 7. Comparer J1 et J2 (bonus)

1. Ouvrir le flow **J1 - Simple Chat** (sans RAG)
2. Poser la même question URSSAF : *"Quels sont les seuils d'écart URSSAF ?"*
3. Comparer les réponses :
   - J1 répond de mémoire (connaissance générale du LLM)
   - J2 répond à partir des documents du corpus (contexte précis et sourcé)

---

## 8. Créer un nouveau flow RAG de zéro (bonus)

1. Créer un nouveau Chatflow
2. Ajouter manuellement les nœuds :
   - **ChatOpenAI** (même credential OpenAI)
   - **OpenAI Embeddings** (même credential)
   - **In-Memory Vector Store**
   - **Conversational Retrieval QA Chain**
3. Connecter les nœuds dans le bon ordre
4. Configurer `topK = 3`
5. Sauvegarder, donner un nom et tester

---

## Vérification

- [ ] Le flow J2 répond avec des sources et des règles précises
- [ ] L'upsert fonctionne et charge les documents
- [ ] L'ajout d'un nouveau document est visible dans les réponses après upsert
- [ ] La modification de `topK` change la qualité des réponses
