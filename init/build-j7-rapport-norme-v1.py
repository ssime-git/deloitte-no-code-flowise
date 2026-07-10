#!/usr/bin/env python3
"""Build 'J7 - Rapport Norme SFDR v1 (durci)' — moteur de règles déterministe (Custom Function).

Différences avec la v0 (build-j7-rapport-norme.py) :
- le mapping faits → sections est un lookup dans data/normes/sfdr-regles.json (nœud Custom Function), plus le LLM ;
- la norme n'est plus injectée en contexte : chaque agent ne reçoit que le nécessaire (vocabulaire, gabarits) ;
- élicitation / récap / vérification sur gpt-4o-mini via le gateway OpenAI, rédaction sur Claude.
"""
import json

ROOT = '/home/seb/project/deloitte/deloitte-no-code-flowise'
J6 = json.load(open(f'{ROOT}/init/flows/J6-Multi-Agent-Supervised.json'))
NORME = json.load(open(f'{ROOT}/data/normes/sfdr-regles.json'))

templates = {}
for n in J6['nodes']:
    templates.setdefault(n['data']['name'], n)

CRED_ANTHROPIC = 'b2c3d4e5-f6a7-8901-bcde-f12345678901'
CRED_OPENAI = '3bf22f9c-6bdc-4e55-9839-c4b9f0300238'
GATEWAY = 'https://ai-gateway.liora.tech/v1'

def cfg_openai(temp):
    return {"llmModel": "chatOpenAI", "FLOWISE_CREDENTIAL_ID": CRED_OPENAI,
            "modelName": "gpt-4o-mini", "temperature": temp, "streaming": True,
            "basepath": GATEWAY}

def cfg_claude(temp):
    return {"llmModel": "chatAnthropic", "FLOWISE_CREDENTIAL_ID": CRED_ANTHROPIC,
            "modelName": "claude-sonnet-4-6", "temperature": temp, "streaming": True,
            "allowImageUploads": False}

def clone(tpl_name, new_id, label, position, inputs, model=None):
    tpl = templates[tpl_name]
    node = json.loads(json.dumps(tpl).replace(tpl['id'], new_id))
    node['position'] = position
    node['positionAbsolute'] = position
    node['data']['label'] = label
    node['data']['inputs'] = inputs
    node['data']['selected'] = False
    if model:  # switch provider fields (template is chatAnthropic)
        inputs['llmModel'] = model['llmModel']
        inputs['llmModelConfig'] = model
    if tpl_name == 'humanInputAgentflow':
        # server routes decision branches by index-based handles (-output-0/-output-1)
        node['data']['outputAnchors'] = [
            {"id": f"{new_id}-output-0", "label": "Proceed", "name": "proceed"},
            {"id": f"{new_id}-output-1", "label": "Reject", "name": "reject"},
        ]
    return node

def custom_fn_node(nid, label, pos, code, update):
    return {"id": nid, "position": pos, "positionAbsolute": pos, "type": "agentFlow",
            "width": 192, "height": 66,
            "data": {"id": nid, "label": label, "version": 1.1,
                     "name": "customFunctionAgentflow", "type": "CustomFunction",
                     "color": "#E4B7FF", "baseClasses": ["CustomFunction"],
                     "category": "Agent Flows", "description": "Execute custom function",
                     "inputs": {"customFunctionInputVariables": [],
                                "customFunctionJavascriptFunction": code,
                                "customFunctionUpdateState": update},
                     "inputAnchors": [],
                     "inputParams": [
                         {"label": "Input Variables", "name": "customFunctionInputVariables",
                          "type": "array", "optional": True,
                          "id": f"{nid}-input-customFunctionInputVariables-array", "display": True},
                         {"label": "Javascript Function", "name": "customFunctionJavascriptFunction",
                          "type": "code",
                          "id": f"{nid}-input-customFunctionJavascriptFunction-code", "display": True},
                         {"label": "Update Flow State", "name": "customFunctionUpdateState",
                          "type": "array", "optional": True,
                          "id": f"{nid}-input-customFunctionUpdateState-array", "display": True}],
                     "outputAnchors": [{"id": f"{nid}-output-customFunctionAgentflow",
                                        "label": "Custom Function", "name": "customFunctionAgentflow"}],
                     "outputs": {}, "selected": False}}

