# TP J1 — Prompting métier, sécurité et psychologie des modèles

**Public** : Utilisateurs métier — pas de code, pas de terminal.

**Durée** : 1 journée (2 sessions de 4h)

**Objectif** : Comprendre comment mieux utiliser un modèle généraliste dans un contexte d'audit paie, avant d'introduire le RAG au jour 2.

---

## Positionnement pédagogique

Le jour 1 n'a pas pour but de "faire du Flowise" pour faire du Flowise.

Le but est de faire pratiquer :

1. la différence entre une question vague et une consigne exploitable
2. l'effet d'un **rôle**, d'un **contexte**, d'une **tâche** et d'un **format**
3. l'intérêt d'un **prompt système**
4. l'intérêt du **few-shot**
5. les réflexes de **confidentialité**
6. la comparaison entre **modèles** et **réglages**

Le flow J1 sert donc de laboratoire de prompting.

---

## Avant de commencer

1. Ouvrir votre navigateur sur **http://localhost:3000**
2. Se connecter avec :
   - **Email** : `admin@local.dev`
   - **Mot de passe** : `changeme_admin_password`
3. Ouvrir **Chatflows**
4. Cliquer sur **J1 - Simple Chat**

---

## Le flow J1 en une minute

| Bloc | Rôle |
|------|------|
| **OpenAI** | Le modèle qui génère la réponse |
| **Buffer Memory** | La mémoire de conversation |
| **Conversation Chain** | Le bloc qui orchestre l'échange |

**À observer avant de commencer :**
- le modèle utilisé
- la température
- le comportement de mémoire

---

## Déroulé conseillé de la journée

### Matin — Comprendre et structurer ses consignes

- introduction aux familles de modèles
- sécurité et confidentialité
- prompting simple vs structuré
- rôle, contexte, tâche, format
- few-shot

### Après-midi — Faire varier le comportement du modèle

- prompt système
- température
- changement de modèle
- comparaison de résultats
- atelier final d'auditeur augmenté

---

## Règle d'animation

Pour chaque challenge :

- **Obligatoire** : à faire par tous les groupes
- **Bonus** : à faire si le groupe avance vite ou pour enrichir le débrief
- **Durée indicative** : aide à tenir le rythme, sans rigidifier l'animation

---

## Challenge 1 — Transformer une question floue en consigne exploitable

**Statut** : Obligatoire  
**Durée indicative** : 30 à 40 min

### Situation métier

Vous recevez une règle RH rédigée de manière peu claire.  
Vous voulez demander à l'IA d'identifier les zones d'ambiguïté.

### Question de départ

*"Analyse cette clause et dis-moi si elle est risquée."*

### Votre mission

1. poser cette version brute
2. constater les limites de la réponse
3. réécrire la consigne pour obtenir quelque chose d'exploitable

### Ce qu'on cherche

Une réponse acceptable doit :
- résumer la clause
- identifier les ambiguïtés
- proposer des points de vigilance
- rester prudente

### Pistes

- donner un rôle au modèle
- expliquer le contexte
- préciser le travail attendu
- imposer un format de restitution

<details>
<summary>Variante de solution A</summary>

```text
Tu es un auditeur paie expérimenté.

Contexte :
Je relis une consigne RH avant de l'utiliser dans un contrôle.

Tâche :
Analyse la clause ci-dessous et identifie les ambiguïtés ou les risques d'interprétation.

Format attendu :
- Résumé en 2 phrases
- 3 points de vigilance maximum
- Conclusion claire
```

</details>

<details>
<summary>Variante de solution B</summary>

```text
Joue le rôle d'un expert paie et conformité.

Je veux savoir si cette clause est exploitable dans un audit.

Merci de répondre avec :
1. Ce que la clause veut dire
2. Ce qui est flou ou risqué
3. Ce qu'un auditeur devrait vérifier avant de l'appliquer
4. Un niveau de confiance : élevé / moyen / faible
```

</details>

### Débrief

