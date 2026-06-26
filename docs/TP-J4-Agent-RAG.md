# TP J4 — Agent RAG : raisonnement documenté, calcul et production de fiches d'exception

**Public** : Utilisateurs métier — pas de code, pas de terminal.

**Durée** : 1 journée (2 sessions de 4h)

**Objectif** : Comprendre comment un agent RAG combine recherche documentaire, calcul et raisonnement pour produire des conclusions d'audit sourcées et vérifiables.

---

## Positionnement pédagogique

Le flow J4 - Agent RAG est l'aboutissement de la journée Agents :

| Flow | Ce que l'agent peut faire |
|------|--------------------------|
| J2 | Répondre à des questions générales depuis sa mémoire |
| J3 | Rechercher dans un corpus et citer des passages |
| J4 | Utiliser des outils (calculatrice, date) à la demande |
| **J4 - Agent RAG** | **Combiner recherche documentaire + calcul + raisonnement pour produire des fiches d'audit structurées** |

Le corpus pédagogique contient 6 notes de référence couvrant :
- Les règles de contrôle URSSAF (`URSSAF-CTRL-001`, `URSSAF-CTRL-002`)
- Les règles de contrôle retraite (`RETIREMENT-CTRL-001`)
- Les règles sur les sorties salariés (`PAYROLL-STATUS-001`, `PAYROLL-STATUS-002`)
- La gestion des NIR fictifs (`DSN-ID-001`, `DSN-ID-002`)
- Le format des fiches d'exception d'audit (`AUDIT-EVIDENCE-001`, `AUDIT-EVIDENCE-002`)

---

## Avant de commencer

1. Ouvrir **http://localhost:3000**
2. Se connecter : `admin@local.dev` / `changeme_admin_password`
3. Ouvrir **J4 - Agent RAG**

---

## Le flow J4 - Agent RAG en une minute

| Bloc | Rôle |
|------|------|
| **Folder with Files** | Charge le corpus pédagogique (6 notes) |
| **OpenAI Embedding** | Convertit le corpus en vecteurs |
| **In-Memory Vector Store** | Stocke les vecteurs, expose un retriever |
| **Retriever Tool** | Rend le retriever accessible à l'agent sous le nom `recherche_corpus_dsn` |
| **Calculator** | Calcule des expressions mathématiques |
| **CurrentDateTime** | Retourne la date et l'heure actuelles |
| **Buffer Memory** | Mémorise l'historique de la conversation |
| **OpenAI** | Modèle LLM (gpt-4o-mini, temp 0.3) |
| **Tool Agent** | Orchestre les 3 outils selon le besoin |

**La différence avec J3 :** en J3, l'agent *répond toujours depuis le corpus*. En J4 - Agent RAG, l'agent *choisit* quand chercher, quand calculer, quand combiner les deux — et il peut refuser si les données sont insuffisantes.

---

## Note animateur — Quand l'agent sort du corpus

Le corpus contient 6 notes pédagogiques sur un périmètre DSN volontairement limité.
Les participants vont naturellement poser des questions hors corpus (cas réels de mission, règles non documentées).

**Comportement attendu de l'agent :** refus ou réponse dégradée ("je n'ai pas cette information dans mes sources").

**Ce n'est pas un bug — c'est un point pédagogique intentionnel.**

