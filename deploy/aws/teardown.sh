#!/usr/bin/env bash
# Terminate the training fleet. Optionally deregister the baked AMI + snapshots.
#
# Usage:
#   ./teardown.sh            # terminate tagged instances only
#   ./teardown.sh --all      # also deregister the baked AMI and delete its snapshots
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
load_config
require_aws

mapfile -t IDS < <(awscli ec2 describe-instances \
  --filters "Name=tag:${TAG_KEY},Values=${TAG_VALUE}" \
            "Name=instance-state-name,Values=pending,running,stopping,stopped" \
  --query 'Reservations[*].Instances[*].InstanceId' --output text | tr '\t' '\n' | sed '/^$/d')

if [ "${#IDS[@]}" -gt 0 ]; then
  warn "About to TERMINATE ${#IDS[@]} instances tagged ${TAG_KEY}=${TAG_VALUE}:"
  printf '  %s\n' "${IDS[@]}"
  read -r -p "Type 'yes' to confirm: " ans
  [ "$ans" = "yes" ] || die "Aborted."
  awscli ec2 terminate-instances --instance-ids "${IDS[@]}" >/dev/null
  info "Termination requested for ${#IDS[@]} instances."
else
  info "No tagged instances to terminate."
fi

if [ "${1:-}" = "--all" ]; then
  AMI_ID="$(state_get AMI_ID)"
  if [ -n "$AMI_ID" ]; then
    info "Looking up snapshots for AMI $AMI_ID ..."
    mapfile -t SNAPS < <(awscli ec2 describe-images --image-ids "$AMI_ID" \
      --query 'Images[0].BlockDeviceMappings[*].Ebs.SnapshotId' --output text | tr '\t' '\n' | sed '/^$/d')
    awscli ec2 deregister-image --image-id "$AMI_ID" && info "Deregistered AMI $AMI_ID"
    for s in "${SNAPS[@]:-}"; do
      [ -n "$s" ] && [ "$s" != "None" ] && awscli ec2 delete-snapshot --snapshot-id "$s" && info "Deleted snapshot $s"
    done
  else
    warn "No AMI_ID in state; skipping AMI cleanup."
  fi
fi
c_grn "=== Teardown done ==="
