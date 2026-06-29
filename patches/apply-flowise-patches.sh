#!/bin/bash
# Apply Flowise 3.1.2 patches to the running container.
# Safe to run multiple times (idempotent via grep check).
set -euo pipefail

DOCKER=$(command -v docker); [ "$(id -u)" != "0" ] && DOCKER="sudo docker"
CONTAINER=$($DOCKER ps --filter name=flowise-flowise -q | head -1)
if [ -z "$CONTAINER" ]; then
  echo "[patch] Flowise container not found, skipping"
  exit 0
fi

TARGET="/usr/local/lib/node_modules/flowise/dist/utils/buildAgentflow.js"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATCHED="${SCRIPT_DIR}/buildAgentflow.js"

# Check if already patched
if $DOCKER exec "$CONTAINER" grep -q 'ponytail: humanInputAgentflow' "$TARGET" 2>/dev/null; then
  echo "[patch] buildAgentflow.js already patched, skipping"
  exit 0
fi

echo "[patch] Applying Flowise patches..."
$DOCKER exec "$CONTAINER" cp "$TARGET" "${TARGET}.bak"
$DOCKER cp "$PATCHED" "$CONTAINER:$TARGET"
$DOCKER restart "$CONTAINER"

echo "[patch] Waiting for Flowise to restart..."
for i in $(seq 1 30); do
  if $DOCKER logs "$CONTAINER" 2>&1 | grep -q "Flowise Server is listening"; then
    echo "[patch] Flowise is up"
    break
  fi
  sleep 2
done
echo "[patch] Done"
