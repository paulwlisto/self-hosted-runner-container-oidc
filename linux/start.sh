#!/bin/bash
set -euo pipefail

ORGANIZATION="${ORGANIZATION:?Environment variable ORGANIZATION is required}"
AZURE_KEY_VAULT_NAME="${AZURE_KEY_VAULT_NAME:?Environment variable AZURE_KEY_VAULT_NAME is required}"
GITHUB_APP_ID_SECRET_NAME="${GITHUB_APP_ID_SECRET_NAME:-github-app-id}"
GITHUB_APP_PRIVATE_KEY_SECRET_NAME="${GITHUB_APP_PRIVATE_KEY_SECRET_NAME:-github-app-private-key}"
GITHUB_APP_INSTALLATION_ID="${GITHUB_APP_INSTALLATION_ID:-}"
AZURE_CLIENT_ID="${AZURE_CLIENT_ID:-}"
RUNNER_NAME="${RUNNER_NAME:-$(hostname)}"
LABELS="${LABELS:-}"

# Authenticate to Azure via managed identity. AZURE_CLIENT_ID selects a
# specific user-assigned identity; without it the system-assigned identity
# (or the only user-assigned identity bound to the host) is used.
if [ -n "$AZURE_CLIENT_ID" ]; then
  az login --identity --username "$AZURE_CLIENT_ID" >/dev/null
else
  az login --identity >/dev/null
fi

GITHUB_APP_ID=$(az keyvault secret show \
  --vault-name "$AZURE_KEY_VAULT_NAME" \
  --name "$GITHUB_APP_ID_SECRET_NAME" \
  --query value -o tsv)

PRIVATE_KEY_FILE=$(mktemp)
trap 'rm -f "$PRIVATE_KEY_FILE"' EXIT
az keyvault secret show \
  --vault-name "$AZURE_KEY_VAULT_NAME" \
  --name "$GITHUB_APP_PRIVATE_KEY_SECRET_NAME" \
  --query value -o tsv > "$PRIVATE_KEY_FILE"

# Mint a GitHub App JWT (RS256) using openssl.
b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }

NOW=$(date +%s)
HEADER=$(printf '{"alg":"RS256","typ":"JWT"}' | b64url)
PAYLOAD=$(printf '{"iat":%d,"exp":%d,"iss":"%s"}' "$((NOW - 60))" "$((NOW + 540))" "$GITHUB_APP_ID" | b64url)
SIGNING_INPUT="${HEADER}.${PAYLOAD}"
SIGNATURE=$(printf '%s' "$SIGNING_INPUT" \
  | openssl dgst -sha256 -sign "$PRIVATE_KEY_FILE" -binary \
  | b64url)
APP_JWT="${SIGNING_INPUT}.${SIGNATURE}"

# Resolve installation id for the org if not provided.
if [ -z "$GITHUB_APP_INSTALLATION_ID" ]; then
  GITHUB_APP_INSTALLATION_ID=$(curl -fsS \
    -H "Authorization: Bearer ${APP_JWT}" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/orgs/${ORGANIZATION}/installation" \
    | jq -r .id)
fi

if [ -z "$GITHUB_APP_INSTALLATION_ID" ] || [ "$GITHUB_APP_INSTALLATION_ID" = "null" ]; then
  echo "ERROR: Unable to resolve GitHub App installation id for org ${ORGANIZATION}." >&2
  exit 1
fi

# Exchange the App JWT for a short-lived installation access token.
INSTALLATION_TOKEN=$(curl -fsS -X POST \
  -H "Authorization: Bearer ${APP_JWT}" \
  -H "Accept: application/vnd.github+json" \
  "https://api.github.com/app/installations/${GITHUB_APP_INSTALLATION_ID}/access_tokens" \
  | jq -r .token)

if [ -z "$INSTALLATION_TOKEN" ] || [ "$INSTALLATION_TOKEN" = "null" ]; then
  echo "ERROR: Failed to obtain GitHub App installation token." >&2
  exit 1
fi

# Request a runner registration token using the installation token.
REG_TOKEN=$(curl -fsS -X POST \
  -H "Authorization: Bearer ${INSTALLATION_TOKEN}" \
  -H "Accept: application/vnd.github+json" \
  "https://api.github.com/orgs/${ORGANIZATION}/actions/runners/registration-token" \
  | jq -r .token)

if [ -z "$REG_TOKEN" ] || [ "$REG_TOKEN" = "null" ]; then
  echo "ERROR: Failed to obtain a runner registration token." >&2
  exit 1
fi

LABEL_ARGS=""
if [ -n "$LABELS" ]; then
  LABEL_ARGS="--labels ${LABELS}"
fi

./config.sh \
  --url "https://github.com/${ORGANIZATION}" \
  --token "${REG_TOKEN}" \
  --name "${RUNNER_NAME}" \
  --unattended \
  --replace \
  ${LABEL_ARGS}

cleanup() {
  echo "Removing runner..."
  ./config.sh remove --token "${REG_TOKEN}" || true
}
trap 'cleanup; rm -f "$PRIVATE_KEY_FILE"' SIGTERM SIGINT EXIT

./run.sh &
wait $!
