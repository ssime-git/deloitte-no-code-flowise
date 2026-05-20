import csv
import json
import os
import re
from collections import defaultdict
from decimal import Decimal
from pathlib import Path

import uvicorn
from mcp.server.fastmcp import FastMCP
from starlette.applications import Starlette
from starlette.requests import Request
from starlette.responses import JSONResponse, Response


mcp = FastMCP(
    "DSN Audit Tools",
    host=os.getenv("FASTMCP_HOST", "0.0.0.0"),
    port=int(os.getenv("FASTMCP_PORT", "8000")),
)

DATA_DIR = Path(os.getenv("DATA_DIR", "/data"))
CORPUS_DIR = Path(os.getenv("CORPUS_DIR", "/corpus"))
FASTMCP_HOST = os.getenv("FASTMCP_HOST", "0.0.0.0")
FASTMCP_PORT = int(os.getenv("FASTMCP_PORT", "8000"))


def _safe_data_path(relative_path: str) -> Path:
    path = (DATA_DIR / relative_path).resolve()
    if not str(path).startswith(str(DATA_DIR.resolve())):
        raise ValueError(f"Path outside DATA_DIR: {relative_path}")
    return path


def _read_csv(relative_path: str) -> list[dict]:
    path = _safe_data_path(relative_path)
    with path.open(newline="", encoding="utf-8") as handle:
        return list(csv.DictReader(handle))


def _read_corpus_manifest() -> dict:
    manifest = CORPUS_DIR / "manifest.json"
    with manifest.open(encoding="utf-8") as handle:
        return json.load(handle)


@mcp.tool()
def aggregate_preprocessed_dsn_like() -> list[dict]:
    """
    Aggregate the normalized DSN-like dataset by establishment without exposing
    employee-level rows, NIR, names, or raw source records.
    """
    rows = _read_csv("dsn-like/expected/normalized_dataset.csv")
    groups: dict[str, dict] = defaultdict(
        lambda: {
            "nb_lignes": 0,
            "matricules": set(),
            "masse_salariale_brute": Decimal("0"),
            "periodes": set(),
        }
    )

    for row in rows:
        siret = row["siret_etablissement"]
        item = groups[siret]
        item["nb_lignes"] += 1
        item["matricules"].add(row["matricule_salarie"])
        item["masse_salariale_brute"] += Decimal(row["salaire_brut"])
        item["periodes"].add(row["periode_declaration"])

    result = []
    for siret, item in sorted(groups.items()):
        periodes = sorted(item["periodes"])
        result.append(
            {
                "siret_etablissement": siret,
                "nb_lignes": item["nb_lignes"],
                "nb_matricules": len(item["matricules"]),
                "masse_salariale_brute": f"{item['masse_salariale_brute']:.2f}",
                "nb_periodes": len(periodes),
                "periodes": periodes,
                "source_artifact": "data/dsn-like/expected/normalized_dataset.csv",
            }
        )
    return result


@mcp.tool()
def get_audit_scope() -> dict:
    """
    Return the governed business scope and dataset counts available to the audit agent.
    No raw payroll rows, NIR, names, or employee-level narratives are returned.
    """
    rows = _read_csv("dsn-like/expected/normalized_dataset.csv")
    exceptions = _read_csv("dsn-like/expected/exceptions.csv")
    return {
        "business_scope": "DSN-like payroll audit training dataset, preprocessed by deterministic controls.",
        "establishments_count": len({row["siret_etablissement"] for row in rows}),
        "periods": sorted({row["periode_declaration"] for row in rows}),
        "normalized_rows_count": len(rows),
        "exceptions_count": len(exceptions),
        "controls_with_exceptions": sorted({row["control_id"] for row in exceptions}),
        "data_policy": "Aggregated audit outputs only. No raw payroll rows, NIR, names, or employee-level narratives.",
        "interpretation_guidance": [
            "Use the returned counts and categories exactly.",
            "Do not infer a business qualification that is not returned by a tool.",
            "Present missing evidence as a follow-up audit question, not as a finding.",
        ],
    }


