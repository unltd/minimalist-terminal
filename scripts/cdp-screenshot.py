#!/usr/bin/env python3
"""Take a screenshot of the Obsidian page via CDP. Saves to screenshots/ directory."""
import sys
import json
import socket
import base64
import os
import struct

HOST = "192.168.65.254"
PORT = 9222
OUTPUT_DIR = "/Users/pavel/IdeaProjects/obsidian-terminal/screenshots"


def http_get(path: str) -> dict:
    """HTTP GET to CDP and return parsed JSON."""
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.settimeout(10)
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
    body = response.split(b"\r\n\r\n", 1)[1]
    return json.loads(body)


def ws_connect_and_exec(expression: str) -> dict:
    """Connect via WebSocket to Obsidian page and execute JS."""
    targets = http_get("/json")
    pages = [t for t in targets if t.get("type") == "page" and "obsidian" in t.get("url", "")]
    if not pages:
        pages = [t for t in targets if t.get("type") == "page"]
    if not pages:
        raise RuntimeError("No page targets found")

    page = pages[0]
    ws_path = page["webSocketDebuggerUrl"]
    path = "/" + ws_path.split("localhost/", 1)[1] if "localhost/" in ws_path else ws_path

    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.settimeout(30)
    sock.connect((HOST, PORT))

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

    resp = b""
    while b"\r\n\r\n" not in resp:
        resp += sock.recv(4096)
    if b"101" not in resp:
        sock.close()
        raise RuntimeError(f"WebSocket handshake failed: {resp.decode()}")

    return sock


def ws_send(sock, msg: dict):
    """Send a JSON message over WebSocket."""
    payload = json.dumps(msg).encode()
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
    frame.extend(bytes(b ^ mask[i % 4] for i, b in enumerate(payload)))
    sock.send(bytes(frame))


def ws_recv(sock) -> dict:
    """Receive a JSON message over WebSocket."""
    header = b""
    while len(header) < 2:
        header += sock.recv(2 - len(header))
    masked = header[1] & 0x80
    length = header[1] & 0x7F

    if length == 126:
        length = struct.unpack(">H", sock.recv(2))[0]
    elif length == 127:
        length = struct.unpack(">Q", sock.recv(8))[0]

    mask_bytes = b""
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

    return json.loads(data)


def screenshot(filename: str = None):
    """Take a screenshot of the Obsidian page."""
    if filename is None:
        # Find next available screenshot number
        os.makedirs(OUTPUT_DIR, exist_ok=True)
        existing = [f for f in os.listdir(OUTPUT_DIR) if f.endswith(".png")]
        nums = []
        for f in existing:
            try:
                nums.append(int(f.replace(".png", "")))
            except ValueError:
                pass
        next_num = max(nums) + 1 if nums else 1
        filename = f"{next_num}.png"

    filepath = os.path.join(OUTPUT_DIR, filename)

    sock = ws_connect_and_exec("1")

    # Send Page.captureScreenshot
    msg = {"id": 1, "method": "Page.captureScreenshot", "params": {"format": "png"}}
    ws_send(sock, msg)
    result = ws_recv(sock)

    if "result" in result and "data" in result["result"]:
        img_data = base64.b64decode(result["result"]["data"])
        with open(filepath, "wb") as f:
            f.write(img_data)
        print(f"Screenshot saved: {filepath} ({len(img_data)} bytes)")
    else:
        print(f"Error: {json.dumps(result, indent=2)}")

    sock.close()


if __name__ == "__main__":
    filename = sys.argv[1] if len(sys.argv) > 1 else None
    screenshot(filename)
