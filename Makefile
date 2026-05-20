STACK := deloitte-no-code-flowise
PORT := $(shell grep FLOWISE_PORT .env 2>/dev/null | cut -d= -f2 || echo 3000)
API_URL := http://localhost:$(PORT)/api/v1
J1_QUESTION := Bonjour, qui es-tu ?
J2_QUESTION := Quels sont les seuils decart pour les controles URSSAF ?
J2_NIR_QUESTION := Que faire avec un NIR fictif dans un audit ?

.PHONY: up down reset force-reset status logs-flowise logs-init api-key ping psql wait-init test-j1 test-j2 test-j2-nir smoke-j2 reset-smoke-j2 from-scratch-j2 docs help

help:
	@echo "Usage: make <target>"
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
	@echo "  wait-init  Wait for init bootstrap and flow import"
	@echo "  psql      Open PostgreSQL shell"
	@echo "  test-j1   Test J1 - Simple Chat prediction"
	@echo "  test-j2   Test J2 - RAG Chat prediction"
	@echo "  test-j2-nir  Test J2 on the NIR fictif question"
	@echo "  smoke-j2  Run the main J2 smoke tests"
	@echo "  reset-smoke-j2  Force reset the stack, then run J2 smoke tests"
	@echo "  from-scratch-j2  Alias simple de reset-smoke-j2"
	@echo ""
	@echo "Docs:"
	@echo "  docs      List available training docs"

up:
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

psql:
	docker exec -it $(STACK)-postgres-1 psql -U flowise -d flowise

wait-init:
	@sh -c ' \
		for i in $$(seq 1 60); do \
			API_KEY=$$(docker compose logs init --tail 120 2>/dev/null | awk "/API key:/ {print \$$NF}" | tail -1); \
			if [ -n "$$API_KEY" ]; then \
				FLOW_COUNT=$$(curl -sf -H "Authorization: Bearer $$API_KEY" $(API_URL)/chatflows 2>/dev/null | jq -r "if type==\"array\" then length else 0 end" 2>/dev/null || echo 0); \
				if [ "$$FLOW_COUNT" -ge 2 ]; then \
					echo "Init ready: API key found, $$FLOW_COUNT flows imported."; \
					exit 0; \
				fi; \
			fi; \
			sleep 2; \
		done; \
		echo "Init not ready in time."; \
		exit 1'

test-j1: wait-init
	@API_KEY=$$(docker compose logs init --tail 120 2>/dev/null | awk '/API key:/ {print $$NF}' | tail -1); \
	J1_ID=$$(curl -sf -H "Authorization: Bearer $$API_KEY" $(API_URL)/chatflows | jq -r '.[] | select(.name | contains("Simple")) | .id' | head -n1); \
	[ -z "$$J1_ID" ] && echo "J1 not found" || { \
		printf '\n[J1] %s\n' "$(J1_QUESTION)"; \
		curl -sf -X POST "$(API_URL)/prediction/$$J1_ID" -H "Authorization: Bearer $$API_KEY" -H "Content-Type: application/json" -d '{"question":"$(J1_QUESTION)"}' | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('text','').strip())"; \
		printf '\n'; \
	}

test-j2: wait-init
	@API_KEY=$$(docker compose logs init --tail 120 2>/dev/null | awk '/API key:/ {print $$NF}' | tail -1); \
	J2_ID=$$(curl -sf -H "Authorization: Bearer $$API_KEY" $(API_URL)/chatflows | jq -r '.[] | select(.name | contains("RAG")) | .id' | head -n1); \
	[ -z "$$J2_ID" ] && echo "J2 not found" || { \
		printf '\n[J2-URSSAF] %s\n' "$(J2_QUESTION)"; \
		curl -sf -X POST "$(API_URL)/prediction/$$J2_ID" -H "Authorization: Bearer $$API_KEY" -H "Content-Type: application/json" -d '{"question":"$(J2_QUESTION)"}' | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('text','').strip())"; \
		printf '\n'; \
	}

test-j2-nir: wait-init
	@API_KEY=$$(docker compose logs init --tail 120 2>/dev/null | awk '/API key:/ {print $$NF}' | tail -1); \
	J2_ID=$$(curl -sf -H "Authorization: Bearer $$API_KEY" $(API_URL)/chatflows | jq -r '.[] | select(.name | contains("RAG")) | .id' | head -n1); \
	[ -z "$$J2_ID" ] && echo "J2 not found" || { \
		printf '\n[J2-NIR] %s\n' "$(J2_NIR_QUESTION)"; \
		curl -sf -X POST "$(API_URL)/prediction/$$J2_ID" -H "Authorization: Bearer $$API_KEY" -H "Content-Type: application/json" -d '{"question":"$(J2_NIR_QUESTION)"}' | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('text','').strip())"; \
		printf '\n'; \
	}

smoke-j2: ping test-j2 test-j2-nir

reset-smoke-j2:
	./reset.sh -f
	$(MAKE) smoke-j2

from-scratch-j2: reset-smoke-j2

docs:
	@ls docs/*.md | sed 's/^/  - /'
