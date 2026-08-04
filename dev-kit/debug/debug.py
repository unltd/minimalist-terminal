#!/usr/bin/env python3
"""
debug.py — Unified CDP debugging client for Obsidian.

Single entry point for all remote (and local) debugging:
  python3 debug.py test              Quick CDP health check
  python3 debug.py screenshot        Take screenshot
  python3 debug.py eval '<js>'       Evaluate JavaScript in Obsidian
  python3 debug.py view              Show Obsidian page info

Works remotely (CDP_HOST env) or locally (--local flag).

Examples:
  CDP_HOST=192.168.1.144 python3 debug.py test
  CDP_HOST=192.168.1.144 python3 debug.py screenshot
  CDP_HOST=192.168.1.144 python3 debug.py eval "navigator.platform"
  python3 debug.py test --local
"""

import argparse
import base64
import json
import os
import socket
import struct
import sys
import time
from datetime import datetime

# ── Config ───────────────────────────────────────────────────────────
HOST = os.environ.get("CDP_HOST", "127.0.0.1")
PORT = int(os.environ.get("CDP_PORT", "9222"))
OUTPUT_DIR = os.environ.get("CDP_SCREENSHOT_DIR",
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "screenshots"))
VAULT = os.environ.get("CDP_VAULT") or None
TIMEOUT = int(os.environ.get("CDP_TIMEOUT", "15"))


# ── HTTP helpers ─────────────────────────────────────────────────────
def http_get(path: str, timeout: int = 10) -> dict:
    """HTTP GET to CDP endpoint, return parsed JSON."""
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.settimeout(timeout)
    try:
        sock.connect((HOST, PORT))
        request = f"GET {path} HTTP/1.1\r\nHost: {HOST}:{PORT}\r\nConnection: close\r\n\r\n"
        sock.send(request.encode())
        response = b""
        while True:
            try:
                chunk = sock.recv(4096)
                if not chunk:
                    break
                response += chunk
            except socket.timeout:
                break
    finally:
        sock.close()

    if not response:
        raise ConnectionError(f"No response from {HOST}:{PORT} — is Obsidian running with CDP?")

    body = response.split(b"\r\n\r\n", 1)[1]
    if not body:
        raise ConnectionError(f"Empty body from {HOST}:{PORT}")
    return json.loads(body)


def find_obsidian_page(targets: list, vault: str | None = None) -> dict:
    """Find an Obsidian page target. Filters by vault name if provided."""
    pages = [t for t in targets if t.get("type") == "page" and t.get("url", "").startswith("app://")]
    if not pages:
        pages = [t for t in targets if t.get("type") == "page"]

    if vault and len(pages) > 1:
        matches = [t for t in pages if vault in t.get("title", "")]
        if matches:
            pages = matches

    if not pages:
        raise RuntimeError(f"No Obsidian page found. Targets: {len(targets)}")
    return pages[0]


# ── WebSocket helpers (raw, no dependencies) ─────────────────────────
def ws_connect(page: dict, timeout: int = TIMEOUT) -> socket.socket:
    """Connect to Obsidian page via raw WebSocket."""
    ws_url = page["webSocketDebuggerUrl"]
    ws_path = "/" + ws_url.split("/", 3)[3] if "://" in ws_url else ws_url

    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.settimeout(timeout)
    sock.connect((HOST, PORT))

    key = base64.b64encode(os.urandom(16)).decode()
    request = (
        f"GET {ws_path} HTTP/1.1\r\n"
        f"Host: {HOST}:{PORT}\r\n"
        "Upgrade: websocket\r\n"
        "Connection: Upgrade\r\n"
        f"Sec-WebSocket-Key: {key}\r\n"
        "Sec-WebSocket-Version: 13\r\n"
        "Origin: http://localhost:9222\r\n"
        "\r\n"
    )
    sock.send(request.encode())

    resp = b""
    while b"\r\n\r\n" not in resp:
        resp += sock.recv(4096)
    if b"101" not in resp:
        sock.close()
        raise RuntimeError(f"WebSocket handshake failed: {resp.decode()[:200]}")
    return sock


def ws_send(sock: socket.socket, msg: dict):
    """Send a JSON message over raw WebSocket (client-masked)."""
    payload = json.dumps(msg).encode()
    mask = os.urandom(4)
    frame = bytearray()
    frame.append(0x81)  # FIN + text opcode
    n = len(payload)
    if n < 126:
        frame.append(0x80 | n)
    elif n < 65536:
        frame.append(0x80 | 126)
        frame.extend(struct.pack(">H", n))
    else:
        frame.append(0x80 | 127)
        frame.extend(struct.pack(">Q", n))
    frame.extend(mask)
    frame.extend(bytes(b ^ mask[i % 4] for i, b in enumerate(payload)))
    sock.send(bytes(frame))


