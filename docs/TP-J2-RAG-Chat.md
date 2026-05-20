# TP J2 — Chat avec mémoire de documents (RAG)

**Public** : Utilisateurs métier — pas de code, pas de terminal.

**Durée** : ~45 min

**Objectif** : Comprendre comment un chatbot peut répondre à partir de vos propres documents (notes de règles RH, procédures, contrôles paie) sans avoir à tout lui réexpliquer.

---

## Avant de commencer

1. Ouvrir votre navigateur sur **http://localhost:3000**
2. Se connecter avec :
   - **Email** : `admin@local.dev`
   - **Mot de passe** : `changeme_admin_password`

---

## 1. Comprendre la différence entre J1 et J2

**J1 - Simple Chat** : le chatbot répond avec sa connaissance générale. Il ne connaît pas vos documents.

**J2 - RAG Chat** : le chatbot lit **vos documents** avant de répondre. Il cherche l'information dans votre corpus, puis répond avec le bon contexte.

> **RAG** = Retrieval-Augmented Generation (génération augmentée par recherche documentaire).

---

## 2. Ouvrir et explorer le flow J2

1. Menu de gauche → **Chatflows** → cliquer sur **J2 - RAG Chat**
2. Observer les blocs :

| Bloc | Rôle |
|------|------|
| **Folder with Files** (bleu) | Charge vos documents depuis le dossier `/corpus/pedagogical/` |
| **OpenAI Embedding** (bleu ciel) | Transforme le texte en "empreinte numérique" (vecteur) |
| **In-Memory Vector Store** (violet) | Stocke les empreintes et cherche les plus proches |
| **OpenAI** | Le cerveau qui génère la réponse |
| **Conversational Retrieval QA Chain** | Le chef d'orchestre du RAG |

**À faire :** Cliquer sur chaque bloc pour découvrir ses réglages.

---

## 3. Tester le RAG

1. Cliquer sur le bouton **Chat**
2. Taper : *"Quels sont les seuils d'écart pour les contrôles URSSAF ?"*

👉 Le chatbot répond avec des informations précises : seuil de 5%, gravité modérée/élevée, règles URSSAF-CTRL-001 et URSSAF-CTRL-002.

3. Tester aussi : *"Comment gérer un salarié qui a une date de sortie mais un statut ACTIF ?"*
4. Puis : *"Que faire avec un NIR fictif dans un audit ?"*

Les réponses sont **sourcées** par les documents du corpus.

---

## 4. Le paramètre topK — combien de documents chercher ?

topK = "top K" = les K meilleurs résultats.

- **topK = 1** : le chatbot ne cherche qu'1 document
- **topK = 4** : le chatbot cherche 4 documents (valeur par défaut)
- **topK = 10** : le chatbot cherche 10 documents (mais coûte plus cher en tokens)

**À faire :**

1. Cliquer sur le bloc **In-Memory Vector Store** (violet)
2. Dans le panneau de droite, repérer le champ **Top K**
3. Noter la valeur actuelle (**4**)
4. La changer à **1**
5. Cliquer sur **Save** (en haut à droite)
6. Rouvrir le Chat, poser la même question : *"Quels sont les seuils URSSAF ?"*
   → La réponse est moins riche, le chatbot a moins de contexte
7. Remettre **Top K = 4**, sauvegarder

---

## 5. Ajouter un nouveau document (sans code)

Vous allez ajouter une nouvelle règle dans le dossier de documents.

**À faire :**

1. Dans le bloc **Folder with Files**, le paramètre **Folder Path** indique `/corpus/pedagogical/`
2. En pratique, vos documents sont dans le dossier `corpus/pedagogical/` sur le poste du formateur

*(Le formateur ajoute un nouveau fichier pendant la démo ou explique le processus)*

---

## 6. Recharger les documents (Upsert)

Une fois un nouveau document ajouté au dossier, il faut le **recharger** dans la mémoire du vector store :

**À faire :**

1. Cliquer sur le bloc **In-Memory Vector Store** (violet)
2. En bas du panneau de droite, cliquer sur le bouton **Upsert**
3. Attendre quelques secondes — un message vert confirme le chargement
4. Ouvrir le Chat et poser une question sur le nouveau document

> **Upsert** = mettre à jour (update + insert). Cela recharge uniquement les nouveaux documents sans perdre les anciens.

**Quand faire l'upsert ?** À chaque fois que vous ajoutez ou modifiez un document dans le dossier.

---

## 7. Comparer J1 (sans RAG) et J2 (avec RAG)

1. Menu de gauche → **Chatflows** → ouvrir **J1 - Simple Chat**
2. Cliquer sur **Chat**
3. Poser la même question : *"Quels sont les seuils URSSAF ?"*
4. Observer la différence :
   - **J1** répond de manière vague (connaissance générale)
   - **J2** répond avec des règles précises, des seuils, des sources

---

## 8. Résumé

Vous avez appris à :
- ✅ Explorer un flow RAG avec 5 blocs
- ✅ Comprendre le rôle de chaque bloc (documents, embeddings, vector store)
- ✅ Modifier le paramètre topK pour contrôler la précision
- ✅ Déclencher l'upsert depuis l'interface pour charger de nouveaux documents
- ✅ Comparer un chat simple vs un chat RAG