# ---------------- moteur de règles (JS embarqué) ----------------

ENGINE_JS = """const DATA = %s;

let faits;
try {
    faits = typeof $flow.state.faits === 'string' ? JSON.parse($flow.state.faits) : $flow.state.faits;
} catch (e) {
    faits = null;
}
if (!faits || typeof faits !== 'object') faits = {};

// Completude calculee ici, pas par le LLM : un fait est acquis s'il porte une valeur canonique du vocabulaire.
const manquants = [];
for (const v of DATA.vocabulaire) {
    const val = faits[v.variable];
    if (val === undefined || val === null || val === '' || !v.valeurs.map(String).includes(String(val))) {
        manquants.push(v.variable);
    }
}
if (manquants.length) {
    const q = ($flow.state.question && String($flow.state.question).trim())
        ? $flow.state.question
        : 'Il manque encore : ' + manquants.join(', ') + '. Pouvez-vous preciser ?';
    return { complet: 'non', manquants, question: q, faits };
}

const evalCond = (c) => {
    if (c.et) return c.et.every(evalCond);
    if (c.ou) return c.ou.some(evalCond);
    const v = faits[c.variable];
    if (v === undefined || v === null || v === '') throw new Error('Fait manquant : ' + c.variable);
    if (c.op === '=') return String(v) === String(c.valeur);
    if (c.op === 'in') return c.valeur.map(String).includes(String(v));
    throw new Error('Operateur inconnu : ' + c.op);
};

const declenchees = [];
const sectionsMap = {};
for (const r of DATA.regles) {
    let ok;
    try { ok = evalCond(r.condition); }
    catch (e) { return { erreur: e.message, faits }; }
    if (!ok) continue;
    declenchees.push(r.rule_id + ' (' + r.ref_norme + ')');
    for (const sid of r.sections_declenchees) {
        if (!sectionsMap[sid]) {
            const s = DATA.sections.find(x => x.section_id === sid);
            sectionsMap[sid] = Object.assign({}, s, { declenchee_par: [], consignes: [] });
        }
        sectionsMap[sid].declenchee_par.push(r.rule_id + ' (' + r.ref_norme + ')');
        if (r.note) sectionsMap[sid].consignes.push(r.note);
    }
}
const sections = Object.values(sectionsMap).sort((a, b) => a.section_id.localeCompare(b.section_id));
return { complet: 'oui', question: '', norme: DATA.meta.norme, version_norme: DATA.meta.version, faits,
         regles_declenchees: declenchees, nb_sections: sections.length, sections };
""" % json.dumps({"meta": NORME["meta"], "vocabulaire": NORME["vocabulaire"], "regles": NORME["regles"], "sections": NORME["sections"]},
                 ensure_ascii=False, indent=1)

# ---------------- prompts ----------------

VOCAB_LINES = "\n".join(
    f"- `{v['variable']}` (valeurs exactes : {', '.join(v['valeurs'])}) — question : {v['question_elicitation']}"
    for v in NORME['vocabulaire'])

