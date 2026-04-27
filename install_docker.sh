#!/usr/bin/env bash
# Install Docker Engine + Compose plugin on Ubuntu/Debian.
# Не для production. Для swift demo deploy.
set -euo pipefail

if [ "$(id -u)" -ne 0 ] && ! sudo -n true 2>/dev/null; then
    echo "Need root or passwordless sudo"
    exit 1
fi
SUDO="sudo"
[ "$(id -u)" -eq 0 ] && SUDO=""

if ! command -v lsb_release >/dev/null; then
    $SUDO apt-get update -y
    $SUDO apt-get install -y lsb-release ca-certificates curl gnupg
fi

. /etc/os-release
DISTRO="${ID:-ubuntu}"

echo "[1/5] Removing legacy packages (if any)..."
$SUDO apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true

echo "[2/5] Adding Docker apt repo..."
$SUDO install -m 0755 -d /etc/apt/keyrings
curl -fsSL "https://download.docker.com/linux/${DISTRO}/gpg" \
    | $SUDO gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg
$SUDO chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/${DISTRO} \
  $(. /etc/os-release && echo "${VERSION_CODENAME}") stable" \
  | $SUDO tee /etc/apt/sources.list.d/docker.list >/dev/null

echo "[3/5] Installing engine + compose plugin..."
$SUDO apt-get update -y
$SUDO apt-get install -y docker-ce docker-ce-cli containerd.io \
    docker-buildx-plugin docker-compose-plugin

echo "[4/5] Enabling service..."
$SUDO systemctl enable --now docker

echo "[5/5] Adding $USER to docker group (re-login required)..."
$SUDO usermod -aG docker "$USER" || true

echo
echo "Done. Versions:"
docker --version
docker compose version
echo
echo "Re-login (or run 'newgrp docker') so 'docker' works without sudo."
