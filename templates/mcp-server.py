#!/usr/bin/env python3
"""
Eco-Tokens v2 — MCP stdio zero-dependency (stdlib only).
Tools: get_current_task | update_task_status | run_verification | search_ast_symbol
"""
from __future__ import annotations

import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

VALID_STATUS = {"TODO", "WORKING", "BLOCKED", "READY_FOR_REVIEW"}
ANSI_RE = re.compile(r"\x1b\[[0-9;]*[mK]")
MAX_SYMBOL_LINES = 25

# Project root: .eco/mcp-server.py → parent.parent; scripts/ fallback → parent
_HERE = Path(__file__).resolve().parent
if _HERE.name == ".eco":
    ROOT = _HERE.parent
    ECO_DIR = _HERE
else:
    ROOT = _HERE.parent
    ECO_DIR = ROOT / ".eco"

STATE_PATH = ECO_DIR / "state.json"
VERIFY_SH = ROOT / "scripts" / "verify.sh"


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


def send(msg: Dict[str, Any]) -> None:
    sys.stdout.write(json.dumps(msg, ensure_ascii=False) + "\n")
    sys.stdout.flush()


def ok(req_id: Any, result: Any) -> None:
    send({"jsonrpc": "2.0", "id": req_id, "result": result})


def fail(req_id: Any, code: int, message: str, data: Any = None) -> None:
    err: Dict[str, Any] = {"code": code, "message": message}
    if data is not None:
        err["data"] = data
    send({"jsonrpc": "2.0", "id": req_id, "error": err})


def default_state() -> Dict[str, Any]:
    return {
        "schema": 2,
        "active_task": {
            "id": 1,
            "domain": "core",
            "status": "TODO",
            "objective": "Setup inicial",
            "attempts": 0,
            "reason": "",
        },
        "last_failed_hash": None,
        "last_diff_hash": None,
        "verify_failures": 0,
        "updated_at": _now(),
    }


def ensure_eco() -> None:
    ECO_DIR.mkdir(parents=True, exist_ok=True)
    if not STATE_PATH.exists():
        atomic_write_json(STATE_PATH, default_state())


