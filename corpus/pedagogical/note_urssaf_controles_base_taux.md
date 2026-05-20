# URSSAF Controls on Bases, Rates, and Amounts

Source ID: URSSAF-CTRL
Version: 1.0
Date: 2026-05-06
Status: Pedagogical fictitious source for training

## Scope

This note defines training rules for checking URSSAF bases, rates, and contribution amounts in a fictitious DSN-like payroll audit dataset.

## Rules

### URSSAF-CTRL-001

The URSSAF contribution base should remain close to the gross salary for the simplified training case. A difference greater than 5 percent is treated as an audit exception unless a documented exclusion explains the gap.

Evidence expected:
- row ID;
- gross salary;
- URSSAF base;
- computed percentage difference.

Limits:
- This is a pedagogical simplification and not a production payroll rule.

### URSSAF-CTRL-002

The URSSAF amount should equal `base_urssaf * taux_urssaf` after rounding to cents. A difference greater than 0.02 is treated as an audit exception.

Evidence expected:
- row ID;
- URSSAF base;
- URSSAF rate;
- observed URSSAF amount;
- expected computed amount.

Limits:
- The training dataset ignores contribution ceilings and special regimes.

## Keywords

URSSAF, base, taux, montant, cotisation, ecart, preuve, paie
