# TP J4 — Agent simple : raisonnement, outils et boucle agentique

**Public** : Utilisateurs métier — pas de code, pas de terminal.

**Durée** : 1 journée (2 sessions de 4h)

**Objectif** : Comprendre ce qu'est un agent IA, comment il diffère d'un chat ou d'une QA chain, et apprendre à configurer son comportement via le prompt système.

---

## Positionnement pédagogique

Le jour 4 marque un saut conceptuel : on passe d'un assistant qui **répond** à un assistant qui **raisonne et agit**.

Les trois journées précédentes ont posé les bases :

| Jour | Concept clé | Limitation visible |
|------|-------------|-------------------|
| J1 | Chat + mémoire | Pas de faits, hallucinations faciles |
| J2 | RAG — recherche dans des documents | Répond mais ne calcule pas |
| J3 | Paramètres, confidentialité, comparaison modèles | — |
| **J4** | **Agent — raisonnement + outils** | — |

Le flow J4 permet de pratiquer :

1. la différence **chaîne vs agent**
2. la lecture du flow bloc par bloc
3. la boucle **Observation → Raisonnement → Action → Réponse**
4. le rôle du **prompt système agentique**
5. la différence entre **répondre directement** et **utiliser un outil**
6. les réglages de modèle et de température sur un agent

---

## Avant de commencer

1. Ouvrir votre navigateur sur **http://localhost:3000**
2. Se connecter avec :
   - **Email** : `admin@local.dev`
   - **Mot de passe** : `changeme_admin_password`
3. Ouvrir **Chatflows**
4. Ouvrir **J4 - Agent Simple**

---

## Le flow J4 en une minute

| Bloc | Rôle |
|------|------|
| **OpenAI** | Modèle LLM avec capacité Function Calling |
| **Buffer Memory** | Mémorise l'historique de la conversation |
| **Calculator** | Outil : effectue des calculs arithmétiques |
| **CurrentDateTime** | Outil : retourne la date et l'heure actuelles |
| **Tool Agent** | Orchestre le raisonnement + les appels d'outils |

**Ce qui change par rapport à J2 :**
- J2 : question → modèle → réponse directe
- J4 : question → modèle **réfléchit** → décide si un outil est utile → appelle l'outil → observe le résultat → produit la réponse

---

## Déroulé conseillé de la journée

### Matin

- comprendre la boucle agentique
- comparer J2 et J4 sur des questions identiques
- lire le flow J4 bloc par bloc
- observer les intermediate steps (si activés)

### Après-midi

- modifier le prompt système
- ajouter un contexte métier plus précis
- tester les cas limites (outil utilisé ou non ?)
- challenge : quel prompt pousse l'agent à toujours utiliser la calculatrice ?

---

## Exercice 1 — Observer la différence agent / chat

### Étape 1 : poser la même question dans J2 et J4

Dans **J2 - Simple Chat**, posez :
```
Combien font 3200 × 6.8% ?
```

Dans **J4 - Agent Simple**, posez la même question.

**Comparez :**
- J2 donne-t-il un résultat ? Est-il exact ?
- J4 utilise-t-il la calculatrice ? Comment le sait-on ?

---

## Exercice 2 — Forcer l'usage d'un outil

### Question de référence (calcul)
```
Un salarié a un salaire brut de 4 500 euros. Le taux de cotisation patronale maladie est de 13%. 
Calcule le montant de la cotisation et le coût total employeur.
```

**Attendu :** l'agent appelle le calculateur. La réponse inclut les étapes.

### Question de référence (date)
```
Nous sommes en quelle période pour la prochaine déclaration DSN mensuelle ?
```

**Attendu :** l'agent appelle `CurrentDateTime` pour connaître la date du jour, puis raisonne sur la périodicité DSN.

---

## Exercice 3 — Réponse sans outil

Posez une question à laquelle l'agent peut répondre sans calculer :
```
Qu'est-ce qu'une DSN et à quelle fréquence doit-elle être déposée ?
```

**Attendu :** l'agent répond directement depuis ses connaissances, sans appeler d'outil.

**Point de discussion :** comment l'agent décide-t-il de ne pas utiliser d'outil ?

---

## Exercice 4 — Modifier le prompt système

### Accès au prompt

