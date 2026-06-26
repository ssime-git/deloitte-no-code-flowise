# Programme de formation IA & Agentique pour l'Audit

IA avancée et systèmes agentiques no-code appliqués à l'audit et à l'analyse de la paie

**Public** : Auditeurs maîtrisant les outils bureautiques et l'analyse de données - aucune compétence en programmation requise

**Objectif** : Concevoir des assistants et agents IA no-code capables d'assister ou d'automatiser des tâches d'audit, appliqués au cas concret de l'audit de la paie via les fichiers DSN (Déclaration Sociale Nominative)

## Compétences acquises

- comprendre l'architecture des LLM, leurs typologies et leurs cas d'usage sans coder
- maîtriser le paramétrage des modèles (température, tokens, niveau de raisonnement) et ses impacts sur la fiabilité
- construire des assistants et agents autonomes via des interfaces no-code
- exploiter le RAG (Retrieval Augmented Generation) sur des documents RH et DSN
- orchestrer des workflows d'audit intelligents sans ligne de code
- comprendre et configurer le MCP (Model Context Protocol) pour connecter des sources de données
- analyser et auditer des fichiers DSN (structure, rémunérations, cotisations)

## Jour 1 - Introduction à l'IA et au prompt engineering

**Objectif** : Comprendre le potentiel, les limites et les grands usages de l'IA générative sans complexité technique.

**Support** : Copie de TECHaway x ORT LYON - Slides Kickoff & intro prompt for code (FR)

### Matin

Panorama des familles de modèles :
- Modèles de rédaction (rapides)
- Modèles de raisonnement (logique complexe)
- Modèles multimodaux (analyse de documents visuels)

L'IA et ses domaines :
- IA, Machine Learning, Deep Learning
- modèles génératifs
- LLM pour le texte et le code
- modèles de diffusion pour l'image
- modèles multimodaux pour texte + image

Le "cerveau" de l'IA :
- comment un modèle traite l'information
- ce qu'il sait faire
- ce qu'il ne comprend pas réellement

Sécurité & Confidentialité :
- enjeux RGPD et secret professionnel en audit
- différence entre IA publique et instances privées
- bonnes pratiques d'anonymisation avant traitement

Bonnes pratiques de prompts :
- rôle
- contexte
- tâche
- format

### Après-midi

Techniques de Prompt Engineering :
- zero-shot
- one-shot
- few-shot
- chain-of-thought guidé
- auto-critique
- auto-prompting

Qualité & fiabilité :
- checklist qualité
- signaux d'alerte
- hallucinations
- ton inadapté
- informations manquantes
- tests sur différents modèles
- itération et affinage progressif

Atelier :
- "L'auditeur augmenté" : utiliser un modèle de raisonnement pour interpréter une clause complexe de convention collective ou un guide de remplissage DSN
- mini-challenges de prompts

Clôture :
- quiz / Kahoot

## Jour 2 - Approfondissement du prompt engineering et des modèles

**Objectif** : Comprendre l'utilisation des API de modèles, les différences entre expériences utilisateur et l'impact des paramètres de génération.

### Matin

Les différentes expériences pour le prompt :
- applications web
- applications desktop
- API
- comparatif des expériences, avantages, limites et publics cibles

Introduction à l'utilisation des API :
- comptes providers
- URL d'API
- clé API
- facturation
- différence entre IA publique et instances privées

Paramètres de modèles :
- température
- topP
- topK
- max tokens
- niveau de raisonnement selon les modèles

Panorama des familles de modèles :
- modèles de rédaction
- modèles de raisonnement
- modèles multimodaux

### Après-midi

Rappels des bonnes pratiques :
- structure de prompt
- importance du format de sortie
- pratiques de sécurité

Bonnes pratiques RGPD :
- qu'est-ce qu'une donnée personnelle
- risque de fuite de données
- anonymisation et contrôle d'anonymisation des données de paie avant traitement

Atelier pratique :
- mini-challenges autour du prompt avec API et Flowise
- comparaison de réponses selon le modèle
- comparaison de réponses selon la température
- construction de prompts plus robustes pour des cas d'audit

