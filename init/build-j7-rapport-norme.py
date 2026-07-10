#!/usr/bin/env python3
"""Build J7-Rapport-Norme agentflow by cloning node shells from J6."""
import json, copy, re

ROOT = '/home/seb/project/deloitte/deloitte-no-code-flowise'
J6 = json.load(open(f'{ROOT}/init/flows/J6-Multi-Agent-Supervised.json'))
NORME = open(f'{ROOT}/data/normes/sfdr-articles-fr.txt').read().strip()

templates = {}
for n in J6['nodes']:
    templates.setdefault(n['data']['name'], n)

edge_tpl = J6['edges'][0]

CRED = 'b2c3d4e5-f6a7-8901-bcde-f12345678901'
MODEL = 'claude-sonnet-4-6'

def model_cfg(temp):
    return {"llmModel": "chatAnthropic", "FLOWISE_CREDENTIAL_ID": CRED,
            "modelName": MODEL, "temperature": temp, "streaming": True,
            "allowImageUploads": False}

def clone(tpl_name, new_id, label, position, inputs):
    tpl = templates[tpl_name]
    s = json.dumps(tpl)
    s = s.replace(tpl['id'], new_id)
    node = json.loads(s)
    node['position'] = position
    node['positionAbsolute'] = position
    node['data']['label'] = label
    node['data']['inputs'] = inputs
    node['data']['selected'] = False
    if tpl_name == 'humanInputAgentflow':
        # server routes decision branches by index-based handles (-output-0/-output-1),
        # J6's -output-proceed/-output-reject handles are never matched -> both branches run
        node['data']['outputAnchors'] = [
            {"id": f"{new_id}-output-0", "label": "Proceed", "name": "proceed"},
            {"id": f"{new_id}-output-1", "label": "Reject", "name": "reject"},
        ]
    return node

# ---------------- prompts ----------------

VOCAB = """Vocabulaire d'entree (faits a collecter, TOUS obligatoires) :
1. type_acteur : "acteur_marches_financiers" ou "conseiller_financier" (art. 2)
2. plus_de_500_salaries : oui / non (pertinent pour l'art. 4, par. 3 et 4)
3. prise_en_compte_pai : oui / non — l'entite prend-elle en compte les principales incidences negatives (PAI) de ses decisions d'investissement sur les facteurs de durabilite ? (art. 4)
4. type_produit : "produit_art8" (promeut des caracteristiques environnementales ou sociales), "produit_art9" (a pour objectif l'investissement durable) ou "produit_standard" (art. 8 et 9)
5. indice_reference_designe : oui / non / non_applicable — un indice de reference a-t-il ete designe pour le produit ? (art. 9, par. 1 et 2)"""

CATALOGUE = """Catalogue des sections candidates (le perimetre final depend des faits, justifie chaque section retenue par son article) :
- S-01 | Politique d'integration des risques en matiere de durabilite | art. 3 | toujours applicable
- S-02 | Declaration PAI ou explication de non-prise en compte (comply or explain) | art. 4, par. 1 a 4 | toujours ; declaration obligatoire (pas d'explain possible) si plus de 500 salaries chez un acteur des marches financiers
- S-03 | Politiques de remuneration et integration des risques de durabilite | art. 5 | toujours applicable
- S-04 | Informations precontractuelles sur les risques de durabilite | art. 6 | toujours applicable pour un produit financier
- S-05 | PAI au niveau du produit financier | art. 7 | si prise_en_compte_pai = oui
- S-06 | Informations precontractuelles produit promouvant des caracteristiques E/S | art. 8 | si type_produit = produit_art8
- S-07 | Informations precontractuelles produit a objectif d'investissement durable | art. 9 | si type_produit = produit_art9 (contenu different selon indice_reference_designe)
- S-08 | Publication sur le site internet du produit | art. 10 | si type_produit = produit_art8 ou produit_art9
- S-09 | Informations dans les rapports periodiques | art. 11 | si type_produit = produit_art8 ou produit_art9"""

ELICIT_SYS = f"""Tu es l'agent d'ELICITATION d'un generateur de rapport de conformite SFDR (reglement UE 2019/2088).

Ta mission : collecter, par un dialogue naturel, les faits du vocabulaire d'entree, puis deduire les sections applicables du rapport.

{VOCAB}

{CATALOGUE}

Regles :
- Exploite d'abord ce que l'utilisateur a deja dit : ne redemande jamais un fait deja fourni.
- Pose UNE question a la fois, courte et fermee, tant qu'il manque des faits.
- Si une reponse est ambigue, signale-le dans "incertitudes" et reformule la question.
- Quand TOUS les faits sont connus : complete = "oui", et deduis la liste des sections applicables a partir des faits et de la norme ci-dessous (chaque section avec son id, son titre et sa reference d'article).
- Si un humain rejette la validation avec un feedback, corrige les faits ou les sections selon ce feedback exactement, puis re-produis la sortie complete.

Texte de la norme (articles du reglement UE 2019/2088) :
<norme>
{{{{ $flow.state.norme }}}}
</norme>"""

