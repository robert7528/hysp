#!/usr/bin/env bash
# Sync CLAUDE.md from sub-repos into workspace docs/
# Usage: bash scripts/sync-docs.sh
#
# Run this after updating CLAUDE.md in hyadmin-api or hyadmin-ui.

set -euo pipefail

WORKSPACE="$(cd "$(dirname "$0")/.." && pwd)"

declare -A SERVICES=(
    ["hyadmin-api"]="$WORKSPACE/hyadmin-api/CLAUDE.md"
    ["hyadmin-ui"]="$WORKSPACE/hyadmin-ui/CLAUDE.md"
)

echo "=== Syncing docs ==="
for service in "${!SERVICES[@]}"; do
    src="${SERVICES[$service]}"
    dest="$WORKSPACE/docs/$service/CLAUDE.md"
    if [ ! -f "$src" ]; then
        echo "  !! $src not found, skipping"
        continue
    fi
    cp "$src" "$dest"
    echo "  $service → docs/$service/CLAUDE.md"
done

cd "$WORKSPACE"
git add docs/

if git diff --cached --quiet; then
    echo "No changes to commit."
    exit 0
fi

git commit -m "sync: update docs from sub-repos"
git push
echo "Done."