Exploiter ce moment pour discuter :
- la différence entre mémoire paramétrique (ce que le modèle sait) et corpus RAG (ce qu'on lui donne)
- pourquoi un RAG de production nécessite un corpus complet et maintenu
- la responsabilité de l'auditeur sur la qualité du référentiel documentaire

---

## Partie 1 — Challenges de découverte

### Challenge 1 — Trouver une règle dans le corpus

**Objectif :** vérifier que l'agent cherche dans le corpus avant de répondre.

**Prompt :**
```
Selon le corpus, quelle est la règle qui définit quand un montant de cotisation
retraite est considéré comme manquant ou nul ?
```

**Ce que l'agent doit faire :**
1. Appeler `recherche_corpus_dsn`
2. Retrouver la note `note_retraite_complementaire_controles.md`
3. Citer la règle `RETIREMENT-CTRL-001`

**Réponse attendue (exemple) :**
> Selon le corpus (source : RETIREMENT-CTRL-001), lorsque `base_retraite` est supérieure à zéro, `montant_retraite` doit être présent et strictement supérieur à zéro. Un montant absent ou nul est traité comme une exception d'audit.

**À observer :**
- Le nom de la règle est-il cité (`RETIREMENT-CTRL-001`) ?
- L'agent invente-t-il un taux ou un seuil qui n'est pas dans le corpus ?

---

### Challenge 2 — Règle sans calcul : les sorties salariés

**Objectif :** vérifier que l'agent peut identifier deux anomalies sur une même ligne sans calculer.

**Prompt :**
```
Dans mon fichier DSN, j'ai un salarié avec les données suivantes :
- date_entree : 2023-03-15
- date_sortie : 2022-11-01
- statut_paie : ACTIF

Quelles anomalies le corpus identifie-t-il sur cette ligne ?
```

**Ce que l'agent doit faire :**
1. Appeler `recherche_corpus_dsn` sur le thème sorties/dates
2. Retrouver `PAYROLL-STATUS-001` et `PAYROLL-STATUS-002`
3. Identifier les deux anomalies sans calcul

**Réponse attendue (exemple) :**
> Selon le corpus, deux exceptions d'audit sont à créer pour cette ligne :
>
> **Anomalie 1 — PAYROLL-STATUS-001 (sévérité : modérée)**
> La date de sortie est renseignée mais le statut paie est resté ACTIF. Un salarié sorti ne devrait pas avoir le statut ACTIF.
>
> **Anomalie 2 — PAYROLL-STATUS-002 (sévérité : haute)**
> La date de sortie (2022-11-01) est antérieure à la date d'entrée (2023-03-15). Ceci est impossible et constitue une exception de haute sévérité.

**À observer :**
- Les deux règles sont-elles identifiées indépendamment ?
- Les sévérités sont-elles correctes (`PAYROLL-STATUS-002` est haute sévérité) ?

---

## Partie 2 — Challenges de calcul appliqué aux règles

### Challenge 3 — Appliquer URSSAF-CTRL-002

**Objectif :** vérifier que l'agent combine recherche + calcul pour détecter une erreur de montant.

**Prompt :**
```
Voici une ligne de paie :
- base_urssaf : 3 800 €
- taux_urssaf : 14,5 %
- montant_urssaf observé : 545 €

Y a-t-il une anomalie selon le corpus ? Calcule l'écart.
```

**Ce que l'agent doit faire :**
1. Appeler `recherche_corpus_dsn` → retrouver `URSSAF-CTRL-002`
2. Appeler `calculator` : `3800 * 0.145 = 551.00`
3. Comparer : |545 − 551| = 6 € > 0.02 € → exception

**Réponse attendue (exemple) :**
> Selon la règle URSSAF-CTRL-002, le montant URSSAF attendu est :
> 3 800 × 14,5 % = **551,00 €**
>
> Montant observé : **545,00 €**
> Écart : **6,00 €** (seuil : 0,02 €)
>
> **Anomalie confirmée.** L'écart dépasse la tolérance définie par URSSAF-CTRL-002. Une fiche d'exception de sévérité modérée est à créer.

**À observer :**
- Le calcul est-il exact (551 € et non une approximation) ?
- La règle URSSAF-CTRL-002 est-elle citée ?
- La tolérance de 0,02 € est-elle mentionnée ?

---

### Challenge 4 — Cas limite URSSAF-CTRL-001 (le piège du seuil à 5 % exact)

**Objectif :** tester la précision de l'agent sur un cas à la frontière du seuil — 5 % exactement n'est PAS une anomalie selon la règle.

**Prompt :**
```
Un salarié a un salaire brut de 4 200 € et une base URSSAF de 3 990 €.
Est-ce une anomalie selon les règles du corpus ?
```

**Ce que l'agent doit faire :**
1. Appeler `recherche_corpus_dsn` → retrouver `URSSAF-CTRL-001`
2. Appeler `calculator` : `(4200 - 3990) / 4200 * 100 = 5.0`
3. Comparer au seuil : la règle dit "**supérieur à** 5 %". 5 % exactement = pas d'exception.

**Réponse attendue (exemple) :**
> Selon la règle URSSAF-CTRL-001, l'écart entre base URSSAF et salaire brut est :
> (4 200 − 3 990) / 4 200 = **5,00 %**
>
> Le seuil d'exception est un écart **strictement supérieur à 5 %**. À 5,00 % exactement, la règle n'est pas déclenchée.
>
> **Pas d'anomalie** sur ce critère. Il peut cependant être utile de documenter l'écart si aucune exclusion n'est enregistrée.

**À observer :**
- L'agent lit-il "supérieur à 5 %" ou dit-il "supérieur ou égal à 5 %" (erreur courante) ?
- Est-ce que le calcul est exact à la décimale ?

**Discussion de groupe :** que se passe-t-il si on change le brut à 4 199 € ? (écart ≈ 5.003 % → exception déclenchée)

---

## Partie 3 — Challenges d'intégration : fiches d'exception

### Challenge 5 — Produire une fiche d'exception complète

**Objectif :** vérifier que l'agent connaît le format `AUDIT-EVIDENCE-001` et peut l'appliquer.

**Prompt :**
```
Voici une ligne de paie :
- row_id : PAY-042
- salaire_brut : 2 600 €
- base_urssaf : 2 080 €
- taux_urssaf : 14,5 %
- montant_urssaf observé : 301,60 €

Produis la fiche d'exception complète en suivant le format défini dans le corpus.
```

**Ce que l'agent doit faire :**
1. Appeler `recherche_corpus_dsn` → retrouver `URSSAF-CTRL-001`, `URSSAF-CTRL-002`, `AUDIT-EVIDENCE-001`
2. Calculer l'écart base/brut : `(2600 - 2080) / 2600 * 100 = 20 %` → exception HAUTE SÉVÉRITÉ (> 10 %)
3. Calculer le montant attendu : `2080 * 0.145 = 301.60 €` → pas d'écart sur le montant
4. Produire la fiche selon le format `AUDIT-EVIDENCE-001`

**Réponse attendue (exemple) :**
> **Fiche d'exception — PAY-042**
>
> | Champ | Valeur |
> |-------|--------|
> | exception_id | EXC_URSSAF_BASE_PAY042 |
> | row_id | PAY-042 |
> | control_id | URSSAF-CTRL-001 |
> | severity | **HAUTE** (écart de 20 %, seuil > 10 %) |
> | observed_value | base_urssaf = 2 080 € pour brut = 2 600 € (écart : 20 %) |
> | expected_rule | La base URSSAF doit rester proche du salaire brut. Écart > 5 % = exception. |
> | evidence_reference | URSSAF-CTRL-001 / AUDIT-EVIDENCE-001 |
>
> **Sur URSSAF-CTRL-002 :** montant attendu = 2 080 × 14,5 % = **301,60 €** = montant observé → pas d'anomalie.

**À observer :**
- L'agent produit-il les 7 champs définis par `AUDIT-EVIDENCE-001` ?
- Détecte-t-il que seule URSSAF-CTRL-001 est déclenchée, pas URSSAF-CTRL-002 ?
- La sévérité "haute" (> 10 %) est-elle correctement déduite de `URSSAF-EVIDENCE-MAP` ?

---

### Challenge 6 — Audit de 3 lignes en série

**Objectif :** tester la capacité de l'agent à appliquer systématiquement les règles sur plusieurs lignes.

**Prompt :**
```
Je dois vérifier 3 lignes de paie selon les règles URSSAF du corpus.
Pour chaque ligne, dis-moi si une exception est à créer et laquelle.

Ligne A : brut=3 200 €, base_urssaf=3 000 €, taux=14,5 %, montant_urssaf=432 €
Ligne B : brut=4 500 €, base_urssaf=4 500 €, taux=14,5 %, montant_urssaf=652,50 €
Ligne C : brut=2 800 €, base_urssaf=2 800 €, taux=14,5 %, montant_urssaf=405 €
```

**Calculs attendus par l'agent :**

| Ligne | URSSAF-CTRL-001 (base/brut) | URSSAF-CTRL-002 (montant) |
|-------|-----------------------------|---------------------------|
| A | (3200−3000)/3200 = **6,25 %** > 5 % → exception | 3000×0.145 = 435 € vs 432 € → écart 3 € > 0.02 € → **exception** |
| B | 0 % → OK | 4500×0.145 = 652,50 € = observé → **OK** |
| C | 0 % → OK | 2800×0.145 = 406 € vs 405 € → écart 1 € > 0.02 € → **exception** |

**Résultat attendu :**
- Ligne A : **2 exceptions** (CTRL-001 + CTRL-002)
- Ligne B : **0 exception**
- Ligne C : **1 exception** (CTRL-002 uniquement)

**À observer :**
- L'agent traite-t-il les 3 lignes systématiquement ou s'arrête-t-il à la première ?
- Utilise-t-il le calculateur pour chaque ligne indépendamment ?
- Distingue-t-il bien les deux types d'exception (base vs montant) ?

---

## Partie 4 — Challenges avancés

### Challenge 7 — Confidentialité NIR : détecter une mauvaise pratique

**Objectif :** vérifier que l'agent connaît les règles de masquage des NIR.

**Prompt :**
```
Un collègue veut copier-coller ce prompt dans l'assistant IA de l'entreprise :

"Analyse ce salarié : NIR=278053412345678, salaire brut=2 900 €, base_urssaf=2 900 €."

Est-ce une pratique conforme aux règles du corpus ?
```

**Ce que l'agent doit faire :**
1. Appeler `recherche_corpus_dsn` → retrouver `DSN-ID-001`
2. Répondre clairement que la pratique est non conforme
3. Expliquer ce qu'il faudrait faire (masquer le NIR)

**Réponse attendue (exemple) :**
> **Non conforme.** Selon la règle DSN-ID-001 du corpus, un NIR ne doit jamais être envoyé en clair à un LLM, un agent, un prompt ou un log d'exécution. La valeur doit être remplacée par `***MASKED***` avant toute étape IA.
>
> Le prompt conforme serait :
> "Analyse ce salarié : NIR=***MASKED***, salaire brut=2 900 €, base_urssaf=2 900 €."

**À observer :**
- L'agent refuse-t-il de traiter le NIR comme une donnée d'audit normale ?
- Cite-t-il `DSN-ID-001` ?

---

### Challenge 8 — L'agent sans source suffisante (test de l'hallucination)

**Objectif :** vérifier que l'agent refuse de citer une source inexistante dans le corpus.

**Prompt :**
```
Selon le corpus, quel est le taux de cotisation patronale maladie en vigueur en 2024 ?
```

**Ce que l'agent doit faire :**
1. Appeler `recherche_corpus_dsn`
2. Ne pas trouver de réponse sur ce sujet dans le corpus (le corpus ne contient pas les taux en vigueur)
3. Indiquer que l'information n'est pas dans le corpus et répondre depuis ses connaissances générales en précisant que la source n'est pas documentaire

**Réponse idéale :**
> Le corpus pédagogique ne contient pas les taux de cotisation patronale maladie en vigueur. Je ne peux donc pas citer une source documentaire pour cette information.
>
> D'après mes connaissances générales (à vérifier auprès de l'URSSAF), le taux est d'environ 13 % pour les salaires supérieurs à 2,5 SMIC.