RECAP_SYS = """Tu prepares la validation humaine n°1 d'un generateur de rapport SFDR.

Presente de facon claire et compacte, en francais :
1. **Faits retenus** — tableau variable / valeur : {{ $flow.state.faits }}
2. **Sections applicables deduites** (avec reference d'article) : {{ $flow.state.sections }}
3. Les eventuelles incertitudes signalees.

Termine par : "Validez ce perimetre, ou rejetez en indiquant le fait a corriger ou la section a ajouter/retirer."
N'ajoute rien d'autre : pas de redaction de rapport a ce stade."""

REDIGE_SYS = f"""Tu es l'agent de REDACTION d'un rapport de conformite SFDR (reglement UE 2019/2088).

Regles imperatives :
- Redige UNIQUEMENT les sections listees, une par une, dans l'ordre, avec un titre de niveau ## par section (id + titre).
- Chaque affirmation doit etre rattachable soit a un article de la norme (cite "(art. X)"), soit a un fait declare (cite "(fait : variable = valeur)"). Aucune invention : pas de chiffres, pas de donnees d'entite non declarees.
- Pour chaque section, couvre les exigences de contenu prevues par l'article correspondant de la norme.
- Si une exigence ne peut pas etre remplie avec les faits disponibles, ecris explicitement "[A COMPLETER PAR L'AUDITEUR : ...]" — l'echec visible prime sur l'omission silencieuse.
- Si la conversation contient un feedback humain de correction, applique-le precisement et ne modifie que ce qui est concerne.

Texte de la norme :
<norme>
{{{{ $flow.state.norme }}}}
</norme>"""

VERIF_SYS = f"""Tu es l'agent de VERIFICATION d'un rapport de conformite SFDR. Tu appliques un bareme explicite, jamais un jugement vague.

Bareme (applique chaque point systematiquement) :
1. COMPLETUDE : toutes les sections attendues sont-elles presentes dans le brouillon ? Liste toute section manquante — c'est le defaut le plus grave.
2. TRACABILITE : chaque affirmation est-elle rattachee a un article de la norme ou a un fait declare ? Cite les affirmations orphelines.
3. COHERENCE : y a-t-il des contradictions internes entre sections ?
4. PERIMETRE : y a-t-il des mentions hors perimetre (donnees chiffrees inventees, sections non demandees, conseils juridiques) ?

Format de sortie :
- Verdict global : CONFORME / A CORRIGER
- Puis, par point du bareme : ✅ ou ❌ avec la liste precise des problemes et la section concernee.
- Sois exigeant : un rapport moyen doit ressortir "A CORRIGER". Ne valide pas par complaisance.

Si tu as deja verifie une version precedente dans cette conversation (rebouclage) : concentre-toi sur ce qui a change depuis, ne re-souleve pas les points deja tranches par l'humain, et SIGNALE sans bloquer — la decision finale appartient a l'humain.

Texte de la norme (pour verifier les references) :
<norme>
{{{{ $flow.state.norme }}}}
</norme>"""

# ---------------- nodes ----------------

nodes = []
X = 0
def pos(x, y=100):
    return {"x": x, "y": y}

nodes.append(clone('startAgentflow', 'startAgentflow_0', 'Start', pos(-200), {
    "startInputType": "chatInput",
    "formTitle": "", "formDescription": "", "formInputTypes": "",
    "startEphemeralMemory": False,
    "startState": [
        {"key": "norme", "value": NORME},
        {"key": "faits", "value": ""},
        {"key": "sections", "value": ""},
        {"key": "faits_complets", "value": ""},
        {"key": "question", "value": ""},
        {"key": "brouillon", "value": ""},
        {"key": "rapport_annote", "value": ""},
    ],
    "startPersistState": True,
}))

