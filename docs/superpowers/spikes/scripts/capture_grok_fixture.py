"""Capture a redacted `_x.ai/billing` response from the Grok CLI as a test fixture.

Usage (after `grok login`):
    python3 -I docs/superpowers/spikes/scripts/capture_grok_fixture.py \
        docs/superpowers/spikes/fixtures/grok-usage.json

- Spawns `grok agent --no-leader stdio` with GROK_DISABLE_AUTOUPDATER=1.
- Sends only `initialize` and `_x.ai/billing` — never a prompt (no quota used).
- Redacts identity-looking keys and emails before writing. Never prints tokens.
"""
import json
import os
import queue
import re
import subprocess
import sys
import threading
import time

OUT = sys.argv[1]
GROK = os.path.expanduser("~/.grok/bin/grok")
SENSITIVE = re.compile(r"(email|userid|user_id|teamid|team_id|principal|accountid|account_id|token|key|secret|name|image|organization)", re.I)
EMAIL = re.compile(r"[\w.+-]+@[\w-]+\.[\w.]+")


def redact(o):
    if isinstance(o, dict):
        return {k: ("<redacted>" if SENSITIVE.search(k) and v is not None and not isinstance(v, (dict, list, bool)) else redact(v))
                for k, v in o.items()}
    if isinstance(o, list):
        return [redact(x) for x in o]
    if isinstance(o, str):
        return EMAIL.sub("<email>", o)
    return o


env = dict(os.environ, GROK_DISABLE_AUTOUPDATER="1")
p = subprocess.Popen([GROK, "agent", "--no-leader", "stdio"], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                     stderr=subprocess.DEVNULL, text=True, bufsize=1, env=env)
lines = queue.Queue()
threading.Thread(target=lambda: [lines.put(l) for l in p.stdout], daemon=True).start()


def call(msg_id, method, params, timeout=25):
    p.stdin.write(json.dumps({"jsonrpc": "2.0", "id": msg_id, "method": method, "params": params}) + "\n")
    p.stdin.flush()
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            line = lines.get(timeout=0.5)
        except queue.Empty:
            continue
        try:
            msg = json.loads(line)
        except json.JSONDecodeError:
            print("(non-JSON stdout line skipped)")
            continue
        if msg.get("id") == msg_id:
            return msg
        if "method" in msg:
            print(f"(notification {msg['method']})")
    raise SystemExit(f"timeout waiting for {method}")


call(1, "initialize", {"protocolVersion": 1, "clientCapabilities": {}})
resp = call(2, "_x.ai/billing", {})
p.stdin.close()
try:
    p.wait(timeout=5)
except subprocess.TimeoutExpired:
    p.terminate()

if "error" in resp:
    raise SystemExit(f"_x.ai/billing error: {json.dumps(resp['error'])}")
with open(OUT, "w") as f:
    json.dump(redact(resp["result"]), f, indent=2)
    f.write("\n")
print(f"wrote {OUT}")
print(json.dumps(redact(resp["result"]), indent=2)[:3000])
