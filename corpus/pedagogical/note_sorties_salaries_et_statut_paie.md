# Employee Exit Dates and Payroll Status

Source ID: PAYROLL-STATUS
Version: 1.0
Date: 2026-05-06
Status: Pedagogical fictitious source for training

## Scope

This note defines training checks for payroll rows where an employee has an exit date.

## Rules

### PAYROLL-STATUS-001

When `date_sortie` is set, `statut_paie` should not remain `ACTIF`. A row with an exit date and active payroll status is treated as an audit exception.

Evidence expected:
- row ID;
- entry date;
- exit date;
- payroll status.

Limits:
- Real payroll systems can have transitional cases; this rule is simplified for training.

### PAYROLL-STATUS-002

The exit date must not be earlier than the entry date. If `date_sortie < date_entree`, the row is treated as a high severity audit exception.

Evidence expected:
- row ID;
- entry date;
- exit date;
- comparison result.

Limits:
- Date comparisons assume ISO date format.

## Keywords

sortie, date sortie, date entree, statut paie, actif, salarie sorti
