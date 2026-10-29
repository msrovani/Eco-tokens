#!/usr/bin/env bash
# Eco-Tokens — instalador / bootstrap automático para qualquer projeto alvo.
# Uso:
#   ./install.sh [--target DIR] [--force]
#   ./install.sh --self-test
#   curl -sSL https://raw.githubusercontent.com/msrovani/Eco-tokens/main/install.sh | bash
set -euo pipefail

REPO_SLUG="${ECO_TOKENS_REPO:-msrovani/Eco-tokens}"
REPO_BRANCH="${ECO_TOKENS_BRANCH:-main}"
REPO_RAW="https://raw.githubusercontent.com/${REPO_SLUG}/${REPO_BRANCH}"
REPO_TARBALL="https://github.com/${REPO_SLUG}/archive/refs/heads/${REPO_BRANCH}.tar.gz"

TARGET=""
FORCE=0
SELF_TEST=0
CLEANUP_KIT=""

usage() {
  cat <<'EOF'
Eco-Tokens installer

  ./install.sh [--target DIR] [--force]
  ./install.sh --self-test

  --target DIR   Projeto destino (default: cwd)
  --force        Sobrescreve .tasks.json e regras existentes
  --self-test    Instala num sandbox temporário e valida artefatos
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

resolve_kit() {
  local self="${BASH_SOURCE[0]:-}"
  if [[ -n "$self" && -f "$self" ]]; then
    local dir
    dir="$(cd "$(dirname "$self")" && pwd)"
    if [[ -d "$dir/templates" && -f "$dir/templates/mcp-server.js" ]]; then
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
  [[ -n "$extracted" && -d "$extracted/templates" ]] || die "falha ao extrair kit"
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
  if [[ -f "$root/Cargo.toml" ]]; then
    echo rust
  elif [[ -f "$root/go.mod" ]]; then
    echo go
  elif [[ -f "$root/CMakeLists.txt" ]] || [[ -f "$root/Makefile" && ( -f "$root/main.c" || -f "$root/main.cpp" || -d "$root/src" ) ]]; then
    # C/C++ heurística leve
    if ls "$root"/*.c "$root"/*.cpp "$root"/src/*.c "$root"/src/*.cpp >/dev/null 2>&1; then
      echo ccpp
    elif [[ -f "$root/package.json" ]]; then
      echo node
    elif [[ -f "$root/pyproject.toml" || -f "$root/pytest.ini" || -f "$root/setup.py" || -f "$root/requirements.txt" ]]; then
      echo python
    else
      echo ccpp
    fi
  elif [[ -f "$root/package.json" ]]; then
    echo node
  elif [[ -f "$root/pyproject.toml" || -f "$root/pytest.ini" || -f "$root/setup.py" || -f "$root/requirements.txt" ]]; then
    echo python
  else
    echo unknown
  fi
}

write_verify_sh() {
  local dest="$1"
  local stack="$2"
  local primary=""
  case "$stack" in
    rust)
      primary='cargo test --workspace --lib -- --quiet 2>/dev/null || cargo test --lib -- --quiet'
      ;;
    node)
      primary='if command -v pnpm >/dev/null 2>&1 && [[ -f pnpm-lock.yaml ]]; then pnpm test; elif command -v yarn >/dev/null 2>&1 && [[ -f yarn.lock ]]; then yarn test; elif command -v npm >/dev/null 2>&1; then npm test --silent; elif command -v node >/dev/null 2>&1; then node -e "const {execSync}=require(\"child_process\"); const t=(require(\"./package.json\").scripts||{}).test; if(!t) process.exit(1); execSync(t,{stdio:\"inherit\"})"; else echo "no node/npm" >&2; exit 127; fi'
      ;;
    python)
      primary='if command -v pytest >/dev/null; then pytest -q; elif command -v python3 >/dev/null; then python3 -m pytest -q; else python -m pytest -q; fi'
      ;;
    go)
      primary='go test ./...'
      ;;
    ccpp)
      primary='if [[ -f CMakeLists.txt ]]; then cmake --build build && ctest --test-dir build --output-on-failure; elif [[ -f Makefile ]]; then make test || make check; else echo "no C/C++ test target" >&2; exit 1; fi'
      ;;
    *)
      primary='echo "VERIFY_FAIL stack=unknown — adicione testes ou defina ECO_VERIFY_CMD" >&2; exit 1'
      ;;
  esac

  cat >"$dest" <<EOF
#!/usr/bin/env bash
# Gerado por Eco-Tokens install.sh — stack=${stack}
# Em falha, imprime só as últimas 20 linhas do log.
set -uo pipefail
ROOT="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")/.." && pwd)"
cd "\$ROOT" || exit 1
STACK="${stack}"
LOG="\$(mktemp -t eco-verify.XXXXXX 2>/dev/null || mktemp)"
trap 'rm -f "\$LOG"' EXIT

# Windows/Git Bash: evita sombrear link.exe do MSVC
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
echo "----- last 20 lines -----" >&2
tail -n 20 "\$LOG" >&2 || true
exit 1
EOF
}

merge_mcp_json() {
  local dest="$1"
  local mcp_rel="${2:-scripts/mcp-server.js}"
  mkdir -p "$(dirname "$dest")"
  if command -v node >/dev/null 2>&1; then
    node - "$dest" "$mcp_rel" <<'NODE'
const fs = require("fs");
const dest = process.argv[2];
const mcpRel = process.argv[3];
let doc = { mcpServers: {} };
if (fs.existsSync(dest)) {
  try { doc = JSON.parse(fs.readFileSync(dest, "utf8")); } catch (_) {}
}
doc.mcpServers = doc.mcpServers || {};
doc.mcpServers["eco-tokens"] = {
  command: "node",
  args: [mcpRel],
  cwd: "${workspaceFolder}",
};
fs.writeFileSync(dest, JSON.stringify(doc, null, 2) + "\n");
NODE
  else
    cat >"$dest" <<EOF
{
  "mcpServers": {
    "eco-tokens": {
      "command": "node",
      "args": ["${mcp_rel}"],
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

  local stack
  stack="$(detect_stack "$target")"
  log "alvo=$target stack=$stack"

  mkdir -p "$target/scripts" "$target/.cursor/rules"

  # MCP server
  cp -f "$kit/templates/mcp-server.js" "$target/scripts/mcp-server.js"

  # tasks
  if [[ ! -f "$target/.tasks.json" || "$FORCE" -eq 1 ]]; then
    cp -f "$kit/templates/tasks.json" "$target/.tasks.json"
  else
    log "keep .tasks.json"
  fi

  # rules
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
  mkdir -p "$target/.cursor/rules"
  cat >"$target/.cursor/rules/eco-tokens.mdc" <<'EOF'
---
description: Eco-Tokens — protocolo CHIEF/SPECIALIST/CHECKER (MCP + verify)
alwaysApply: true
---

# Eco-Tokens

Use MCP `eco-tokens`: `get_current_task`, `update_task_status`, `run_verification`, `search_ast_symbol`.
Proibido ler arquivos/dirs inteiros — use `search_ast_symbol`.
Proibido concluir sem `run_verification`.
2 falhas seguidas de verify → `BLOCKED` + `git checkout .` + parar.
Respostas: 3–5 linhas.
EOF

  # verify.sh customizado
  write_verify_sh "$target/scripts/verify.sh" "$stack"

  # MCP IDE config
  merge_mcp_json "$target/.cursor/mcp.json" "scripts/mcp-server.js"

  chmod +x "$target/scripts/verify.sh" "$target/scripts/mcp-server.js" 2>/dev/null || true

  log "instalado: scripts/mcp-server.js scripts/verify.sh .tasks.json .cursorrules .windsurfrules .cursor/mcp.json"
  log "próximo: recarregue MCP na IDE e rode ./scripts/verify.sh"
}

run_self_test() {
  local kit="$1"
  local sandbox
  sandbox="$(mktemp -d "${TMPDIR:-/tmp}/eco-tokens-selftest.XXXXXX")"
  log "self-test sandbox=$sandbox"

  # mini projeto Node com test no-op
  cat >"$sandbox/package.json" <<'EOF'
{
  "name": "eco-selftest",
  "private": true,
  "scripts": { "test": "node -e \"process.exit(0)\"" }
}
EOF

  FORCE=1
  install_into "$kit" "$sandbox"

  [[ -x "$sandbox/scripts/verify.sh" || -f "$sandbox/scripts/verify.sh" ]] || die "verify.sh ausente"
  [[ -f "$sandbox/scripts/mcp-server.js" ]] || die "mcp-server.js ausente"
  [[ -f "$sandbox/.tasks.json" ]] || die ".tasks.json ausente"
  [[ -f "$sandbox/.cursorrules" ]] || die ".cursorrules ausente"
  [[ -f "$sandbox/.windsurfrules" ]] || die ".windsurfrules ausente"
  [[ -f "$sandbox/.cursor/mcp.json" ]] || die "mcp.json ausente"
  grep -q 'eco-tokens' "$sandbox/.cursor/mcp.json" || die "mcp.json sem eco-tokens"
  grep -q 'VERIFY_OK\|VERIFY_FAIL\|cargo\|npm\|pytest\|go test' "$sandbox/scripts/verify.sh" || die "verify.sh incompleto"

  if command -v node >/dev/null 2>&1; then
    node --check "$sandbox/scripts/mcp-server.js" || die "mcp-server.js sintaxe inválida"
  fi
  bash -n "$sandbox/scripts/verify.sh" || die "verify.sh bash -n falhou"

  # smoke verify no sandbox (Node) — aceita npm ou node puro
  if command -v node >/dev/null 2>&1 || command -v npm >/dev/null 2>&1; then
    if ! (cd "$sandbox" && bash ./scripts/verify.sh); then
      die "verify.sh falhou no sandbox Node"
    fi
  else
    log "skip verify runtime (sem node/npm); sintaxe OK"
  fi

  # segunda stack: Rust stub (só geração + bash -n; não exige toolchain)
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
  grep -q 'cargo test' "$rustbox/scripts/verify.sh" || die "verify Rust sem cargo test"
  bash -n "$rustbox/scripts/verify.sh"

  rm -rf "$sandbox" "$rustbox"
  log "SELF_TEST_OK"
}

KIT="$(resolve_kit)"
[[ -d "$KIT/templates" ]] || die "kit inválido: $KIT"

if [[ "$SELF_TEST" -eq 1 ]]; then
  run_self_test "$KIT"
  exit 0
fi

if [[ -z "$TARGET" ]]; then
  TARGET="$(pwd)"
fi

install_into "$KIT" "$TARGET"