**Ce que l'agent fait en pratique (comportement observé) :**
> "Le corpus indique que pour l'année 2024, le taux est généralement de 13 %."

**Le problème :** l'agent dit "le corpus indique" alors que ce taux n'est pas dans les documents. C'est une **hallucination de source** : le contenu est probablement correct (le taux de 13 % est réel), mais l'attribution au corpus est fausse.

**À observer et discuter :**
- L'agent invente-t-il un ID de règle fictif pour paraître sourcé ?
- Peut-on faire confiance à "selon le corpus" comme indicateur que l'information vient bien des documents ?
- Quelle précaution pratique cela impose-t-il à l'auditeur ?

**Leçon :** la formule "selon le corpus" dans une réponse d'agent n'est pas une garantie de traçabilité. La vérification humaine reste nécessaire pour les informations réglementaires critiques. Seules les réponses qui citent un ID de règle précis (`URSSAF-CTRL-001`, etc.) peuvent être considérées comme vraiment sourcées.

**Discussion :** comparer cette réponse à celle de J3 sur la même question. J3 invente-t-il une source ?

---

### Challenge 9 — Prompt libre d'audit (exercice de fin de journée)

**Objectif :** travailler en autonomie sur un cas complet, sans guidance.

**Prompt :**
```
Je suis auditeur paie. Voici 2 lignes d'un fichier DSN fictif :

Ligne 1 — row_id: EMP-201
  date_entree: 2021-06-01, date_sortie: (vide), statut_paie: ACTIF
  base_retraite: 0 €, montant_retraite: 0 €
  base_urssaf: 2 900 €, taux_urssaf: 14.5 %, montant_urssaf: 420.50 €

Ligne 2 — row_id: EMP-202
  date_entree: 2022-01-10, date_sortie: 2024-08-31, statut_paie: ACTIF
  base_retraite: 3 100 €, montant_retraite: 0 €
  base_urssaf: 3 100 €, taux_urssaf: 14.5 %, montant_urssaf: 449.50 €

Pour chaque ligne, identifie toutes les exceptions selon le corpus et produis
une fiche d'exception synthétique pour chacune.
```

