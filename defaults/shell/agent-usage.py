#!/usr/bin/env python3
"""Read coding-agent allowances without inference calls or credential access."""

import argparse
import contextlib
from datetime import datetime
import fcntl
import hashlib
import json
import math
import os
from pathlib import Path
import selectors
import shutil
import signal
import subprocess
import sys
import tempfile
import time


def directory(variable, fallback):
    return Path(os.environ.get(variable) or Path.home() / fallback)


def cache_dir():
    return directory("XDG_CACHE_HOME", ".cache") / "blankweave/agent-usage"


def identity(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True).encode()).hexdigest()


def read_json(path, default=None):
    try:
        value = json.loads(path.read_text())
        return value if isinstance(value, dict) else default
    except (OSError, ValueError):
        return default


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(prefix=".usage-", dir=path.parent)
    try:
        with os.fdopen(fd, "w") as stream:
            json.dump(value, stream, allow_nan=False)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)


@contextlib.contextmanager
def lock(path, blocking=True):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a") as stream:
        try:
            fcntl.flock(stream, fcntl.LOCK_EX | (0 if blocking else fcntl.LOCK_NB))
        except BlockingIOError:
            yield False
        else:
            try:
                yield True
            finally:
                fcntl.flock(stream, fcntl.LOCK_UN)


def finite(value):
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)


def window(label, data, used_key, reset_key):
    if not isinstance(data, dict) or not finite(data.get(used_key)):
        return None
    used = data[used_key]
    if used < 0:
        return None
    reset = data.get(reset_key)
    return {"label": str(label)[:80], "remaining": max(0, 100 - used),
            "resetsAt": reset if finite(reset) and reset > 0 else None}


def duration_label(minutes, fallback):
    if not finite(minutes) or minutes <= 0:
        return fallback
    if minutes % 1440 == 0:
        return f"{minutes / 1440:g}-day"
    if minutes % 60 == 0:
        return f"{minutes / 60:g}-hour"
    return f"{minutes:g}-minute"


def codex_windows(payload):
    buckets = payload.get("rateLimitsByLimitId")
    if not isinstance(buckets, dict) or not buckets:
        buckets = {"codex": payload.get("rateLimits", {})}
    result = []
    for key, bucket in buckets.items():
        if not isinstance(bucket, dict):
            continue
        prefix = str(bucket.get("limitName") or key) + " · " if len(buckets) > 1 else ""
        for name, fallback in (("primary", "Primary"), ("secondary", "Secondary")):
            data = bucket.get(name)
            if isinstance(data, dict):
                label = prefix + duration_label(data.get("windowDurationMins"), fallback)
                entry = window(label, data, "usedPercent", "resetsAt")
                if entry:
                    result.append(entry)
        spend = bucket.get("individualLimit")
        if isinstance(spend, dict) and finite(spend.get("remainingPercent")):
            entry = window(prefix + "Spend limit", {
                "usedPercent": 100 - spend["remainingPercent"], "resetsAt": spend.get("resetsAt")
            }, "usedPercent", "resetsAt")
            if entry:
                result.append(entry)
    return result


def reset_timestamp(value):
    if isinstance(value, str):
        try:
            value = datetime.fromisoformat(value.replace("Z", "+00:00")).timestamp()
        except ValueError:
            return None
    return value if finite(value) and value > 0 else None


def claude_windows(rates):
    """Prefer the server's named limit rows; retain older CLI response support."""
    result = []
    labels = set()

    def add(label, data, used="utilization"):
        if not isinstance(data, dict) or label in labels:
            return
        entry = window(label, {"used": data.get(used), "reset": reset_timestamp(data.get("resets_at"))}, "used", "reset")
        if entry:
            labels.add(label)
            result.append(entry)

    for data in rates.get("limits") or []:
        if not isinstance(data, dict):
            continue
        kind = data.get("kind")
        if kind == "session":
            add("Session · 5-hour", data, "percent")
        elif kind == "weekly_all":
            add("Weekly · All models", data, "percent")
        elif kind == "weekly_scoped":
            model = ((data.get("scope") or {}).get("model") or {}).get("display_name")
            if model:
                add("Weekly · " + str(model) + " only", data, "percent")

    for key, label in (("five_hour", "Session · 5-hour"), ("seven_day", "Weekly · All models")):
        add(label, rates.get(key))
    for data in rates.get("model_scoped") or []:
        if isinstance(data, dict) and data.get("display_name"):
            add("Weekly · " + str(data["display_name"]) + " only", data)
    for key, label in (("seven_day_opus", "Weekly · Opus only"), ("seven_day_sonnet", "Weekly · Sonnet only")):
        add(label, rates.get(key))
    return result