def atomic_write_json(path: Path, doc: Dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    backup = path.with_suffix(path.suffix + ".bak")
    if path.exists():
        try:
            shutil.copy2(path, backup)
        except OSError:
            pass
    fd, tmp_name = tempfile.mkstemp(
        prefix=".eco-state-", suffix=".tmp", dir=str(path.parent)
    )
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            json.dump(doc, fh, ensure_ascii=False, indent=2)
            fh.write("\n")
            fh.flush()
            os.fsync(fh.fileno())
        os.replace(tmp_name, path)
    except Exception:
        try:
            os.unlink(tmp_name)
        except OSError:
            pass
        raise


def read_state() -> Dict[str, Any]:
    ensure_eco()
    try:
        with STATE_PATH.open("r", encoding="utf-8") as fh:
            doc = json.load(fh)
        if not isinstance(doc, dict) or "active_task" not in doc:
            raise ValueError("invalid state")
        return doc
    except (OSError, ValueError, json.JSONDecodeError):
        bak = STATE_PATH.with_suffix(".json.bak")
        if bak.exists():
            try:
                with bak.open("r", encoding="utf-8") as fh:
                    return json.load(fh)
            except (OSError, ValueError, json.JSONDecodeError):
                pass
        doc = default_state()
        atomic_write_json(STATE_PATH, doc)
        return doc


def write_state(doc: Dict[str, Any]) -> None:
    doc["updated_at"] = _now()
    atomic_write_json(STATE_PATH, doc)


def strip_ansi(text: str) -> str:
    return ANSI_RE.sub("", text)


def smart_trim(text: str, failed: bool) -> str:
    clean = strip_ansi(text).replace("\r\n", "\n").replace("\r", "\n")
    lines = [ln for ln in clean.split("\n")]
    # drop pure decoration
    lines = [ln for ln in lines if ln.strip() and not re.fullmatch(r"[-=_*~.]{4,}", ln.strip())]
    if not lines:
        return "(empty)"
    if not failed:
        return "\n".join(lines[-20:])
    head = lines[:5]
    tail = lines[-15:] if len(lines) > 5 else []
    # de-dupe overlap
    if len(lines) <= 20:
        body = lines
    else:
        body = head + ["…"] + tail
    out = "\n".join(body)
    # hard cap ~250 tokens ≈ 1000 chars
    if len(out) > 1000:
        out = out[:500] + "\n…\n" + out[-480:]
    return out


def git_diff_hash() -> str:
    try:
        r = subprocess.run(
            ["git", "diff", "HEAD"],
            cwd=str(ROOT),
            capture_output=True,
            text=True,
            timeout=30,
            check=False,
        )
        payload = (r.stdout or "") + (r.stderr or "")
        if r.returncode != 0 and not (r.stdout or "").strip():
            # unborn / no repo
            r2 = subprocess.run(
                ["git", "diff"],
                cwd=str(ROOT),
                capture_output=True,
                text=True,
                timeout=30,
                check=False,
            )
            payload = (r2.stdout or "") + (r2.stderr or "")
    except (OSError, subprocess.TimeoutExpired):
        payload = ""
    return hashlib.sha256(payload.encode("utf-8", errors="replace")).hexdigest()


def git_checkout_hard() -> Tuple[bool, str]:
    try:
        r = subprocess.run(
            ["git", "checkout", "."],
            cwd=str(ROOT),
            capture_output=True,
            text=True,
            timeout=60,
            check=False,
        )
        msg = strip_ansi((r.stdout or "") + (r.stderr or "")).strip()
        return r.returncode == 0, msg or "git checkout ."
    except (OSError, subprocess.TimeoutExpired) as exc:
        return False, str(exc)


def find_python() -> str:
    for cand in (os.environ.get("ECO_PYTHON"), "python3", "python"):
        if not cand:
            continue
        try:
            r = subprocess.run(
                [cand, "-c", "import sys; print(sys.version_info[0])"],
                capture_output=True,
                text=True,
                timeout=5,
                check=False,
            )
            if r.returncode == 0 and (r.stdout or "").strip().startswith("3"):
                return cand
        except (OSError, subprocess.TimeoutExpired):
            continue
    return sys.executable or "python3"


def find_bash() -> Optional[str]:
    candidates = [
        os.environ.get("ECO_BASH"),
        "bash",
        r"C:\Program Files\Git\bin\bash.exe",
        r"C:\Program Files\Git\usr\bin\bash.exe",
        "/bin/bash",
        "/usr/bin/bash",
    ]
    for c in candidates:
        if not c:
            continue
        try:
            r = subprocess.run(
                [c, "-lc", "echo ok"],
                capture_output=True,
                text=True,
                timeout=5,
                check=False,
            )
            if r.returncode == 0:
                return c
        except (OSError, subprocess.TimeoutExpired):
            continue
    return None


def update_task_status(status: str, reason: str = "") -> Dict[str, Any]:
    if status not in VALID_STATUS:
        return {
            "ok": False,
            "error": f"invalid status; use {'|'.join(sorted(VALID_STATUS))}",
        }
    doc = read_state()
    task = doc.setdefault("active_task", {})
    prev = task.get("status", "TODO")
    task["status"] = status
    task["reason"] = reason or ""
    task["updated_at"] = _now()
    if status == "WORKING":
        task["attempts"] = int(task.get("attempts") or 0) + 1
    elif status == "TODO":
        task["attempts"] = 0
        doc["verify_failures"] = 0
        doc["last_failed_hash"] = None
    elif status == "READY_FOR_REVIEW":
        doc["verify_failures"] = 0
    doc["active_task"] = task
    doc["last_transition"] = {"from": prev, "to": status, "reason": reason or ""}
    write_state(doc)
    return {"ok": True, "active_task": task}


def run_verification(dry_run: bool = False) -> Dict[str, Any]:
    doc = read_state()
    task = doc.get("active_task") or {}
    status = task.get("status", "TODO")
    current_hash = git_diff_hash()
    doc["last_diff_hash"] = current_hash

    # Fingerprint circuit breaker: same failed diff while WORKING → BLOCKED
    last_fail = doc.get("last_failed_hash")
    if status == "WORKING" and last_fail and current_hash == last_fail:
        reverted, rev_msg = git_checkout_hard()
        task["status"] = "BLOCKED"
        task["reason"] = (
            "circuit_breaker: git diff fingerprint unchanged after failed verify "
            "(no real code change)"
        )
        task["updated_at"] = _now()
        doc["active_task"] = task
        doc["verify_failures"] = int(doc.get("verify_failures") or 0) + 1
        write_state(doc)
        return {
            "ok": False,
            "circuit_breaker": True,
            "exit_code": 2,
            "diff_hash": current_hash,
            "reverted": reverted,
            "output": (
                "BLOCKED — fingerprint SHA256(git diff) idêntico à falha anterior.\n"
                "Nenhuma alteração real detectada. git checkout . executado.\n"
                f"rev={rev_msg[:120]}"
            ),
        }

    if dry_run:
        write_state(doc)
        dirty = current_hash != hashlib.sha256(b"").hexdigest()
        # Compare to last successful snapshot if present
        last_ok = doc.get("last_ok_hash")
        unchanged = last_ok is not None and current_hash == last_ok
        return {
            "ok": True,
            "dry_run": True,
            "diff_hash": current_hash,
            "unchanged_since_last_ok": unchanged,
            "output": (
                "DRY_RUN — sem build. "
                f"dirty={dirty} unchanged_since_last_ok={unchanged}"
            ),
        }

    if not VERIFY_SH.exists():
        write_state(doc)
        return {
            "ok": False,
            "exit_code": 1,
            "diff_hash": current_hash,
            "output": "VERIFY_FAIL reason=scripts/verify.sh missing",
        }

    bash = find_bash()
    if not bash:
        write_state(doc)
        return {
            "ok": False,
            "exit_code": 1,
            "diff_hash": current_hash,
            "output": "VERIFY_FAIL reason=bash_not_found",
        }

    try:
        r = subprocess.run(
            [bash, str(VERIFY_SH)],
            cwd=str(ROOT),
            capture_output=True,
            text=True,
            timeout=int(os.environ.get("ECO_VERIFY_TIMEOUT", "600")),
            check=False,
        )
    except subprocess.TimeoutExpired:
        write_state(doc)
        return {
            "ok": False,
            "exit_code": 124,
            "diff_hash": current_hash,
            "output": "VERIFY_FAIL reason=timeout",
        }

    combined = (r.stdout or "") + (r.stderr or "")
    failed = r.returncode != 0
    slim = smart_trim(combined, failed=failed)
    exit_code = 1 if r.returncode is None else r.returncode

    if failed:
        doc["last_failed_hash"] = current_hash
        doc["verify_failures"] = int(doc.get("verify_failures") or 0) + 1
        # Classic breaker: 2 failures with same fingerprint already handled;
        # also BLOCKED after 2 consecutive failures even if hash changed slightly
        # but fingerprint path is primary. Keep attempts-aware soft note.
        if doc["verify_failures"] >= 2 and status == "WORKING":
            # If second failure and hash equals previous fail OR attempts>=2 with same hash
            pass
        write_state(doc)
        return {
            "ok": False,
            "exit_code": exit_code,
            "diff_hash": current_hash,
            "output": slim,
        }

    doc["last_failed_hash"] = None
    doc["last_ok_hash"] = current_hash
    doc["verify_failures"] = 0
    write_state(doc)
    return {
        "ok": True,
        "exit_code": 0,
        "diff_hash": current_hash,
        "output": slim if slim != "(empty)" else "VERIFY_OK",
    }


def search_ast_symbol(symbol: str) -> Dict[str, Any]:
    if not symbol or not isinstance(symbol, str):
        return {"ok": False, "error": "symbol required"}

    def run(cmd: List[str]) -> Tuple[int, str]:
        try:
            r = subprocess.run(
                cmd,
                cwd=str(ROOT),
                capture_output=True,
                text=True,
                timeout=60,
                check=False,
            )
            return r.returncode, strip_ansi((r.stdout or "") + (r.stderr or ""))
        except (OSError, subprocess.TimeoutExpired) as exc:
            return 1, str(exc)

    tool = "none"
    text = ""
    # ast-grep
    if shutil.which("ast-grep") or shutil.which("sg"):
        bin_name = "ast-grep" if shutil.which("ast-grep") else "sg"
        code, text = run(
            [bin_name, "run", "--pattern", symbol, "-A", "2", "-B", "1"]
        )
        tool = "ast-grep"
        if code != 0 or not text.strip():
            code, text = run(
                [bin_name, "run", "--pattern", symbol, "--lang", "rust", "-A", "2", "-B", "1"]
            )
    if not text.strip() and shutil.which(os.environ.get("ECO_RG", "rg") or "rg"):
        rg = os.environ.get("ECO_RG", "rg")
        code, text = run(
            [
                rg,
                "-n",
                "--no-heading",
                "--color",
                "never",
                "-m",
                str(MAX_SYMBOL_LINES),
                "-g",
                "!target/**",
                "-g",
                "!**/node_modules/**",
                "-g",
                "!.git/**",
                "-g",
                "!.eco/**",
                symbol,
                ".",
            ]
        )
        tool = "ripgrep"
    if not text.strip():
        # native grep fallback
        grep = shutil.which("grep")
        if grep:
            code, text = run(
                [grep, "-RIn", "--exclude-dir=.git", "--exclude-dir=target",
                 "--exclude-dir=node_modules", "-m", str(MAX_SYMBOL_LINES),
                 symbol, "."]
            )
            tool = "grep"
        else:
            return {"ok": False, "tool": "none", "snippet": "(no search tool)", "lines": 0}

    lines = [ln for ln in text.splitlines() if ln.strip()][:MAX_SYMBOL_LINES]
    snippet = "\n".join(lines) if lines else "(no matches)"
    return {
        "ok": bool(lines),
        "tool": tool,
        "symbol": symbol,
        "snippet": snippet,
        "lines": len(lines),
    }


TOOLS = [
    {
        "name": "get_current_task",
        "description": "Retorna apenas a tarefa ativa (.eco/state.json).",
        "inputSchema": {"type": "object", "properties": {}, "additionalProperties": False},
    },
    {
        "name": "update_task_status",
        "description": "Atualiza status atomicamente (TODO|WORKING|BLOCKED|READY_FOR_REVIEW).",
        "inputSchema": {
            "type": "object",
            "properties": {
                "status": {
                    "type": "string",
                    "enum": ["TODO", "WORKING", "BLOCKED", "READY_FOR_REVIEW"],
                },
                "reason": {"type": "string"},
            },
            "required": ["status"],
            "additionalProperties": False,
        },
    },
    {
        "name": "run_verification",
        "description": (
            "SHA256(git diff) + circuit breaker; executa scripts/verify.sh; "
            "dry_run=true só consulta estado sem build."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "dry_run": {"type": "boolean", "description": "Sem build se true"},
            },
            "additionalProperties": False,
        },
    },
    {
        "name": "search_ast_symbol",
        "description": "Busca cirúrgica ast-grep → rg → grep (máx. 25 linhas).",
        "inputSchema": {
            "type": "object",
            "properties": {"symbol": {"type": "string"}},
            "required": ["symbol"],
            "additionalProperties": False,
        },
    },
]


