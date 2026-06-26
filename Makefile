STACK := deloitte-no-code-flowise
PORT := $(shell grep FLOWISE_PORT .env 2>/dev/null | cut -d= -f2 || echo 3000)
API_URL := http://localhost:$(PORT)/api/v1
J2_QUESTION := Bonjour, qui es-tu ?
J3_QUESTION := Quels sont les seuils decart pour les controles URSSAF ?
J3_NIR_QUESTION := Que faire avec un NIR fictif dans un audit ?
J4_QUESTION_CALC := Calcule le montant de la CSG sur un salaire brut de 3200 euros. Le taux de CSG deductible est 6.8%.
J4_QUESTION_DATE := Nous sommes en quelle periode de declaration DSN ?
J4_RAG_QUESTION := Quels sont les seuils URSSAF a verifier dans un audit paie ? Cite tes sources.
J4_RAG_COMBO_QUESTION := Un salarie a un brut de 3500 euros. Quelles anomalies dois-je verifier selon le corpus, et calcule le montant de la cotisation patronale maladie a 13%.
J5_QUESTION_SCOPE := Quel est le perimetre de donnees auditables disponible via tes outils ? Reponds sans inventer de lignes brutes.
J5_QUESTION_AGGREGATE := Donne-moi une vue agregée par etablissement des donnees DSN disponibles.
J5_QUESTION_CASE := Analyse lexception EXC_URSSAF_AMOUNT_INCONSISTENT et dis-moi quelles preuves daudit et documentaires sont disponibles.
J6_QUESTION := Un salarie presente une variation de brut de 18 pourcent et lexception EXC_URSSAF_AMOUNT_INCONSISTENT. Prepare une alerte daudit DSN exploitable par un auditeur.

.PHONY: setup install-deps up down reset force-reset status logs-flowise logs-init api-key ping mcp-health psql wait-init test-j2 test-j3 test-j3-nir smoke-j3 reset-smoke-j3 from-scratch-j3 test-j4 test-j4-date test-j4-rag test-j4-rag-combo smoke-j4 reset-smoke-j4 from-scratch-j4 test-j5-scope test-j5-aggregate test-j5-case smoke-j5 reset-smoke-j5 from-scratch-j5 test-j6 smoke-j6 reset-smoke-j6 from-scratch-j6 docs help deploy-test deploy-bake deploy-launch deploy-access deploy-teardown

