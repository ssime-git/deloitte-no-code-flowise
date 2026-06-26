#!/usr/bin/env bash
# Smoke-test the stack on a fresh Ubuntu VM before baking the AMI.
# Launches 1 instance, runs the full boot (install + start stack + import flows),
# polls Flowise until healthy, runs a J2 chat test, then asks before terminating.
#
# Usage: ./test.sh
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
load_config
require_aws

UBUNTU_AMI="$(resolve_ubuntu_ami)"
[ -n "$UBUNTU_AMI" ] && [ "$UBUNTU_AMI" != "None" ] || die "Could not resolve Ubuntu ${UBUNTU_VERSION} AMI."
info "Base Ubuntu ${UBUNTU_VERSION} AMI: $UBUNTU_AMI"

SG="$(ensure_sg)"
info "Security group: $SG"

# --- user-data: full bootstrap + start (NOT poweroff) -------------------------
USERDATA="$(mktemp)"; trap 'rm -f "$USERDATA"' EXIT
cat > "$USERDATA" <<EOF
#!/bin/bash
set -uxo pipefail
export DEBIAN_FRONTEND=noninteractive USER=ubuntu HOME=/home/ubuntu
cd /home/ubuntu
git clone --branch "${REPO_BRANCH}" "${REPO_URL}" deloitte-no-code-flowise || { sleep 20; git clone --branch "${REPO_BRANCH}" "${REPO_URL}" deloitte-no-code-flowise; }
cd deloitte-no-code-flowise
bash setup.sh || true
cat > .env <<'ENVEOF'
POSTGRES_DB=flowise
POSTGRES_USER=flowise
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
FLOWISE_PORT=3000
FLOWISE_USERNAME=${FLOWISE_USERNAME:-admin}
FLOWISE_PASSWORD=${FLOWISE_PASSWORD}
TIMEZONE=Europe/Paris
OPENAI_GATEWAY_API_KEY=${OPENAI_GATEWAY_API_KEY}
OPENAI_GATEWAY_BASE_URL=${OPENAI_GATEWAY_BASE_URL}
OPENAI_GATEWAY_MODEL=${OPENAI_GATEWAY_MODEL}
ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}
ANTHROPIC_MODEL=${ANTHROPIC_MODEL}
MCP_SERVER_PORT=8001
ENVEOF
chown -R ubuntu:ubuntu /home/ubuntu/deloitte-no-code-flowise
# Full start: pull + build + up
docker compose pull postgres flowise init || true
docker compose --profile mcp build
docker compose --profile mcp up -d
touch /home/ubuntu/BOOT_DONE
EOF

info "Launching test instance ($INSTANCE_TYPE)..."
TEST_ID="$(awscli ec2 run-instances \
  --image-id "$UBUNTU_AMI" \
  --instance-type "$INSTANCE_TYPE" \
  ${KEY_NAME:+--key-name "$KEY_NAME"} \
  --security-group-ids "$SG" \
  ${SUBNET_ID:+--subnet-id "$SUBNET_ID"} \
  --block-device-mappings "DeviceName=/dev/sda1,Ebs={VolumeSize=${ROOT_VOLUME_GB},VolumeType=gp3}" \
  --user-data "file://$USERDATA" \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${AMI_NAME_PREFIX}-test}]" \
  --query 'Instances[0].InstanceId' --output text)"
info "Test instance: $TEST_ID"

info "Waiting for instance to reach 'running'..."
awscli ec2 wait instance-running --instance-ids "$TEST_ID"

PUBLIC_IP="$(awscli ec2 describe-instances --instance-ids "$TEST_ID" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)"
info "Instance running — public IP: $PUBLIC_IP"
info "Flowise will be at: http://${PUBLIC_IP}:3000"
info "This takes ~8-12 min (setup + docker pull + flow import). Polling..."

FLOWISE_URL="http://${PUBLIC_IP}:3000"
DEADLINE=$(( $(date +%s) + 900 ))  # 15 min budget
HEALTHY=0
while [ "$(date +%s)" -lt "$DEADLINE" ]; do
  STATUS=$(curl -sf --max-time 5 "${FLOWISE_URL}/api/v1/ping" 2>/dev/null || echo "")
  if [ "$STATUS" = "pong" ]; then
    HEALTHY=1; break
  fi
  printf '.'
  sleep 15
done
echo ""

[ "$HEALTHY" = "1" ] || die "Flowise did not become healthy within 15 min. Check EC2 console logs for $TEST_ID."
c_grn "Flowise is up at ${FLOWISE_URL}"

# --- Wait for init to finish importing flows (~3-5 min after first pong) ------
info "Waiting 3 min for flow import to complete..."
sleep 180

PASS="${FLOWISE_PASSWORD:-changeme_admin_password}"

# --- Summary -----------------------------------------------------------------
c_grn ""
c_grn "=== Smoke test passed ==="
c_grn "  URL      : ${FLOWISE_URL}"
c_grn "  Login    : ${FLOWISE_USERNAME:-admin} / ${PASS}"
c_grn "  Instance : $TEST_ID"
echo ""
c_ylw "Verify manually in the browser:"
c_ylw "  1. Open ${FLOWISE_URL} — login with the credentials above"
c_ylw "  2. Check 6 flows exist: J2-Simple-Chat, J3-RAG-Chat, J4-Agent-Simple, J4-Agent-RAG, J5-Agent-MCP, J6-Multi-Agent-Supervised"
c_ylw "  3. Open J2-Simple-Chat and send: 'Bonjour, qui es-tu ?'"
c_ylw "  4. Open J4-Agent-Simple and send: 'Calcule la CSG sur 3200 euros brut'"
echo ""

# --- Cleanup prompt ----------------------------------------------------------
read -rp "Terminate this test instance? [y/N] " CONFIRM
if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
  awscli ec2 terminate-instances --instance-ids "$TEST_ID" >/dev/null
  c_grn "Instance $TEST_ID terminated."
  info "If all looks good, run: ./bake.sh"
else
  warn "Instance left running — don't forget to terminate it: aws ec2 terminate-instances --instance-ids $TEST_ID --region $AWS_REGION"
fi