ELICIT_SYS = f"""Tu es l'agent d'ELICITATION d'un generateur de rapport de conformite SFDR (reglement UE 2019/2088).

Ta seule mission : collecter les 5 faits du vocabulaire ci-dessous. Tu ne deduis PAS les sections applicables — un moteur de regles deterministe s'en charge apres toi.

Vocabulaire d'entree (TOUS les faits sont obligatoires) :
{VOCAB_LINES}

Regles :
- Exploite d'abord TOUT ce que l'utilisateur a deja dit : extrais chaque fait present dans son message avant de poser la moindre question. Ne redemande JAMAIS un fait deja fourni, meme formule autrement.
- Pose UNE question a la fois, courte, uniquement pour les faits reellement absents.
- Dans "faits", utilise EXACTEMENT les valeurs canoniques listees — jamais de valeur libre.
- Exemples de correspondance obligatoires :
  * "gestionnaire d'actifs", "assureur", "fonds" => type_acteur = "acteur_marches_financiers"
  * "620 salaries", "1200 salaries" => plus_de_500_salaries = "oui" ; "45 salaries" => "non"
  * "PAI pris en compte" => prise_en_compte_pai = "oui" ; "ne prend pas en compte les PAI" => "non"
  * "produit article 8" => type_produit = "produit_art8" ; "produit article 9" => "produit_art9" ; "produit standard", "ni article 8 ni article 9" => "produit_standard"
  * "sans indice de reference" => indice_reference_designe = "non" ; "avec un indice de reference designe" => "oui"
- Si le produit n'est pas art. 9, indice_reference_designe = "non_applicable" sans poser la question.
- Si une reponse est ambigue, signale-le dans "incertitudes" et reformule la question.
- Quand TOUS les faits sont connus : question = "" (chaine vide).
- Si un humain rejette la validation avec un feedback, corrige les faits selon ce feedback exactement."""

RECAP_SYS = """Tu prepares la validation humaine n°1 d'un generateur de rapport SFDR.

Resultat du moteur de regles deterministe (lookup dans la table de decision versionnee, sans LLM) :
{{ $flow.state.moteur }}

- Si le resultat contient une cle "erreur" : affiche l'erreur en gras et demande a l'utilisateur de rejeter avec la correction — n'invente rien d'autre.
- Sinon, presente de facon claire et compacte, en francais :
  1. **Faits retenus** — tableau variable / valeur.
  2. **Sections applicables** — tableau : section, titre, declenchee par (regle + article), consignes eventuelles.
  3. Rappelle que ce perimetre sort d'une table de decision deterministe : memes faits => memes sections.
Termine par : "Validez ce perimetre, ou rejetez en indiquant le fait a corriger."
N'ajoute rien d'autre : pas de redaction de rapport a ce stade."""

REDIGE_SYS = """Tu es l'agent de REDACTION d'un rapport de conformite SFDR (reglement UE 2019/2088).

Regles imperatives :
- Redige UNIQUEMENT les sections fournies dans le perimetre, une par une, dans l'ordre, avec un titre de niveau ## par section (id + titre).
- Pour chaque section : suis son "gabarit", couvre TOUS ses "points_obligatoires", applique ses "consignes".
- Chaque affirmation doit etre rattachable soit a l'article cite dans "ref_norme" (cite "(art. X)"), soit a un fait declare (cite "(fait : variable = valeur)"). Aucune invention : pas de chiffres ni de donnees d'entite non declares.
- Si une exigence ne peut pas etre remplie avec les faits disponibles, ecris explicitement "[A COMPLETER PAR L'AUDITEUR : ...]" — l'echec visible prime sur l'omission silencieuse.
- Si la conversation contient un feedback humain de correction, applique-le precisement et ne modifie que ce qui est concerne."""

VERIF_SYS = """Tu es l'agent de VERIFICATION d'un rapport de conformite SFDR. Tu appliques un bareme explicite, jamais un jugement vague.

Bareme (applique chaque point systematiquement) :
1. COMPLETUDE : chaque section du perimetre attendu est-elle presente dans le brouillon ? Liste toute section manquante — c'est le defaut le plus grave.
2. POINTS OBLIGATOIRES : pour chaque section, chaque point obligatoire du perimetre est-il couvert ?
3. TRACABILITE : chaque affirmation est-elle rattachee a un article (art. X) ou a un fait declare ? Cite les affirmations orphelines.
4. COHERENCE ET PERIMETRE : contradictions internes ? mentions hors perimetre (chiffres inventes, sections non demandees, conseils juridiques) ?

Format de sortie :
- Verdict global : CONFORME / A CORRIGER
- Puis, par point du bareme : OK ou PROBLEME avec la liste precise des defauts et la section concernee.
- Sois exigeant : ne valide pas par complaisance.

Si tu as deja verifie une version precedente dans cette conversation (rebouclage) : concentre-toi sur ce qui a change depuis, ne re-souleve pas les points deja tranches par l'humain, et SIGNALE sans bloquer — la decision finale appartient a l'humain."""

