#!/usr/bin/env bash
set -euo pipefail

FLOWS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/flows.json"
URL="http://localhost:1881/flows"

echo "Validating flows.json..."
if ! python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$FLOWS" 2>/dev/null \
    && ! jq empty "$FLOWS" 2>/dev/null \
    && ! node -e "JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'))" "$FLOWS" 2>/dev/null; then
    echo "INVALID JSON"
    exit 1
fi
echo "OK"

echo "Uploading to $URL"
if curl -fsS -X POST "$URL" \
    -H "Content-Type: application/json" \
    -H "Node-RED-Deployment-Type: full" \
    --data-binary "@$FLOWS" >/dev/null; then
    echo "Deployed"
else
    echo "API failed, fallback to docker cp"
    docker cp "$FLOWS" birthday-bot-nodered:/data/flows.json
    docker restart birthday-bot-nodered
    echo "Container restarted"
fi