def ws_recv(sock: socket.socket) -> dict:
    """Receive a JSON message from raw WebSocket."""
    header = b""
    while len(header) < 2:
        chunk = sock.recv(2 - len(header))
        if not chunk:
            raise RuntimeError("WebSocket closed by peer")
        header += chunk

    opcode = header[0] & 0x0F
    masked = bool(header[1] & 0x80)
    length = header[1] & 0x7F

    if length == 126:
        length = struct.unpack(">H", _recv_exact(sock, 2))[0]
    elif length == 127:
        length = struct.unpack(">Q", _recv_exact(sock, 8))[0]

    mask_bytes = _recv_exact(sock, 4) if masked else b""
    data = _recv_exact(sock, length)

    if masked:
        data = bytes(b ^ mask_bytes[i % 4] for i, b in enumerate(data))

    if opcode == 0x08:  # Close frame
        raise RuntimeError(f"WebSocket closed: {data.decode(errors='replace')}")
    if opcode == 0x09:  # Ping
        return ws_recv(sock)

    return json.loads(data.decode())


def _recv_exact(sock: socket.socket, n: int) -> bytes:
    """Receive exactly n bytes from socket."""
    data = b""
    while len(data) < n:
        chunk = sock.recv(n - len(data))
        if not chunk:
            raise RuntimeError(f"WebSocket closed after {len(data)} of {n} bytes")
        data += chunk
    return data


def ws_eval(expression: str, timeout: int = TIMEOUT) -> dict:
    """Connect to Obsidian via CDP and evaluate JavaScript."""
    targets = http_get("/json")
    page = find_obsidian_page(targets, VAULT)
    sock = ws_connect(page, timeout)

    ws_send(sock, {
        "id": 1,
        "method": "Runtime.evaluate",
        "params": {
            "expression": expression,
            "returnByValue": True,
            "awaitPromise": True,
        },
    })

    result = ws_recv(sock)
    sock.close()
    return result


# ── Commands ─────────────────────────────────────────────────────────
def cmd_test():
    """Quick health check: connectivity, CDP, Obsidian, plugin."""
    ts = datetime.now().strftime("%H:%M:%S")
    print(f"[{ts}] Testing CDP connection to {HOST}:{PORT} ...")

    # 1. TCP connectivity
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.settimeout(5)
    try:
        sock.connect((HOST, PORT))
        print(f"  [OK] TCP connected to {HOST}:{PORT}")
    except Exception as e:
        print(f"  [FAIL] Cannot connect: {e}")
        sys.exit(1)
    finally:
        sock.close()

    # 2. CDP HTTP endpoint
    try:
        targets = http_get("/json", timeout=5)
        pages = [t for t in targets if t.get("type") == "page"]
        obsidian_pages = [t for t in pages if t.get("url", "").startswith("app://")]
        print(f"  [OK] CDP HTTP: {len(targets)} targets ({len(pages)} pages, {len(obsidian_pages)} Obsidian)")
        for t in obsidian_pages[:3]:
            print(f"       {t.get('title', '?')[:80]}")
    except Exception as e:
        print(f"  [FAIL] CDP HTTP: {e}")
        sys.exit(1)

    # 3. WebSocket eval
    try:
        result = ws_eval(
            "JSON.stringify({"
            "platform: navigator.platform,"
            "title: document.title,"
            "plugin_loaded: !!(app.plugins.plugins['minimalist-terminal']),"
            "plugin_version: (app.plugins.plugins['minimalist-terminal']?.manifest?.version) || 'N/A',"
            "vault: (app.vault?.getName?.() || 'unknown')"
            "})",
            timeout=10
        )
        r = result.get("result", {})
        if "value" in r:
            info = json.loads(r["value"])
            print(f"  [OK] JS eval: platform={info['platform']}, vault={info['vault']}")
            print(f"       Plugin: {'loaded v' + info['plugin_version'] if info['plugin_loaded'] else 'NOT LOADED'}")
        elif "exceptionDetails" in r:
            print(f"  [FAIL] JS exception: {r['exceptionDetails'].get('text', '?')}")
            sys.exit(1)
        elif "error" in result:
            print(f"  [FAIL] CDP error: {json.dumps(result['error'])[:200]}")
            sys.exit(1)
        else:
            print(f"  [WARN] Unexpected response: {json.dumps(result)[:200]}")
    except Exception as e:
        print(f"  [FAIL] WebSocket eval: {e}")
        sys.exit(1)

    print(f"\n  All checks passed! CDP is ready.")


