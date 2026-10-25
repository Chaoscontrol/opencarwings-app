#!/usr/bin/env python3
"""Check the real notification websocket survives idle Redis BRPOP cycles.

Uses an Authorization header, never a URL token. Only connects, listens and
exchanges websocket control frames; no vehicle or account changes are made.
"""
from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import select
import socket
import struct
import sys
import time


class Failure(RuntimeError):
    pass


class ReadTimeout(Exception):
    pass


class WebSocket:
    MAX_PAYLOAD = 1024 * 1024

    def __init__(self, connection, initial=b""):
        self.connection = connection
        self.buffer = bytearray(initial)
        self.fragments = bytearray()
        self.fragment_type = None

    def send(self, opcode, payload=b""):
        mask = os.urandom(4)
        length = len(payload)
        header = bytes([0x80 | opcode])
        if length < 126:
            header += bytes([0x80 | length])
        elif length < 65536:
            header += bytes([0xFE]) + struct.pack("!H", length)
        else:
            header += bytes([0xFF]) + struct.pack("!Q", length)
        self.connection.sendall(header + mask + bytes(value ^ mask[i % 4] for i, value in enumerate(payload)))

    def frame(self, deadline):
        while True:
            if len(self.buffer) >= 2:
                first, second = self.buffer[:2]
                if first & 0x70 or second & 0x80:
                    raise Failure("Invalid server websocket frame flags")
                length, offset = second & 0x7F, 2
                extended = 2 if length == 126 else 8 if length == 127 else 0
                if len(self.buffer) >= offset + extended:
                    if extended:
                        length = int.from_bytes(self.buffer[offset:offset + extended], "big")
                        offset += extended
                    if length > self.MAX_PAYLOAD:
                        raise Failure("Server frame exceeds test size limit")
                    opcode, final = first & 0x0F, bool(first & 0x80)
                    if opcode >= 8 and (not final or length > 125):
                        raise Failure("Invalid websocket control frame")
                    if len(self.buffer) >= offset + length:
                        payload = bytes(self.buffer[offset:offset + length])
                        del self.buffer[:offset + length]
                        return opcode, final, payload
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise ReadTimeout()
            if not select.select([self.connection], [], [], min(remaining, 2))[0]:
                continue
            received = self.connection.recv(65536)
            if not received:
                raise Failure("Server disconnected without a websocket close frame")
            self.buffer.extend(received)

    def event(self, timeout):
        deadline = time.monotonic() + timeout
        while True:
            opcode, final, payload = self.frame(deadline)
            if opcode == 9:
                self.send(10, payload)
                continue
            if opcode == 10:
                return "pong", payload
            if opcode == 8:
                if len(payload) == 1:
                    raise Failure("Invalid websocket close frame")
                return "close", struct.unpack("!H", payload[:2])[0] if payload else None
            if opcode not in (0, 1, 2):
                raise Failure("Unexpected websocket opcode")
            if opcode:
                if self.fragment_type is not None:
                    raise Failure("Overlapping fragmented websocket messages")
                self.fragment_type = opcode
            elif self.fragment_type is None:
                raise Failure("Unexpected websocket continuation")
            self.fragments.extend(payload)
            if len(self.fragments) > self.MAX_PAYLOAD:
                raise Failure("Server message exceeds test size limit")
            if final:
                kind = "text" if self.fragment_type == 1 else "binary"
                message = bytes(self.fragments)
                self.fragments.clear()
                self.fragment_type = None
                return kind, message


