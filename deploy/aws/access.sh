#!/usr/bin/env bash
# Print the learner access table (and write access.csv) for the running fleet.
#
# Usage: ./access.sh
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
load_config
require_aws

USER_LOGIN="admin@local.dev"
PASS="${FLOWISE_PASSWORD:-changeme_admin_password}"
CSV="${SCRIPT_DIR}/access.csv"

mapfile -t ROWS < <(awscli ec2 describe-instances \
  --filters "Name=tag:${TAG_KEY},Values=${TAG_VALUE}" \
            "Name=instance-state-name,Values=running" \
  --query 'Reservations[*].Instances[*].[InstanceId,PublicIpAddress]' \
  --output text | sort)

[ "${#ROWS[@]}" -gt 0 ] || die "No running instances tagged ${TAG_KEY}=${TAG_VALUE}."

echo "learner,instance_id,url,user,password" > "$CSV"
printf '\n%-10s  %-19s  %-28s  %-18s  %s\n' "LEARNER" "INSTANCE" "URL" "USER" "PASSWORD"
printf '%s\n' "-------------------------------------------------------------------------------------------------------"
i=0
for row in "${ROWS[@]}"; do
  id="$(echo "$row" | awk '{print $1}')"
  ip="$(echo "$row" | awk '{print $2}')"
  i=$((i+1))
  label="$(printf 'apprenant-%02d' "$i")"
  url="http://${ip}:3000"
  printf '%-10s  %-19s  %-28s  %-18s  %s\n' "$label" "$id" "$url" "$USER_LOGIN" "$PASS"
  echo "${label},${id},${url},${USER_LOGIN},${PASS}" >> "$CSV"
done
echo
info "Wrote $CSV (${i} learners)"