help:
	@echo "Usage: make <target>"
	@echo ""
	@echo "First-time setup (run once on a fresh VM):"
	@echo "  setup        Bootstrap dependencies: make, docker, curl, jq, python3 (via setup.sh)"
	@echo "  install-deps Verify that docker, curl, jq and python3 are available"
	@echo ""
	@echo "Stack management:"
	@echo "  up           Start all services (postgres, flowise, init)"
	@echo "  down         Stop all services"
	@echo "  reset        Reset stack (prompts for confirmation)"
	@echo "  force-reset  Reset stack without confirmation"
	@echo "  status       Show container status"
	@echo ""
	@echo "Logs:"
	@echo "  logs-flowise  Tail Flowise logs"
	@echo "  logs-init     Show init bootstrap logs"
	@echo ""
	@echo "API & Debug:"
	@echo "  api-key   Get auto-generated API key from init logs"
	@echo "  ping      Healthcheck"
	@echo "  mcp-health  Healthcheck for the MCP server"
	@echo "  wait-init  Wait for init bootstrap and flow import"
	@echo "  psql      Open PostgreSQL shell"
	@echo "  test-j2   Test J2 - Simple Chat prediction"
	@echo "  test-j3   Test J3 - RAG Chat prediction"
	@echo "  test-j3-nir  Test J3 on the NIR fictif question"
	@echo "  smoke-j3  Run the main J3 smoke tests"
	@echo "  reset-smoke-j3  Force reset the stack, then run J3 smoke tests"
	@echo "  from-scratch-j3  Alias simple de reset-smoke-j3"
	@echo "  test-j4   Test J4 - Agent Simple (calcul CSG)"
	@echo "  test-j4-date  Test J4 - Agent Simple (date DSN)"
	@echo "  test-j4-rag  Test J4 - Agent RAG (recherche corpus)"
	@echo "  test-j4-rag-combo  Test J4 - Agent RAG (recherche + calcul)"
	@echo "  smoke-j4  Run the main J4 smoke tests (agent simple + agent RAG)"
	@echo "  reset-smoke-j4  Force reset the stack, then run J4 smoke tests"
	@echo "  from-scratch-j4  Alias de reset-smoke-j4"
	@echo "  test-j5-scope  Test J5 - Agent MCP (perimetre gouverne)"
	@echo "  test-j5-aggregate  Test J5 - Agent MCP (vue agregée)"
	@echo "  test-j5-case  Test J5 - Agent MCP (dossier d exception)"
	@echo "  smoke-j5  Run the main J5 smoke tests (requires profile mcp)"
	@echo "  reset-smoke-j5  Force reset the stack with profile mcp, then run J5 smoke tests"
	@echo "  from-scratch-j5  Alias de reset-smoke-j5"
	@echo "  test-j6  Test J6 - Multi-agent supervise (retour jusqu au point de validation humaine)"
	@echo "  smoke-j6  Run the main J6 smoke test (requires profile mcp)"
	@echo "  reset-smoke-j6  Force reset the stack with profile mcp, then run J6 smoke test"
	@echo "  from-scratch-j6  Alias de reset-smoke-j6"
	@echo ""
	@echo "Docs:"
	@echo "  docs      List available training docs"
	@echo ""
	@echo "AWS fleet deployment (17 instances):"
	@echo "  deploy-test     Launch 1 test VM, verify stack, prompt before terminate"
	@echo "  deploy-bake     Bake the training AMI (run after deploy-test passes)"
	@echo "  deploy-launch   Launch 17 instances from the baked AMI"
	@echo "  deploy-access   Print the access table (URL + credentials per instance)"
	@echo "  deploy-teardown Terminate all running training instances"

setup:
	./setup.sh

REQUIRED_CMDS := curl jq python3

install-deps:
	@echo "Checking prerequisites..."
	@for cmd in $(REQUIRED_CMDS); do \
		if ! command -v $$cmd >/dev/null 2>&1; then \
			echo "ERROR: '$$cmd' is not installed."; \
			echo "Run 'make setup' or './setup.sh' to install all dependencies."; \
			exit 1; \
		fi; \
	done
	@if ! command -v docker >/dev/null 2>&1; then \
		echo "ERROR: 'docker' is not installed."; \
		echo "Run 'make setup' or './setup.sh' to install Docker."; \
		exit 1; \
	fi
	@if ! docker compose version >/dev/null 2>&1; then \
		echo "ERROR: 'docker compose' plugin is not installed."; \
		echo "Run 'sudo apt-get install -y docker-compose-plugin' or './setup.sh'."; \
		exit 1; \
	fi
	@echo "All prerequisites met."

up: install-deps
	docker compose up -d

down:
	docker compose down

reset:
	./reset.sh

force-reset:
	./reset.sh -f

status:
	docker compose ps

logs-flowise:
	docker compose logs -f flowise

logs-init:
	docker compose logs init

api-key:
	@docker logs $(STACK)-init-1 2>/dev/null | grep "API key:" | tail -1 | awk '{print $$NF}' || echo "Init container not started yet. Run 'make up' first."

ping:
	@curl -sf $(API_URL)/ping && echo " - pong" || echo "FAILED"

mcp-health:
	@curl -sf http://localhost:8001/health && echo " - mcp ok" || echo "FAILED"

psql:
	docker exec -it $(STACK)-postgres-1 psql -U flowise -d flowise

wait-init:
	@sh -c ' \
		for i in $$(seq 1 60); do \
			API_KEY=$$(docker compose logs init --tail 120 2>/dev/null | awk "/API key:/ {print \$$NF}" | tail -1); \
			if [ -n "$$API_KEY" ]; then \
				FLOW_COUNT=$$(curl -sf -H "Authorization: Bearer $$API_KEY" $(API_URL)/chatflows 2>/dev/null | jq -r "if type==\"array\" then length else 0 end" 2>/dev/null || echo 0); \
				if [ "$$FLOW_COUNT" -ge 5 ]; then \
					echo "Init ready: API key found, $$FLOW_COUNT flows imported."; \
					exit 0; \
				fi; \
			fi; \
			sleep 2; \
		done; \
		echo "Init not ready in time."; \
		exit 1'

