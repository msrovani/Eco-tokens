# BOOTSTRAP — cole isto na IDE de QUALQUER projeto alvo

Copie o bloco abaixo para o chat do Cursor/Windsurf no repositório que deve receber o Eco-Tokens:

---

```text
Instale o Eco-Tokens neste projeto atual a partir de
https://github.com/msrovani/Eco-tokens

Faça o seguinte, sem pedir confirmação extra:

1. No terminal do workspace, execute UMA destas opções (prefira a primeira se houver rede):

   curl -sSL https://raw.githubusercontent.com/msrovani/Eco-tokens/main/install.sh | bash

   OU, se curl|bash falhar:

   git clone --depth 1 https://github.com/msrovani/Eco-tokens.git /tmp/Eco-tokens
   bash /tmp/Eco-tokens/install.sh --target "$(pwd)" --force

2. Confirme que existem: `.tasks.json`, `scripts/verify.sh`, `scripts/mcp-server.js`,
   `.cursorrules`, `.windsurfrules`, `.cursor/mcp.json`.

3. Rode `bash scripts/verify.sh` e reporte VERIFY_OK ou as últimas linhas de falha.

4. Avise que o MCP `eco-tokens` precisa ser recarregado na IDE (Node ≥ 18 no PATH).

Responda em no máximo 5 linhas.
```

---

## Alternativa só-terminal (sem IA)

```bash
curl -sSL https://raw.githubusercontent.com/msrovani/Eco-tokens/main/install.sh | bash
```
