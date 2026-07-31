#!/usr/bin/env python3
"""Upload a MicroPython main.py to the Tower Pico over Wi-Fi."""

import argparse
import ast
import base64
import hashlib
from pathlib import Path
import socket
import sys


def read_wifi_password(config_path):
    source = config_path.read_text(encoding="utf-8")
    tree = ast.parse(source, filename=str(config_path))

    for statement in tree.body:
        if not isinstance(statement, ast.Assign):
            continue

        for target in statement.targets:
            if isinstance(target, ast.Name) and target.id == "WIFI_PASSWORD":
                value = ast.literal_eval(statement.value)

                if not isinstance(value, str) or not value:
                    raise ValueError("WIFI_PASSWORD must be a non-empty string")

                return value

    raise ValueError("WIFI_PASSWORD was not found")


def receive_line(connection, maximum=4096):
    received = bytearray()

    while len(received) < maximum:
        chunk = connection.recv(min(1024, maximum - len(received)))

        if not chunk:
            break

        received.extend(chunk)

        if b"\n" in chunk:
            break

    if b"\n" not in received:
        raise RuntimeError("Pico closed the connection without a response")

    return received.split(b"\n", 1)[0].decode().strip()


def main():
    parser = argparse.ArgumentParser(
        description="Upload main.py to the Tower Pico over Wi-Fi.")
    parser.add_argument(
        "source",
        nargs="?",
        default="pico/main.py",
        type=Path,
        help="main.py to upload (default: pico/main.py)")
    parser.add_argument(
        "--host",
        default="192.168.2.30",
        help="Tower Pico address (default: 192.168.2.30)")
    parser.add_argument(
        "--port",
        default=42101,
        type=int,
        help="Tower Pico command port (default: 42101)")
    parser.add_argument(
        "--config",
        default="pico/wifi_config.py",
        type=Path,
        help="Wi-Fi configuration containing WIFI_PASSWORD")
    args = parser.parse_args()

    try:
        source = args.source.read_bytes()
        password = read_wifi_password(args.config)
    except (OSError, SyntaxError, ValueError) as error:
        print("ERROR:", error, file=sys.stderr)
        return 1

    digest = hashlib.sha256(source).hexdigest()
    key = hashlib.sha256(password.encode()).hexdigest()
    encoded = base64.b64encode(source).decode()
    request = (
        "UPDATE_MAIN "
        + key + " "
        + str(len(source)) + " "
        + digest + " "
        + encoded + "\n"
    ).encode()

    try:
        with socket.create_connection((args.host, args.port), timeout=15) as connection:
            connection.sendall(request)
            response = receive_line(connection)
    except OSError as error:
        print("ERROR: Network failure:", error, file=sys.stderr)
        return 1

    print(response)

    if response != "OK UPDATE_MAIN " + digest:
        return 1

    print("Pico accepted the update and is restarting.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