test-j2: wait-init
	@API_KEY=$$(docker compose logs init --tail 120 2>/dev/null | awk '/API key:/ {print $$NF}' | tail -1); \
	J2_ID=$$(curl -sf -H "Authorization: Bearer $$API_KEY" $(API_URL)/chatflows | jq -r '.[] | select(.name | contains("Simple")) | .id' | head -n1); \
	[ -z "$$J2_ID" ] && echo "J2 not found" || { \
		printf '\n[J2] %s\n' "$(J2_QUESTION)"; \
		curl -sf -X POST "$(API_URL)/prediction/$$J2_ID" -H "Authorization: Bearer $$API_KEY" -H "Content-Type: application/json" -d '{"question":"$(J2_QUESTION)"}' | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('text','').strip())"; \
		printf '\n'; \
	}

test-j3: wait-init
	@API_KEY=$$(docker compose logs init --tail 120 2>/dev/null | awk '/API key:/ {print $$NF}' | tail -1); \
	J3_ID=$$(curl -sf -H "Authorization: Bearer $$API_KEY" $(API_URL)/chatflows | jq -r '.[] | select(.name == "J3 - RAG Chat") | .id' | head -n1); \
	[ -z "$$J3_ID" ] && echo "J3 not found" || { \
		printf '\n[J3-URSSAF] %s\n' "$(J3_QUESTION)"; \
		curl -sf -X POST "$(API_URL)/prediction/$$J3_ID" -H "Authorization: Bearer $$API_KEY" -H "Content-Type: application/json" -d '{"question":"$(J3_QUESTION)"}' | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('text','').strip())"; \
		printf '\n'; \
	}

test-j3-nir: wait-init
	@API_KEY=$$(docker compose logs init --tail 120 2>/dev/null | awk '/API key:/ {print $$NF}' | tail -1); \
	J3_ID=$$(curl -sf -H "Authorization: Bearer $$API_KEY" $(API_URL)/chatflows | jq -r '.[] | select(.name == "J3 - RAG Chat") | .id' | head -n1); \
	[ -z "$$J3_ID" ] && echo "J3 not found" || { \
		printf '\n[J3-NIR] %s\n' "$(J3_NIR_QUESTION)"; \
		curl -sf -X POST "$(API_URL)/prediction/$$J3_ID" -H "Authorization: Bearer $$API_KEY" -H "Content-Type: application/json" -d '{"question":"$(J3_NIR_QUESTION)"}' | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('text','').strip())"; \
		printf '\n'; \
	}

smoke-j3: ping test-j3 test-j3-nir

reset-smoke-j3:
	./reset.sh -f
	$(MAKE) smoke-j3

from-scratch-j3: reset-smoke-j3

test-j4: wait-init
	@API_KEY=$$(docker compose logs init --tail 120 2>/dev/null | awk '/API key:/ {print $$NF}' | tail -1); \
	J4_ID=$$(curl -sf -H "Authorization: Bearer $$API_KEY" $(API_URL)/chatflows | jq -r '.[] | select(.name == "J4 - Agent Simple") | .id' | head -n1); \
	[ -z "$$J4_ID" ] && echo "J4 not found" || { \
		printf '\n[J4-CALC] %s\n' "$(J4_QUESTION_CALC)"; \
		curl -sf -X POST "$(API_URL)/prediction/$$J4_ID" -H "Authorization: Bearer $$API_KEY" -H "Content-Type: application/json" -d "{\"question\":\"$(J4_QUESTION_CALC)\"}" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('text','').strip())"; \
		printf '\n'; \
	}

