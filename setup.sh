#!/bin/bash
set -euo pipefail

# ──────────────────────────────────────────────
# setup.sh — Bootstrap a fresh VM for the
#            Deloitte No-Code Flowise training stack
#
# Usage:
#   ./setup.sh
#
# Installs: make, docker, docker-compose-plugin,
#           curl, jq, python3, postgresql-client
# ──────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { printf "${GREEN}[setup]${NC} %s\n" "$*"; }
warn()  { printf "${YELLOW}[setup]${NC} %s\n" "$*"; }
error() { printf "${RED}[setup]${NC} %s\n" "$*" >&2; }

# -- Detect OS ---------------------------------------------------------------
if ! command -v apt-get &>/dev/null; then
  error "Unsupported distribution. This script currently supports Ubuntu/Debian with apt-get."
  exit 1
fi

# NB: if sudo is not available, the user is probably root already
SUDO=""
if command -v sudo &>/dev/null && [ "$(id -u)" -ne 0 ]; then
  SUDO="sudo"
fi

# -- Update package index ----------------------------------------------------
info "Updating package index..."
$SUDO apt-get update -qq

# -- Install base packages ---------------------------------------------------
BASE_PKGS="make curl jq python3 python3-pip postgresql-client ca-certificates"
info "Installing base packages: $BASE_PKGS"
$SUDO apt-get install -y -qq $BASE_PKGS

# -- Docker ------------------------------------------------------------------
if command -v docker &>/dev/null; then
  info "Docker already installed."
else
  info "Installing Docker via get.docker.com..."
  curl -fsSL https://get.docker.com | sh
  $SUDO usermod -aG docker "$USER"
  warn "Docker installed. You must log out and back in (or run 'newgrp docker')"
  warn "for the docker group membership to take effect."
fi

# -- Docker Compose plugin ---------------------------------------------------
if docker compose version &>/dev/null 2>&1; then
  info "Docker Compose plugin already installed."
else
  info "Installing Docker Compose plugin..."
  $SUDO apt-get install -y -qq docker-compose-plugin
fi

# -- .env file ---------------------------------------------------------------
if [ -f .env ]; then
  info ".env file found."
else
  if [ -f .env.example ]; then
    info "Creating .env from .env.example..."
    cp .env.example .env
    warn "IMPORTANT: Edit .env and set your OPENAI_GATEWAY_API_KEY before running make up."
  else
    warn "No .env or .env.example found. You must create a .env file manually."
  fi
fi

# -- Verify ------------------------------------------------------------------
info "Verifying installation..."
for cmd in make docker curl jq python3; do
  if command -v "$cmd" &>/dev/null; then
    info "  $cmd: OK ($(command -v "$cmd"))"
  else
    error "  $cmd: NOT FOUND"
    exit 1
  fi
done

if docker compose version &>/dev/null 2>&1; then
  info "  docker compose: OK ($(docker compose version --short 2>/dev/null || docker compose version))"
else
  error "  docker compose: NOT FOUND"
  exit 1
fi

printf "\n${GREEN}=== Setup complete ===${NC}\n"
printf "Run '%s' to start the stack.\n" "${YELLOW}make up${NC}"