## Jour 3 - RAG & fiabilité

**Objectif** : Connecter l'IA à ses propres référentiels et valider les résultats.

**Support** : Datatelier RAG+ 02 - RAG (FR)

### Matin

Le concept de RAG (Retrieval Augmented Generation) :
- pourquoi donner une bibliothèque de documents à l'IA
- comment brancher conventions, fiches consignes et règles DSN

Mémoire paramétrique vs non paramétrique :
- ce que le modèle sait déjà
- ce qu'il doit aller chercher

Rappels des limites du prompt même avec du few-shot

La philosophie du RAG :
- retrouver avant de répondre
- ancrer la réponse dans des documents
- réduire les hallucinations documentaires

Comment les algorithmes lisent les mots :
- comprendre ce que l'on nomme embeddings
- ce qui influence la qualité des embeddings

Use cases où le RAG est nécessaire

### Après-midi

Les paramètres qui influencent le RAG :
- topK
- type de modèle
- provider
- qualité du corpus

Avec ou sans RAG :
- comparaison des réponses
- différences observables
- limites du RAG

Conseils méthodologiques :
- organisation du corpus
- nettoyage
- anonymisation
- processing des documents
- questions de test de validation

Gestion des hallucinations :
- techniques de double check
- citation des sources
- lecture critique des réponses

Atelier :
- créer un assistant documentaire sur les règles de gestion DSN
- tester sa fiabilité sur des cas limites
- identifier ses zones d'erreur
- mini-challenge RAG avec Flowise

## Jour 4 - Agents avec Flowise

**Objectif** : Comprendre ce qu'est un agent IA, comment il diffère d'un chat ou d'une chaîne RAG, et apprendre à le piloter dans Flowise.

**Support** : Flow 3 - Agent simple, puis transition vers Flow 4 - Agent RAG

### Matin

Introduction aux agents :
- différence entre chat, chaîne et agent
- boucle agentique
- rôle du prompt système agentique
- rôle des outils
- différence entre réponse directe et usage d'un outil

Comprendre l'architecture d'un agent dans Flowise :
- node agent
- modèle
- outils
- mémoire
- intermediate steps si visibles

Démo guidée :
- agent simple orienté audit paie / DSN
- cas où l'agent appelle un calculateur
- cas où l'agent appelle un outil de date
- cas où l'agent répond sans outil

Travail sur le prompt de l'agent :
- formuler son rôle
- définir ses limites
- lui dire quand utiliser ou non un outil
- le rendre plus prudent ou plus directif

### Après-midi

Transition vers le RAG agentique :
- différence entre QA chain RAG et agent RAG
- quand l'agent décide lui-même d'aller chercher une information
- différence entre savoir paramétrique, outil et recherche documentaire

Construction d'un agent RAG dans Flowise :
- retriever
- retriever tool
- agent + outil documentaire
- combinaison recherche + calcul si nécessaire

Tests pédagogiques :
- question documentaire simple
- question documentaire + calcul
- cas sans source suffisante
- cas RGPD/NIR

Atelier :
- faire évoluer un agent simple en agent RAG
- tester son comportement sur des cas limites
- comparer la réponse d'une chaîne RAG et celle d'un agent RAG

## Jour 5 - MCP et accès contrôlé aux données

**Objectif** : Comprendre comment connecter un agent à des outils et à des vues de données contrôlées, sans envoyer des fichiers bruts entiers au modèle.

**Support** : Flow 5 - Agent connecté via MCP

### Matin

Introduction au MCP (Model Context Protocol) :
- pourquoi connecter des outils plutôt qu'envoyer des masses de données dans le prompt
- notion de source contrôlée
- notion de traçabilité
- différence entre document, outil et vue de données

Réalité de la donnée volumineuse :
- limites de contexte
- coût
- perte de fiabilité
- intérêt du filtrage et de l'agrégation

Cas d'usage audit paie / DSN :
- interroger une vue ciblée
- récupérer un sous-ensemble utile
- garder la maîtrise des données exposées à l'agent

### Après-midi