Dans le flow J4, cliquer sur le bloc **Tool Agent**, puis ouvrir **Additional Parameters** → **System Message**.

Le prompt actuel définit :
- le rôle de l'agent (expert paie/DSN)
- les cas d'usage
- la règle d'utilisation des outils

### Challenge : modifier le comportement

**Variante A — Rendre l'agent plus prudent**
Ajoutez à la fin du prompt :
```
Quand tu utilises le calculateur, rappelle toujours les formules que tu appliques avant de donner le résultat.
```

**Variante B — Changer le domaine**
Remplacez "audit de la paie" par "audit des notes de frais" et observez si le comportement change.

**Variante C — Interdire un outil**
Ajoutez : `Tu n'utilises jamais l'outil de date.`

Posez la question de date de l'exercice 2. L'agent respecte-t-il la consigne ?

---

## Exercice 5 — Régler le modèle

Dans le bloc **OpenAI**, modifiez :

| Paramètre | Valeur de départ | À tester |
|-----------|-----------------|----------|
| `temperature` | 0.7 | 0.0 puis 1.2 |
| `modelName` | gpt-4.1-nano | gpt-4o-mini |

Reposez la question de calcul de l'exercice 2. Observez :
- La formulation change-t-elle ?
- Le résultat numérique change-t-il ? (il ne devrait pas — le calcul est délégué à l'outil)
- Que se passe-t-il si `temperature = 1.2` sur un calcul ?

---

## Exercice 6 — Trouver les limites

Posez ces questions et notez le comportement :

1. `Calcule la racine carrée de 17.` — l'outil est-il utilisé ?
2. `Qui a créé la DSN en France et quand ?` — l'agent invente-t-il ?
3. `Donne-moi le taux de cotisation retraite AGIRC-ARRCO exact pour 2024.` — hallucination ou refus ?
4. `Calcule le net à payer d'un salarié avec un brut de 2800€ en tenant compte de toutes les cotisations.` — l'agent reconnaît-il ses limites (données manquantes) ?

**Conclusion :** quelles questions l'agent gère-t-il bien seul ? Quand lui manque-t-il des données (→ besoin du RAG agentique, deuxième flow de J4) ?

---

## Ce qu'on veut démontrer

| Notion | Comment elle est visible dans J4 |
|--------|----------------------------------|
| Boucle agentique | Les intermediate steps montrent Thought / Action / Observation |
| Séparation raisonnement / outil | L'outil calcule, le LLM interprète et reformule |
| Prompt système agentique | Modifier le prompt change les décisions de l'agent |
| Limites du savoir paramétrique | Sans RAG, l'agent invente ou refuse — prépare le flow `J4 - Agent RAG` |
| Function calling | Le modèle choisit l'outil, l'invoque et traite le résultat |

---

## Transition vers le Flow 4 (J4 - Agent RAG)

Le flow J4 a une limite claire : l'agent ne connaît pas vos documents. S'il pose une question sur un taux URSSAF spécifique, il répond depuis son entraînement (potentiellement obsolète) ou refuse.

**Le flow J4 - Agent RAG** ajoutera un outil `retrieverTool` connecté au vector store J3. L'agent pourra alors :
1. Chercher dans les documents DSN si nécessaire
2. Combiner une recherche documentaire + un calcul
3. Citer ses sources

La structure du flow J4 est conçue pour cette évolution : ajouter un nœud `Retriever Tool` branché sur l'ancre `tools` du `Tool Agent` est la seule modification structurelle requise.

---

## Référence rapide — Blocs du flow

### Tool Agent — paramètres clés

| Paramètre | Rôle |
|-----------|------|
| `System Message` | Définit le rôle, les outils disponibles, les règles de comportement |
| `Max Iterations` | Limite le nombre de tours raisonnement/action (évite les boucles) |
| `Enable Detailed Streaming` | Affiche les étapes intermédiaires dans le chat |

### Calculator — comportement

Le calculateur interprète des expressions mathématiques en texte naturel. Exemples qui fonctionnent :
- `3200 * 0.068`
- `(4500 * 13) / 100`
- `sqrt(144)`

### CurrentDateTime — comportement

Retourne la date, l'heure et le jour actuels. Utile pour raisonner sur des échéances DSN ou des périodes de paie.
