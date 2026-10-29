# BOOTSTRAP v2 — cole na IDE de QUALQUER projeto alvo

```text
Instale Eco-Tokens v2 neste projeto a partir de
https://github.com/msrovani/Eco-tokens

1) Preferir:
   curl -sSL https://raw.githubusercontent.com/msrovani/Eco-tokens/main/install.sh | bash

   Fallback:
   git clone --depth 1 https://github.com/msrovani/Eco-tokens.git /tmp/Eco-tokens
   bash /tmp/Eco-tokens/install.sh --target "$(pwd)" --force

2) Confirme: `.eco/mcp-server.py`, `.eco/state.json`, `scripts/verify.sh`,
   `.cursorrules`, `.windsurfrules`, `.cursor/mcp.json` (command=python3).

3) Rode `python3 -m py_compile .eco/mcp-server.py` e `bash scripts/verify.sh`.

4) Recarregue o MCP `eco-tokens` (Python 3 no PATH). Sem Node.

Responda em no máximo 5 linhas.
```
