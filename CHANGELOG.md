# Changelog — eco-tokens

## [0.3.0] — 2026-10-29

### Added
- Suíte de testes: `tests/test_mcp_unit.py` (smart_trim, estado atômico, anti-loop, MCP initialize).
- Integração: `tests/test_install_integration.sh` + `scripts/run-tests.sh`.
- Protocolo Context Engineering & Token Economy (CoD, cache-friendly rules).
- Anti-loop `SHA256(git diff)` sem re-build; mensagem `LOOP DETECTADO…`.
- `smart_trim` ANSI ECMA-48 (5 head + 15 tail se >20 linhas).
- Estado atômico `.eco/state.json.tmp` → `os.replace`.
- MCP Python zero-dep em `.eco/mcp-server.py`; `dry_run` no CHECKER.

### Changed
- Versão de produto **0.3.0** (protocolo interno v3).
- Installer gera verify stack-aware + regras CoD.

### Verified
- `python3 -m py_compile templates/mcp-server.py`
- `python3 -m unittest discover -s tests`
- `./install.sh --self-test`
