#!/usr/bin/env bash
# Launch COUNT instances from the baked AMI. Each boots the full stack
# (mcp profile) and imports the flows on first boot.
#
# Usage: ./launch.sh [COUNT]           override count (default: COUNT from config.env)
#        make deploy-launch COUNT=1    same via make
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
load_config
require_aws

# CLI arg overrides config.env COUNT (use case: make deploy-launch COUNT=1)
[ -n "${1:-}" ] && COUNT="$1"
AMI_ID="$(state_get AMI_ID)"
[ -n "$AMI_ID" ] || die "No AMI_ID. Run ./bake.sh first."
SG="$(state_get SG_ID)"; [ -n "$SG" ] || SG="$(ensure_sg)"
info "Using AMI $AMI_ID, security group $SG, count $COUNT"

# First-boot user-data: bring up the full stack (mcp profile included).
USERDATA="$(mktemp)"; trap 'rm -f "$USERDATA"' EXIT
cat > "$USERDATA" <<'EOF'
#!/bin/bash
set -uxo pipefail
cd /home/ubuntu/deloitte-no-code-flowise
docker compose --profile mcp up -d
EOF

info "Launching $COUNT instances ($INSTANCE_TYPE)..."
mapfile -t IDS < <(awscli ec2 run-instances \
  --image-id "$AMI_ID" \
  --instance-type "$INSTANCE_TYPE" \
  --count "$COUNT" \
  ${KEY_NAME:+--key-name "$KEY_NAME"} \
  --security-group-ids "$SG" \
  ${SUBNET_ID:+--subnet-id "$SUBNET_ID"} \
  --user-data "file://$USERDATA" \
  --tag-specifications "ResourceType=instance,Tags=[{Key=${TAG_KEY},Value=${TAG_VALUE}},{Key=Name,Value=${AMI_NAME_PREFIX}}]" \
  --query 'Instances[*].InstanceId' --output text | tr '\t' '\n')

info "Launched ${#IDS[@]} instances:"
printf '  %s\n' "${IDS[@]}"
info "Waiting for them to reach 'running'..."
awscli ec2 wait instance-running --instance-ids "${IDS[@]}"

c_grn "=== ${#IDS[@]} instances running ==="
echo "Flowise needs ~60-90s more to migrate the DB and import flows."
echo "Then run: ./access.sh"
