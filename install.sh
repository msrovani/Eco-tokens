#!/usr/bin/env bash
# Eco-Tokens v2 — instalador zero-dep (Python3 MCP + smart verify + .eco/)
# Uso:
#   ./install.sh [--target DIR] [--force]
#   ./install.sh --self-test
#   curl -sSL https://raw.githubusercontent.com/msrovani/Eco-tokens/main/install.sh | bash
set -euo pipefail

REPO_SLUG="${ECO_TOKENS_REPO:-msrovani/Eco-tokens}"
REPO_BRANCH="${ECO_TOKENS_BRANCH:-main}"
REPO_TARBALL="https://github.com/${REPO_SLUG}/archive/refs/heads/${REPO_BRANCH}.tar.gz"

TARGET=""
FORCE=0
SELF_TEST=0
CLEANUP_KIT=""

usage() {
  cat <<'EOF'
Eco-Tokens v2 installer

  ./install.sh [--target DIR] [--force]
  ./install.sh --self-test

  --target DIR   Projeto destino (default: cwd)
  --force        Sobrescreve state/regras existentes
  --self-test    Sandbox + py_compile + bash -n
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target) TARGET="${2:-}"; shift 2 ;;
    --force) FORCE=1; shift ;;
    --self-test) SELF_TEST=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "arg desconhecido: $1" >&2; usage; exit 2 ;;
  esac
done

log() { printf '[eco-tokens] %s\n' "$*"; }
die() { printf '[eco-tokens] ERROR: %s\n' "$*" >&2; exit 1; }

resolve_python() {
  for c in "${ECO_PYTHON:-}" python3 python; do
    [[ -z "$c" ]] && continue
    if command -v "$c" >/dev/null 2>&1; then
      if "$c" -c 'import sys; raise SystemExit(0 if sys.version_info[0]>=3 else 1)' 2>/dev/null; then
        printf '%s\n' "$c"
        return 0
      fi
    fi
  done
  return 1
}

resolve_kit() {
  local self="${BASH_SOURCE[0]:-}"
  if [[ -n "$self" && -f "$self" ]]; then
    local dir
    dir="$(cd "$(dirname "$self")" && pwd)"
    if [[ -d "$dir/templates" && -f "$dir/templates/mcp-server.py" ]]; then
      printf '%s\n' "$dir"
      return 0
    fi
  fi
  command -v curl >/dev/null 2>&1 || die "curl necessário para bootstrap remoto"
  command -v tar >/dev/null 2>&1 || die "tar necessário para bootstrap remoto"
  local tmp
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/eco-tokens-kit.XXXXXX")"
  CLEANUP_KIT="$tmp"
  log "baixando kit ${REPO_SLUG}@${REPO_BRANCH}…"
  curl -fsSL "$REPO_TARBALL" | tar -xz -C "$tmp"
  local extracted
  extracted="$(find "$tmp" -maxdepth 1 -type d -name 'Eco-tokens-*' | head -n1)"
  [[ -n "$extracted" && -f "$extracted/templates/mcp-server.py" ]] || die "falha ao extrair kit v2"
  printf '%s\n' "$extracted"
}

cleanup() {
  if [[ -n "$CLEANUP_KIT" && -d "$CLEANUP_KIT" ]]; then
    rm -rf "$CLEANUP_KIT"
  fi
}
trap cleanup EXIT

detect_stack() {
  local root="$1"
  if [[ -f "$root/Cargo.toml" ]]; then echo rust
  elif [[ -f "$root/go.mod" ]]; then echo go
  elif [[ -f "$root/package.json" ]]; then echo node
  elif [[ -f "$root/pyproject.toml" || -f "$root/pytest.ini" || -f "$root/setup.py" || -f "$root/requirements.txt" ]]; then echo python
  elif [[ -f "$root/CMakeLists.txt" || -f "$root/Makefile" ]]; then echo ccpp
  else echo unknown
  fi
}

write_verify_sh() {
  local dest="$1"
  local stack="$2"
  local primary=""
  case "$stack" in
    rust) primary='cargo test --workspace --lib -- --quiet 2>/dev/null || cargo test --lib -- --quiet' ;;
    node) primary='if command -v pnpm >/dev/null 2>&1 && [[ -f pnpm-lock.yaml ]]; then pnpm test; elif command -v yarn >/dev/null 2>&1 && [[ -f yarn.lock ]]; then yarn test; elif command -v npm >/dev/null 2>&1; then npm test --silent; elif command -v node >/dev/null 2>&1; then node -e "const {execSync}=require(\"child_process\"); const t=(require(\"./package.json\").scripts||{}).test; if(!t) process.exit(1); execSync(t,{stdio:\"inherit\"})"; else echo "no node/npm" >&2; exit 127; fi' ;;
    python) primary='if command -v pytest >/dev/null 2>&1; then pytest -q; elif command -v python3 >/dev/null 2>&1; then python3 -m pytest -q; else python -m pytest -q; fi' ;;
    go) primary='go test ./...' ;;
    ccpp) primary='if [[ -f CMakeLists.txt ]]; then cmake --build build && ctest --test-dir build --output-on-failure; elif [[ -f Makefile ]]; then make test || make check; else echo "no C/C++ test target" >&2; exit 1; fi' ;;
    *) primary='echo "VERIFY_FAIL stack=unknown — defina ECO_VERIFY_CMD" >&2; exit 1' ;;
  esac

  cat >"$dest" <<EOF
