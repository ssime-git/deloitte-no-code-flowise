# DSN-Like Data Dictionary

## Scope

This dataset is fictitious and exists only for payroll/DSN audit training.

## Fields

| Field | Type | Required | Accepted values | Notes |
| --- | --- | --- | --- | --- |
| periode_declaration | YYYY-MM | Yes | 2025-01 to 2025-03 | Declaration period. |
| siret_etablissement | string | Yes | 14 digits | Fictitious SIRET. |
| matricule_salarie | string | Yes | MAT-0001 style | Fictitious employee ID. |
| nir_fictif | string | No | 13 to 15 digits or blank | Fictitious only; masked before LLM use. |
| nom_fictif | string | Yes | Fictitious names | Never real names. |
| date_entree | YYYY-MM-DD | Yes | ISO date | Employment start. |
| date_sortie | YYYY-MM-DD or blank | No | ISO date | Employment end. |
| type_contrat | controlled string | Yes | CDI, CDD, APPRENTI, STAGE | Training categories. |
| salaire_brut | decimal | Yes | >= 0 except anomaly rows | Gross salary. |
| base_urssaf | decimal | Yes | Normally close to salaire_brut | URSSAF base. |
| taux_urssaf | decimal | Yes | 0.01 to 0.30 | Training range. |
| montant_urssaf | decimal | Yes | base_urssaf * taux_urssaf | Rounded to cents. |
| base_retraite | decimal | Yes | >= 0 | Retirement base. |
| montant_retraite | decimal | No | > 0 when base_retraite > 0 | Missing value is an anomaly. |
| heures_remunerees | decimal | Yes | 0 to 220 | Paid hours. |
| statut_paie | controlled string | Yes | ACTIF, SORTI, SUSPENDU | Payroll status. |
