# Eco-Tokens 0.3 — Context Engineering & Token Economy

Bootstrap **zero-dependency** (Python 3 stdlib + Bash) que move inteligência da janela de contexto para validações determinísticas locais.

**Versão:** `0.3.0` · protocolo interno v3 · tag `v0.3.0`

## Instalação em 1 linha

```bash
curl -sSL https://raw.githubusercontent.com/msrovani/Eco-tokens/main/install.sh | bash
```

## Testes

```bash
bash scripts/run-tests.sh
# ou
./install.sh --self-test
python3 -m unittest discover -s tests -v
```

Prompt para IDE: [`BOOTSTRAP.md`](./BOOTSTRAP.md).

## Anti-Loop SHA256

Cada `run_verification` calcula `hash = SHA256(git diff)`.

| Condição | Ação |
|----------|------|
| `hash == last_hash` **e** verificação anterior falhou | Circuit breaker **sem build**: `git checkout .`, status `BLOCKED`, mensagem `LOOP DETECTADO…` |
| Diff mudou | Roda `scripts/verify.sh` + `smart_trim` |
| `dry_run=true` | Só consulta fingerprint / estado |

## Higienização Head/Tail (`smart_trim`)

- Remove ANSI (`\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])`).
- Se erro com **>20 linhas**: **5 primeiras** (tipo/cabeçalho) + **15 últimas** (stack/local) — meio descartado.
- Cap ~1000 chars (~250 tokens).

## Estado atômico

`.eco/state.json` gravado via `.eco/state.json.tmp` + `os.replace` (+ `.bak`).

## Layout no projeto alvo

```
.eco/mcp-server.py
.eco/state.json
scripts/verify.sh          # stack-aware + smart_trim
.cursorrules / .windsurfrules   # CoD + cache-friendly
.cursor/mcp.json           # python3 .eco/mcp-server.py
```

## Papéis + CoD

- **CHIEF** orquestra · **SPECIALIST** edita · **CHECKER** valida.
- Chain-of-Draft: ≤5 palavras/passo de raciocínio; sem filler conversacional.
- Ordem de prompt: FIXO → REPO → ESTADO → DINÂMICO (cache-friendly).

## Requisitos

Python ≥ 3.8 · Bash · opcional `rg`/`ast-grep`

## Licença

MIT