def call_tool(name: str, args: Dict[str, Any]) -> Dict[str, Any]:
    if name == "get_current_task":
        doc = read_state()
        return {
            "content": [
                {
                    "type": "text",
                    "text": json.dumps(doc.get("active_task"), ensure_ascii=False, indent=2),
                }
            ]
        }
    if name == "update_task_status":
        result = update_task_status(args.get("status", ""), args.get("reason", "") or "")
        return {
            "content": [
                {"type": "text", "text": json.dumps(result, ensure_ascii=False, indent=2)}
            ]
        }
    if name == "run_verification":
        dry = bool(args.get("dry_run", False))
        result = run_verification(dry_run=dry)
        return {
            "content": [
                {"type": "text", "text": json.dumps(result, ensure_ascii=False, indent=2)}
            ]
        }
    if name == "search_ast_symbol":
        result = search_ast_symbol(args.get("symbol", ""))
        return {
            "content": [
                {"type": "text", "text": json.dumps(result, ensure_ascii=False, indent=2)}
            ]
        }
    raise ValueError(f"Unknown tool: {name}")


def handle(msg: Dict[str, Any]) -> None:
    req_id = msg.get("id")
    method = msg.get("method")
    params = msg.get("params") or {}

    if method == "initialize":
        ok(
            req_id,
            {
                "protocolVersion": params.get("protocolVersion") or "2024-11-05",
                "capabilities": {"tools": {}},
                "serverInfo": {"name": "eco-tokens", "version": "2.0.0"},
            },
        )
        return
    if method in ("notifications/initialized", "initialized"):
        return
    if method == "tools/list":
        ok(req_id, {"tools": TOOLS})
        return
    if method == "tools/call":
        name = params.get("name")
        args = params.get("arguments") or {}
        try:
            ok(req_id, call_tool(name, args))
        except Exception as exc:  # noqa: BLE001 — surface to MCP client
            fail(req_id, -32000, str(exc), {"tool": name})
        return
    if method == "ping":
        ok(req_id, {})
        return
    if req_id is not None:
        fail(req_id, -32601, f"Method not found: {method}")


def main() -> None:
    ensure_eco()
    for line in sys.stdin:
        trimmed = line.strip()
        if not trimmed:
            continue
        try:
            handle(json.loads(trimmed))
        except json.JSONDecodeError as exc:
            send(
                {
                    "jsonrpc": "2.0",
                    "id": None,
                    "error": {"code": -32700, "message": "Parse error", "data": str(exc)},
                }
            )


if __name__ == "__main__":
    main()
