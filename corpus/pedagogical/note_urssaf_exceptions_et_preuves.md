# URSSAF Exceptions and Audit Evidence — Mapping

Source ID: URSSAF-EVIDENCE-MAP
Version: 1.0
Date: 2026-05-20
Status: Pedagogical fictitious source for training

## Scope

Ce document fait le lien entre les règles de contrôle URSSAF et le format d'exception d'audit attendu. Il est destiné à guider les workflows RAG qui combinent la détection d'un écart et la production d'une fiche d'exception structurée.

## Mapping URSSAF-CTRL-001 → AUDIT-EVIDENCE-001

### URSSAF-CTRL-001 : Écart base URSSAF / salaire brut supérieur à 5%

Règle source : URSSAF-CTRL-001 (voir note_urssaf_controles_base_taux.md)

Déclencheur : `|base_urssaf - salaire_brut| / salaire_brut > 0.05`

Preuve attendue pour la vérification des données :
- row ID : identifiant de la ligne de paie contrôlée ;
- gross salary (`salaire_brut`) : valeur observée dans la donnée ;
- URSSAF base (`base_urssaf`) : valeur observée dans la donnée ;
- computed percentage difference : `abs(base_urssaf - salaire_brut) / salaire_brut * 100`, exprimé en pourcentage.

Fiche d'exception à produire (format AUDIT-EVIDENCE-001) :
- exception ID : identifiant stable de l'exception, par exemple `EXC_URSSAF_BASE_001` ;
- row ID : identifiant de la ligne de paie concernée ;
- control ID : `URSSAF-CTRL-001` ;
- severity : élevée si l'écart dépasse 10%, modérée entre 5% et 10% ;
- observed value : écart calculé en pourcentage ;
- expected rule : "La base URSSAF doit rester proche du salaire brut. Un écart supérieur à 5% constitue une exception d'audit." ;
- evidence reference : `URSSAF-CTRL-001 / AUDIT-EVIDENCE-001`.

Niveau de confiance attendu dans la réponse sourcée :
- Élevé si les deux champs (`base_urssaf` et `salaire_brut`) sont présents dans la donnée et si l'écart est calculable.
- Faible si les données sont manquantes ou si une exclusion documentée justifie l'écart.

Limites :
- Cette règle est une simplification pédagogique. Elle ne tient pas compte des plafonds de cotisation, des régimes spéciaux ou des exclusions contractuelles.
- Un écart documenté (prime exceptionnelle, avantage en nature, etc.) peut justifier une différence supérieure à 5% sans constituer une anomalie.

## Mapping URSSAF-CTRL-002 → AUDIT-EVIDENCE-001

### URSSAF-CTRL-002 : Montant URSSAF calculé incorrect

Règle source : URSSAF-CTRL-002 (voir note_urssaf_controles_base_taux.md)

Déclencheur : `|montant_urssaf_observe - base_urssaf * taux_urssaf| > 0.02`

Preuve attendue pour la vérification des données :
- row ID ;
- URSSAF base (`base_urssaf`) ;
- URSSAF rate (`taux_urssaf`) ;
- observed URSSAF amount (`montant_urssaf`) ;
- expected computed amount : `base_urssaf * taux_urssaf` arrondi au centime.

Fiche d'exception à produire (format AUDIT-EVIDENCE-001) :
- exception ID : par exemple `EXC_URSSAF_AMOUNT_001` ;
- row ID ;
- control ID : `URSSAF-CTRL-002` ;
- severity : modérée ;
- observed value : écart en euros entre montant observé et montant attendu ;
- expected rule : "Le montant URSSAF doit égaler base_urssaf * taux_urssaf arrondi au centime." ;
- evidence reference : `URSSAF-CTRL-002 / AUDIT-EVIDENCE-001`.

Limites :
- Le dataset de formation ignore les plafonds et les régimes spéciaux.

## Keywords

URSSAF, CTRL-001, CTRL-002, base_urssaf, salaire_brut, taux_urssaf, montant_urssaf, exception, audit, preuve, evidence, fiche, écart, mapping, AUDIT-EVIDENCE-001
