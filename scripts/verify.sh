#!/usr/bin/env bash
# Eco-Tokens — verificação determinística enxuta (exit 0/1).
# Detecta a stack do projeto consumidor; no kit puro, roda smoke do próprio kit.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

sanitize_windows_path() {
  case "$(uname -s 2>/dev/null || echo unknown)" in
    MINGW*|MSYS*|CYGWIN*) ;;
    *) return 0 ;;
  esac
  local cleaned="" part
  IFS=':'
  for part in $PATH; do
    case "$part" in
      */Git/usr/bin|*/Git/usr/bin/|*/git/usr/bin|*/git/usr/bin/) continue ;;
    esac
    if [[ -z "$cleaned" ]]; then
      cleaned="$part"
    else
      cleaned="${cleaned}:${part}"
    fi
  done
  unset IFS
  export PATH="$cleaned"
}

LOG="$(mktemp -t eco-verify.XXXXXX 2>/dev/null || mktemp)"
cleanup() { rm -f "$LOG"; }
trap cleanup EXIT

STACK="unknown"
CMD_LABEL="none"

run_silent() {
  local rc=0
  CMD_LABEL="$*"
  "$@" >"$LOG" 2>&1 || rc=$?
  if [[ "$rc" -eq 0 ]]; then
    echo "VERIFY_OK stack=${STACK} cmd=${CMD_LABEL}"
    return 0
  fi
  echo "VERIFY_FAIL stack=${STACK} cmd=${CMD_LABEL} exit=${rc}" >&2
  echo "----- last 20 lines -----" >&2
  tail -n 20 "$LOG" >&2 || true
  return 1
}

kit_smoke() {
  STACK="eco-kit"
  CMD_LABEL="kit-smoke"
  {
    bash -n "$ROOT/scripts/verify.sh"
    bash -n "$ROOT/scripts/install-into.sh"
    if command -v node >/dev/null 2>&1; then
      node --check "$ROOT/scripts/mcp-server.js"
    fi
    if command -v python3 >/dev/null 2>&1; then
      python3 -c "import json; json.load(open('.tasks.json',encoding='utf-8'))"
    elif command -v python >/dev/null 2>&1; then
      python -c "import json; json.load(open('.tasks.json',encoding='utf-8'))"
    elif command -v node >/dev/null 2>&1; then
      node -e "JSON.parse(require('fs').readFileSync('.tasks.json','utf8'))"
    else
      test -s .tasks.json
    fi
    test -f .cursorrules
    test -f .cursor/mcp.json
    test -f scripts/mcp-server.js
  } >"$LOG" 2>&1
  local rc=$?
  if [[ "$rc" -eq 0 ]]; then
    echo "VERIFY_OK stack=${STACK} cmd=${CMD_LABEL}"
    return 0
  fi
  echo "VERIFY_FAIL stack=${STACK} cmd=${CMD_LABEL} exit=${rc}" >&2
  echo "----- last 20 lines -----" >&2
  tail -n 20 "$LOG" >&2 || true
  return 1
}

# --- Rust ---
if [[ -f Cargo.toml ]]; then
  STACK="rust"
  sanitize_windows_path
  PKG="${ECO_VERIFY_PACKAGE:-}"
  rust_try() {
    local label="$1"
    shift
    CMD_LABEL="$label"
    local rc=0
    "$@" >"$LOG" 2>&1 || rc=$?
    [[ "$rc" -eq 0 ]]
  }
  if [[ "${ECO_VERIFY_FULL:-0}" == "1" ]]; then
    if rust_try "cargo test --workspace --lib" \
      cargo test --workspace --lib -- --quiet; then
      echo "VERIFY_OK stack=${STACK} cmd=${CMD_LABEL}"
      exit 0
    fi
  elif [[ -n "$PKG" ]]; then
    if rust_try "cargo test -p ${PKG} --lib" \
      cargo test -p "$PKG" --lib -- --quiet; then
      echo "VERIFY_OK stack=${STACK} cmd=${CMD_LABEL}"
      exit 0
    fi
  else
    if rust_try "cargo test --lib" cargo test --lib -- --quiet; then
      echo "VERIFY_OK stack=${STACK} cmd=${CMD_LABEL}"
      exit 0
    fi
  fi
  if grep -qiE 'link\.exe|linking with|missing operand' "$LOG" 2>/dev/null; then
    if [[ -n "$PKG" ]]; then
      if rust_try "cargo check -p ${PKG} (fallback-link)" cargo check -p "$PKG"; then
        echo "VERIFY_OK stack=${STACK} cmd=${CMD_LABEL}"
        exit 0
      fi
    elif rust_try "cargo check (fallback-link)" cargo check; then
      echo "VERIFY_OK stack=${STACK} cmd=${CMD_LABEL}"
      exit 0
    fi
  fi
  echo "VERIFY_FAIL stack=${STACK} cmd=${CMD_LABEL}" >&2
  echo "----- last 20 lines -----" >&2
  tail -n 20 "$LOG" >&2 || true
  exit 1
fi

# --- Node (projeto consumidor com testes; ignore kit package.json sem script test) ---
if [[ -f package.json ]]; then
  has_test=0
  if command -v node >/dev/null 2>&1; then
    if node -e "const p=require('./package.json'); process.exit(p.scripts&&p.scripts.test?0:1)"; then
      has_test=1
    fi
  elif grep -q '"test"' package.json; then
    has_test=1
  fi
  if [[ "$has_test" -eq 1 ]]; then
    STACK="node"
    if [[ -f pnpm-lock.yaml ]] && command -v pnpm >/dev/null 2>&1; then
      run_silent pnpm test; exit $?
    elif [[ -f yarn.lock ]] && command -v yarn >/dev/null 2>&1; then
      run_silent yarn test; exit $?
    elif command -v npm >/dev/null 2>&1; then
      run_silent npm test --silent; exit $?
    else
      echo "VERIFY_FAIL stack=node reason=no_npm_yarn_pnpm" >&2
      exit 1
    fi
  fi
fi

# --- Python ---
if [[ -f pyproject.toml ]] || [[ -f pytest.ini ]] || [[ -f setup.py ]] || [[ -f requirements.txt ]]; then
  STACK="python"
  if command -v pytest >/dev/null 2>&1; then
    run_silent pytest -q; exit $?
  elif command -v python3 >/dev/null 2>&1; then
    run_silent python3 -m pytest -q; exit $?
  elif command -v python >/dev/null 2>&1; then
    run_silent python -m pytest -q; exit $?
  else
    echo "VERIFY_FAIL stack=python reason=no_pytest" >&2
    exit 1
  fi
fi

# --- Go ---
if [[ -f go.mod ]]; then
  STACK="go"
  run_silent go test ./...
  exit $?
fi

# --- Kit puro ---
kit_smoke
exit $?
