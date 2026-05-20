# TP J1 — Mon premier chat avec Flowise

**Public** : Utilisateurs métier — pas de code, pas de terminal.

**Durée** : ~30 min

**Objectif** : Découvrir Flowise en explorant un chat simple, comprendre les blocs visuels, et personnaliser le comportement du chatbot.

---

## Avant de commencer

1. Ouvrir votre navigateur sur **http://localhost:3000**
2. Se connecter avec :
   - **Email** : `admin@local.dev`
   - **Mot de passe** : `changeme_admin_password`

---

## 1. Ouvrir le flow

1. Dans le menu de gauche, cliquer sur **Chatflows**
2. Cliquer sur la carte **J1 - Simple Chat** pour l'ouvrir
3. Vous voyez un canvas (toile blanche) avec des blocs reliés par des flèches

---

## 2. Comprendre les blocs

Il y a **3 blocs** reliés entre eux :

| Bloc | À quoi ça sert ? |
|------|-----------------|
| **OpenAI** (vert) | C'est le cerveau du chatbot — un modèle GPT qui comprend et répond |
| **Buffer Memory** (violet) | La mémoire — sans lui le chatbot oublierait tout après chaque message |
| **Conversation Chain** (orange) | Le chef d'orchestre qui relie le cerveau et la mémoire |

**À faire :** Cliquer sur chaque bloc pour voir ses réglages (colonne de droite).

> **Question :** Quel est le modèle utilisé dans le bloc OpenAI ?
> <details><summary>Réponse</summary>gpt-4.1-nano — un modèle rapide et économique.</details>

---

## 3. Tester le chat

1. Cliquer sur le bouton **Chat** (en haut à droite)
2. Taper : *"Bonjour, qui es-tu ?"*
3. Puis : *"Quel temps fait-il à Paris aujourd'hui ?"*
4. Puis : *"Que viens-je de te demander ?"*

👉 La 3e question montre que le chatbot **se souvient** de la conversation — c'est la **Buffer Memory** qui garde l'historique.

---

## 4. Rendre le chatbot moins créatif

Le paramètre **Temperature** contrôle la créativité des réponses :
- **0** = réponses toujours identiques (prévisible)
- **1** = réponses variées (créatif)
- **2** = réponses très variables (peut inventer)

**À faire :**

1. Cliquer sur le bloc **OpenAI** (vert)
2. Dans le panneau de droite, repérer le champ **Temperature**
3. Mettre la valeur à **0** (au lieu de 0.9)
4. Cliquer sur le bouton **Save** en haut à droite
5. Rouvrir le Chat et poser la même question 2 fois → les réponses sont presque identiques
6. Remettre la température à **0.9** et sauvegarder

---

## 5. Donner un rôle au chatbot

Actuellement le chatbot répond de manière générale. On va lui donner des **instructions personnalisées**.

**À faire :**

1. Dans le panneau de gauche, cliquer sur l'onglet **Prompts**
2. Chercher le bloc **Prompt Template** dans la liste
3. Le **glisser-déposer** sur le canvas (la toile blanche)
4. Relier les blocs :
   - Cliquer sur la sortie (point noir) du bloc **Prompt Template**
   - Glisser jusqu'à l'entrée **Prompt** du bloc **Conversation Chain** (orange)
5. Cliquer sur le bloc **Prompt Template** pour ouvrir ses réglages
6. Dans le champ texte, écrire :

```
Tu es un expert en paie et RH français.
Tu réponds de manière claire et professionnelle.
Si tu ne sais pas, tu le dis honnêtement.
```

7. Cliquer sur **Save** (en haut à droite)
8. Tester dans le Chat : *"C'est quoi la DSN ?"*
   → La réponse doit maintenant être précise et liée à la paie

---

## 6. Résumé

Vous avez appris à :
- ✅ Ouvrir et explorer un flow Flowise
- ✅ Comprendre le rôle des blocs (modèle, mémoire, chaîne)
- ✅ Modifier la température du modèle
- ✅ Ajouter un bloc d'instructions (Prompt Template)
- ✅ Tester le chat et voir l'effet de la mémoire