# ---------------- nodes ----------------

nodes = []
def pos(x, y=100):
    return {"x": x, "y": y}

nodes.append(clone('startAgentflow', 'startAgentflow_0', 'Start', pos(-200), {
    "startInputType": "chatInput",
    "formTitle": "", "formDescription": "", "formInputTypes": "",
    "startEphemeralMemory": False,
    "startState": [
        {"key": "faits", "value": ""},
        {"key": "faits_complets", "value": ""},
        {"key": "question", "value": ""},
        {"key": "moteur", "value": ""},
        {"key": "brouillon", "value": ""},
        {"key": "rapport_annote", "value": ""},
    ],
    "startPersistState": True,
}))

nodes.append(clone('llmAgentflow', 'llmAgentflow_0', 'Agent 1 - Elicitation', pos(60), {
    "llmModel": "chatOpenAI",
    "llmMessages": [{"role": "system", "content": ELICIT_SYS}],
    "llmEnableMemory": True,
    "llmMemoryType": "allMessages",
    "llmUserMessage": "",
    "llmReturnResponseAs": "assistantMessage",
    "llmStructuredOutput": [
        {"key": "question", "type": "string",
         "description": "Prochaine question a poser a l'utilisateur (vide si tous les faits sont connus)"},
        {"key": "faits", "type": "string",
         "description": "Objet JSON des faits collectes, uniquement les valeurs canoniques du vocabulaire"},
        {"key": "incertitudes", "type": "string",
         "description": "Ambiguites a signaler (vide sinon)"},
    ],
    "llmUpdateState": [
        {"key": "question", "value": "{{ output.question }}"},
        {"key": "faits", "value": "{{ output.faits }}"},
    ],
    "llmModelConfig": cfg_openai(0.1),
}))