nodes.append(clone('llmAgentflow', 'llmAgentflow_0', 'Agent 1 - Elicitation', pos(60), {
    "llmModel": "chatAnthropic",
    "llmMessages": [{"role": "system", "content": ELICIT_SYS}],
    "llmEnableMemory": True,
    "llmMemoryType": "allMessages",
    "llmUserMessage": "",
    "llmReturnResponseAs": "assistantMessage",
    "llmStructuredOutput": [
        {"key": "complete", "type": "enum", "enumValues": "oui, non",
         "description": "oui si tous les faits du vocabulaire sont collectes"},
        {"key": "question", "type": "string",
         "description": "Prochaine question a poser a l'utilisateur (vide si complete = oui)"},
        {"key": "faits", "type": "string",
         "description": "Faits collectes jusqu'ici, au format JSON variable: valeur"},
        {"key": "sections", "type": "string",
         "description": "Si complete = oui : sections applicables, une par ligne, format 'S-XX | titre | art. Y | justification'. Sinon vide."},
        {"key": "incertitudes", "type": "string",
         "description": "Ambiguites ou reponses incertaines a signaler (vide sinon)"},
    ],
    "llmUpdateState": [
        {"key": "faits_complets", "value": "{{ output.complete }}"},
        {"key": "question", "value": "{{ output.question }}"},
        {"key": "faits", "value": "{{ output.faits }}"},
        {"key": "sections", "value": "{{ output.sections }}"},
    ],
    "llmModelConfig": model_cfg(0.1),
}))

cond = clone('conditionAgentflow', 'conditionAgentflow_0', 'Faits complets ?', pos(320), {
    "conditions": [{
        "type": "string",
        "value1": "{{ $flow.state.faits_complets }}",
        "operation": "equal",
        "value2": "oui",
    }],
})
cond['data']['outputAnchors'] = [
    {"id": "conditionAgentflow_0-output-0", "label": 0, "name": 0, "description": "Condition 0"},
    {"id": "conditionAgentflow_0-output-1", "label": 1, "name": 1, "description": "Else"},
]
nodes.append(cond)

nodes.append(clone('directReplyAgentflow', 'directReplyAgentflow_0', 'Question suivante', pos(580, 320), {
    "directReplyMessage": "{{ $flow.state.question }}",
}))

nodes.append(clone('llmAgentflow', 'llmAgentflow_1', 'Recap faits + sections', pos(580, -80), {
    "llmModel": "chatAnthropic",
    "llmMessages": [{"role": "system", "content": RECAP_SYS}],
    "llmEnableMemory": True,
    "llmMemoryType": "allMessages",
    "llmUserMessage": "Presente le recapitulatif pour validation.",
    "llmReturnResponseAs": "assistantMessage",
    "llmStructuredOutput": [],
    "llmUpdateState": [],
    "llmModelConfig": model_cfg(0.1),
}))

nodes.append(clone('humanInputAgentflow', 'humanInputAgentflow_0', 'HITL 1 - Validation perimetre', pos(840, -80), {
    "humanInputDescriptionType": "fixed",
    "humanInputDescription": "HITL 1 — Validez les faits retenus et le perimetre de sections. Pour corriger : rejetez en precisant le fait a amender ou la section a ajouter/retirer.",
    "humanInputEnableFeedback": True,
}))

nodes.append(clone('loopAgentflow', 'loopAgentflow_0', 'Corriger elicitation', pos(840, 160), {
    "loopBackToNode": "llmAgentflow_0-Agent 1 - Elicitation",
    "maxLoopCount": 5,
    "fallbackMessage": "Nombre maximum de corrections du perimetre atteint. Relancez une nouvelle conversation.",
    "loopUpdateState": [{"key": "faits_complets", "value": ""}],
}))

nodes.append(clone('llmAgentflow', 'llmAgentflow_2', 'Agent 2 - Redaction', pos(1100, -80), {
    "llmModel": "chatAnthropic",
    "llmMessages": [{"role": "system", "content": REDIGE_SYS}],
    "llmEnableMemory": True,
    "llmMemoryType": "allMessages",
    "llmUserMessage": "Redige le brouillon complet du rapport, section par section.\n\nFaits confirmes : {{ $flow.state.faits }}\n\nSections a couvrir (toutes, sans exception) :\n{{ $flow.state.sections }}",
    "llmReturnResponseAs": "assistantMessage",
    "llmStructuredOutput": [],
    "llmUpdateState": [{"key": "brouillon", "value": "{{ output }}"}],
    "llmModelConfig": model_cfg(0.3),
}))

