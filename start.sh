#!/usr/bin/env bash
# Bootstrap: build → up → wait → migrations → redeploy flows.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

if [ ! -f .env ]; then
    echo ".env not found. Copy .env.example to .env and fill in values."
    exit 1
fi

DC="docker compose"
if ! $DC version >/dev/null 2>&1; then
    DC="docker-compose"
fi

echo "[1/4] Building + starting containers..."
$DC up -d --build

echo "[2/4] Waiting for postgres..."
for i in {1..30}; do
    if docker exec birthday-bot-db pg_isready -U postgres >/dev/null 2>&1; then
        echo "  postgres ready"
        break
    fi
    sleep 1
done

echo "[3/4] Applying migrations..."
./apply_migrations.sh

echo "[4/4] Waiting for Node-RED admin API..."
for i in {1..30}; do
    if curl -fsS http://localhost:1881/flows >/dev/null 2>&1; then
        break
    fi
    sleep 1
done

./redeploy.sh

echo
echo "Stack is up. Logs: $DC logs -f"
