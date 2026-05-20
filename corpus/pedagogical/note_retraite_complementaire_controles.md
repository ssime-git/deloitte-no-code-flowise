# Retirement Contribution Controls

Source ID: RETIREMENT-CTRL
Version: 1.0
Date: 2026-05-06
Status: Pedagogical fictitious source for training

## Scope

This note defines a simplified retirement contribution completeness control for the training dataset.

## Rules

### RETIREMENT-CTRL-001

When `base_retraite` is greater than zero, `montant_retraite` should be present and greater than zero. A missing or zero amount is treated as an audit exception.

Evidence expected:
- row ID;
- retirement base;
- observed retirement amount;
- missing or zero label.

Limits:
- This training control does not model all retirement scheme exceptions.

## Keywords

retraite, cotisation, base retraite, montant retraite, manquant, controle