@mcp.tool()
def get_exception_investigation_case(
    exception_id: str = "EXC_URSSAF_AMOUNT_INCONSISTENT",
) -> dict:
    """
    Return one sanitized exception dossier built from exceptions.csv and the
    normalized dataset. This is safe for learner-facing MCP usage.
    """
    exceptions = _read_csv("dsn-like/expected/exceptions.csv")
    normalized_rows = {
        row["row_id"]: row
        for row in _read_csv("dsn-like/expected/normalized_dataset.csv")
    }
    exception = next(
        (row for row in exceptions if row["exception_id"] == exception_id), None
    )
    if not exception:
        return {
            "status": "not_found",
            "requested_exception_id": exception_id,
            "available_exception_ids": sorted(
                {row["exception_id"] for row in exceptions}
            ),
            "policy": "No invented investigation dossier. Ask for an available exception ID.",
        }

    source = normalized_rows.get(exception["row_id"], {})
    expected_amount = None
    gap = None
    if exception["control_id"] == "CTRL-007" and source:
        expected = Decimal(source["base_urssaf"]) * Decimal(source["taux_urssaf"])
        observed = Decimal(source["montant_urssaf"])
        expected_amount = f"{expected:.2f}"
        gap = f"{observed - expected:.2f}"

    return {
        "status": "found",
        "exception": {
            "exception_id": exception["exception_id"],
            "row_id": exception["row_id"],
            "control_id": exception["control_id"],
            "severity": exception["severity"],
            "field": exception["field"],
            "observed_value": exception["observed_value"],
            "expected_rule": exception["expected_rule"],
            "evidence_ref": exception["evidence_ref"],
        },
        "sanitized_row": {
            "row_id": source.get("row_id"),
            "periode_declaration": source.get("periode_declaration"),
            "siret_etablissement": source.get("siret_etablissement"),
            "type_contrat": source.get("type_contrat"),
            "salaire_brut": source.get("salaire_brut"),
            "base_urssaf": source.get("base_urssaf"),
            "taux_urssaf": source.get("taux_urssaf"),
            "montant_urssaf": source.get("montant_urssaf"),
            "base_retraite": source.get("base_retraite"),
            "montant_retraite": source.get("montant_retraite"),
            "statut_paie": source.get("statut_paie"),
        },
        "computed_evidence": {
            "expected_urssaf_amount": expected_amount,
            "gap_observed_minus_expected": gap,
            "calculation_available": expected_amount is not None,
        },
        "documentary_support": {
            "source_rules": ["URSSAF-CTRL", "AUDIT-EVIDENCE"],
            "corpus_version": "Pedagogical corpus manifest",
            "evidence_expected": [
                "row ID",
                "URSSAF base",
                "URSSAF rate",
                "observed URSSAF amount",
                "expected computed amount",
                "exception ID",
                "control ID",
                "severity",
                "evidence reference",
            ],
        },
        "governance": {
            "allowed_outputs": "Sanitized row fields, exception metadata, computed evidence, source rule IDs, limits.",
            "forbidden_outputs": "NIR, names, first names, raw payroll files, full employee-level narratives.",
            "validation": "Agents may draft analysis, but final validation remains human.",
        },
    }


def _score_text(text: str, query_terms: set[str], source_ids: set[str]) -> int:
    lowered = text.lower()
    score = sum(1 for term in query_terms if term in lowered)
    score += sum(3 for source_id in source_ids if source_id.lower() in lowered)
    return score


@mcp.tool()
def search_documentary_sources(
    query: str,
    source_ids: list[str] | None = None,
    limit: int = 3,
) -> dict:
    """
    Search the pedagogical corpus with a lightweight keyword strategy and return
    compact excerpts suitable for learner-facing MCP demonstrations.
    """
    requested = {item.strip() for item in (source_ids or []) if item and item.strip()}
    capped_limit = max(1, min(int(limit), 5))
    manifest = _read_corpus_manifest()
    query_terms = {
        token.lower()
        for token in re.findall(r"[A-Za-zÀ-ÿ0-9_-]{3,}", query)
        if token.lower()
        not in {"avec", "pour", "dans", "une", "des", "les", "the", "and"}
    }

    matches = []
    for document in manifest.get("documents", []):
        path = Path(document["path"])
        if path.parts and path.parts[0] == "corpus":
            path = Path(*path.parts[1:])
        full_path = (CORPUS_DIR / path).resolve()
        text = full_path.read_text(encoding="utf-8")
        score = _score_text(text, query_terms, requested | {document.get("id", "")})
        if score <= 0 and requested and document.get("id") not in requested:
            continue
        if score <= 0 and not requested:
            continue
        matches.append(
            {
                "source_id": document.get("id"),
                "score": score,
                "snippet": re.sub(r"\s+", " ", text).strip()[:500],
                "limits": "Keyword search over the pedagogical corpus. Documentary support only.",
            }
        )

    matches.sort(key=lambda item: (-item["score"], item["source_id"] or ""))
    return {
        "query": query,
        "requested_source_ids": sorted(requested),
        "matches": matches[:capped_limit],
        "status": "found" if matches else "no_relevant_source",
        "refusal_policy": "If no relevant source is returned, do not invent citations.",
    }


async def health_check(_request: Request) -> Response:
    return JSONResponse(
        {
            "status": "ok",
            "transport": "streamable-http",
            "tools": [
                "aggregate_preprocessed_dsn_like",
                "get_audit_scope",
                "get_exception_investigation_case",
                "search_documentary_sources",
            ],
        }
    )


def create_app() -> Starlette:
    app = mcp.streamable_http_app()
    app.router.add_route("/health", health_check, methods=["GET"])
    return app


if __name__ == "__main__":
    uvicorn.run(create_app(), host=FASTMCP_HOST, port=FASTMCP_PORT)
