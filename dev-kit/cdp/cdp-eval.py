#!/usr/bin/env python3
"""
Execute JavaScript in Obsidian via CDP (Chrome DevTools Protocol).
Uses raw WebSocket to bypass origin restrictions.

Usage: python3 dev-kit/cdp/cdp-eval.py '<javascript>'
"""
import sys, json, socket, base64, os, struct, time


HOST = os.environ.get("CDP_HOST", "192.168.65.254")
PORT = int(os.environ.get("CDP_PORT", "9222"))
WS_TIMEOUT = 30  # seconds for JS execution


def http_get(path: str) -> dict:
    """HTTP GET to CDP endpoint, return parsed JSON."""
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.settimeout(5)
    sock.connect((HOST, PORT))
    request = f"GET {path} HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n"
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
    sock.close()
    return json.loads(response.split(b"\r\n\r\n", 1)[1])


def ws_eval(expression: str, vault: str | None = None) -> dict:
    """Connect via WebSocket to Obsidian, evaluate JS, return result."""
    # Get Obsidian page target
    targets = http_get("/json")
    pages = [t for t in targets if t.get("type") == "page" and "obsidian" in t.get("url", "")]

    # Filter by vault name (appears in title like "Terminal - vault-name - Obsidian ...")
    if vault and len(pages) > 1:
        matches = [t for t in pages if vault in t.get("title", "")]
        if matches:
            pages = matches

    if not pages:
        pages = [t for t in targets if t.get("type") == "page"]
    if not pages:
        raise RuntimeError("No Obsidian page found. Is it running with --remote-debugging-port?")

    ws_url = pages[0]["webSocketDebuggerUrl"]
    # Extract path from ws://host:port/path → /path
    ws_path = "/" + ws_url.split("/", 3)[3] if "://" in ws_url else ws_url

    # WebSocket handshake
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.settimeout(WS_TIMEOUT)
    sock.connect((HOST, PORT))

    key = base64.b64encode(os.urandom(16)).decode()
    req = (
        f"GET {ws_path} HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Upgrade: websocket\r\n"
        "Connection: Upgrade\r\n"
        f"Sec-WebSocket-Key: {key}\r\n"
        "Sec-WebSocket-Version: 13\r\n"
        "Origin: http://localhost:9222\r\n"
        "\r\n"
    )
    sock.send(req.encode())

    resp = b""
    while b"\r\n\r\n" not in resp:
        resp += sock.recv(4096)
    if b"101" not in resp:
        sock.close()
        raise RuntimeError(f"WebSocket handshake failed: {resp.decode()[:200]}")

    # Send Runtime.evaluate
    msg = json.dumps({
        "id": 1,
        "method": "Runtime.evaluate",
        "params": {
            "expression": expression,
            "returnByValue": True,
            "awaitPromise": True,
        },
    })
    ws_send(sock, msg)

    # Read response
    result = ws_recv(sock)
    sock.close()
    return result


def ws_send(sock, msg: str):
    """Send a text frame over WebSocket."""
    payload = msg.encode()
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


def ws_recv(sock) -> dict:
    """Receive a text frame from WebSocket, return parsed JSON."""
    # Read exactly 2 header bytes
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

    mask_bytes = b""
    if masked:
        mask_bytes = _recv_exact(sock, 4)

    data = _recv_exact(sock, length)

    if masked:
        data = bytes(b ^ mask_bytes[i % 4] for i, b in enumerate(data))

    if opcode == 0x08:  # Close frame
        raise RuntimeError(f"WebSocket closed: {data.decode()}")
    if opcode == 0x09:  # Ping — ignore, read next
        return ws_recv(sock)

    return json.loads(data.decode())


def _recv_exact(sock, n: int) -> bytes:
    """Receive exactly n bytes from socket."""
    data = b""
    while len(data) < n:
        chunk = sock.recv(n - len(data))
        if not chunk:
            raise RuntimeError(f"WebSocket closed after {len(data)} of {n} bytes")
        data += chunk
    return data


if __name__ == "__main__":
    js_code = sys.argv[1] if len(sys.argv) > 1 else "1 + 1"
    vault = os.environ.get("CDP_VAULT") or None
    try:
        result = ws_eval(js_code, vault=vault)
        if "result" in result:
            r = result["result"]
            # Check for JS exception (thrown errors, syntax errors, etc.)
            if "exceptionDetails" in r:
                details = r["exceptionDetails"]
                text = details.get("text", "unknown error")
                print(f"JS EXCEPTION: {text}", file=sys.stderr)
                exc = details.get("exception", {})
                if exc.get("description"):
                    print(f"  {exc['description']}", file=sys.stderr)
                sys.exit(1)
            elif r.get("subtype") == "error":
                print("JS ERROR:", r.get("description", "unknown"))
                sys.exit(1)
            else:
                val = r.get("value", r)
                print(json.dumps(val, indent=2, ensure_ascii=False))
        elif "error" in result:
            print("CDP ERROR:", json.dumps(result["error"], indent=2))
            sys.exit(1)
        else:
            print(json.dumps(result, indent=2, ensure_ascii=False))
    except Exception as e:
        print(f"FATAL: {e}")
        sys.exit(1)
