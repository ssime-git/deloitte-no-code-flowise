#!/usr/bin/env bash
# Regenerate the gateway Caddyfile (one reverse_proxy block per running training
# VM, all hostnamed under the instructor VM's sslip.io domain) and push it to
# the instructor VM. Run this after every fleet reset/relaunch (IPs change).
#
# Usage: ./gateway.sh
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
load_config
require_aws

INSTRUCTOR_IP="35.181.26.207"
INSTRUCTOR_DOMAIN="35-181-26-207.sslip.io"
SSH_KEY="${SCRIPT_DIR}/flowise-training-key.pem"
REMOTE_DIR="deloitte-no-code-flowise"

mapfile -t ROWS < <(awscli ec2 describe-instances \
  --filters "Name=tag:${TAG_KEY},Values=${TAG_VALUE}" \
            "Name=instance-state-name,Values=running" \
  --query 'Reservations[*].Instances[*].[InstanceId,PublicIpAddress]' \
  --output text | sort)

[ "${#ROWS[@]}" -gt 0 ] || die "No running training instances tagged ${TAG_KEY}=${TAG_VALUE}."

TMP_CADDYFILE="$(mktemp)"
trap 'rm -f "$TMP_CADDYFILE"' EXIT

{
  printf '{$DOMAIN} {\n\treverse_proxy flowise:3000\n}\n\n'
  i=0
  for row in "${ROWS[@]}"; do
    ip="$(echo "$row" | awk '{print $2}')"
    i=$((i+1))
    label="$(printf 'learner%02d' "$i")"
    printf '%s.%s {\n\treverse_proxy %s:3000\n}\n\n' "$label" "$INSTRUCTOR_DOMAIN" "$ip"
  done
} > "$TMP_CADDYFILE"

info "Generated gateway Caddyfile for ${#ROWS[@]} learner VMs."

scp -i "$SSH_KEY" -o StrictHostKeyChecking=accept-new "$TMP_CADDYFILE" \
  "ubuntu@${INSTRUCTOR_IP}:${REMOTE_DIR}/Caddyfile"

ssh -i "$SSH_KEY" -o StrictHostKeyChecking=accept-new "ubuntu@${INSTRUCTOR_IP}" \
  "cd ${REMOTE_DIR} && sudo docker compose --profile mcp --profile https up -d caddy && sudo docker exec \$(sudo docker compose ps -q caddy) caddy reload --config /etc/caddy/Caddyfile"

info "Gateway updated. Learner URLs:"
i=0
for row in "${ROWS[@]}"; do
  i=$((i+1))
  label="$(printf 'learner%02d' "$i")"
  printf '  %-12s https://%s.%s\n' "$label" "$label" "$INSTRUCTOR_DOMAIN"
done