Questions à poser :
- Qu'est-ce qui a le plus amélioré la réponse ?
- Le rôle a-t-il changé quelque chose ?
- Le format imposé a-t-il rendu la réponse plus utile ?

---

## Challenge 2 — Sécurité : que peut-on ou non coller dans un prompt ?

**Statut** : Obligatoire  
**Durée indicative** : 30 min

### Situation métier

Un collègue veut copier-coller un extrait de paie contenant :
- nom
- matricule
- NIR
- montant de salaire

Il vous demande : *"Je peux l'envoyer tel quel au modèle pour gagner du temps ?"*

### Votre mission

1. poser la question au chatbot
2. obtenir une réponse prudente
3. reformuler la demande pour faire ressortir les bonnes pratiques

### Ce qu'on cherche

La réponse acceptable doit :
- déconseiller l'envoi brut
- parler d'anonymisation ou de masquage
- rappeler le caractère sensible des données

### Pistes

- demander explicitement les risques
- demander une conduite à tenir
- faire apparaître RGPD / secret professionnel / anonymisation

<details>
<summary>Variante de solution A</summary>

```text
Tu es un assistant spécialisé en audit paie et confidentialité.

Question :
Un utilisateur veut copier-coller un extrait de paie avec nom, matricule et NIR dans une IA.

Explique :
- les risques
- pourquoi ce n'est pas une bonne pratique
- ce qu'il faudrait masquer avant tout traitement
```

</details>

<details>
<summary>Variante de solution B</summary>

```text
Réponds comme un référent conformité.

Je veux une réponse courte et opérationnelle :
- Est-ce acceptable ?
- Quels champs faut-il anonymiser ?
- Quelle règle simple faut-il retenir avant d'utiliser une IA en audit paie ?
```

</details>

### Mini-atelier

Transformer cette donnée :

```text
Nom : Marie Dupont
Matricule : 45872
NIR : 2850675123456
```

en version exploitable :

```text
Nom : SALARIE_01
Matricule : ID_001
NIR : ***MASKED***
```

---

## Challenge 3 — Utiliser un prompt système pour stabiliser le comportement

**Statut** : Obligatoire  
**Durée indicative** : 25 à 30 min

### Situation métier

Vous voulez que le chatbot réponde toujours comme un assistant d'audit paie prudent, même si l'utilisateur pose une question floue.

### Votre mission

1. ouvrir le bloc **Conversation Chain**
2. renseigner un **System Message**
3. tester plusieurs questions courtes

### Questions à tester

- *"C'est quoi la DSN ?"*
- *"Peux-tu interpréter cette consigne de contrôle ?"*
- *"Si tu hésites, tu fais quoi ?"*

### Ce qu'on cherche

Le chatbot doit :
- répondre en français
- rester structuré
- ne pas inventer une règle
- reconnaître l'incertitude

<details>
<summary>Variante de solution A</summary>

```text
Tu es un assistant d'audit paie.
Tu réponds en français.
Tu es prudent, clair et structuré.
Tu n'inventes pas de règle juridique ou sociale.
Si l'information est incertaine, tu le dis explicitement.
```

</details>

<details>
<summary>Variante de solution B</summary>

```text
Tu aides un auditeur paie à préparer ses analyses.
Ton rôle est d'expliquer, de structurer et de signaler les points de vigilance.
Tu privilégies des réponses courtes, concrètes et prudentes.
Quand tu n'as pas assez d'éléments, tu l'indiques au lieu d'improviser.
```

</details>

### Débrief

- Le système change-t-il une seule réponse ou tout le comportement ?
- Les réponses deviennent-elles plus homogènes ?

---

## Challenge 4 — Few-shot : obtenir un bon format de restitution

**Statut** : Obligatoire  
**Durée indicative** : 30 à 40 min

### Situation métier

Vous voulez que chaque réponse ressemble à une mini-fiche d'analyse.

### Votre mission

1. donner un exemple du format attendu
2. poser une nouvelle question métier
3. comparer avec une réponse sans exemple

### Question à tester