nodes.append(clone('llmAgentflow', 'llmAgentflow_3', 'Agent 3 - Verification', pos(1360, -80), {
    "llmModel": "chatAnthropic",
    "llmMessages": [{"role": "system", "content": VERIF_SYS}],
    "llmEnableMemory": True,
    "llmMemoryType": "allMessages",
    "llmUserMessage": "Verifie le brouillon selon le bareme.\n\nSections attendues :\n{{ $flow.state.sections }}\n\nFaits declares : {{ $flow.state.faits }}\n\nBrouillon a verifier :\n{{ $flow.state.brouillon }}",
    "llmReturnResponseAs": "assistantMessage",
    "llmStructuredOutput": [],
    "llmUpdateState": [{"key": "rapport_annote", "value": "{{ output }}"}],
    "llmModelConfig": model_cfg(0.1),
}))

nodes.append(clone('humanInputAgentflow', 'humanInputAgentflow_1', 'HITL 2 - Revue finale', pos(1620, -80), {
    "humanInputDescriptionType": "fixed",
    "humanInputDescription": "HITL 2 — Relisez le rapport annote par la verification. Validez pour livrer, ou rejetez avec vos corrections : le rapport sera revise puis re-verifie.",
    "humanInputEnableFeedback": True,
}))

nodes.append(clone('loopAgentflow', 'loopAgentflow_1', 'Rebouclage correction', pos(1620, 160), {
    "loopBackToNode": "llmAgentflow_2-Agent 2 - Redaction",
    "maxLoopCount": 3,
    "fallbackMessage": "Plafond de tours de rebouclage atteint (FR-09). Le dernier brouillon est disponible ci-dessus ; la decision finale appartient a l'auditeur.",
    "loopUpdateState": [],
}))

nodes.append(clone('directReplyAgentflow', 'directReplyAgentflow_1', 'Rapport livre', pos(1880, -80), {
    "directReplyMessage": "✅ **Rapport valide et livre** (norme : reglement UE 2019/2088 — SFDR)\n\n{{ $flow.state.brouillon }}",
}))

# ---------------- edges ----------------

COLORS = {"startAgentflow": "#7EE787", "llmAgentflow": "#64B5F6",
          "conditionAgentflow": "#FFB938", "humanInputAgentflow": "#6E6EFD",
          "loopAgentflow": "#FFA07A", "directReplyAgentflow": "#4DDBBB"}
by_id = {n['id']: n for n in nodes}

def edge(src, sh_suffix, tgt, label=None, human=False):
    sname, tname = by_id[src]['data']['name'], by_id[tgt]['data']['name']
    sh = f"{src}-output-{sh_suffix}"
    d = {"sourceColor": COLORS[sname], "targetColor": COLORS[tname], "isHumanInput": human}
    if label: d["edgeLabel"] = label
    return {"source": src, "sourceHandle": sh, "target": tgt, "targetHandle": tgt,
            "data": d, "type": "agentFlow", "id": f"{src}-{sh}-{tgt}-{tgt}"}

edges = [
    edge('startAgentflow_0', 'startAgentflow', 'llmAgentflow_0'),
    edge('llmAgentflow_0', 'llmAgentflow', 'conditionAgentflow_0'),
    edge('conditionAgentflow_0', '0', 'llmAgentflow_1', label='oui'),
    edge('conditionAgentflow_0', '1', 'directReplyAgentflow_0', label='sinon'),
    edge('llmAgentflow_1', 'llmAgentflow', 'humanInputAgentflow_0'),
    edge('humanInputAgentflow_0', '0', 'llmAgentflow_2', label='Proceed', human=True),
    edge('humanInputAgentflow_0', '1', 'loopAgentflow_0', label='Reject', human=True),
    edge('llmAgentflow_2', 'llmAgentflow', 'llmAgentflow_3'),
    edge('llmAgentflow_3', 'llmAgentflow', 'humanInputAgentflow_1'),
    edge('humanInputAgentflow_1', '0', 'directReplyAgentflow_1', label='Proceed', human=True),
    edge('humanInputAgentflow_1', '1', 'loopAgentflow_1', label='Reject', human=True),
]

flow = {
    "name": "J7 - Rapport Norme SFDR",
    "type": "AGENTFLOW",
    "flowData": json.dumps({"nodes": nodes, "edges": edges, "viewport": {"x": 100, "y": 100, "zoom": 0.6}}, ensure_ascii=False),
    "nodes": nodes,
    "edges": edges,
}
out = f'{ROOT}/init/flows/J7-Rapport-Norme.json'
json.dump(flow, open(out, 'w'), ensure_ascii=False, indent=1)
print('written', out)
print('nodes:', [n['data']['label'] for n in nodes])
import os
print('size:', os.path.getsize(out))
