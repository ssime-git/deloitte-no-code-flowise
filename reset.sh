#!/bin/bash
set -euo pipefail

COMPOSE_PROFILE="${COMPOSE_PROFILE:-}"
IMPORT_FLOWS="${IMPORT_FLOWS:-true}"

if [ -f .env ]; then
  set -a
  source .env
  set +a
fi

case "${1:-}" in
  --help)
    cat <<EOF
Usage: ./reset.sh [OPTIONS]

Reset the Flowise training stack to a clean state.

Options:
  -f          Force reset without confirmation
  --help      Show this help message

Environment variables:
  COMPOSE_PROFILE  Docker Compose profile(s) (default: "")
  IMPORT_FLOWS     Run import-flows.sh after reset (default: true)
EOF
    exit 0
    ;;
  -f)
    FORCE=true
    ;;
  "")
    FORCE=false
    ;;
  *)
    echo "Unknown option: $1"
    exit 1
    ;;
esac

if [ "$FORCE" = false ]; then
  echo "WARNING: This will destroy all Docker volumes (PostgreSQL data, Flowise config)"
  echo "         and clean the project/ directory (student output files)."
  read -p "Are you sure? [y/N] " -r
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Reset cancelled."
    exit 0
  fi
fi

echo "Stopping stack and removing volumes..."
docker compose down -v

echo "Cleaning student project files..."
shopt -s dotglob nullglob
rm -rf project/*
shopt -u dotglob nullglob

echo "Starting stack..."
if [ -n "$COMPOSE_PROFILE" ]; then
  docker compose --profile "$COMPOSE_PROFILE" up -d
else
  docker compose up -d postgres flowise
fi

echo "Waiting for Flowise to be ready..."
FLOWISE_PORT="${FLOWISE_PORT:-3000}"
for i in $(seq 1 60); do
  if curl -sf "http://localhost:$FLOWISE_PORT/api/v1/ping" > /dev/null 2>&1; then
    break
  fi
  sleep 2
done

if [ "$IMPORT_FLOWS" = true ] && [ -f import-flows.sh ]; then
  echo "Importing flows..."
  bash import-flows.sh
fi

echo "Reset complete. Flowise is available at http://localhost:$FLOWISE_PORT"
