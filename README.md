# Eco-Tokens

**Orquestração Econômica de Agentes** — pacote autoinstalável de bootstrap para qualquer projeto (Rust, Node, Python, Go, C/C++).

Objetivo: cortar tokens e loops ruins. A IA não lê o repo inteiro, não declara “feito” sem teste, e após 2 falhas de verify trava (circuit breaker).

## Instalação em 1 linha (terminal)

No diretório do **projeto alvo**:

```bash
curl -sSL https://raw.githubusercontent.com/msrovani/Eco-tokens/main/install.sh | bash
```

Clone local:

```bash
git clone https://github.com/msrovani/Eco-tokens.git
cd Eco-tokens && ./install.sh --self-test   # valida o kit
./install.sh --target /caminho/do/projeto   # instala no alvo
```

## Instalação em 1 linha (prompt de IDE)

Cole o conteúdo de [`BOOTSTRAP.md`](./BOOTSTRAP.md) no chat do projeto destino, ou use:

```text
Acesse https://github.com/msrovani/Eco-tokens e execute install.sh neste projeto.
Configure MCP e regras de orquestração de economia de tokens automaticamente.
```

## O que o instalador faz

1. Detecta a stack (`Cargo.toml`, `package.json`, `pyproject`/`pytest`, `go.mod`, CMake/Make).
2. Gera `scripts/verify.sh` customizado (testes silenciosos; em falha, só 20 linhas de log).
3. Copia `scripts/mcp-server.js` e `.tasks.json`.
4. Injeta `.cursorrules`, `.windsurfrules` e `.cursor/mcp.json` (+ rule `eco-tokens.mdc`).
5. `chmod +x` nos scripts gerados.

## Economia de tokens e papéis

| Papel | Função |
|-------|--------|
| **CHIEF** | Escolhe/atualiza a tarefa via MCP; não implementa |
| **SPECIALIST** | Edita o mínimo, só após `search_ast_symbol` |
| **CHECKER** | Só valida com `run_verification` |

Regras duras:

- **Proibição**: sem leitura massiva de arquivos/dirs — use `search_ast_symbol` (≤30 linhas).
- **Validação**: sem `run_verification` não há “concluído”.
- **Circuit breaker**: 2 falhas seguidas → `BLOCKED` + `git checkout .` + parar.
- **Verbosidade**: 3–5 linhas de resumo no chat.

## MCP tools

`get_current_task` · `update_task_status` · `run_verification` · `search_ast_symbol`

Requer **Node.js ≥ 18** no PATH da IDE.

## Layout do kit

```
install.sh              # bootstrap / instalador
BOOTSTRAP.md            # prompt pronto para outras IDEs
templates/
  tasks.json
  rules.markdown
  mcp-server.js
```

## Self-test

```bash
./install.sh --self-test
```

## Licença

MIT — veja `LICENSE`.