class Rpc:
    """Bounded stdio requests; never start a thread, turn, tool, or login."""

    def __init__(self, command=None, control=False):
        self.command = command or ["codex", "app-server"]
        self.control = control

    def __enter__(self):
        self.process = subprocess.Popen(
            self.command, cwd=Path.home(), stdin=subprocess.PIPE,
            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, start_new_session=True)
        self.selector = selectors.DefaultSelector()
        self.selector.register(self.process.stdout, selectors.EVENT_READ)
        self.buffer = b""
        self.deadline = time.monotonic() + 15
        self.sequence = 0
        return self

    def send(self, message):
        self.process.stdin.write((json.dumps(message) + "\n").encode())
        self.process.stdin.flush()

    def request(self, method, params=None):
        self.sequence += 1
        request_id = str(self.sequence) if self.control else self.sequence
        if self.control:
            self.send({"type": "control_request", "request_id": request_id,
                       "request": dict(params or {}, subtype=method)})
        else:
            self.send({"id": request_id, "method": method, "params": params})
        while time.monotonic() < self.deadline:
            while b"\n" in self.buffer:
                line, self.buffer = self.buffer.split(b"\n", 1)
                message = json.loads(line)
                if self.control:
                    response = message.get("response", {})
                    if message.get("type") != "control_response" or response.get("request_id") != request_id:
                        continue
                    if response.get("subtype") != "success":
                        raise RuntimeError("Usage control request failed")
                    return response.get("response", {})
                if message.get("id") != request_id:
                    continue
                if "error" in message:
                    raise RuntimeError("Codex request failed")
                return message["result"]
            if self.selector.select(max(0, self.deadline - time.monotonic())):
                chunk = os.read(self.process.stdout.fileno(), 65536)
                if not chunk:
                    raise RuntimeError("Codex disconnected")
                self.buffer += chunk
                if len(self.buffer) > 2_000_000:
                    raise RuntimeError("Codex response too large")
        raise TimeoutError("Codex timed out")

    def __exit__(self, *_):
        self.selector.close()
        try:
            os.killpg(self.process.pid, signal.SIGTERM)
            self.process.wait(timeout=2)
        except subprocess.TimeoutExpired:
            os.killpg(self.process.pid, signal.SIGKILL)
            self.process.wait()
        except ProcessLookupError:
            self.process.wait()
        self.process.stdin.close()
        self.process.stdout.close()


def base(agent_id, name):
    return {"id": agent_id, "name": name, "installed": bool(shutil.which(agent_id)),
            "authenticated": False, "plan": "", "windows": [], "updatedAt": 0,
            "status": "signed-out", "message": "Sign in using the agent's CLI."}


def read_codex(previous):
    row = base("codex", "Codex")
    if not row["installed"]:
        return row
    try:
        with Rpc() as rpc:
            rpc.request("initialize", {"clientInfo": {"name": "blankweave_usage", "version": "1.0"}})
            rpc.send({"method": "initialized"})
            account = rpc.request("account/read", {"refreshToken": False}).get("account")
            if not account:
                return row
            row.update(authenticated=True, accountKey=identity(account) if account.get("email") else None,
                       plan=account.get("planType") or "")
            if account.get("type") != "chatgpt":
                row.update(status="unsupported", message="Subscription allowance is unavailable for this login type.")
                return row
            payload = rpc.request("account/rateLimits/read")
            row.update(windows=codex_windows(payload), updatedAt=int(time.time()), status="ready", message="")
            buckets = payload.get("rateLimitsByLimitId") or {"codex": payload.get("rateLimits", {})}
            if payload.get("ordinaryUsageAllowed") is False or any(
                b.get("rateLimitReachedType") or b.get("spendControlReached") is True
                for b in buckets.values() if isinstance(b, dict)
            ):
                row["message"] = "Your account has reached a usage or spending limit."
            elif not row["windows"]:
                row["message"] = "No allowance windows were reported for this account."
    except (OSError, ValueError, KeyError, TypeError, RuntimeError, TimeoutError):
        # Only retain usage after validating that the same account is still active.
        if row.get("accountKey") and row.get("accountKey") == previous.get("accountKey"):
            row.update(windows=previous.get("windows", []), updatedAt=previous.get("updatedAt", 0))
        row.update(status="error", message="Could not refresh Codex usage. Try again shortly.")
    return row