test-j4-date: wait-init
	@API_KEY=$$(docker compose logs init --tail 120 2>/dev/null | awk '/API key:/ {print $$NF}' | tail -1); \
	J4_ID=$$(curl -sf -H "Authorization: Bearer $$API_KEY" $(API_URL)/chatflows | jq -r '.[] | select(.name == "J4 - Agent Simple") | .id' | head -n1); \
	[ -z "$$J4_ID" ] && echo "J4 not found" || { \
		printf '\n[J4-DATE] %s\n' "$(J4_QUESTION_DATE)"; \
		curl -sf -X POST "$(API_URL)/prediction/$$J4_ID" -H "Authorization: Bearer $$API_KEY" -H "Content-Type: application/json" -d "{\"question\":\"$(J4_QUESTION_DATE)\"}" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('text','').strip())"; \
		printf '\n'; \
	}

test-j4-rag: wait-init
	@API_KEY=$$(docker compose logs init --tail 120 2>/dev/null | awk '/API key:/ {print $$NF}' | tail -1); \
	J4R_ID=$$(curl -sf -H "Authorization: Bearer $$API_KEY" $(API_URL)/chatflows | jq -r '.[] | select(.name == "J4 - Agent RAG") | .id' | head -n1); \
	[ -z "$$J4R_ID" ] && echo "J4 Agent RAG not found" || { \
		printf '\n[J4-RAG] %s\n' "$(J4_RAG_QUESTION)"; \
		curl -sf -X POST "$(API_URL)/prediction/$$J4R_ID" -H "Authorization: Bearer $$API_KEY" -H "Content-Type: application/json" -d "{\"question\":\"$(J4_RAG_QUESTION)\"}" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('text','').strip())"; \
		printf '\n'; \
	}

test-j4-rag-combo: wait-init
	@API_KEY=$$(docker compose logs init --tail 120 2>/dev/null | awk '/API key:/ {print $$NF}' | tail -1); \
	J4R_ID=$$(curl -sf -H "Authorization: Bearer $$API_KEY" $(API_URL)/chatflows | jq -r '.[] | select(.name == "J4 - Agent RAG") | .id' | head -n1); \
	[ -z "$$J4R_ID" ] && echo "J4 Agent RAG not found" || { \
		printf '\n[J4-RAG-COMBO] %s\n' "$(J4_RAG_COMBO_QUESTION)"; \
		curl -sf -X POST "$(API_URL)/prediction/$$J4R_ID" -H "Authorization: Bearer $$API_KEY" -H "Content-Type: application/json" -d "{\"question\":\"$(J4_RAG_COMBO_QUESTION)\"}" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('text','').strip())"; \
		printf '\n'; \
	}

smoke-j4: ping test-j4 test-j4-date test-j4-rag test-j4-rag-combo

reset-smoke-j4:
	./reset.sh -f
	$(MAKE) smoke-j4

from-scratch-j4: reset-smoke-j4

test-j5-scope: wait-init
	@API_KEY=$$(docker compose logs init --tail 120 2>/dev/null | awk '/API key:/ {print $$NF}' | tail -1); \
	J5_ID=$$(curl -sf -H "Authorization: Bearer $$API_KEY" $(API_URL)/chatflows | jq -r '.[] | select(.name == "J5 - Agent MCP") | .id' | head -n1); \
	[ -z "$$J5_ID" ] && echo "J5 not found" || { \
		printf '\n[J5-SCOPE] %s\n' "$(J5_QUESTION_SCOPE)"; \
		curl -sf -X POST "$(API_URL)/prediction/$$J5_ID" -H "Authorization: Bearer $$API_KEY" -H "Content-Type: application/json" -d "{\"question\":\"$(J5_QUESTION_SCOPE)\"}" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('text','').strip())"; \
		printf '\n'; \
	}

test-j5-aggregate: wait-init
	@API_KEY=$$(docker compose logs init --tail 120 2>/dev/null | awk '/API key:/ {print $$NF}' | tail -1); \
	J5_ID=$$(curl -sf -H "Authorization: Bearer $$API_KEY" $(API_URL)/chatflows | jq -r '.[] | select(.name == "J5 - Agent MCP") | .id' | head -n1); \
	[ -z "$$J5_ID" ] && echo "J5 not found" || { \
		printf '\n[J5-AGGREGATE] %s\n' "$(J5_QUESTION_AGGREGATE)"; \
		curl -sf -X POST "$(API_URL)/prediction/$$J5_ID" -H "Authorization: Bearer $$API_KEY" -H "Content-Type: application/json" -d "{\"question\":\"$(J5_QUESTION_AGGREGATE)\"}" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('text','').strip())"; \
		printf '\n'; \
	}

