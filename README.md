# Eco-Tokens v2

**Orquestração Econômica de Agentes** — bootstrap zero-dependency (Python 3 stdlib + Bash). Move inteligência da janela de contexto para scripts determinísticos locais.

## Instalação (1 linha)

No projeto alvo:

```bash
curl -sSL https://raw.githubusercontent.com/msrovani/Eco-tokens/main/install.sh | bash
```

Self-test do kit:

```bash
./install.sh --self-test
```

Prompt para IDE: veja [`BOOTSTRAP.md`](./BOOTSTRAP.md).

## O que muda na v2

| v1 | v2 |
|----|----|
| MCP Node (`mcp-server.js`) | MCP Python stdlib (`.eco/mcp-server.py`) |
| `tail -n 20` cego | `smart_trim`: 5 head + 15 tail, strip ANSI |
| `.tasks.json` direto | `.eco/state.json` com write atômico + `.bak` |
| Circuit breaker só por `attempts` | Fingerprint `SHA256(git diff)` → BLOCKED + `git checkout .` |
| — | `run_verification(dry_run=true)` sem build |

## Layout instalado no alvo

```
.eco/mcp-server.py      # MCP stdio
.eco/state.json         # estado + hashes
scripts/verify.sh       # smart_trim por stack
.cursorrules / .windsurfrules
.cursor/mcp.json        # python3 .eco/mcp-server.py
```

## MCP tools

- `get_current_task` — só a tarefa ativa
- `update_task_status(status, reason)` — atômico
- `run_verification` — fingerprint + verify + sanitize (`dry_run` opcional)
- `search_ast_symbol` — ast-grep → rg → grep (≤25 linhas)

## Papéis (economia de tokens)

**CHIEF** orquestra · **SPECIALIST** edita cirúrgico · **CHECKER** só valida.

Payloads de erro tipicamente **&lt;250 tokens**. BLOCKED → parar em 3 linhas e aguardar humano.

## Requisitos

- Python ≥ 3.8 (stdlib)
- Bash (Git Bash no Windows)
- Opcional: `rg` / `ast-grep`, toolchain da stack do projeto

## Licença

MIT
