"""Isolated provider/protocol, cache, and account-tier regression checks."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location(
    "usage", Path(__file__).resolve().parents[1] / "defaults/shell/agent-usage.py")
usage = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(usage)


class AgentUsageTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.env = patch.dict(os.environ, {
            "HOME": str(self.root), "XDG_CACHE_HOME": str(self.root / "cache"),
            "XDG_CONFIG_HOME": str(self.root / "config"), "CLAUDE_CONFIG_DIR": str(self.root / "claude")})
        self.env.start()
        self.addCleanup(self.tmp.cleanup)
        self.addCleanup(self.env.stop)

    def test_windows_preserve_zero_missing_duration_and_multiple_buckets(self):
        windows = usage.codex_windows({"rateLimitsByLimitId": {
            "codex": {"primary": {"usedPercent": 100, "windowDurationMins": 10080, "resetsAt": 10}},
            "other": {"limitName": "Other model", "primary": {"usedPercent": 0},
                      "secondary": {"usedPercent": None}}}})
        self.assertEqual([w["remaining"] for w in windows], [0, 100])
        self.assertEqual(windows[0]["label"], "codex · 7-day")
        self.assertEqual(windows[0]["resetsAt"], 10)  # expired != replenished
        self.assertIsNone(windows[1]["resetsAt"])
        self.assertEqual(usage.codex_windows({"rateLimits": {"primary": None}}), [])

    def test_invalid_numbers_are_not_reported_as_allowance(self):
        for value in (None, True, "20", float("nan"), float("inf"), -1):
            self.assertIsNone(usage.window("test", {"used": value}, "used", "reset"))
        self.assertEqual(usage.window("spend", {"used": 125}, "used", "reset")["remaining"], 0)

    def fake_codex(self):
        folder = self.root / "bin"
        folder.mkdir(exist_ok=True)
        binary = folder / "codex"
        binary.write_text('''#!/usr/bin/env python3
import json, os, sys
for line in sys.stdin:
    q = json.loads(line)
    method = q['method']
    if method == 'initialized':
        continue
    if method == 'initialize':
        result = {}
    elif method == 'account/read':
        account = os.environ.get('TEST_ACCOUNT', 'alice')
        result = {'account': None if account == 'none' else {
            'type': os.environ.get('TEST_AUTH_TYPE', 'chatgpt'), 'email': account, 'planType': 'pro'}}
    elif method == 'account/rateLimits/read':
        if os.environ.get('TEST_RATE_ERROR'):
            print(json.dumps({'id': q['id'], 'error': {'message': 'private provider error'}}), flush=True)
            continue
        result = {'rateLimits': {'primary': {'usedPercent': 23, 'windowDurationMins': 300, 'resetsAt': 2000}}}
    else:
        sys.exit('Unexpected request (must never start inference): ' + method)
    print(json.dumps({'method': 'notice', 'params': {}}), flush=True)
    print(json.dumps({'id': q['id'], 'result': result}), flush=True)
''')
        binary.chmod(0o755)
        self.path = patch.dict(os.environ, {"PATH": str(folder) + os.pathsep + os.environ["PATH"]})
        self.path.start()
        self.addCleanup(self.path.stop)

    def test_codex_rpc_account_change_signout_and_failure(self):
        self.fake_codex()
        first = usage.read_codex({})
        self.assertEqual(first["windows"][0]["remaining"], 77)
        self.assertNotIn("alice", json.dumps(first))
        with patch.dict(os.environ, {"TEST_RATE_ERROR": "1"}):
            stale = usage.read_codex(first)
            self.assertEqual(stale["windows"], first["windows"])
            self.assertEqual(stale["status"], "error")
            self.assertNotIn("private", json.dumps(stale))
            with patch.dict(os.environ, {"TEST_ACCOUNT": "bob"}):
                self.assertEqual(usage.read_codex(first)["windows"], [])
        with patch.dict(os.environ, {"TEST_ACCOUNT": "none"}):
            signed_out = usage.read_codex(first)
            self.assertFalse(signed_out["authenticated"])
            self.assertEqual(signed_out["windows"], [])
        with patch.dict(os.environ, {"TEST_AUTH_TYPE": "apiKey"}):
            self.assertEqual(usage.read_codex(first)["status"], "unsupported")

    def test_codex_timeout_does_not_leave_child(self):
        self.fake_codex()
        with usage.Rpc() as rpc:
            rpc.deadline = 0
            with self.assertRaises(TimeoutError):
                rpc.request("initialize", {})
        self.assertIsNotNone(rpc.process.poll())

    def test_cache_throttles_refresh_and_handles_corruption(self):
        with patch.object(usage, "read_codex", return_value=usage.base("codex", "Codex")) as codex, \
                patch.object(usage, "read_claude", return_value=usage.base("claude", "Claude")), \
                patch.object(usage.time, "time", return_value=1000):
            usage.status()
            usage.status()
            usage.status(True)
            self.assertEqual(codex.call_count, 1)
            with patch.object(usage.time, "time", return_value=1020):
                usage.status(True)
            self.assertEqual(codex.call_count, 2)
            path = usage.cache_dir() / "status.json"
            path.write_text("[]")
            usage.status()
            self.assertEqual(codex.call_count, 3)
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)

    def fake_claude(self):
        folder = self.root / "bin"
        folder.mkdir(exist_ok=True)
        binary = folder / "claude"
        binary.write_text('''#!/usr/bin/env python3
import json, os, sys
if sys.argv[1:3] == ['auth', 'status']:
    print(json.dumps({'loggedIn': True, 'authMethod': 'claude.ai', 'email': os.environ.get('TEST_ACCOUNT', 'alice'), 'orgId': 'org', 'subscriptionType': 'max'}))
    sys.exit()
assert '--safe-mode' in sys.argv and '--no-session-persistence' in sys.argv
assert sys.argv[sys.argv.index('--tools')+1] == ''
assert '--strict-mcp-config' in sys.argv
for line in sys.stdin:
    q = json.loads(line)
    assert q['type'] == 'control_request', 'Never send a user prompt'
    subtype = q['request']['subtype']
    if subtype == 'initialize':
        result = {}
    elif subtype == 'get_usage':
        assert q['request']['skip_behaviors'] is True
        if os.environ.get('TEST_RATE_ERROR'):
            print(json.dumps({'type': 'control_response', 'response': {'subtype': 'error', 'request_id': q['request_id'], 'error': 'private error'}}), flush=True)
            continue
        result = {'rate_limits_available': True, 'rate_limits': {'limits': [
            {'kind': 'weekly_all', 'percent': 41, 'resets_at': '2030-01-01T00:00:00Z'},
            {'kind': 'weekly_scoped', 'percent': 64, 'resets_at': '2030-01-01T00:00:00Z', 'scope': {'model': {'display_name': 'Fable'}}}]}}
    else:
        raise AssertionError(subtype)
    print(json.dumps({'type': 'control_response', 'response': {'subtype': 'success', 'request_id': q['request_id'], 'response': result}}), flush=True)
''')
        binary.chmod(0o755)
        self.path = patch.dict(os.environ, {"PATH": str(folder) + os.pathsep + os.environ["PATH"]})
        self.path.start()
        self.addCleanup(self.path.stop)

    def test_claude_control_protocol_dual_weekly_limits_and_account_change(self):
        self.fake_claude()
        first = usage.read_claude({})
        self.assertEqual(first["status"], "ready")
        self.assertEqual([w["remaining"] for w in first["windows"]], [59, 36])
        self.assertEqual([w["label"] for w in first["windows"]], ["Weekly · All models", "Weekly · Fable only"])
        self.assertNotIn("alice", json.dumps(first))
        with patch.dict(os.environ, {"TEST_RATE_ERROR": "1"}):
            self.assertEqual(usage.read_claude(first)["windows"], first["windows"])
            with patch.dict(os.environ, {"TEST_ACCOUNT": "bob"}):
                self.assertEqual(usage.read_claude(first)["windows"], [])
        with patch.object(usage, "claude_auth", return_value={"loggedIn": False}):
            self.assertFalse(usage.read_claude(first)["authenticated"])

    def test_claude_legacy_response_and_scoped_deduplication(self):
        rates = {"five_hour": {"utilization": 0, "resets_at": None},
                 "seven_day": {"utilization": 100, "resets_at": "2030-01-01T00:00:00Z"},
                 "model_scoped": [{"display_name": "Fable", "utilization": 50, "resets_at": None}],
                 "limits": [{"kind": "weekly_scoped", "percent": 50, "resets_at": None,
                             "scope": {"model": {"display_name": "Fable"}}}]}
        windows = usage.claude_windows(rates)
        self.assertEqual(len(windows), 3)
        self.assertEqual(sum(w["label"] == "Weekly · Fable only" for w in windows), 1)
        self.assertEqual(usage.claude_windows({}), [])
        self.assertIsNone(usage.reset_timestamp("not-a-date"))
        self.assertEqual(usage.reset_timestamp("2030-01-01T00:00:00+00:00"), 1893456000)

    def test_max_tier_requires_matching_account_and_known_tier(self):
        auth = {"subscriptionType": "max", "email": "alice", "orgId": "org"}
        profile = {"emailAddress": "alice", "organizationUuid": "org",
                   "organizationRateLimitTier": "default_claude_max_5x"}
        path = Path(os.environ["CLAUDE_CONFIG_DIR"]) / ".claude.json"
        usage.write_json(path, {"oauthAccount": profile})
        self.assertEqual(usage.claude_plan(auth), "max_5x")
        profile["userRateLimitTier"] = "default_claude_max_20x"
        usage.write_json(path, {"oauthAccount": profile})
        self.assertEqual(usage.claude_plan(auth), "max_20x")
        self.assertEqual(usage.claude_plan(dict(auth, email="bob")), "max")
        self.assertEqual(usage.claude_plan(dict(auth, orgId="different")), "max")
        profile["userRateLimitTier"] = "unknown-tier"
        usage.write_json(path, {"oauthAccount": profile})
        self.assertEqual(usage.claude_plan(auth), "max")
        path.unlink()
        self.assertEqual(usage.claude_plan(auth), "max")
        self.assertEqual(usage.claude_plan(dict(auth, subscriptionType="pro")), "pro")

    def test_api_login_is_explicit_and_missing_cli_starts_nothing(self):
        with patch.object(usage.shutil, "which", return_value="/fake/claude"), \
                patch.object(usage, "claude_auth", return_value={"loggedIn": True, "authMethod": "api_key"}):
            row = usage.read_claude({})
        self.assertEqual(row["status"], "unsupported")
        self.assertEqual(row["windows"], [])
        with patch.object(usage.shutil, "which", return_value=None), patch.object(usage.subprocess, "Popen") as spawn:
            self.assertFalse(usage.read_codex({})["installed"])
            self.assertFalse(usage.read_claude({})["installed"])
            spawn.assert_not_called()


if __name__ == "__main__":
    unittest.main()