def claude_auth():
    result = subprocess.run(["claude", "auth", "status", "--json"], cwd=Path.home(),
                            capture_output=True, timeout=8, text=True)
    data = json.loads(result.stdout)
    if not isinstance(data, dict) or not isinstance(data.get("loggedIn"), bool):
        raise ValueError("Invalid authentication status")
    return data


def claude_identity(auth):
    if not any(auth.get(key) for key in ("email", "orgId", "organizationId")):
        return None
    return identity({key: auth.get(key) for key in
                     ("email", "orgId", "organizationId", "authMethod", "apiProvider", "configDirectory")})


def claude_plan(auth):
    plan = auth.get("subscriptionType") or ""
    if plan != "max":
        return plan
    # This is non-secret profile metadata, not .credentials.json. Only use a
    # tier belonging to the account that the CLI just authenticated.
    config = os.environ.get("CLAUDE_CONFIG_DIR")
    path = (Path(config) if config else Path.home()) / ".claude.json"
    account = read_json(path, {}).get("oauthAccount") or {}
    if not isinstance(account, dict) or not auth.get("email") or not auth.get("orgId"):
        return plan
    if account.get("emailAddress") != auth["email"] or account.get("organizationUuid") != auth["orgId"]:
        return plan
    tier = account.get("userRateLimitTier") or account.get("organizationRateLimitTier")
    return {"default_claude_max_5x": "max_5x", "default_claude_max_20x": "max_20x"}.get(tier, plan)


def read_claude(previous):
    row = base("claude", "Claude Code")
    if not row["installed"]:
        return row
    try:
        auth = claude_auth()
        row.update(authenticated=auth["loggedIn"], accountKey=claude_identity(auth),
                   plan=claude_plan(auth))
        if not row["authenticated"]:
            return row
        if auth.get("authMethod") not in ("claude.ai", "oauth"):
            row.update(status="unsupported", message="Subscription allowance is unavailable for this login type.")
            return row
        # Experimental CLI control request. Safe mode disables hooks/plugins;
        # empty tools and MCP config prevent startup side effects. No user turn
        # is sent and no session is saved. Credentials remain owned by Claude.
        command = ["claude", "--print", "--input-format", "stream-json", "--output-format", "stream-json",
                   "--verbose", "--no-session-persistence", "--safe-mode", "--tools", "",
                   "--strict-mcp-config", "--mcp-config", '{"mcpServers":{}}']
        with Rpc(command, control=True) as rpc:
            rpc.request("initialize")
            payload = rpc.request("get_usage", {"skip_behaviors": True})
        row["plan"] = claude_plan(auth)
        if not payload.get("rate_limits_available"):
            row.update(status="unsupported", message="Subscription allowance is unavailable for this account.")
            return row
        rates = payload.get("rate_limits")
        if not isinstance(rates, dict):
            raise ValueError("Usage unavailable")
        row.update(windows=claude_windows(rates), updatedAt=int(time.time()), status="ready", message="")
        if not row["windows"]:
            row["message"] = "No allowance windows were reported for this account."
    except (OSError, ValueError, KeyError, TypeError, AttributeError, RuntimeError, TimeoutError, subprocess.TimeoutExpired):
        if row.get("accountKey") and row.get("accountKey") == previous.get("accountKey"):
            row.update(windows=previous.get("windows", []), updatedAt=previous.get("updatedAt", 0))
        row.update(status="error", message="Could not refresh Claude usage. Retry or update Claude Code if this persists.")
    return row


def status(refresh=False):
    path = cache_dir() / "status.json"
    with lock(cache_dir() / "status.lock", blocking=False) as acquired:
        saved = read_json(path, {})
        if saved.get("version") != 2 or not finite(saved.get("checkedAt")) or not isinstance(saved.get("agents"), list):
            saved = {}
        age = time.time() - saved.get("checkedAt", 0)
        if acquired and (age < 0 or age >= (15 if refresh else 300)):
            old = {r["id"]: r for r in saved.get("agents", []) if isinstance(r, dict) and "id" in r}
            saved = {"version": 2, "checkedAt": int(time.time()), "agents": [
                read_codex(old.get("codex", {})), read_claude(old.get("claude", {}))]}
            write_json(path, saved)
    rows = []
    for row in saved.get("agents", []):
        if shutil.which(row["id"]):
            rows.append(row)
    return {"agents": rows, "checkedAt": saved.get("checkedAt", 0)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--refresh", action="store_true")
    args = parser.parse_args()
    try:
        print(json.dumps(status(args.refresh), allow_nan=False))
    except (OSError, ValueError, TypeError):
        print(json.dumps({"error": "Could not read agent usage."}))
        sys.exit(1)


if __name__ == "__main__":
    main()