test-j5-case: wait-init
	@API_KEY=$$(docker compose logs init --tail 120 2>/dev/null | awk '/API key:/ {print $$NF}' | tail -1); \
	J5_ID=$$(curl -sf -H "Authorization: Bearer $$API_KEY" $(API_URL)/chatflows | jq -r '.[] | select(.name == "J5 - Agent MCP") | .id' | head -n1); \
	[ -z "$$J5_ID" ] && echo "J5 not found" || { \
		printf '\n[J5-CASE] %s\n' "$(J5_QUESTION_CASE)"; \
		curl -sf -X POST "$(API_URL)/prediction/$$J5_ID" -H "Authorization: Bearer $$API_KEY" -H "Content-Type: application/json" -d "{\"question\":\"$(J5_QUESTION_CASE)\"}" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('text','').strip())"; \
		printf '\n'; \
	}

smoke-j5: ping mcp-health test-j5-scope test-j5-aggregate test-j5-case

reset-smoke-j5:
	COMPOSE_PROFILE=mcp ./reset.sh -f
	$(MAKE) smoke-j5

from-scratch-j5: reset-smoke-j5

test-j6: wait-init
	@API_KEY=$$(docker compose logs init --tail 120 2>/dev/null | awk '/API key:/ {print $$NF}' | tail -1); \
	[ -z "$$API_KEY" ] && API_KEY=$$(docker compose exec -T postgres psql -U flowise -d flowise -At -c 'select "apiKey" from apikey order by "updatedDate" desc limit 1;' 2>/dev/null); \
	J6_ID=$$(docker compose exec -T postgres psql -U flowise -d flowise -At -c "select id from chat_flow where name = 'J6 - Multi-Agent Supervised' and type = 'AGENTFLOW' order by \"updatedDate\" desc limit 1;" 2>/dev/null); \
	[ -z "$$J6_ID" ] && echo "J6 not found" || { \
		RESP_FILE=$$(mktemp); \
		printf '\n[J6-MULTI-AGENT] %s\n' "$(J6_QUESTION)"; \
		HTTP_CODE=$$(curl --max-time 15 -sS -o "$$RESP_FILE" -w "%{http_code}" -X POST "$(API_URL)/prediction/$$J6_ID" -H "Authorization: Bearer $$API_KEY" -H "Content-Type: application/json" -d "{\"question\":\"$(J6_QUESTION)\"}" || true); \
		if [ "$$HTTP_CODE" = "200" ] && [ -s "$$RESP_FILE" ]; then \
			python3 -c "import json,sys; d=json.load(sys.stdin); text=d.get('text','').strip(); print(text if text else d)" < "$$RESP_FILE"; \
		elif [ "$$HTTP_CODE" = "000" ] && [ ! -s "$$RESP_FILE" ]; then \
			echo "J6 reached the interactive AgentFlow stage and is awaiting human validation; no immediate non-streaming response is expected in headless curl mode."; \
		else \
			echo "Unexpected J6 HTTP status: $$HTTP_CODE"; \
			[ -s "$$RESP_FILE" ] && cat "$$RESP_FILE"; \
			rm -f "$$RESP_FILE"; \
			exit 1; \
		fi; \
		rm -f "$$RESP_FILE"; \
		printf '\n'; \
	}

smoke-j6: ping mcp-health test-j6

reset-smoke-j6:
	COMPOSE_PROFILE=mcp ./reset.sh -f
	$(MAKE) smoke-j6

from-scratch-j6: reset-smoke-j6

docs:
	@ls docs/*.md | sed 's/^/  - /'

# ── AWS fleet deployment ──────────────────────────────────────────────────────

DEPLOY_DIR := deploy/aws

deploy-test:
	cd $(DEPLOY_DIR) && ./test.sh

deploy-bake:
	cd $(DEPLOY_DIR) && ./bake.sh

deploy-launch:
	cd $(DEPLOY_DIR) && ./launch.sh

deploy-access:
	cd $(DEPLOY_DIR) && ./access.sh

deploy-teardown:
	cd $(DEPLOY_DIR) && ./teardown.sh
