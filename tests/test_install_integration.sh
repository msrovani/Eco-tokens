#!/usr/bin/env bash
# Integração: install --self-test + unitários Python.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo "[test] py_compile"
python3 -m py_compile templates/mcp-server.py

echo "[test] bash -n install.sh"
bash -n install.sh

echo "[test] unit"
python3 -m unittest discover -s tests -p 'test_*.py' -v

echo "[test] install --self-test"
chmod +x install.sh
./install.sh --self-test

echo "[test] INTEGRATION_OK"