#!/usr/bin/env bash
# Eco-Tokens v2 verify — stack=${stack}
# smart_trim: 5 head + 15 tail, strip ANSI, payload curto.
set -uo pipefail
ROOT="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")/.." && pwd)"
cd "\$ROOT" || exit 1
STACK="${stack}"
LOG="\$(mktemp -t eco-verify.XXXXXX 2>/dev/null || mktemp)"
trap 'rm -f "\$LOG"' EXIT

strip_ansi() { sed -E 's/\x1b\[[0-9;]*[mK]//g'; }

smart_trim_fail() {
  local clean head tail
  clean="\$(strip_ansi <"\$LOG" | tr -d '\r')"
  head="\$(printf '%s\n' "\$clean" | sed '/^[[:space:]]*\$/d' | head -n 5)"
  tail="\$(printf '%s\n' "\$clean" | sed '/^[[:space:]]*\$/d' | tail -n 15)"
  echo "----- smart_trim (5 head + 15 tail) -----" >&2
  printf '%s\n' "\$head" >&2
  echo "…" >&2
  printf '%s\n' "\$tail" >&2
}

# Git Bash: não deixar link do Git sombrear link.exe MSVC
case "\$(uname -s 2>/dev/null || echo unknown)" in
  MINGW*|MSYS*|CYGWIN*)
    CLEAN=""
    IFS=':'
    for p in \$PATH; do
      case "\$p" in */Git/usr/bin|*/Git/usr/bin/|*/git/usr/bin|*/git/usr/bin/) continue ;; esac
      CLEAN="\${CLEAN:+\$CLEAN:}\$p"
    done
    unset IFS
    export PATH="\$CLEAN"
    ;;
esac

if [[ -n "\${ECO_VERIFY_CMD:-}" ]]; then
  CMD="\$ECO_VERIFY_CMD"
else
  CMD='${primary}'
fi

rc=0
eval "\$CMD" >"\$LOG" 2>&1 || rc=\$?
if [[ "\$rc" -eq 0 ]]; then
  echo "VERIFY_OK stack=\$STACK"
  exit 0
fi
echo "VERIFY_FAIL stack=\$STACK exit=\$rc" >&2
smart_trim_fail
exit 1
EOF
}

merge_mcp_json() {
  local dest="$1"
  local py_bin="$2"
  mkdir -p "$(dirname "$dest")"
  if command -v "$py_bin" >/dev/null 2>&1; then
    "$py_bin" - "$dest" "$py_bin" <<'PY'
import json, sys
from pathlib import Path
dest, py = Path(sys.argv[1]), sys.argv[2]
doc = {"mcpServers": {}}
if dest.exists():
    try:
        doc = json.loads(dest.read_text(encoding="utf-8"))
    except Exception:
        doc = {"mcpServers": {}}
doc.setdefault("mcpServers", {})
doc["mcpServers"]["eco-tokens"] = {
    "command": py,
    "args": [".eco/mcp-server.py"],
    "cwd": "${workspaceFolder}",
}
dest.write_text(json.dumps(doc, indent=2) + "\n", encoding="utf-8")
PY
  else
    cat >"$dest" <<EOF
{
  "mcpServers": {
    "eco-tokens": {
      "command": "python3",
      "args": [".eco/mcp-server.py"],
      "cwd": "\${workspaceFolder}"
    }
  }
}
EOF
  fi
}

install_into() {
  local kit="$1"
  local target="$2"
  [[ -d "$target" ]] || die "alvo inexistente: $target"
  target="$(cd "$target" && pwd)"
  local py
  py="$(resolve_python)" || die "Python 3 necessário (zero-dep MCP)"

  local stack
  stack="$(detect_stack "$target")"
  log "alvo=$target stack=$stack python=$py"

  mkdir -p "$target/.eco" "$target/scripts" "$target/.cursor/rules"

  cp -f "$kit/templates/mcp-server.py" "$target/.eco/mcp-server.py"

  if [[ ! -f "$target/.eco/state.json" || "$FORCE" -eq 1 ]]; then
    cp -f "$kit/templates/state.json" "$target/.eco/state.json"
  else
    log "keep .eco/state.json"
  fi

  # legado: .tasks.json aponta aviso → state canônico é .eco/state.json
  if [[ ! -f "$target/.tasks.json" || "$FORCE" -eq 1 ]]; then
    cat >"$target/.tasks.json" <<'EOF'
{
  "_deprecated": "Eco-Tokens v2: estado canônico em .eco/state.json",
  "see": ".eco/state.json"
}
EOF
  fi

  if [[ ! -f "$target/.cursorrules" || "$FORCE" -eq 1 ]]; then
    cp -f "$kit/templates/rules.markdown" "$target/.cursorrules"
  else
    log "keep .cursorrules"
  fi
  if [[ ! -f "$target/.windsurfrules" || "$FORCE" -eq 1 ]]; then
    cp -f "$kit/templates/rules.markdown" "$target/.windsurfrules"
  else
    log "keep .windsurfrules"
  fi

  cat >"$target/.cursor/rules/eco-tokens.mdc" <<'EOF'
---
description: Eco-Tokens v2 — CHIEF/SPECIALIST/CHECKER + fingerprint circuit breaker
alwaysApply: true
---

# Eco-Tokens v2

MCP `eco-tokens` (Python): `get_current_task`, `update_task_status`, `run_verification`, `search_ast_symbol`.
Estado: `.eco/state.json`. PROIBIDO leitura massiva. Sem `run_verification` PASS ≠ concluído.
BLOCKED → parar em 3 linhas e aguardar humano.
EOF

  write_verify_sh "$target/scripts/verify.sh" "$stack"
  merge_mcp_json "$target/.cursor/mcp.json" "$py"

  chmod +x "$target/scripts/verify.sh" "$target/.eco/mcp-server.py" 2>/dev/null || true

  log "instalado: .eco/mcp-server.py .eco/state.json scripts/verify.sh regras + mcp.json"
  log "próximo: recarregue MCP (python .eco/mcp-server.py) e rode ./scripts/verify.sh"
}

