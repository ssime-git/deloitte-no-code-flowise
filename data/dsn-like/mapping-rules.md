# Mapping Rules

## Input delimiter

Raw files use semicolon delimiters.

## Normalization

- Trim all string fields.
- Convert empty strings to null for optional fields.
- Keep dates in ISO `YYYY-MM-DD`.
- Keep periods in `YYYY-MM`.
- Convert numeric fields to decimals with dot separator.
- Mask `nir_fictif` as `***MASKED***` before any LLM or RAG step.
- Generate `row_id` as `ROW-0001`, `ROW-0002`, in source order.

## Rejection

Reject a row technically only when required fields for parsing are missing: `periode_declaration`, `siret_etablissement`, `matricule_salarie`, or `date_entree`.

Business anomalies remain in the normalized dataset and are reported in `exceptions.csv`.
