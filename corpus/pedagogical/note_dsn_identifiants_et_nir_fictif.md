# DSN Identifiers and Fictitious NIR Handling

Source ID: DSN-ID
Version: 1.0
Date: 2026-05-06
Status: Pedagogical fictitious source for training

## Scope

This note defines how the training kit handles fictitious employee identifiers and fictitious NIR-like values.

## Rules

### DSN-ID-001

The payroll audit workflow must never send a raw NIR-like value to an LLM, RAG prompt, agent prompt, report, or execution log. The value must be replaced by `***MASKED***` before any AI step.

Evidence expected:
- row ID;
- masked field name;
- proof that the prompt or report contains only the masked value.

Limits:
- The training dataset uses fictitious identifiers only.

### DSN-ID-002

A fictitious NIR-like value is considered structurally valid for this training if it contains 13 to 15 digits. Blank values or non-digit values are reported as audit exceptions.

Evidence expected:
- row ID;
- validation status;
- reason label such as `missing` or `invalid_format`.

Limits:
- This is not a real NIR validation algorithm.

## Keywords

DSN, NIR, identifiant, masque, fictif, PII, donnees personnelles, logs
