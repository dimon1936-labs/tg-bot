#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/db"

shopt -s nullglob
migrations=( "$DIR"/migration_*.sql )

if [ ${#migrations[@]} -eq 0 ]; then
    echo "No migrations found in $DIR"
    exit 1
fi

IFS=$'\n' migrations=( $(printf '%s\n' "${migrations[@]}" | sort) )

echo "Found ${#migrations[@]} migrations:"
for m in "${migrations[@]}"; do echo "  - $(basename "$m")"; done
echo

for m in "${migrations[@]}"; do
    name="$(basename "$m")"
    echo "Applying $name..."
    if docker exec -i birthday-bot-db psql -U postgres -d birthday_bot < "$m"; then
        echo "  OK"
    else
        echo "  FAILED"
        exit 1
    fi
done

echo
echo "All migrations applied successfully"
