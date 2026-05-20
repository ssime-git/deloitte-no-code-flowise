# TP J2 — RAG, fiabilité et reconstruction d'un assistant documentaire

**Public** : Utilisateurs métier — pas de code, pas de terminal.

**Durée** : 1 journée (2 sessions de 4h)

**Objectif** : Comprendre le fonctionnement d'un assistant RAG, apprendre à le fiabiliser, puis reconstruire le flow J2 à partir des notions vues pendant la journée.

---

## Positionnement pédagogique

Le jour 2 repose sur de vrais challenges.

On ne cherche pas juste à "cliquer dans Flowise", mais à faire pratiquer :

1. la différence **sans RAG / avec RAG**
2. la lecture du flow bloc par bloc
3. les réglages utiles :
   - modèle
   - température
   - `topK`
4. la gestion des hallucinations
5. l'évaluation de la fiabilité
6. la reconstruction finale du flow

---

## Avant de commencer

1. Ouvrir votre navigateur sur **http://localhost:3000**
2. Se connecter avec :
   - **Email** : `admin@local.dev`
   - **Mot de passe** : `changeme_admin_password`
3. Ouvrir **Chatflows**
4. Ouvrir **J2 - RAG Chat**

---

## Le flow J2 en une minute

| Bloc | Rôle |
|------|------|
| **Folder with Files** | Charge le corpus pédagogique |
| **File Loader** | Permet un upload ponctuel depuis le chat |
| **OpenAI Embedding** | Convertit les documents en vecteurs |
| **In-Memory Vector Store** | Recherche les passages pertinents |
| **OpenAI** | Génère la réponse finale |
| **Conversational Retrieval QA Chain** | Orchestre retrieval + réponse |

---

## Déroulé conseillé de la journée

### Matin

- comprendre le principe du RAG
- comparer J1 et J2
- lire le flow J2
- faire les premiers tests métier

### Après-midi

- tester la fiabilité
- jouer avec `topK`, température et modèle
- faire un upsert
- tester l'upload manuel
- reconstruire le flow complet

---

## Règle d'animation

Pour chaque challenge :

- **Obligatoire** : à faire par tous les groupes
- **Bonus** : à faire si le groupe avance vite
- **Durée indicative** : aide à équilibrer présentation, démo, pratique et correction

---

## Challenge 1 — Montrer la différence sans RAG / avec RAG

**Statut** : Obligatoire  
**Durée indicative** : 20 à 30 min

### Situation métier

Vous voulez démontrer à un participant pourquoi un assistant documentaire apporte quelque chose par rapport à un simple chat.

### Votre mission

1. ouvrir **J1 - Simple Chat**
2. poser :
   - *"Quels sont les seuils d'écart pour les contrôles URSSAF ?"*
3. noter la réponse
4. ouvrir **J2 - RAG Chat**
5. poser la même question
6. comparer

### Ce qu'on cherche

Le groupe doit voir que :
- J1 répond plus généralement
- J2 restitue des règles plus précises

### Débrief

- quelle réponse est la plus exploitable ?
- laquelle semble la plus proche d'un référentiel métier ?

---

## Challenge 2 — Identifier les bonnes réponses et les réponses fragiles

**Statut** : Obligatoire  
**Durée indicative** : 30 min

### Situation métier

On veut tester la robustesse du flow J2 sur plusieurs règles du corpus.

### Questions à tester

1. *"Quels sont les seuils d'écart pour les contrôles URSSAF ?"*
2. *"Comment gérer un salarié qui a une date de sortie mais un statut ACTIF ?"*
3. *"Que faire avec un NIR fictif dans un audit ?"*

### Votre mission

Pour chaque question, classer la réponse :
- **fiable**
- **à vérifier**
- **insuffisante**

### Ce qu'on cherche

Le participant doit comprendre qu'un RAG ne rend pas automatiquement toutes les réponses parfaites.

### Piste de débrief

- une question peut retrouver le bon document mais donner une mauvaise synthèse
- la qualité dépend :
  - du retrieval
  - du modèle
  - de la formulation de la question

