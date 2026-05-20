# TP J1 — Chat Simple avec Flowise

## Objectif

Prendre en main Flowise en explorant un flow de chat simple, comprendre ses composants et le modifier.

## Durée

~45 minutes

## Avant de commencer

Vérifier que la stack est opérationnelle :

```bash
# Depuis la racine du projet
make up
make ping      # doit répondre "pong"
make api-key   # récupérer la clé API
```

Ouvrir http://localhost:3000 et se connecter avec :
- **Email** : `admin@local.dev`
- **Mot de passe** : `changeme_admin_password`

---

## 1. Explorer le flow J1 (10 min)

1. Aller dans **Chatflows** → ouvrir **J1 - Simple Chat**
2. Observer les 3 nœuds connectés :

| Nœud | Rôle |
|------|------|
| **ChatOpenAI** | Modèle de langage (GPT-4.1 nano via la gateway Liora) |
| **Buffer Memory** | Stocke l'historique de la conversation |
| **Conversation Chain** | Chaîne qui relie le modèle et la mémoire |

3. Cliquer sur chaque nœud pour inspecter ses paramètres
4. Trouver le paramètre `temperature` du ChatOpenAI — quelle est sa valeur ?

<details>
<summary>Réponse</summary>
0.9 — une valeur relativement haute qui rend les réponses plus créatives.
</details>

---

## 2. Tester le chat (10 min)

1. Cliquer sur le bouton **Chat** en haut à droite
2. Poser les questions suivantes :
   - *"Bonjour, qui es-tu ?"*
   - *"Quel temps fait-il aujourd'hui ?"*
   - *"Que viens-je de te demander ?"*
3. La troisième question montre que la **Buffer Memory** retient le contexte
4. Observer que les réponses du LLM sont générales — il n'a pas accès à des documents spécifiques

---

## 3. Modifier la température (10 min)

1. Cliquer sur le nœud **ChatOpenAI**
2. Modifier `temperature` :
   - Mettre à `0` → les réponses seront plus déterministes
   - Cliquer sur **Save**
3. Tester à nouveau : la variabilité des réponses diminue
4. Remettre `temperature` à `0.9`

---

## 4. Ajouter un System Prompt (15 min)

Le flow actuel n'a pas de **System Prompt** — le LLM n'a pas d'instructions de base.

1. Dans le panneau de gauche, chercher **Prompt Template** (catégorie Prompts)
2. Le glisser-déposer sur le canvas
3. Le connecter :
   - Sortie de **Prompt Template** → entrée `Prompt` de **Conversation Chain**
4. Dans **Prompt Template**, écrire :

```
Tu es un assistant expert en paie et RH français.
Réponds de manière concise et professionnelle.
Si tu ne connais pas la réponse, dis-le honnêtement.
```

5. Cliquer sur **Save**
6. Tester : *"Qu'est-ce que la DSN ?"* → la réponse doit refléter le rôle RH

---

## 5. Aller plus loin (bonus)

- Essayer un autre modèle dans la liste des Chat Models (ex: **ChatMistral**)
- Ajouter un nœud **Sticky Note** avec une consigne pour l'équipe
- Exporter le flow : cliquez sur l'icône d'export (download) → observer le JSON

---

## Vérification

Votre flow modifié doit inclure :
- [ ] Un nœud **Prompt Template** connecté à la Conversation Chain
- [ ] Un système prompt qui définit le rôle RH de l'assistant
- [ ] Le chat retient le contexte (Buffer Memory fonctionnelle)