run_self_test() {
  local kit="$1"
  local py
  py="$(resolve_python)" || die "Python 3 necessário para self-test"

  log "py_compile mcp-server.py"
  "$py" -m py_compile "$kit/templates/mcp-server.py" || die "py_compile falhou"
  bash -n "$kit/install.sh" || die "install.sh bash -n falhou"

  local sandbox
  sandbox="$(mktemp -d "${TMPDIR:-/tmp}/eco-tokens-selftest.XXXXXX")"
  cat >"$sandbox/package.json" <<'EOF'
{ "name": "eco-selftest", "private": true, "scripts": { "test": "python -c \"raise SystemExit(0)\"" } }
EOF
  # node-less: force unknown then override verify via ECO — use python stack marker
  rm -f "$sandbox/package.json"
  printf 'pytest\n' >"$sandbox/requirements.txt"
  mkdir -p "$sandbox/tests"
  printf 'def test_ok():\n    assert True\n' >"$sandbox/tests/test_ok.py"

  FORCE=1
  install_into "$kit" "$sandbox"

  [[ -f "$sandbox/.eco/mcp-server.py" ]] || die "mcp-server.py ausente"
  [[ -f "$sandbox/.eco/state.json" ]] || die "state.json ausente"
  [[ -f "$sandbox/scripts/verify.sh" ]] || die "verify.sh ausente"
  grep -q 'smart_trim' "$sandbox/scripts/verify.sh" || die "verify sem smart_trim"
  grep -q 'eco-tokens' "$sandbox/.cursor/mcp.json" || die "mcp.json incompleto"
  grep -q '.eco/mcp-server.py' "$sandbox/.cursor/mcp.json" || die "mcp.json não aponta .eco/"

  "$py" -m py_compile "$sandbox/.eco/mcp-server.py" || die "destino py_compile falhou"
  bash -n "$sandbox/scripts/verify.sh" || die "verify bash -n falhou"

  # smoke MCP initialize
  printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' \
    | (cd "$sandbox" && "$py" .eco/mcp-server.py) | head -n1 | grep -q 'eco-tokens' \
    || die "MCP initialize falhou"

  # dry_run tool
  printf '%s\n' \
    '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"run_verification","arguments":{"dry_run":true}}}' \
    | (cd "$sandbox" && "$py" .eco/mcp-server.py) | grep -q 'dry_run' \
    || die "dry_run falhou"

  # verify runtime se pytest disponível
  if command -v pytest >/dev/null 2>&1; then
    (cd "$sandbox" && bash ./scripts/verify.sh) || die "verify.sh falhou no sandbox"
  else
    log "skip pytest runtime"
  fi

  local rustbox
  rustbox="$(mktemp -d "${TMPDIR:-/tmp}/eco-tokens-rust.XXXXXX")"
  cat >"$rustbox/Cargo.toml" <<'EOF'
[package]
name = "eco_selftest"
version = "0.1.0"
edition = "2021"
[lib]
path = "lib.rs"
EOF
  echo '// stub' >"$rustbox/lib.rs"
  FORCE=1
  install_into "$kit" "$rustbox"
  grep -q 'cargo test' "$rustbox/scripts/verify.sh" || die "verify Rust incompleto"
  bash -n "$rustbox/scripts/verify.sh"

  rm -rf "$sandbox" "$rustbox"
  log "SELF_TEST_OK v2"
}

KIT="$(resolve_kit)"
[[ -f "$KIT/templates/mcp-server.py" ]] || die "kit v2 inválido: $KIT"

if [[ "$SELF_TEST" -eq 1 ]]; then
  run_self_test "$KIT"
  exit 0
fi

if [[ -z "$TARGET" ]]; then
  TARGET="$(pwd)"
fi
install_into "$KIT" "$TARGET"