cond = clone('conditionAgentflow', 'conditionAgentflow_0', 'Faits complets ?', pos(580), {
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

nodes.append(custom_fn_node('customFunctionAgentflow_0', 'Moteur de regles', pos(320, -80),
    ENGINE_JS,
    [{"key": "moteur", "value": "{{ output }}"},
     {"key": "faits_complets", "value": "{{ output.complet }}"},
     {"key": "question", "value": "{{ output.question }}"}]))

nodes.append(clone('llmAgentflow', 'llmAgentflow_1', 'Recap faits + sections', pos(840, -80), {
    "llmModel": "chatOpenAI",
    "llmMessages": [{"role": "system", "content": RECAP_SYS}],
    "llmEnableMemory": True,
    "llmMemoryType": "allMessages",
    "llmUserMessage": "Presente le recapitulatif pour validation.",
    "llmReturnResponseAs": "assistantMessage",
    "llmStructuredOutput": [],
    "llmUpdateState": [],
    "llmModelConfig": cfg_openai(0.1),
}))

nodes.append(clone('humanInputAgentflow', 'humanInputAgentflow_0', 'HITL 1 - Validation perimetre', pos(1100, -80), {
    "humanInputDescriptionType": "fixed",
    "humanInputDescription": "HITL 1 — Validez les faits retenus et le perimetre de sections calcule par le moteur. Pour corriger : rejetez en precisant le fait a amender.",
    "humanInputEnableFeedback": True,
}))

nodes.append(clone('loopAgentflow', 'loopAgentflow_0', 'Corriger elicitation', pos(1100, 160), {
    "loopBackToNode": "llmAgentflow_0-Agent 1 - Elicitation",
    "maxLoopCount": 5,
    "fallbackMessage": "Nombre maximum de corrections du perimetre atteint. Relancez une nouvelle conversation.",
    "loopUpdateState": [{"key": "faits_complets", "value": ""}],
}))

nodes.append(clone('llmAgentflow', 'llmAgentflow_2', 'Agent 2 - Redaction', pos(1360, -80), {
    "llmModel": "chatAnthropic",
    "llmMessages": [{"role": "system", "content": REDIGE_SYS}],
    "llmEnableMemory": True,
    "llmMemoryType": "allMessages",
    "llmUserMessage": "Redige le brouillon complet du rapport, section par section.\n\nPerimetre calcule par le moteur de regles (faits, sections, gabarits, points obligatoires, consignes) :\n{{ $flow.state.moteur }}",
    "llmReturnResponseAs": "assistantMessage",
    "llmStructuredOutput": [],
    "llmUpdateState": [{"key": "brouillon", "value": "{{ output }}"}],
    "llmModelConfig": cfg_claude(0.3),
}))

nodes.append(clone('llmAgentflow', 'llmAgentflow_3', 'Agent 3 - Verification', pos(1620, -80), {
    "llmModel": "chatOpenAI",
    "llmMessages": [{"role": "system", "content": VERIF_SYS}],
    "llmEnableMemory": True,
    "llmMemoryType": "allMessages",
    "llmUserMessage": "Verifie le brouillon selon le bareme.\n\nPerimetre attendu (sections et points obligatoires) :\n{{ $flow.state.moteur }}\n\nBrouillon a verifier :\n{{ $flow.state.brouillon }}",
    "llmReturnResponseAs": "assistantMessage",
    "llmStructuredOutput": [],
    "llmUpdateState": [{"key": "rapport_annote", "value": "{{ output }}"}],
    "llmModelConfig": cfg_openai(0.1),
}))

nodes.append(clone('humanInputAgentflow', 'humanInputAgentflow_1', 'HITL 2 - Revue finale', pos(1880, -80), {
    "humanInputDescriptionType": "fixed",
    "humanInputDescription": "HITL 2 — Relisez le rapport annote par la verification. Validez pour livrer, ou rejetez avec vos corrections : le rapport sera revise puis re-verifie.",
    "humanInputEnableFeedback": True,
}))

nodes.append(clone('loopAgentflow', 'loopAgentflow_1', 'Rebouclage correction', pos(1880, 160), {
    "loopBackToNode": "llmAgentflow_2-Agent 2 - Redaction",
    "maxLoopCount": 3,
    "fallbackMessage": "Plafond de tours de rebouclage atteint (FR-09). Le dernier brouillon est disponible ci-dessus ; la decision finale appartient a l'auditeur.",
    "loopUpdateState": [],
}))

nodes.append(clone('directReplyAgentflow', 'directReplyAgentflow_1', 'Rapport livre', pos(2140, -80), {
    "directReplyMessage": "✅ **Rapport valide et livre** (norme : reglement UE 2019/2088 — SFDR, perimetre calcule par table de decision)\n\n{{ $flow.state.brouillon }}",
}))

# ---------------- edges ----------------

COLORS = {"startAgentflow": "#7EE787", "llmAgentflow": "#64B5F6",
          "conditionAgentflow": "#FFB938", "humanInputAgentflow": "#6E6EFD",
          "loopAgentflow": "#FFA07A", "directReplyAgentflow": "#4DDBBB",
          "customFunctionAgentflow": "#E4B7FF"}
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
    edge('llmAgentflow_0', 'llmAgentflow', 'customFunctionAgentflow_0'),
    edge('customFunctionAgentflow_0', 'customFunctionAgentflow', 'conditionAgentflow_0'),
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
    "name": "J7 - Rapport Norme SFDR v1 (durci)",
    "type": "AGENTFLOW",
    "flowData": json.dumps({"nodes": nodes, "edges": edges, "viewport": {"x": 100, "y": 100, "zoom": 0.6}}, ensure_ascii=False),
    "nodes": nodes,
    "edges": edges,
}
out = f'{ROOT}/init/flows/J7-Rapport-Norme-v1.json'
json.dump(flow, open(out, 'w'), ensure_ascii=False, indent=1)
print('written', out)
print('nodes:', [n['data']['label'] for n in nodes])
import os
print('size:', os.path.getsize(out))