---

## Challenge 3 — Faire un double check sur un cas limite

**Statut** : Obligatoire  
**Durée indicative** : 30 à 40 min

### Situation métier

Le cas du **NIR fictif** est utile pour montrer qu'une réponse peut être partiellement correcte mais mal priorisée.

### Votre mission

Poser successivement :

1. *"Que faire avec un NIR fictif dans un audit ?"*
2. *"Quelle règle s'applique à un NIR fictif ?"*
3. *"Selon les documents, comment traiter un NIR fictif ?"*

Puis répondre à ces questions :
- la réponse change-t-elle ?
- la règle de masquage ressort-elle bien ?
- la formulation utilisateur a-t-elle un impact ?

### Ce qu'on cherche

Le bon résultat métier attendu est :
- ne pas envoyer de NIR brut à l'IA
- remplacer la valeur par `***MASKED***`
- considérer ensuite les règles de validation de format comme information secondaire

<details>
<summary>Variante de formulation A</summary>

```text
Selon les documents, que faut-il faire d'un NIR fictif avant toute étape impliquant l'IA ?
```

</details>

<details>
<summary>Variante de formulation B</summary>

```text
Je suis en audit paie. Donne-moi l'action opérationnelle à faire sur un NIR fictif avant un prompt, un rapport ou un log.
```

</details>

### Débrief

- la reformulation est un outil de fiabilité
- une bonne question peut aider à faire ressortir la bonne règle

---

## Challenge 4 — Régler `topK`

**Statut** : Obligatoire  
**Durée indicative** : 25 min

### Situation métier

Vous voulez observer l'effet du nombre de passages récupérés.

### Votre mission

1. ouvrir **In-Memory Vector Store**
2. relever la valeur de **Top K**
3. tester successivement :
   - `1`
   - `4`
   - `8`
4. rejouer la question URSSAF

### Ce qu'on cherche

- `1` : parfois trop peu de contexte
- `4` : bon compromis
- `8` : parfois plus de bruit

### Critère d'analyse

Comparer :
- précision
- longueur
- clarté
- stabilité

---

## Challenge 5 — Changer le modèle

**Statut** : Obligatoire  
**Durée indicative** : 30 min

### Situation métier

Vous voulez comprendre si un autre modèle améliore une réponse documentaire fragile.

### Votre mission

1. ouvrir le bloc **OpenAI**
2. noter le modèle courant
3. tester un autre modèle disponible
4. rejouer :
   - la question URSSAF
   - la question NIR

### Ce qu'on cherche

Comparer :
- vitesse
- cohérence
- bonne priorisation de la règle métier
- robustesse sur les cas limites

### Débrief

- un modèle plus robuste peut mieux synthétiser les sources
- un modèle rapide peut suffire sur des cas simples

---

## Challenge 6 — Régler la température

**Statut** : Bonus utile  
**Durée indicative** : 15 à 20 min

### Situation métier

Vous voulez vérifier si une température plus faible rend le flow plus stable pour un assistant documentaire.

### Votre mission

1. dans **OpenAI**, tester une température basse
2. rejouer la même question deux fois
3. augmenter la température
4. rejouer la question

### Question conseillée

*"Que faire avec un NIR fictif dans un audit ?"*

### Ce qu'on cherche

- température basse : plus de stabilité
- température plus haute : plus de variation, parfois moins de fiabilité

---

## Challenge 7 — Ajouter un document et recharger le corpus

**Statut** : Obligatoire  
**Durée indicative** : 25 à 30 min

### Situation métier

Vous voulez enrichir l'assistant avec une nouvelle règle.

### Votre mission

1. observer le bloc **Folder with Files**
2. relever le chemin du corpus
3. ajouter un nouveau document pédagogique
4. lancer un **Upsert**
5. poser une question qui cible ce nouveau document

### Ce qu'on cherche

Comprendre que :
- le modèle ne sait pas magiquement
- le corpus fait partie du système
- l'upsert fait partie du cycle d'usage

---

## Challenge 8 — Tester l'upload manuel

