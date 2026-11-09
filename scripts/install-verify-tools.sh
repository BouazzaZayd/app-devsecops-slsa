#!/usr/bin/env bash
# Installe les outils de verification (cosign, slsa-verifier, conftest, crane) + utilitaires.
# Idempotent : ne reinstalle pas ce qui est deja present a la bonne version.
# A lancer une fois sur la machine qui execute le gate (VM4 a la main, ou le runner Gitea).
set -euo pipefail
COSIGN_VERSION="${COSIGN_VERSION:-v3.1.1}"
BIN=/usr/local/bin
SUDO=""; [ "$(id -u)" -ne 0 ] && SUDO="sudo"

$SUDO apt-get update -qq
$SUDO apt-get install -y curl jq ca-certificates openssh-client tar >/dev/null

# Horloge : prerequis de securite (certificat Fulcio valable 10 min, TLS d'apt)
$SUDO timedatectl set-ntp true 2>/dev/null || true
echo "Date : $(date)"

install_bin() { $SUDO curl -sSLo "$BIN/$1" "$2"; $SUDO chmod +x "$BIN/$1"; }

command -v cosign >/dev/null 2>&1 || \
  install_bin cosign "https://github.com/sigstore/cosign/releases/download/${COSIGN_VERSION}/cosign-linux-amd64"

if ! command -v slsa-verifier >/dev/null 2>&1; then
  V=$(curl -s https://api.github.com/repos/slsa-framework/slsa-verifier/releases/latest | jq -r .tag_name)
  install_bin slsa-verifier "https://github.com/slsa-framework/slsa-verifier/releases/download/${V}/slsa-verifier-linux-amd64"
fi

if ! command -v conftest >/dev/null 2>&1; then
  V=$(curl -s https://api.github.com/repos/open-policy-agent/conftest/releases/latest | jq -r .tag_name | tr -d v)
  curl -sSLo /tmp/conftest.tgz "https://github.com/open-policy-agent/conftest/releases/download/v${V}/conftest_${V}_Linux_x86_64.tar.gz"
  $SUDO tar -xzf /tmp/conftest.tgz -C "$BIN" conftest
fi

if ! command -v crane >/dev/null 2>&1; then
  V=$(curl -s https://api.github.com/repos/google/go-containerregistry/releases/latest | jq -r .tag_name)
  curl -sSL "https://github.com/google/go-containerregistry/releases/download/${V}/go-containerregistry_Linux_x86_64.tar.gz" | $SUDO tar -xz -C "$BIN" crane
fi

echo "--- versions ---"
cosign version | grep GitVersion || true
slsa-verifier version 2>&1 | grep GitVersion || true
conftest --version | head -1
crane version