def cmd_view():
    """Show detailed Obsidian page info from CDP."""
    targets = http_get("/json")
    pages = [t for t in targets if t.get("type") == "page"]

    print(f"CDP targets at {HOST}:{PORT}:")
    print(f"  Total: {len(targets)}")
    print(f"  Pages: {len(pages)}")
    print()

    for i, t in enumerate(pages):
        obsidian = "obsidian" in t.get("url", "").lower()
        marker = " [OBSIDIAN]" if obsidian else ""
        print(f"  [{i}] {t.get('type','?')}{marker}")
        print(f"      Title: {t.get('title','?')[:100]}")
        print(f"      URL:   {t.get('url','?')[:100]}")
        if obsidian:
            print(f"      WS:    {t.get('webSocketDebuggerUrl','?')[:100]}")
        print()


def cmd_eval(expression: str):
    """Evaluate JavaScript in Obsidian and print result."""
    try:
        result = ws_eval(expression)
    except Exception as e:
        print(f"FATAL: {e}", file=sys.stderr)
        sys.exit(1)

    if "result" in result:
        r = result["result"]
        if "exceptionDetails" in r:
            details = r["exceptionDetails"]
            text = details.get("text", "unknown error")
            print(f"JS EXCEPTION: {text}", file=sys.stderr)
            exc = details.get("exception", {})
            if exc.get("description"):
                print(f"  {exc['description']}", file=sys.stderr)
            sys.exit(1)
        elif r.get("subtype") == "error":
            print(f"JS ERROR: {r.get('description', 'unknown')}", file=sys.stderr)
            sys.exit(1)
        else:
            val = r.get("value", r)
            if isinstance(val, str):
                print(val)
            else:
                print(json.dumps(val, indent=2, ensure_ascii=False))
    elif "error" in result:
        print(f"CDP ERROR: {json.dumps(result['error'], indent=2)}", file=sys.stderr)
        sys.exit(1)
    else:
        print(json.dumps(result, indent=2, ensure_ascii=False))


def cmd_screenshot(filename: str = None):
    """Take a screenshot of the Obsidian page and save to screenshots/."""
    targets = http_get("/json")
    page = find_obsidian_page(targets, VAULT)
    sock = ws_connect(page, 30)

    ws_send(sock, {"id": 1, "method": "Page.captureScreenshot", "params": {"format": "png"}})
    result = ws_recv(sock)
    sock.close()

    if "result" in result and "data" in result["result"]:
        img_data = base64.b64decode(result["result"]["data"])

        if filename is None:
            os.makedirs(OUTPUT_DIR, exist_ok=True)
            existing = [f for f in os.listdir(OUTPUT_DIR) if f.endswith(".png")]
            nums = []
            for f in existing:
                try:
                    nums.append(int(f.replace(".png", "")))
                except ValueError:
                    pass
            next_num = max(nums) + 1 if nums else 1
            filename = f"win-{next_num:02d}.png"

        filepath = os.path.join(OUTPUT_DIR, filename)
        with open(filepath, "wb") as f:
            f.write(img_data)
        print(f"Screenshot saved: {filepath} ({len(img_data):,} bytes)")
    else:
        print(f"Error: {json.dumps(result, indent=2)}", file=sys.stderr)
        sys.exit(1)


# ── Main ─────────────────────────────────────────────────────────────
def main():
    parser = argparse.ArgumentParser(
        description="Unified CDP debugging client for Obsidian",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  CDP_HOST=192.168.1.144 python3 debug.py test
  python3 debug.py test --local
  CDP_HOST=192.168.1.144 python3 debug.py eval "app.plugins.plugins"
  CDP_HOST=192.168.1.144 python3 debug.py screenshot
  CDP_HOST=192.168.1.144 python3 debug.py screenshot my-screenshot.png
  python3 debug.py view --local
        """
    )
    sub = parser.add_subparsers(dest="command", help="Command to run")

    sub.add_parser("test", help="Quick health check (TCP, CDP, JS eval)")

    sub.add_parser("view", help="Show Obsidian page info from CDP")

    eval_parser = sub.add_parser("eval", help="Evaluate JavaScript in Obsidian")
    eval_parser.add_argument("expression", help="JavaScript expression to evaluate")

    shot_parser = sub.add_parser("screenshot", help="Take screenshot of Obsidian")
    shot_parser.add_argument("filename", nargs="?", default=None, help="Output filename (auto-named if omitted)")

    parser.add_argument("--local", action="store_true", help="Use 127.0.0.1 instead of CDP_HOST")

    args = parser.parse_args()

    if args.local:
        global HOST
        HOST = "127.0.0.1"

    if args.command == "test":
        cmd_test()
    elif args.command == "view":
        cmd_view()
    elif args.command == "eval":
        cmd_eval(args.expression)
    elif args.command == "screenshot":
        cmd_screenshot(args.filename)
    elif args.command is None:
        # Default: run test
        cmd_test()
    else:
        parser.print_help()


if __name__ == "__main__":
    main()
