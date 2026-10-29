# Eco-Tokens

**Orquestração Econômica de Agentes** — kit portable para IDEs (Cursor/Windsurf): estado de tarefa, verificação determinística enxuta e MCP local com 4 tools.

## Ideia

Minimizar tokens e loops ruins: a IA não lê o repo inteiro, não declara “feito” sem teste, e após 2 falhas de verify trava (circuit breaker) pedindo humano.

## Artefatos

| Path | Função |
|------|--------|
| `.tasks.json` | Estado da tarefa ativa |
| `scripts/verify.sh` | Detecta stack (Rust/Node/Python/Go) e roda testes; stderr truncado (20 linhas) |
| `scripts/mcp-server.js` | MCP stdio: `get_current_task`, `update_task_status`, `run_verification`, `search_ast_symbol` |
| `.cursor/mcp.json` | Registro do servidor MCP |
| `.cursorrules` | Protocolo CHIEF / SPECIALIST / CHECKER |
| `.cursor/rules/eco-tokens.mdc` | Mesma regra com `alwaysApply` (Cursor moderno) |
| `scripts/install-into.sh` | Copia o kit para outro repositório |

## Requisitos

- Bash (Git Bash no Windows)
- Node.js ≥ 18 (só para o MCP)
- `rg` (ripgrep) ou `ast-grep` para `search_ast_symbol`

## Uso rápido neste repo

```bash
chmod +x scripts/verify.sh scripts/mcp-server.js scripts/install-into.sh
./scripts/verify.sh
```

No Cursor: habilite o MCP **eco-tokens** (`.cursor/mcp.json`).

## Instalar em outro projeto

```bash
./scripts/install-into.sh /caminho/do/seu/projeto
```

Depois, no projeto alvo, rode `./scripts/verify.sh` e recarregue o MCP.

## Variáveis

| Var | Efeito |
|-----|--------|
| `ECO_VERIFY_FULL=1` | Rust: `cargo test --workspace --lib` (em vez do smoke) |
| `ECO_VERIFY_PACKAGE=foo` | Rust smoke: `cargo test -p <crate> --lib` |
| `ECO_BASH` / `ECO_RG` | Override dos binários |

## Status da tarefa

`TODO` → `WORKING` → `READY_FOR_REVIEW` | `BLOCKED`

## Licença

MIT — veja `LICENSE`.
