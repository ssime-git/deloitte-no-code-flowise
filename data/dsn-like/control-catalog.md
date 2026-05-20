# Control Catalog

| control_id | exception_id | Severity | Rule | Evidence |
| --- | --- | --- | --- | --- |
| CTRL-001 | EXC_DUPLICATE_EMPLOYEE_PERIOD | High | Same `matricule_salarie` and `periode_declaration` appears more than once. | Duplicate row IDs and period. |
| CTRL-002 | EXC_MISSING_NIR | Medium | `nir_fictif` is blank. | Row ID and masked identifier field. |
| CTRL-003 | EXC_INVALID_NIR_FORMAT | Medium | `nir_fictif` is present but not 13 to 15 digits. | Row ID and invalid format label. |
| CTRL-004 | EXC_NON_POSITIVE_GROSS_SALARY | High | `salaire_brut <= 0` on a paid active payroll row. | Observed salary. |
| CTRL-005 | EXC_URSSAF_BASE_INCONSISTENT | High | `base_urssaf` differs from `salaire_brut` by more than 5%. | Salary, base, delta. |
| CTRL-006 | EXC_URSSAF_RATE_OUT_OF_RANGE | High | `taux_urssaf < 0.01` or `taux_urssaf > 0.30`. | Observed rate. |
| CTRL-007 | EXC_URSSAF_AMOUNT_INCONSISTENT | High | `montant_urssaf` differs from `base_urssaf * taux_urssaf` by more than 0.02. | Base, rate, expected amount, observed amount. |
| CTRL-008 | EXC_EXITED_EMPLOYEE_ACTIVE | Medium | `date_sortie` is set and `statut_paie = ACTIF`. | Exit date and status. |
| CTRL-009 | EXC_EXIT_BEFORE_ENTRY | High | `date_sortie < date_entree`. | Entry and exit dates. |
| CTRL-010 | EXC_MISSING_RETIREMENT_CONTRIBUTION | Medium | `base_retraite > 0` and `montant_retraite` is blank or zero. | Base and missing amount. |