def connect(args, token):
    host_header = args.http_host or f"{args.host}:{args.port}"
    if any(character.isspace() for character in host_header) or any(character in host_header for character in "/\\"):
        raise Failure("Invalid HTTP Host header")
    key = base64.b64encode(os.urandom(16)).decode("ascii")
    request = (f"GET /ws/notif/ HTTP/1.1\r\nHost: {host_header}\r\n"
               "Upgrade: websocket\r\nConnection: Upgrade\r\n"
               f"Sec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n"
               f"Authorization: Token {token}\r\n\r\n").encode("ascii")
    connection = socket.create_connection((args.host, args.port), timeout=5)
    try:
        connection.settimeout(2)
        connection.sendall(request)
        response = bytearray()
        deadline = time.monotonic() + 10
        while b"\r\n\r\n" not in response:
            if time.monotonic() >= deadline:
                raise Failure("Websocket upgrade timed out")
            if not select.select([connection], [], [], min(2, max(0, deadline - time.monotonic())))[0]:
                continue
            chunk = connection.recv(4096)
            if not chunk:
                raise Failure("Server disconnected during websocket upgrade")
            response.extend(chunk)
            if len(response) > 16384:
                raise Failure("Websocket upgrade response exceeds size limit")
        headers, initial = bytes(response).split(b"\r\n\r\n", 1)
        lines = headers.decode("iso-8859-1").split("\r\n")
        status = lines[0].split()
        if len(status) < 2 or status[1] != "101":
            raise Failure("Server refused websocket upgrade")
        fields = {name.lower(): value.strip() for name, value in
                  (line.split(":", 1) for line in lines[1:] if ":" in line)}
        expected = base64.b64encode(hashlib.sha1((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode()).digest()).decode()
        if fields.get("sec-websocket-accept", "") != expected:
            raise Failure("Invalid websocket upgrade signature")
        if fields.get("upgrade", "").lower() != "websocket" or "upgrade" not in fields.get("connection", "").lower():
            raise Failure("Invalid websocket upgrade headers")
        return WebSocket(connection, initial)
    except BaseException:
        connection.close()
        raise


def check(args, token):
    websocket = connect(args, token)
    try:
        deadline = time.monotonic() + 10
        while True:
            kind, value = websocket.event(max(0, deadline - time.monotonic()))
            if kind == "close":
                raise Failure(f"Server closed before notification acknowledgment (code {value})")
            if kind == "text":
                try:
                    acknowledgment = json.loads(value)
                except (ValueError, UnicodeError):
                    raise Failure("Notification acknowledgment is not JSON") from None
                if acknowledgment != {"type": "listen", "data": True}:
                    raise Failure("Unexpected notification acknowledgment")
                break
        print(f"Notification acknowledgment received; checking {args.idle_seconds:g}s idle", flush=True)
        deadline = time.monotonic() + args.idle_seconds
        while time.monotonic() < deadline:
            try:
                kind, value = websocket.event(min(2, deadline - time.monotonic()))
            except ReadTimeout:
                continue
            if kind == "close":
                raise Failure(f"Server closed during idle observation (code {value})")
        nonce = os.urandom(12)
        websocket.send(9, nonce)
        deadline = time.monotonic() + 5
        while True:
            kind, value = websocket.event(max(0, deadline - time.monotonic()))
            if kind == "close":
                raise Failure(f"Server closed before post-idle pong (code {value})")
            if kind == "pong" and value == nonce:
                break
        websocket.send(8, struct.pack("!H", 1000))
        deadline = time.monotonic() + 5
        while True:
            kind, value = websocket.event(max(0, deadline - time.monotonic()))
            if kind == "close":
                if value not in (None, 1000):
                    raise Failure(f"Unclean server close code {value}")
                break
    finally:
        websocket.connection.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8124)
    parser.add_argument("--http-host", help="Trusted HTTP Host header when connecting to a direct IP")
    parser.add_argument("--idle-seconds", type=float, default=40)
    credentials = parser.add_mutually_exclusive_group(required=True)
    credentials.add_argument("--token-file", type=Path, help="Private file containing only the API key")
    credentials.add_argument("--token-env", help="Name of an environment variable containing the API key")
    args = parser.parse_args()
    if not 1 <= args.port <= 65535 or not 10 <= args.idle_seconds <= 3600:
        parser.error("port must be 1..65535 and idle-seconds must be 10..3600")
    started = time.monotonic()
    try:
        token = args.token_file.read_text().strip() if args.token_file else os.environ.get(args.token_env, "").strip()
        if not token or not token.isascii() or any(character.isspace() for character in token):
            raise Failure("Missing or invalid API key input")
        check(args, token)
    except ReadTimeout:
        print(f"notification-idle-failed: protocol response timed out after {time.monotonic() - started:.1f}s", file=sys.stderr)
        return 1
    except Failure as error:
        print(f"notification-idle-failed: {error}; elapsed={time.monotonic() - started:.1f}s", file=sys.stderr)
        return 1
    except (OSError, ValueError):
        print(f"notification-idle-failed: connection or credential input error; elapsed={time.monotonic() - started:.1f}s", file=sys.stderr)
        return 1
    print(f"notification-idle-ok: survived {args.idle_seconds:g}s, post-idle pong and clean close")
    return 0


if __name__ == "__main__":
    sys.exit(main())
