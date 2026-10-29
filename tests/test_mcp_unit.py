#!/usr/bin/env python3
"""Testes unitários Eco-Tokens 0.3 — smart_trim, estado atômico, anti-loop."""
from __future__ import annotations

import hashlib
import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

KIT = Path(__file__).resolve().parents[1]
MCP_PATH = KIT / "templates" / "mcp-server.py"


def load_mcp():
    spec = importlib.util.spec_from_file_location("eco_mcp", MCP_PATH)
    assert spec and spec.loader
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


class TestSmartTrim(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.m = load_mcp()

    def test_strip_ansi_ecma48(self):
        raw = "\x1b[31mERROR\x1b[0m: fail\x1b[1;32mok\x1b[0m"
        out = self.m.strip_ansi(raw)
        self.assertNotIn("\x1b", out)
        self.assertIn("ERROR", out)

    def test_smart_trim_short_fail_keeps_all(self):
        text = "\n".join(f"L{i}" for i in range(10))
        out = self.m.smart_trim(text, failed=True)
        self.assertIn("L0", out)
        self.assertIn("L9", out)
        self.assertNotIn("…", out)

    def test_smart_trim_long_fail_head_tail(self):
        text = "\n".join(f"LINE_{i:03d}" for i in range(40))
        out = self.m.smart_trim(text, failed=True)
        self.assertIn("LINE_000", out)
        self.assertIn("LINE_004", out)
        self.assertIn("…", out)
        self.assertIn("LINE_039", out)
        self.assertNotIn("LINE_020", out)

    def test_smart_trim_success_last_20(self):
        text = "\n".join(f"OK{i}" for i in range(30))
        out = self.m.smart_trim(text, failed=False)
        self.assertNotIn("OK0", out)
        self.assertIn("OK29", out)


class TestAtomicState(unittest.TestCase):
    def setUp(self):
        self.m = load_mcp()
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        (self.root / ".eco").mkdir()
        self.m.ROOT = self.root
        self.m.ECO_DIR = self.root / ".eco"
        self.m.STATE_PATH = self.m.ECO_DIR / "state.json"
        self.m.STATE_TMP = self.m.ECO_DIR / "state.json.tmp"
        self.m.VERIFY_SH = self.root / "scripts" / "verify.sh"

    def tearDown(self):
        self.tmp.cleanup()

    def test_atomic_write_creates_state(self):
        doc = self.m.default_state()
        self.m.atomic_write_json(doc)
        self.assertTrue(self.m.STATE_PATH.exists())
        self.assertFalse(self.m.STATE_TMP.exists())
        loaded = json.loads(self.m.STATE_PATH.read_text(encoding="utf-8"))
        self.assertEqual(loaded["schema"], 3)

    def test_update_task_status_working_increments(self):
        self.m.ensure_eco()
        r1 = self.m.update_task_status("WORKING", "t1")
        self.assertTrue(r1["ok"])
        self.assertEqual(r1["active_task"]["attempts"], 1)
        r2 = self.m.update_task_status("WORKING", "t2")
        self.assertEqual(r2["active_task"]["attempts"], 2)

    def test_backup_on_rewrite(self):
        self.m.ensure_eco()
        self.m.update_task_status("WORKING", "x")
        bak = self.m.STATE_PATH.with_suffix(".json.bak")
        self.assertTrue(bak.exists())


class TestCircuitBreaker(unittest.TestCase):
    def setUp(self):
        self.m = load_mcp()
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        (self.root / ".eco").mkdir()
        (self.root / "scripts").mkdir()
        # verify that would hang/fail if circuit broken incorrectly
        (self.root / "scripts" / "verify.sh").write_text(
            "#!/usr/bin/env bash\necho SHOULD_NOT_RUN\nexit 99\n",
            encoding="utf-8",
        )
        os.chmod(self.root / "scripts" / "verify.sh", 0o755)
        subprocess.run(["git", "init", "-q"], cwd=self.root, check=True)
        (self.root / "f.txt").write_text("a\n", encoding="utf-8")
        subprocess.run(["git", "add", "-A"], cwd=self.root, check=True)
        subprocess.run(
            ["git", "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-qm", "i"],
            cwd=self.root,
            check=True,
        )
        self.m.ROOT = self.root
        self.m.ECO_DIR = self.root / ".eco"
        self.m.STATE_PATH = self.m.ECO_DIR / "state.json"
        self.m.STATE_TMP = self.m.ECO_DIR / "state.json.tmp"
        self.m.VERIFY_SH = self.root / "scripts" / "verify.sh"

    def tearDown(self):
        self.tmp.cleanup()

    def _diff_hash(self) -> str:
        r = subprocess.run(
            ["git", "diff", "HEAD"], cwd=self.root, capture_output=True
        )
        return hashlib.sha256(r.stdout or b"").hexdigest()

    def test_loop_detected_without_running_verify(self):
        h = self._diff_hash()
        doc = self.m.default_state()
        doc["last_verify_failed"] = True
        doc["last_hash"] = h
        doc["last_failed_hash"] = h
        doc["active_task"]["status"] = "WORKING"
        self.m.atomic_write_json(doc)
        result = self.m.run_verification(dry_run=False)
        self.assertFalse(result["ok"])
        self.assertTrue(result.get("circuit_breaker"))
        self.assertIn("LOOP DETECTADO", result["output"])
        self.assertNotIn("SHOULD_NOT_RUN", result["output"])
        state = self.m.read_state()
        self.assertEqual(state["active_task"]["status"], "BLOCKED")

    def test_dry_run_skips_breaker_build(self):
        h = self._diff_hash()
        doc = self.m.default_state()
        doc["last_verify_failed"] = True
        doc["last_hash"] = h
        doc["active_task"]["status"] = "WORKING"
        self.m.atomic_write_json(doc)
        result = self.m.run_verification(dry_run=True)
        self.assertTrue(result["ok"])
        self.assertTrue(result.get("dry_run"))


class TestMcpProtocol(unittest.TestCase):
    def test_initialize_version_0_3(self):
        proc = subprocess.run(
            [sys.executable, str(MCP_PATH)],
            input='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}\n',
            capture_output=True,
            text=True,
            cwd=str(KIT),
            timeout=10,
            check=False,
        )
        self.assertEqual(proc.returncode, 0)
        line = proc.stdout.strip().splitlines()[0]
        msg = json.loads(line)
        self.assertEqual(msg["result"]["serverInfo"]["version"], "0.3.0")


if __name__ == "__main__":
    unittest.main(verbosity=2)
