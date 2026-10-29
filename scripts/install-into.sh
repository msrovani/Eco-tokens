#!/usr/bin/env bash
# Copia o kit Eco-Tokens para um repositório alvo (não sobrescreve .tasks.json se existir).
set -euo pipefail

KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="${1:-}"

if [[ -z "$TARGET" ]]; then
  echo "uso: $0 /caminho/do/projeto" >&2
  exit 2
fi
if [[ ! -d "$TARGET" ]]; then
  echo "alvo inexistente: $TARGET" >&2
  exit 1
fi

mkdir -p "$TARGET/scripts" "$TARGET/.cursor/rules"

cp -f "$KIT/scripts/verify.sh" "$TARGET/scripts/verify.sh"
cp -f "$KIT/scripts/mcp-server.js" "$TARGET/scripts/mcp-server.js"
cp -f "$KIT/.cursorrules" "$TARGET/.cursorrules"
cp -f "$KIT/.cursor/mcp.json" "$TARGET/.cursor/mcp.json"
cp -f "$KIT/.cursor/rules/eco-tokens.mdc" "$TARGET/.cursor/rules/eco-tokens.mdc"

if [[ ! -f "$TARGET/.tasks.json" ]]; then
  cp -f "$KIT/.tasks.json" "$TARGET/.tasks.json"
else
  echo "keep: $TARGET/.tasks.json (já existia)"
fi

chmod +x "$TARGET/scripts/verify.sh" "$TARGET/scripts/mcp-server.js" 2>/dev/null || true
echo "Eco-Tokens instalado em: $TARGET"
echo "Próximo: cd \"$TARGET\" && ./scripts/verify.sh"
