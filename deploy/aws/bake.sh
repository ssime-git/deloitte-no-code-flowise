#!/usr/bin/env bash
# Bake the training AMI: launch a temp instance that installs deps, clones the
# repo, writes .env, pre-pulls images and BUILDS mcp-server, then powers off.
# We then create an image from the stopped instance and terminate it.
#
# Usage: ./bake.sh
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
load_config
require_aws

AMI_NAME="${AMI_NAME_PREFIX}-$(date +%Y%m%d-%H%M%S)"
UBUNTU_AMI="$(resolve_ubuntu_ami)"
[ -n "$UBUNTU_AMI" ] && [ "$UBUNTU_AMI" != "None" ] || die "Could not resolve Ubuntu ${UBUNTU_VERSION} AMI via SSM."
info "Base Ubuntu ${UBUNTU_VERSION} AMI: $UBUNTU_AMI"

SG="$(ensure_sg)"
info "Security group: $SG"

# --- Build the bake user-data (cloud-init, runs as root on first boot) -------
USERDATA="$(mktemp)"
trap 'rm -f "$USERDATA"' EXIT
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
COMPOSE_PROFILES=mcp
ENVEOF
chown -R ubuntu:ubuntu /home/ubuntu/deloitte-no-code-flowise
# Pre-pull pullable images and BUILD mcp-server (build: ./mcp-server)
docker compose pull postgres flowise init || true
docker compose --profile mcp build
# IMPORTANT: never 'up' here, or the volumes get baked into the AMI.
touch /home/ubuntu/BAKE_DONE
sync
sleep 5
poweroff
EOF

# --- Launch the bake instance ------------------------------------------------
info "Launching bake instance ($INSTANCE_TYPE)..."
BAKE_ID="$(awscli ec2 run-instances \
  --image-id "$UBUNTU_AMI" \
  --instance-type "$INSTANCE_TYPE" \
  ${KEY_NAME:+--key-name "$KEY_NAME"} \
  --security-group-ids "$SG" \
  ${SUBNET_ID:+--subnet-id "$SUBNET_ID"} \
  --block-device-mappings "DeviceName=/dev/sda1,Ebs={VolumeSize=${ROOT_VOLUME_GB},VolumeType=gp3}" \
  --user-data "file://$USERDATA" \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${AMI_NAME_PREFIX}-bake}]" \
  --query 'Instances[0].InstanceId' --output text)"
info "Bake instance: $BAKE_ID"

info "Waiting for bake to finish (install + pull + build, then auto power-off)..."
DEADLINE=$(( $(date +%s) + 1500 ))   # 25 min budget
while :; do
  ST="$(awscli ec2 describe-instances --instance-ids "$BAKE_ID" \
        --query 'Reservations[0].Instances[0].State.Name' --output text 2>/dev/null || echo unknown)"
  case "$ST" in
    stopped) info "Bake instance stopped — bake complete."; break ;;
    terminated|shutting-down) die "Bake instance terminated unexpectedly." ;;
  esac
  [ "$(date +%s)" -lt "$DEADLINE" ] || die "Timed out waiting for bake. Check console logs of $BAKE_ID."
  sleep 15
done

info "Creating image $AMI_NAME ..."
AMI_ID="$(awscli ec2 create-image --instance-id "$BAKE_ID" --name "$AMI_NAME" \
  --description "Flowise training stack (flows pre-imported on first boot)" \
  --query 'ImageId' --output text)"
info "Waiting for AMI $AMI_ID to be available..."
awscli ec2 wait image-available --image-ids "$AMI_ID"
state_set AMI_ID "$AMI_ID"
state_set AMI_NAME "$AMI_NAME"
state_set SG_ID "$SG"

info "Terminating bake instance $BAKE_ID ..."
awscli ec2 terminate-instances --instance-ids "$BAKE_ID" >/dev/null

c_grn "=== AMI ready: $AMI_ID ($AMI_NAME) ==="
echo "Next: ./launch.sh"
