STACK := deloitte-no-code-flowise
PORT := $(shell grep FLOWISE_PORT .env 2>/dev/null | cut -d= -f2 || echo 3000)

.PHONY: up down reset force-reset status logs-flowise logs-init api-key ping psql test-j1 test-j2 docs help

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
	@echo "  psql      Open PostgreSQL shell"
	@echo "  test-j1   Test J1 - Simple Chat prediction"
	@echo "  test-j2   Test J2 - RAG Chat prediction"
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
	@curl -sf http://localhost:$(PORT)/api/v1/ping && echo " - pong" || echo "FAILED"

psql:
	docker exec -it $(STACK)-postgres-1 psql -U flowise -d flowise

test-j1:
	@API_KEY=$$(docker logs $(STACK)-init-1 2>/dev/null | grep "API key:" | tail -1 | awk '{print $$NF}'); \
	J1_ID=$$(curl -s -H "Authorization: Bearer $$API_KEY" http://localhost:$(PORT)/api/v1/chatflows | python3 -c "import json,sys; flows=json.load(sys.stdin); print(next((f['id'] for f in flows if 'Simple' in f['name']),''))"); \
	[ -z "$$J1_ID" ] && echo "J1 not found" || curl -s -X POST "http://localhost:$(PORT)/api/v1/prediction/$$J1_ID" -H "Authorization: Bearer $$API_KEY" -H "Content-Type: application/json" -d '{"question":"Bonjour, qui es-tu ?"}' | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('text','')[:300])"

test-j2:
	@API_KEY=$$(docker logs $(STACK)-init-1 2>/dev/null | grep "API key:" | tail -1 | awk '{print $$NF}'); \
	J2_ID=$$(curl -s -H "Authorization: Bearer $$API_KEY" http://localhost:$(PORT)/api/v1/chatflows | python3 -c "import json,sys; flows=json.load(sys.stdin); print(next((f['id'] for f in flows if 'RAG' in f['name']),''))"); \
	[ -z "$$J2_ID" ] && echo "J2 not found" || curl -s -X POST "http://localhost:$(PORT)/api/v1/prediction/$$J2_ID" -H "Authorization: Bearer $$API_KEY" -H "Content-Type: application/json" -d '{"question":"Quels sont les seuils decart pour les controles URSSAF ?"}' | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('text','')[:300])"

docs:
	@ls docs/*.md | sed 's/^/  - /'
