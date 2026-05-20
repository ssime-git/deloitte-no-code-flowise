#!/bin/bash

FLOWISE_URL="${FLOWISE_URL:-http://localhost:3000}"
FLOWS_DIR="/init/flows"

log() {
  echo "[import-flows] $*"
}

error() {
  echo "[import-flows] ERROR: $*" >&2
}

log "Waiting for Flowise at $FLOWISE_URL..."

for i in $(seq 1 60); do
  if curl -sf "${FLOWISE_URL}/api/v1/chatflows" > /dev/null 2>&1; then
    log "Flowise is ready."
    break
  fi
  if [ "$i" -eq 60 ]; then
    error "Flowise did not become ready within 120 seconds."
    exit 1
  fi
  sleep 2
done

if [ ! -d "$FLOWS_DIR" ]; then
  log "Flows directory $FLOWS_DIR does not exist. Nothing to import."
  exit 0
fi

shopt -s nullglob
FLOW_FILES=("$FLOWS_DIR"/*.json)
shopt -u nullglob

if [ ${#FLOW_FILES[@]} -eq 0 ]; then
  log "No .json files found in $FLOWS_DIR. Nothing to import."
  exit 0
fi

log "Fetching existing flows from Flowise..."
EXISTING_RESPONSE=$(curl -sf "${FLOWISE_URL}/api/v1/chatflows" 2>/dev/null) || {
  error "Failed to fetch existing flows."
  exit 1
}

EXISTING_NAMES=""
if command -v jq &> /dev/null; then
  EXISTING_NAMES=$(echo "$EXISTING_RESPONSE" | jq -r '.[].name' 2>/dev/null || true)
else
  EXISTING_NAMES=$(echo "$EXISTING_RESPONSE" | grep -o '"name":"[^"]*"' | sed 's/"name":"//;s/"//' || true)
fi

HAS_ERROR=0

for FLOW_FILE in "${FLOW_FILES[@]}"; do
  FLOW_NAME=""
  if command -v jq &> /dev/null; then
    FLOW_NAME=$(jq -r '.name' "$FLOW_FILE" 2>/dev/null || echo "")
  else
    FLOW_NAME=$(grep -o '"name":"[^"]*"' "$FLOW_FILE" | head -1 | sed 's/"name":"//;s/"//' || echo "")
  fi

  FLOW_BASENAME=$(basename "$FLOW_FILE")

  if [ -z "$FLOW_NAME" ]; then
    error "Could not extract name from $FLOW_BASENAME. Skipping."
    HAS_ERROR=1
    continue
  fi

  if echo "$EXISTING_NAMES" | grep -Fxq "$FLOW_NAME"; then
    log "SKIP: flow '$FLOW_NAME' already exists ($FLOW_BASENAME)"
    continue
  fi

  log "Importing flow '$FLOW_NAME' from $FLOW_BASENAME..."
  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    -X POST "${FLOWISE_URL}/api/v1/chatflows" \
    -H "Content-Type: application/json" \
    -d @"$FLOW_FILE" 2>/dev/null)

  if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "201" ]; then
    log "OK: flow '$FLOW_NAME' imported (HTTP $HTTP_CODE)"
  else
    error "FAIL: flow '$FLOW_NAME' returned HTTP $HTTP_CODE"
    HAS_ERROR=1
  fi
done

if [ "$HAS_ERROR" -eq 1 ]; then
  error "One or more flows failed to import."
  exit 1
fi

log "All flows imported successfully."
exit 0
