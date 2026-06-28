# shellcheck shell=bash
# Shared helpers for the deploy/aws scripts. Source this, do not run it.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.env"
STATE_FILE="${SCRIPT_DIR}/.state"

c_red()   { printf '\033[0;31m%s\033[0m\n' "$*"; }
c_grn()   { printf '\033[0;32m%s\033[0m\n' "$*"; }
c_ylw()   { printf '\033[1;33m%s\033[0m\n' "$*"; }
info()    { c_grn "[deploy] $*"; }
warn()    { c_ylw "[deploy] $*"; }
die()     { c_red  "[deploy] ERROR: $*"; exit 1; }

load_config() {
  [ -f "$CONFIG_FILE" ] || die "Missing $CONFIG_FILE. Copy config.env.example to config.env and fill it in."
  # shellcheck disable=SC1090
  set -a; source "$CONFIG_FILE"; set +a
  : "${AWS_REGION:?set AWS_REGION in config.env}"
  : "${COUNT:?set COUNT in config.env}"
  AMI_NAME_PREFIX="${AMI_NAME_PREFIX:-flowise-training}"
  TAG_KEY="${TAG_KEY:-training}"
  TAG_VALUE="${TAG_VALUE:-flowise-j2026}"
  UBUNTU_VERSION="${UBUNTU_VERSION:-22.04}"
  INSTANCE_TYPE="${INSTANCE_TYPE:-t3.medium}"
  ROOT_VOLUME_GB="${ROOT_VOLUME_GB:-30}"
  # Empty AWS_PROFILE means "use key/secret directly" — unset it so aws CLI
  # doesn't try to load a profile named "".
  [ -z "${AWS_PROFILE:-}" ] && unset AWS_PROFILE || true
}

# aws CLI wrapper: injects region, profile, and explicit key/secret when no profile is set.
awscli() {
  if [ -n "${AWS_PROFILE:-}" ]; then
    command aws --region "$AWS_REGION" --profile "$AWS_PROFILE" "$@"
  else
    command aws --region "$AWS_REGION" "$@"
  fi
}

require_aws() {
  command -v aws >/dev/null 2>&1 || die "aws CLI not found. Install it and run 'aws configure'."
  awscli sts get-caller-identity >/dev/null 2>&1 || die "AWS credentials not valid (aws sts get-caller-identity failed)."
}

# Resolve the latest Canonical Ubuntu AMI id via the SSM public parameter store.
resolve_ubuntu_ami() {
  local param="/aws/service/canonical/ubuntu/server/${UBUNTU_VERSION}/stable/current/amd64/hvm/ebs-gp2/ami-id"
  awscli ssm get-parameters --names "$param" \
    --query 'Parameters[0].Value' --output text 2>/dev/null
}

default_vpc_id() {
  awscli ec2 describe-vpcs --filters Name=isDefault,Values=true \
    --query 'Vpcs[0].VpcId' --output text 2>/dev/null
}

# Ensure a security group exists with ingress for SSH (22) and Flowise (3000).
# Prints the security group id on stdout.
ensure_sg() {
  if [ -n "${SG_ID:-}" ]; then echo "$SG_ID"; return; fi
  local vpc sg name="flowise-training-sg"
  vpc="$(default_vpc_id)"
  [ "$vpc" != "None" ] && [ -n "$vpc" ] || die "No default VPC found. Set SG_ID and SUBNET_ID in config.env."
  sg="$(awscli ec2 describe-security-groups \
        --filters "Name=group-name,Values=${name}" "Name=vpc-id,Values=${vpc}" \
        --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null || echo None)"
  if [ "$sg" = "None" ] || [ -z "$sg" ]; then
    sg="$(awscli ec2 create-security-group --group-name "$name" \
          --description "Flowise training (SSH + Flowise 3000)" --vpc-id "$vpc" \
          --query 'GroupId' --output text)"
    warn "Created security group $sg ($name) in $vpc" >&2
  fi
  awscli ec2 authorize-security-group-ingress --group-id "$sg" \
    --protocol tcp --port 22 --cidr "${SSH_CIDR:-0.0.0.0/0}" >/dev/null 2>&1 || true
  awscli ec2 authorize-security-group-ingress --group-id "$sg" \
    --protocol tcp --port 3000 --cidr "${APP_CIDR:-0.0.0.0/0}" >/dev/null 2>&1 || true
  echo "$sg"
}

# Create an EC2 keypair if KEY_NAME is not set in config.env.
# Saves the .pem next to config.env and writes KEY_NAME back into config.env.
ensure_keypair() {
  if [ -n "${KEY_NAME:-}" ]; then
    info "Using existing keypair: $KEY_NAME"
    return
  fi
  local name="flowise-training-key"
  local pem_path="${SCRIPT_DIR}/${name}.pem"
  # Reuse if already exists on AWS
  local existing
  existing="$(awscli ec2 describe-key-pairs --key-names "$name" \
    --query 'KeyPairs[0].KeyName' --output text 2>/dev/null || echo None)"
  if [ "$existing" = "$name" ]; then
    warn "Keypair $name already exists on AWS but .pem not found locally — delete it first if you lost the key." >&2
    warn "aws ec2 delete-key-pair --key-name $name --region $AWS_REGION" >&2
    [ -f "$pem_path" ] || die "Keypair $name exists on AWS but $pem_path is missing. See warning above."
  else
    info "Creating keypair $name..."
    awscli ec2 create-key-pair --key-name "$name" \
      --query 'KeyMaterial' --output text > "$pem_path"
    chmod 600 "$pem_path"
    info "Saved: $pem_path"
  fi
  # Persist KEY_NAME in config.env
  sed -i "s|^KEY_NAME=.*|KEY_NAME=${name}|" "$CONFIG_FILE"
  KEY_NAME="$name"
  info "KEY_NAME set to $KEY_NAME in config.env"
}

state_set() { # key value
  touch "$STATE_FILE"
  grep -v "^$1=" "$STATE_FILE" > "${STATE_FILE}.tmp" 2>/dev/null || true
  echo "$1=$2" >> "${STATE_FILE}.tmp"
  mv "${STATE_FILE}.tmp" "$STATE_FILE"
}
state_get() { # key
  [ -f "$STATE_FILE" ] || return 0
  grep "^$1=" "$STATE_FILE" | tail -1 | cut -d= -f2-
}
