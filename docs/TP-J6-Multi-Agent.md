# TP J6 - Multi-agent supervise

## Objectif

Construire et tester un vrai `AgentFlow V2` Flowise dans lequel :
- un **superviseur** distribue le travail
- trois **workers specialises** cooperent
- un **point de validation humaine** arrete le flow avant la restitution finale

Le but n'est pas de faire "plus d'IA", mais de rendre le travail :
- plus lisible
- plus tracable
- plus controlable

## Flow support

Flow utilise :
- `J6 - Multi-Agent Supervised`

Architecture :
- `Supervisor`
- `Worker - Doc`
- `Worker - Calc`
- `Worker - Report`
- `Human Input`
- `Direct Reply`

## Ce que le flow demontre

- un agent unique n'est pas toujours le bon niveau d'architecture
- un **superviseur** peut distribuer des sous-taches sequentielles
- un worker documentaire et un worker quantitatif n'ont pas le meme role
- la **validation humaine** n'est pas un decor, mais un vrai point de controle
- la restitution finale doit etre produite seulement apres revue humaine

## Repartition des roles

### Supervisor

Il choisit le prochain worker a activer parmi :
- `DOC`
- `CALC`
- `REPORT`

Il ne fait pas lui-meme la recherche ni la restitution finale.

### Worker - Doc

Il utilise des outils MCP gouvernes pour :
- retrouver une regle
- retrouver un dossier d'exception
- verifier le perimetre d'information disponible

### Worker - Calc

Il utilise :
- `calculator`
- des vues MCP ciblees si besoin

Il sert a :
- recalculer un montant
- qualifier une variation
- verifier un ecart

### Worker - Report

Il ne cherche pas de nouvelles informations.

Il transforme les messages precedents en :
- synthese d'audit
- source principale
- actions recommandees
- demande explicite de validation humaine

### Human Input

Le flow s'arrete ici pour demander a l'auditeur :
- de valider
- ou de rejeter avec un feedback

En cas de rejet :
- le feedback repart dans la conversation
- le superviseur redistribue une sous-tache

## Challenge 1 - Lire l'architecture

### Mission

Expliquez a quoi sert chaque bloc et pourquoi il ne faut pas fusionner tous les roles dans un seul agent.

### Pistes

- Quel node prend la decision d'orchestration ?
- Quel node produit la restitution ?
- Quel node est le point d'arret humain ?
- Que se passe-t-il si l'auditeur rejette ?

<details>
<summary>Solution A</summary>

Le superviseur ne produit pas le fond du controle. Il choisit seulement le bon specialiste.  
Le worker doc cherche les regles et sources.  
Le worker calc verifie les chiffres.  
Le worker report redige une synthese.  
Le human input sert de porte de validation avant la reponse finale.

</details>

<details>
<summary>Solution B</summary>

Le multi-agent sert a separer :
- collecte documentaire
- verification quantitative
- redaction
- arbitrage humain

Cette separation ameliore la tracabilite et evite qu'un seul agent melange recherche, calcul et conclusion dans une seule reponse opaque.

</details>

## Challenge 2 - Observer la specialisation

### Mission

Posez une question qui oblige :
- une recherche documentaire
- un controle quantitatif
- une restitution finale

Exemple :

`Un salarie presente une variation de brut de 18% et lexception EXC_URSSAF_AMOUNT_INCONSISTENT. Prepare une alerte daudit DSN exploitable par un auditeur.`

### Ce qu'il faut observer

- le superviseur ne fait pas tout
- les workers n'ont pas la meme mission
- le flow s'arrete avant la reponse finale sur un point de validation humaine

<details>
<summary>Solution A</summary>

On doit voir une logique du type :
- DOC pour comprendre l'exception et la regle associee
- CALC pour qualifier l'ecart ou les montants
- REPORT pour ecrire la synthese
- HUMAN INPUT pour valider

</details>

<details>
<summary>Solution B</summary>

Si le superviseur envoie trop vite vers `REPORT`, il faut durcir son prompt :
- demander explicitement un passage par `DOC` si la question contient une exception ou une source
- demander explicitement un passage par `CALC` si la question contient variation, pourcentage ou montant

</details>

## Challenge 3 - Tester le human-in-the-loop

### Mission

Refaites le test precedent puis :
- validez une fois
- rejetez une fois avec un feedback

Exemple de feedback :

`La synthese ne cite pas assez clairement la source principale et ne chiffre pas assez l anomalie.`

### Ce qu'il faut observer

- le feedback humain retourne dans la conversation
- le superviseur repart avec une nouvelle consigne
- le flow ne doit pas ignorer le rejet

<details>
<summary>Solution A</summary>

Un bon comportement est :
- rejet
- nouvelle consigne du superviseur
- nouveau passage par `REPORT`, ou par `DOC` puis `REPORT` si le feedback demande une meilleure source

</details>

<details>
<summary>Solution B</summary>

Si le superviseur boucle mal, il faut simplifier :
- garder `DOC`, `CALC`, `REPORT`
- expliciter dans le prompt du superviseur comment reagir a un rejet humain
- limiter les iterations

</details>

## Challenge 4 - Faire varier l'architecture

### Mission

Testez deux variantes :
- variante 1 : le worker report est trop generique
- variante 2 : le worker report est tres contraint

Comparez :
- la lisibilite
- la tracabilite
- le risque d'invention

<details>
<summary>Solution A</summary>

Un worker report trop libre produit souvent une synthese plus elegante, mais moins fiable.  
Un worker report tres contraint produit souvent une synthese moins fluide, mais plus exploitable en audit.

</details>

<details>
<summary>Solution B</summary>

Le bon compromis pour l'audit est en general :
- ton sobre
- sections fixes
- source principale obligatoire
- action recommandee explicite
- besoin de validation humaine explicite

</details>

## Points de vigilance

- eviter qu'un worker refasse le travail d'un autre
- limiter les outils par worker
- garder un superviseur qui oriente, pas un superviseur qui re-fait le fond
- ne pas supprimer la validation humaine sur un cas sensible

## Variante minimale si le groupe prend du retard

Minimum pedagogique a couvrir :
- comprendre `Supervisor / Workers / Human Input`
- lancer un cas multi-agent
- observer le point d'arret humain
- expliquer pourquoi cette architecture est plus robuste qu'un agent unique
