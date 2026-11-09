#!/usr/bin/env bash
# =============================================================================
# Gate d'admission : verifie (cosign + slsa-verifier + conftest), copie dans Zot
# par digest, puis deploie par digest.
#
# Utilisable DE DEUX FACONS, avec exactement le meme code :
#   - A LA MAIN  :  ./scripts/verify-deploy.sh            (DEPLOY_MODE=local par defaut)
#   - EN CI Gitea:  DEPLOY_MODE=ssh ./scripts/verify-deploy.sh
#
# Si l'un des trois controles echoue, le script s'arrete : pas de deploiement.
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."

# --- Configuration (toutes surchargeables par variable d'environnement) ---
IMAGE="${IMAGE:-ghcr.io/bouazzazayd/app-devsecops-slsa}"
REPO="${REPO:-BouazzaZayd/app-devsecops-slsa}"
BUILDER_ID="${BUILDER_ID:-https://github.com/slsa-framework/slsa-github-generator/.github/workflows/generator_container_slsa3.yml}"
ISSUER="https://token.actions.githubusercontent.com"
POLICY_DIR="${POLICY_DIR:-./policy}"
ZOT="${ZOT:-10.0.0.13:5000}"
ZOT_REPO="${ZOT_REPO:-app-devsecops-slsa}"
ZOT_USERNAME="${ZOT_USERNAME:-admin}"
ZOT_PASSWORD="${ZOT_PASSWORD:-}"   # jamais de secret en dur : export en local, ou secret CI
APP_NAME="${APP_NAME:-app-staging}"
APP_PORT="${APP_PORT:-8080}"
DEPLOY_MODE="${DEPLOY_MODE:-local}"      # local | ssh
VM4_HOST="${VM4_HOST:-10.0.0.14}"
VM4_USER="${VM4_USER:-debian}"

red(){ printf '\033[1;31m%s\033[0m\n' "$*"; }
green(){ printf '\033[1;32m%s\033[0m\n' "$*"; }
refuse(){ red "REFUSE : $*"; red ">>> DEPLOIEMENT BLOQUE"; exit 1; }

# 1. Resoudre le digest immuable a partir du tag latest
DIGEST="${DIGEST:-$(crane digest "${IMAGE}:latest")}"
echo "Image a admettre : ${IMAGE}@${DIGEST}"

# 2. Controle 1/3 : signature keyless (identite du workflow)
echo "== [1/3] cosign verify (identite + emetteur) =="
cosign verify \
  --certificate-identity-regexp "(?i)^https://github\.com/${REPO}/\.github/workflows/release\.yml@refs/.*$" \
  --certificate-oidc-issuer "$ISSUER" \
  "${IMAGE}@${DIGEST}" >/dev/null 2>&1 || refuse "signature keyless invalide ou mauvaise identite"
green "   OK signature keyless"

# 3. Controle 2/3 : provenance SLSA L3
echo "== [2/3] slsa-verifier (provenance L3) =="
slsa-verifier verify-image "${IMAGE}@${DIGEST}" \
  --source-uri "github.com/${REPO}" --builder-id "$BUILDER_ID" \
  --print-provenance > /tmp/prov.json 2>/dev/null || refuse "provenance SLSA absente ou non conforme"
green "   OK provenance SLSA L3"

# 4. Controle 3/3 : politique de l'organisation (Rego)
echo "== [3/3] conftest (politique org) =="
conftest test /tmp/prov.json --policy "$POLICY_DIR" || refuse "politique de l'organisation non respectee"
green "   OK politique Rego"

# 5. Copie GHCR -> Zot en preservant le digest
echo "== Copie GHCR -> Zot (meme digest) =="
[ -n "$ZOT_PASSWORD" ] || refuse "ZOT_PASSWORD requis (export en local, ou secret en CI)"
crane auth login "$ZOT" -u "$ZOT_USERNAME" -p "$ZOT_PASSWORD" >/dev/null 2>&1
crane copy --insecure "${IMAGE}@${DIGEST}" "${ZOT}/${ZOT_REPO}:verified"
ZOT_DIGEST=$(crane digest --insecure "${ZOT}/${ZOT_REPO}:verified")
[ "$ZOT_DIGEST" = "$DIGEST" ] || refuse "digest different apres copie ($ZOT_DIGEST != $DIGEST)"
green "   OK digest identique dans Zot : $ZOT_DIGEST"

# 6. Deploiement PAR DIGEST (jamais par tag)
echo "== Deploiement ($DEPLOY_MODE), par digest =="
RUN_CMD="docker rm -f ${APP_NAME} >/dev/null 2>&1 || true; \
docker run -d --name ${APP_NAME} -p ${APP_PORT}:8080 -e FLASK_HOST=0.0.0.0 ${ZOT}/${ZOT_REPO}@${DIGEST}; \
sleep 5; curl -fsS http://localhost:${APP_PORT}/health"

if [ "$DEPLOY_MODE" = "ssh" ]; then
  : "${SSH_DEPLOY_KEY:?SSH_DEPLOY_KEY requis en mode ssh}"
  mkdir -p ~/.ssh
  echo "$SSH_DEPLOY_KEY" | base64 -d > /tmp/deploy_key
  chmod 600 /tmp/deploy_key
  ssh-keyscan -H "$VM4_HOST" >> ~/.ssh/known_hosts 2>/dev/null
  ssh -i /tmp/deploy_key "${VM4_USER}@${VM4_HOST}" "$RUN_CMD"
else
  bash -c "$RUN_CMD"
fi
echo
green ">>> IMAGE ADMISE, DEPLOYEE ET VERIFIEE : ${ZOT}/${ZOT_REPO}@${DIGEST}"