MCP dans Flowise :
- brancher un outil MCP à un agent
- exposer des données filtrées
- requêtes ciblées
- agrégations et découpage

Stratégies de passage à l'échelle :
- pré-agrégation
- filtrage côté outil
- partitionnement
- traitement par lots
- échantillonnage intelligent

Atelier :
- interroger un jeu de données DSN via un agent connecté à une source contrôlée
- poser des questions ciblées
- observer quand le modèle commence à se tromper
- rétablir la fiabilité grâce au filtrage ou à l'agrégation

## Jour 6 - Systèmes multi-agents & Human-in-the-loop

**Objectif** : Faire collaborer plusieurs agents spécialisés sous supervision humaine dans un flow unique Flowise.

**Support** : Flow 6 - Multi-agent supervisé

### Matin

Pourquoi passer au multi-agent :
- limites d'un agent unique
- manque d'exhaustivité
- difficulté à cumuler raisonnement, recherche, contrôle et restitution

Architecture d'un système multi-agent :
- superviseur
- agents workers spécialisés
- circulation des consignes et des résultats

Exemples de répartition des rôles :
- un agent pour la recherche documentaire
- un agent pour les calculs et contrôles quantitatifs
- un agent pour la synthèse ou la rédaction

Validation humaine :
- où placer l'humain dans la boucle
- quand demander une validation
- quelles anomalies nécessitent une revue humaine

### Après-midi

Démo guidée :
- flow multi-agent orienté audit DSN
- superviseur
- workers spécialisés
- étape de validation humaine

Atelier :
- construire une mini-chaîne de contrôle
- agent 1 détecte une variation suspecte
- agent 2 vérifie si la variation est justifiée
- agent 3 prépare la restitution
- l'auditeur valide ou rejette l'alerte

Points de vigilance :
- éviter qu'un agent fasse tout
- bien spécialiser les rôles
- contrôler les sorties
- maintenir la traçabilité

## Jour 7 - Projet final : Product Build

**Objectif** : Cadrer, prototyper et présenter un outil d'audit actionnable, 100% no-code, construit dans Flowise.

## Contraintes de cadrage (à annoncer en ouverture de J7)

- Périmètre technique : Flowise no-code uniquement, pas d'architecture enterprise
- Durée de prototypage : 3h maximum, un seul cas d'usage DSN précis par groupe
- Livrable : un flow Flowise fonctionnel + présentation de 10 min
- Hors scope : connecteurs ERP, SSO, RBAC, audit trail enterprise, fine-tuning
- La grille d'évaluation porte sur : fiabilité des réponses, conformité RGPD, limites identifiées

### Matin

Méthodologie Product Build :
- partir du besoin métier
- identifier le risque ou l'anomalie à forte valeur
- choisir le bon niveau de sophistication

Arbre de décision de l'auditeur :
- quand un bon prompt suffit
- quand le RAG est nécessaire
- quand un agent est utile
- quand il faut plusieurs agents
- quand ajouter une validation humaine

Gestion des erreurs et robustesse :
- fallback
- refus
- contrôle qualité
- alerte en cas de comportement anormal

### Après-midi

Projet de groupe :
- prototypage d'une solution d'assistance à l'audit DSN 100% no-code
- ingestion
- contrôle
- validation humaine
- rapport final

Restitution :
- présentation du workflow
- grille d'évaluation de fiabilité
- analyse de conformité RGPD
- discussion des limites et améliorations possibles

## Ligne directrice pédagogique de la semaine

La progression suit une logique de maturité d'usage :

1. parler correctement à un modèle
2. comprendre les différences entre modèles et réglages
3. fiabiliser une réponse avec du RAG
4. passer du chat à l'agent
5. connecter l'agent à des outils et données contrôlées
6. faire collaborer plusieurs agents sous supervision humaine
7. assembler une solution métier cohérente

## Outils et flows pédagogiques associés

- `Flow 1` : chat / prompting
- `Flow 2` : RAG
- `Flow 3` : agent simple
- `Flow 4` : agent RAG
- `Flow 5` : agent connecté via MCP
- `Flow 6` : multi-agent supervisé
- `Flow 7` : prototype final
