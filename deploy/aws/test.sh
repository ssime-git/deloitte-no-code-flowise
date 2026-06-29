#!/usr/bin/env bash
# Smoke-test the stack on a fresh Ubuntu VM before baking the AMI.
# Launches 1 instance, runs the full boot + flow import, then executes
# make test-j2/j3/j4/j4-rag/j5-scope on the VM via EC2 console output.
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

# --- user-data: full bootstrap + start + async smoke tests -------------------
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

# Write async smoke runner (single-quoted inner heredoc — no expansion on VM)
cat > /tmp/run-smoke.sh <<'SMOKEEOF'
#!/bin/bash
set -e
cd /home/ubuntu/deloitte-no-code-flowise
STACK=deloitte-no-code-flowise
echo "[smoke] Waiting for flows to be imported..."
for i in \$(seq 1 90); do
  AK=\$(docker logs \${STACK}-init-1 2>/dev/null | awk '/API key:/ {print \$NF}' | tail -1 || echo "")
  if [ -n "\$AK" ]; then
    FC=\$(curl -sf -H "Authorization: Bearer \$AK" http://localhost:3000/api/v1/chatflows 2>/dev/null \
      | python3 -c "import json,sys; d=json.load(sys.stdin); print(len(d) if isinstance(d,list) else 0)" 2>/dev/null || echo 0)
    if [ "\$FC" -ge 5 ]; then
      echo "[smoke] \$FC flows ready."
      break
    fi
  fi
  sleep 10
done
echo "[smoke] Applying Flowise engine patches..."
make patch-flowise
echo "[smoke] Running make smoke tests..."
for T in test-j2 test-j3 test-j4 test-j4-rag test-j5-scope test-j6; do
  if make "\$T" >/tmp/smoke-\${T}.out 2>&1; then
    echo "SMOKE_PASS \$T"
  else
    echo "SMOKE_FAIL \$T"
    tail -5 /tmp/smoke-\${T}.out
  fi
done
echo "SMOKE_COMPLETE"
SMOKEEOF
chmod +x /tmp/run-smoke.sh
nohup /tmp/run-smoke.sh >>/dev/console 2>&1 &
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

# --- Phase 1: wait for Flowise to respond ------------------------------------
FLOWISE_URL="http://${PUBLIC_IP}:3000"
DEADLINE=$(( $(date +%s) + 900 ))  # 15 min
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

# --- Phase 2: wait for smoke tests to complete (console output) --------------
info "Waiting for smoke tests to complete on the VM (up to 20 min)..."
info "  [smoke runner started in background on VM — reads docker logs + runs make test-j*]"
SMOKE_DONE=0
DEADLINE2=$(( $(date +%s) + 1200 ))
while [ "$(date +%s)" -lt "$DEADLINE2" ]; do
  CON=$(awscli ec2 get-console-output --instance-id "$TEST_ID" \
    --output json 2>/dev/null | python3 -c "
import json,sys,base64
d=json.load(sys.stdin)
out=d.get('Output','')
try: print(base64.b64decode(out).decode('utf-8','replace'))
except: print(out)
" 2>/dev/null || echo "")
  if echo "$CON" | grep -q "SMOKE_COMPLETE"; then
    SMOKE_DONE=1
    break
  fi
  printf '.'
  sleep 30
done
echo ""

# --- Results -----------------------------------------------------------------
c_grn ""
c_grn "=== Flowise smoke test ==="
c_grn "  URL      : ${FLOWISE_URL}"
c_grn "  Login    : ${FLOWISE_USERNAME:-admin} / ${FLOWISE_PASSWORD:-changeme_admin_password}"
c_grn "  Instance : $TEST_ID"
echo ""

if [ "$SMOKE_DONE" = "1" ]; then
  c_grn "=== Automated smoke results ==="
  CON=$(awscli ec2 get-console-output --instance-id "$TEST_ID" \
    --output json 2>/dev/null | python3 -c "
import json,sys,base64
d=json.load(sys.stdin)
out=d.get('Output','')
try: print(base64.b64decode(out).decode('utf-8','replace'))
except: print(out)
" 2>/dev/null || echo "")
  PASS_COUNT=0; FAIL_COUNT=0
  while IFS= read -r line; do
    if echo "$line" | grep -q "^SMOKE_PASS"; then
      c_grn "  PASS: $(echo "$line" | sed 's/SMOKE_PASS //')"
      PASS_COUNT=$(( PASS_COUNT + 1 ))
    elif echo "$line" | grep -q "^SMOKE_FAIL"; then
      c_red "  FAIL: $(echo "$line" | sed 's/SMOKE_FAIL //')"
      FAIL_COUNT=$(( FAIL_COUNT + 1 ))
    fi
  done < <(echo "$CON" | grep -E "^SMOKE_(PASS|FAIL)")
  echo ""
  if [ "$FAIL_COUNT" -eq 0 ]; then
    c_grn "All ${PASS_COUNT} tests passed."
  else
    c_ylw "${PASS_COUNT} passed, ${FAIL_COUNT} failed."
    c_ylw "Fetch full output: aws ec2 get-console-output --instance-id $TEST_ID --region $AWS_REGION"
  fi
else
  warn "Smoke tests did not complete within 20 min."
  warn "Console output: aws ec2 get-console-output --instance-id $TEST_ID --region $AWS_REGION --output text"
  echo ""
  c_ylw "Verify manually in the browser:"
  c_ylw "  1. Open ${FLOWISE_URL} and log in"
  c_ylw "  2. Check 6 flows exist (J2, J3, J4-Simple, J4-RAG, J5-MCP, J6)"
  c_ylw "  3. Open J2 and send: 'Bonjour, qui es-tu ?'"
fi

# --- Cleanup prompt ----------------------------------------------------------
echo ""
read -rp "Terminate this test instance? [y/N] " CONFIRM
if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
  awscli ec2 terminate-instances --instance-ids "$TEST_ID" >/dev/null
  c_grn "Instance $TEST_ID terminated."
  info "If all looks good, run: ./bake.sh"
else
  warn "Instance left running — don't forget to terminate it: aws ec2 terminate-instances --instance-ids $TEST_ID --region $AWS_REGION"
fi
