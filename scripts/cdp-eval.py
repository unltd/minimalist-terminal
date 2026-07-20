#!/usr/bin/env python3
"""
Execute JavaScript in Obsidian via CDP (Chrome DevTools Protocol).
Uses raw sockets to bypass origin restrictions.
"""
import sys
import json
import socket
import base64
import os
import hashlib
import struct

CDP_BASE = "http://192.168.65.254:9222"
HEADERS = {"Host": "localhost"}


def http_get(path: str) -> dict:
    """Make an HTTP GET request to CDP and return parsed JSON."""
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.settimeout(10)
    sock.connect(("192.168.65.254", 9222))

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

    body = response.split(b"\r\n\r\n", 1)[1]
    return json.loads(body)


def ws_eval(expression: str) -> dict:
    """Connect via WebSocket, evaluate JS expression, return result."""
    # Step 1: get page target
    targets = http_get("/json")
    pages = [t for t in targets if t.get("type") == "page" and "obsidian" in t.get("url", "")]
    if not pages:
        pages = [t for t in targets if t.get("type") == "page"]
        raise RuntimeError("No page targets found. Is Obsidian open?")

    page = pages[0]
    ws_path = page["webSocketDebuggerUrl"]
    # ws_path looks like: ws://localhost/devtools/page/XXX
    # Extract just the path
    path = "/" + ws_path.split("localhost/", 1)[1] if "localhost/" in ws_path else ws_path

    # Step 2: WebSocket handshake (raw)
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.settimeout(10)
    sock.connect(("192.168.65.254", 9222))

    key = base64.b64encode(os.urandom(16)).decode()
    request = (
        f"GET {path} HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Upgrade: websocket\r\n"
        "Connection: Upgrade\r\n"
        f"Sec-WebSocket-Key: {key}\r\n"
        "Sec-WebSocket-Version: 13\r\n"
        "Origin: http://localhost:9222\r\n"
        "\r\n"
    )
    sock.send(request.encode())

    # Read handshake response
    resp = b""
    while b"\r\n\r\n" not in resp:
        resp += sock.recv(4096)

    if b"101" not in resp:
        sock.close()
        raise RuntimeError(f"WebSocket handshake failed: {resp.decode()}")

    # Step 3: send evaluation request
    msg = json.dumps({
        "id": 1,
        "method": "Runtime.evaluate",
        "params": {
            "expression": expression,
            "returnByValue": True,
            "awaitPromise": True,
        },
    })

    # WebSocket frame: FIN=1, opcode=1 (text), masked, payload
    payload = msg.encode()
    mask = os.urandom(4)
    frame = bytearray()
    frame.append(0x81)  # FIN + text opcode
    length = len(payload)
    if length < 126:
        frame.append(0x80 | length)
    elif length < 65536:
        frame.append(0x80 | 126)
        frame.extend(struct.pack(">H", length))
    else:
        frame.append(0x80 | 127)
        frame.extend(struct.pack(">Q", length))
    frame.extend(mask)
    masked_payload = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
    frame.extend(masked_payload)

    sock.send(bytes(frame))

    # Step 4: read response frame
    def read_frame():
        header = b""
        while len(header) < 2:
            header += sock.recv(2 - len(header))
        opcode = header[0] & 0x0F
        masked = header[1] & 0x80
        length = header[1] & 0x7F

        if length == 126:
            length = struct.unpack(">H", sock.recv(2))[0]
        elif length == 127:
            length = struct.unpack(">Q", sock.recv(8))[0]

        # Server frames are not masked, but read mask if present
        if masked:
            mask_bytes = sock.recv(4)

        data = b""
        while len(data) < length:
            chunk = sock.recv(length - len(data))
            if not chunk:
                break
            data += chunk

        if masked:
            data = bytes(b ^ mask_bytes[i % 4] for i, b in enumerate(data))

        return opcode, data.decode()

    opcode, response = read_frame()
    sock.close()

    return json.loads(response)


if __name__ == "__main__":
    js_code = sys.argv[1] if len(sys.argv) > 1 else "1 + 1"
    try:
        result = ws_eval(js_code)
        if "result" in result:
            r = result["result"]
            if r.get("subtype") == "error":
                print("JS ERROR:", r.get("description", "unknown"))
            else:
                val = r.get("value", r)
                print(json.dumps(val, indent=2, ensure_ascii=False))
        elif "error" in result:
            print("CDP ERROR:", json.dumps(result["error"], indent=2))
        else:
            print(json.dumps(result, indent=2, ensure_ascii=False))
    except Exception as e:
        print(f"FATAL: {e}")
        sys.exit(1)