*"Cette procédure RH est-elle exploitable telle quelle dans un contrôle de paie ?"*

### Ce qu'on cherche

La réponse acceptable doit suivre un format stable, par exemple :
- résumé
- risque principal
- point à vérifier
- niveau de confiance

<details>
<summary>Variante de solution A</summary>

```text
Exemple de format attendu :

Question :
"Cette règle est-elle exploitable en audit ?"

Réponse :
- Résumé
- Risque principal
- Point à vérifier
- Niveau de confiance

Maintenant applique exactement ce format à la question suivante :
```

</details>

<details>
<summary>Variante de solution B</summary>

```text
Quand tu réponds, utilise toujours cette structure :

1. Résumé
2. Ce qui est exploitable
3. Ce qui doit être vérifié
4. Niveau de confiance

Exemple :
Question : "Une consigne partielle peut-elle être utilisée telle quelle ?"
Réponse :
1. Résumé : ...
2. Ce qui est exploitable : ...
3. Ce qui doit être vérifié : ...
4. Niveau de confiance : ...
```

</details>

---

## Challenge 5 — Température et stabilité

**Statut** : Obligatoire  
**Durée indicative** : 20 min

### Situation métier

Vous voulez comprendre si le modèle est stable quand on lui pose plusieurs fois la même question.

### Votre mission

1. mettre **Temperature = 0**
2. poser deux fois la même question
3. mettre ensuite une température plus haute
4. comparer

### Question proposée

*"Résume la DSN en 3 phrases pour un responsable RH."*

### Ce qu'on cherche

- à température basse : plus de stabilité
- à température haute : plus de variation

### Débrief

- quel réglage semble le plus adapté à un usage d'audit ?

---

## Challenge 6 — Changer de modèle

**Statut** : Bonus fort  
**Durée indicative** : 20 à 30 min

### Situation métier

Vous voulez comparer un modèle plus rapide et un modèle plus robuste sur la même consigne.

### Votre mission

1. noter le modèle actuel dans **OpenAI**
2. tester un autre modèle disponible
3. rejouer un même challenge
4. comparer :
   - vitesse
   - qualité
   - prudence
   - structure

### Cas conseillé

Rejouer **Challenge 1** ou **Challenge 4** avec les deux modèles.

### Débrief

- quel modèle semble suffisant pour une rédaction simple ?
- quel modèle gère le mieux une consigne plus structurée ?

---

## Challenge 7 — Atelier final : l'auditeur augmenté

**Statut** : Obligatoire  
**Durée indicative** : 45 à 60 min

### Situation métier

Vous devez interpréter une clause complexe de convention collective ou une consigne DSN ambiguë.

### Votre mission

Produire successivement :

1. un prompt simple
2. un prompt structuré
3. un prompt avec rôle métier
4. un prompt avec prompt système
5. un prompt avec exemple few-shot

### Restitution attendue

Pour chaque version :
- ce qui marche
- ce qui ne marche pas
- ce qui devient exploitable

### Critère de réussite

À la fin, le participant doit pouvoir expliquer :
- pourquoi la version finale est meilleure
- ce qui relève encore du jugement humain
- pourquoi une bonne réponse n'est pas une preuve

---

## Ce qui doit être acquis à la fin du jour 1

- ✅ structurer une demande métier
- ✅ utiliser un rôle, un contexte, une tâche et un format
- ✅ comprendre l'effet d'un prompt système
- ✅ utiliser un exemple few-shot
- ✅ adapter température et modèle
- ✅ appliquer un réflexe de confidentialité avant tout usage
- ✅ distinguer réponse plausible et réponse fiable

### Priorité minimale si le temps manque

Si la journée prend du retard, conserver absolument :

1. Challenge 1
2. Challenge 2
3. Challenge 3
4. Challenge 7

---

## Transition vers le jour 2

> Le jour 1 vous apprend à mieux parler à l'IA.  
> Le jour 2 vous apprendra à lui donner une bibliothèque documentaire et à tester sa fiabilité sur des règles métier.
