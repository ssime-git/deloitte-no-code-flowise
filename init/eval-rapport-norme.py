#!/usr/bin/env python3
"""Jeu d'évaluation du mapping faits → sections (PRD §10 / E6).

Envoie chaque cas (tous les faits en un message) aux flows J7 v0 et v1,
extrait les S-XX du récap HITL 1, et mesure précision / rappel contre
les sections attendues (définies à la main depuis la norme).

Usage : python3 init/eval-rapport-norme.py <API_KEY> <FLOW_ID_V0> <FLOW_ID_V1>
"""
import json, re, sys, time, urllib.request

API_KEY, FLOW_V0, FLOW_V1 = sys.argv[1], sys.argv[2], sys.argv[3]
BASE = "http://localhost:3000/api/v1/prediction/"

CASES = [
    {"id": "C1", "prompt": "Rapport SFDR pour un gestionnaire d'actifs (acteur des marches financiers) de 620 salaries, PAI pris en compte, produit article 8 sans indice de reference.",
     "attendu": {"S-01", "S-02", "S-03", "S-04", "S-05", "S-06", "S-08", "S-09"}},
    {"id": "C2", "prompt": "Rapport SFDR pour un acteur des marches financiers de 45 salaries, qui ne prend pas en compte les PAI, produit financier standard (ni article 8 ni article 9), donc aucun indice de reference (non applicable).",
     "attendu": {"S-01", "S-02", "S-03", "S-04", "S-05"}},
    {"id": "C3", "prompt": "Rapport SFDR pour un conseiller financier de 30 salaries, PAI non pris en compte, produit standard, aucun indice de reference (non applicable).",
     "attendu": {"S-01", "S-02", "S-03", "S-04", "S-05"}},
    {"id": "C4", "prompt": "Rapport SFDR pour un acteur des marches financiers de 1200 salaries, PAI pris en compte, produit article 9 avec un indice de reference designe.",
     "attendu": {"S-01", "S-02", "S-03", "S-04", "S-05", "S-07", "S-08", "S-09"}},
    {"id": "C5", "prompt": "Rapport SFDR pour un acteur des marches financiers de 300 salaries, PAI pris en compte, produit article 9 sans indice de reference designe.",
     "attendu": {"S-01", "S-02", "S-03", "S-04", "S-05", "S-07", "S-08", "S-09"}},
    {"id": "C6", "prompt": "Rapport SFDR pour un conseiller financier de 600 salaries, PAI non pris en compte, produit article 8 sans indice de reference.",
     "attendu": {"S-01", "S-02", "S-03", "S-04", "S-05", "S-06", "S-08", "S-09"}},
    {"id": "C7", "prompt": "Rapport SFDR pour un gestionnaire d'actifs (acteur des marches financiers) de 900 salaries qui ne prend pas en compte les PAI, produit article 8 sans indice de reference.",
     "attendu": "incoherence"},
]

def predict(flow_id, question, session):
    body = json.dumps({"question": question, "overrideConfig": {"sessionId": session}}).encode()
    req = urllib.request.Request(BASE + flow_id, data=body, headers={
        "Authorization": f"Bearer {API_KEY}", "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=300) as r:
        d = json.load(r)
    return d.get("text", ""), [x.get("nodeLabel") for x in d.get("agentFlowExecutedData", [])]

def run(flow_id, tag):
    rows = []
    for c in CASES:
        session = f"eval-{tag}-{c['id']}-{int(time.time())}"
        try:
            text, nodes = predict(flow_id, c["prompt"], session)
        except Exception as e:
            rows.append((c["id"], set(), c["attendu"], f"ERREUR: {e}"))
            continue
        if c["attendu"] == "incoherence":
            # attendu : le flow s'arrete AVANT le HITL 1 avec une question signalant l'incoherence
            blocked = "HITL 1" not in " ".join(str(n) for n in nodes)
            signale = bool(re.search(r"incoheren|coheren", text, re.I))
            err = "" if blocked and signale else f"incoherence non signalee (nodes: {nodes}, text: {text[:120]!r})"
            rows.append((c["id"], "incoherence-ok" if not err else set(), "incoherence", err))
            continue
        if "HITL 1" not in " ".join(str(n) for n in nodes):
            rows.append((c["id"], set(), c["attendu"], f"HITL 1 non atteint (nodes: {nodes})"))
            continue
        trouve = set(re.findall(r"S-\d\d", text))
        rows.append((c["id"], trouve, c["attendu"], ""))
    return rows

def report(tag, rows):
    print(f"\n=== {tag} ===")
    tp = fp = fn = 0
    for cid, trouve, attendu, err in rows:
        if attendu == "incoherence":
            print(f"{cid}: {'OK (incoherence signalee)' if not err else err}")
            continue
        if err:
            print(f"{cid}: {err}")
            fn += len(attendu)
            continue
        manque, exces = attendu - trouve, trouve - attendu
        tp += len(attendu & trouve); fp += len(exces); fn += len(manque)
        status = "OK" if not manque and not exces else f"manque={sorted(manque)} exces={sorted(exces)}"
        print(f"{cid}: {status}")
    rappel = tp / (tp + fn) if tp + fn else 0
    precision = tp / (tp + fp) if tp + fp else 0
    print(f"rappel={rappel:.0%}  precision={precision:.0%}  (tp={tp} fp={fp} fn={fn})")
    return rappel, precision

if __name__ == "__main__":
    for tag, fid in (("v0 (mapping LLM)", FLOW_V0), ("v1 (moteur deterministe)", FLOW_V1)):
        report(tag, run(fid, tag.split()[0]))
