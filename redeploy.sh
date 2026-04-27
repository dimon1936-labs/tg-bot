#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLOWS="$DIR/flows.json"

if [ -f "$DIR/.env" ]; then
    set -a
    . "$DIR/.env"
    set +a
fi

HOST="${NODE_RED_HOST:-http://localhost:1881}"
USER="${NODE_RED_USER:-admin}"
PASS="${NODE_RED_PASS:?set NODE_RED_PASS env var (Node-RED admin password)}"

echo "Validating flows.json..."
if ! jq empty "$FLOWS" 2>/dev/null \
    && ! python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$FLOWS" 2>/dev/null \
    && ! node -e "JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'))" "$FLOWS" 2>/dev/null; then
    echo "INVALID JSON"
    exit 1
fi
echo "OK"

echo "Authenticating to Node-RED..."
TOKEN="$(curl -fsS -X POST "$HOST/auth/token" \
    -H "Content-Type: application/json" \
    -d "{\"client_id\":\"node-red-admin\",\"grant_type\":\"password\",\"scope\":\"*\",\"username\":\"$USER\",\"password\":\"$PASS\"}" \
    | jq -r '.access_token' 2>/dev/null || true)"

if [ -z "${TOKEN:-}" ] || [ "$TOKEN" = "null" ]; then
    echo "Auth failed, fallback to docker cp"
    docker cp "$FLOWS" birthday-bot-nodered:/data/flows.json
    docker restart birthday-bot-nodered
    echo "Container restarted"
    exit 0
fi

echo "Uploading to $HOST/flows"
if curl -fsS -X POST "$HOST/flows" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Node-RED-Deployment-Type: full" \
    --data-binary "@$FLOWS" >/dev/null; then
    echo "Deployed"
else
    echo "API failed, fallback to docker cp"
    docker cp "$FLOWS" birthday-bot-nodered:/data/flows.json
    docker restart birthday-bot-nodered
    echo "Container restarted"
fi
