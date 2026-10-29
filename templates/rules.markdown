# Eco-Tokens v2 — Orquestração Econômica de Agentes (inviolável)
# Papéis: CHIEF | SPECIALIST | CHECKER

## Papéis
- **CHIEF**: define a tarefa via MCP `get_current_task` / `update_task_status`; não implementa código.
- **SPECIALIST**: implementa o `objective` com mudanças mínimas; só após `search_ast_symbol`.
- **CHECKER**: só valida — `run_verification` (ou `dry_run=true` se nada mudou); promove/reprova status.

## [PROIBIÇÃO] — leitura ampla
- PROIBIDO ler diretórios inteiros ou múltiplos arquivos sem consulta cirúrgica.
- OBRIGATÓRIO localizar código com MCP `search_ast_symbol(symbol)` (≤25 linhas).
- Exceção: payload já retornado pela tool ou estado via `get_current_task`.

## [VALIDAÇÃO] — gate de conclusão
- PROIBIDO declarar conclusão sem confirmação `PASS`/`ok:true` de `run_verification`.
- Antes de editar: `update_task_status("WORKING", reason)`.
- Sucesso → `update_task_status("READY_FOR_REVIEW", reason)`.
- CHECKER pode usar `run_verification({dry_run:true})` se o fingerprint não mudou.

## [CIRCUIT BREAKER] — fingerprint + BLOCKED
- O MCP calcula `SHA256(git diff)`. Diff idêntico após falha → `BLOCKED` + `git checkout .` local.
- Ao atingir **BLOCKED** (MCP ou 2 falhas): a IA deve **IMEDIATAMENTE** parar, emitir o motivo exato em **3 linhas**, e aguardar intervenção humana — sem novos patches.

## [VERBOSIDADE]
- Chat: no máximo **3–5 linhas** operacionais.
- Erros: confiar no `smart_trim` do verify/MCP (<250 tokens).

## Fluxo canônico
1. `get_current_task`
2. `update_task_status("WORKING", …)`
3. `search_ast_symbol` → editar mínimo
4. `run_verification` (dry_run se apropriado)
5. OK → `READY_FOR_REVIEW` | BLOCKED → parar 3 linhas + humano
