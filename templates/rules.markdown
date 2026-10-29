# Eco-Tokens — Orquestração Econômica de Agentes
# Protocolo obrigatório para papéis CHIEF | SPECIALIST | CHECKER

## Papéis
- **CHIEF**: define/seleciona a tarefa em `.tasks.json` via MCP `get_current_task` / `update_task_status`; não implementa.
- **SPECIALIST**: implementa o `objective` da tarefa ativa com mudanças mínimas e cirúrgicas.
- **CHECKER**: só valida; chama `run_verification` e promove/reprova status.

## [PROIBIÇÃO] — leitura ampla
- Proibido ler arquivos ou diretórios inteiros (`Read` em massa, `Glob` amplo, dump de pasta).
- Obrigatório localizar código com MCP `search_ast_symbol(symbol)` (ripgrep/ast-grep, ≤30 linhas).
- Exceção: arquivos ≤40 linhas já retornados pelo trecho da busca, ou `.tasks.json` via `get_current_task`.

## [VALIDAÇÃO] — gate de conclusão
- Proibido declarar tarefa concluída sem chamar MCP `run_verification`.
- Sucesso (`VERIFY_OK`) → `update_task_status("READY_FOR_REVIEW", reason)`.
- Antes de editar: `update_task_status("WORKING", reason)`.

## [CIRCUIT BREAKER]
- Se `run_verification` falhar **2 vezes seguidas** na mesma tarefa (`attempts` / falhas de verify):
  1. `update_task_status("BLOCKED", "verify failed twice")`
  2. `git checkout .` (reverter working tree)
  3. Parar e solicitar intervenção humana — sem novos patches.

## [VERBOSIDADE]
- Respostas de chat: no máximo **3–5 linhas** de resumo operacional.
- Sem dumps longos de log; use o output enxuto do MCP.

## Fluxo canônico
1. `get_current_task`
2. `update_task_status("WORKING", …)`
3. `search_ast_symbol` → editar mínimo
4. `run_verification`
5. OK → `READY_FOR_REVIEW` | 2× FAIL → `BLOCKED` + `git checkout .`
