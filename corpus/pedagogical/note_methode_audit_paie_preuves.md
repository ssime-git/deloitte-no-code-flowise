# Payroll Audit Evidence Method

Source ID: AUDIT-EVIDENCE
Version: 1.0
Date: 2026-05-06
Status: Pedagogical fictitious source for training

## Scope

This note defines the expected evidence pattern for audit exceptions produced by the training workflows.

## Rules

### AUDIT-EVIDENCE-001

Every audit exception must include a stable exception ID, row ID, control ID, severity, observed value, expected rule, and evidence reference.

Evidence expected:
- exception ID;
- row ID;
- control ID;
- severity;
- observed value;
- expected rule;
- evidence reference.

Limits:
- The format is optimized for training and automated correction.

### AUDIT-EVIDENCE-002

A sourced audit recommendation must cite at least one source rule ID when the finding relies on documentary support. If no relevant source is retrieved, the workflow must refuse to invent a source.

Evidence expected:
- source rule ID;
- citation field;
- confidence level;
- refusal reason when source support is insufficient.

Limits:
- Citation quality is evaluated against the pedagogical corpus first.

## Keywords

audit, preuve, evidence, exception, citation, source, recommandation, rapport