**Statut** : Bonus utile  
**Durée indicative** : 20 min

### Situation métier

Vous voulez analyser rapidement un document ponctuel sans modifier le corpus global.

### Votre mission

1. ouvrir le chat J2
2. cliquer sur l'icône d'upload
3. envoyer un document
4. poser une question ciblée

### Exemples

- *"Quel est le montant total ?"*
- *"Quels sont les points de vigilance dans cette note ?"*
- *"Cette pièce contient-elle un élément à contrôler ?"*

### Ce qu'on cherche

- l'upload manuel est pratique pour un test rapide
- il ne remplace pas une base documentaire gouvernée

---

## Challenge 9 — Construire un protocole de fiabilité

**Statut** : Obligatoire  
**Durée indicative** : 30 à 40 min

### Situation métier

Vous devez évaluer si l'assistant peut être utilisé sérieusement sur un périmètre donné.

### Votre mission

Créer une mini-grille de test avec :

1. une question simple
2. une question ambiguë
3. une question limite

Pour chaque question :
- noter la réponse
- noter les sources récupérées
- tester une reformulation
- tester un autre réglage

### Restitution attendue

- réponses fiables
- réponses à surveiller
- réponses insuffisantes

---

## Challenge 10 — Challenge final : reconstruire le flow J2

**Statut** : Obligatoire  
**Durée indicative** : 60 à 90 min

### Situation métier

À la fin de la journée, les participants doivent être capables de reconstituer le flow documentaire à partir de ce qu'ils ont compris.

### Votre mission

Sur un canvas vide, reconstruire un flow inspiré de **J2 - RAG Chat**.

### Contraintes

Le flow reconstruit doit contenir :
- un loader de dossier
- un bloc d'embeddings
- un vector store
- un modèle de chat
- une chaîne de retrieval QA

Bonus :
- ajout d'un **File Loader**
- réglage de `topK`
- test de plusieurs modèles

### Aide minimale à donner

Ordre logique à retrouver :

1. documents
2. embeddings
3. vector store
4. retriever
5. modèle
6. chaîne de réponse

<details>
<summary>Variante de solution A — reconstruction minimale</summary>

Ordre de construction attendu :

1. **Folder with Files**
2. **OpenAI Embedding**
3. **In-Memory Vector Store**
4. **OpenAI**
5. **Conversational Retrieval QA Chain**

Connexions :

- `Folder with Files` → `In-Memory Vector Store` sur l'entrée document
- `OpenAI Embedding` → `In-Memory Vector Store` sur l'entrée embeddings
- `In-Memory Vector Store` → `Conversational Retrieval QA Chain` sur l'entrée retriever
- `OpenAI` → `Conversational Retrieval QA Chain` sur l'entrée modèle

</details>

<details>
<summary>Variante de solution B — reconstruction enrichie</summary>

Même base que la solution minimale, avec en plus :

1. **File Loader**
2. connexion du `File Loader` vers `In-Memory Vector Store`
3. réglage de `topK`
4. changement de modèle pour comparer les réponses
5. test d'un upload manuel depuis le chat

</details>

### Critère de réussite

Le participant doit être capable d'expliquer :
- à quoi sert chaque bloc
- où se fait la recherche documentaire
- où se fait la réponse finale
- quels paramètres influencent la fiabilité

---

## Ce qui doit être acquis à la fin du jour 2

- ✅ expliquer simplement le RAG
- ✅ comparer J1 et J2
- ✅ régler `topK`, température et modèle
- ✅ tester un cas limite avec reformulation
- ✅ faire un double check
- ✅ distinguer retrieval correct et synthèse fragile
- ✅ reconstruire un flow documentaire cohérent

### Priorité minimale si le temps manque

Si la journée prend du retard, conserver absolument :

1. Challenge 1
2. Challenge 3
3. Challenge 5
4. Challenge 9
5. Challenge 10

---

## Conclusion des 2 jours

Le jour 1 apprend à mieux **parler au modèle**.  
Le jour 2 apprend à mieux **l'ancrer dans des documents** et à **contrôler sa fiabilité**.