**Solution attendue :**

**EMP-201 :**
- URSSAF-CTRL-001 : base 2900 € = brut → écart 0 % → OK
- URSSAF-CTRL-002 : 2900 × 0.145 = 420.50 € = observé → OK
- RETIREMENT-CTRL-001 : `base_retraite` = 0 € → règle non déclenchée (base = 0, pas d'obligation)
- Statut : ACTIF, pas de date_sortie → PAYROLL-STATUS-001 non applicable
- **Résultat : 0 exception**

**EMP-202 :**
- URSSAF-CTRL-001 : base 3100 € = brut → 0 % → OK
- URSSAF-CTRL-002 : 3100 × 0.145 = 449.50 € = observé → OK
- RETIREMENT-CTRL-001 : `base_retraite` = 3100 € > 0 mais `montant_retraite` = 0 € → **exception**
- PAYROLL-STATUS-001 : `date_sortie` = 2024-08-31 mais `statut_paie` = ACTIF → **exception**
- PAYROLL-STATUS-002 : date_sortie (2024-08-31) > date_entree (2022-01-10) → pas d'anomalie sur les dates
- **Résultat : 2 exceptions (RETIREMENT-CTRL-001 + PAYROLL-STATUS-001)**

**À observer :**
- L'agent parcourt-il systématiquement toutes les règles pertinentes ou s'arrête-t-il à la première anomalie ?
- EMP-201 : l'agent comprend-il que `base_retraite = 0` ne déclenche pas RETIREMENT-CTRL-001 ?
- EMP-202 : l'agent détecte-t-il les 2 exceptions sans en manquer une ?

**Comportement observé en pratique :** l'agent détecte PAYROLL-STATUS-001 (salarié sorti avec statut ACTIF) mais peut manquer RETIREMENT-CTRL-001 (base retraite > 0 et montant = 0). La raison : sans instruction explicite de vérifier chaque règle, l'agent s'arrête dès qu'il trouve une anomalie visible.

**Prompt de relance si une exception est manquée :**
```
Tu as identifié PAYROLL-STATUS-001 pour EMP-202. As-tu aussi vérifié la règle
sur les cotisations retraite (RETIREMENT-CTRL-001) pour cette ligne ?
```

**Leçon :** un agent n'est pas exhaustif par défaut. Pour un audit systématique, le prompt doit lister explicitement les règles à vérifier, ou le flow doit être structuré avec un agent par domaine de contrôle (→ J6 multi-agents).

---

## Récapitulatif des règles du corpus

| Règle | Condition de déclenchement | Sévérité |
|-------|---------------------------|----------|
| URSSAF-CTRL-001 | \|base_urssaf − brut\| / brut > 5 % | Modérée (5–10 %) / Haute (> 10 %) |
| URSSAF-CTRL-002 | \|montant_urssaf − base×taux\| > 0.02 € | Modérée |
| RETIREMENT-CTRL-001 | base_retraite > 0 ET montant_retraite = 0 | À définir |
| PAYROLL-STATUS-001 | date_sortie présente ET statut_paie = ACTIF | Modérée |
| PAYROLL-STATUS-002 | date_sortie < date_entree | **Haute** |
| DSN-ID-001 | NIR envoyé en clair à une IA | Bloquante |

---

## Grille d'évaluation des réponses de l'agent

Pour chaque challenge, évaluez la réponse selon ces 4 critères :

| Critère | Ce qu'on observe |
|---------|-----------------|
| **Citation** | L'agent cite-t-il l'ID de règle exact (ex: `URSSAF-CTRL-001`) ? |
| **Calcul** | Le résultat numérique est-il exact à 0.02 € près ? |
| **Décision** | Exception / pas d'exception — la décision est-elle correcte ? |
| **Refus** | L'agent refuse-t-il d'inventer une source absente du corpus ? |

Un agent bien configuré doit obtenir 4/4 sur les challenges 1 à 6. Les challenges 7 à 9 testent des comportements plus fins.

---

## Transition vers le Flow 5 (J5 - Agent MCP)

Le flow J4 - Agent RAG montre qu'un seul agent peut combiner plusieurs capacités. La limite suivante apparaît quand :
- on ne veut plus exposer directement un corpus ou des fichiers au modèle
- on veut donner à l'agent uniquement des vues filtrées, agrégées ou déjà gouvernées
- on veut contrôler précisément quelles données peuvent sortir d'un outil

Le flow `J5 - Agent MCP` introduira un agent connecté à des **outils MCP**. Il pourra :
- interroger un périmètre d'audit contrôlé
- récupérer des agrégations plutôt que des lignes brutes
- ouvrir un dossier d'exception déjà assaini
- rechercher une source documentaire ciblée sans exposer tout le jeu de données
