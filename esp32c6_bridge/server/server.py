#!/usr/bin/env python3
"""
TCP server for the ESP32-C6 UART<->WiFi bridge.

The ESP32 connects here and forwards everything it reads from the NEORV32 UART.
Incoming bytes are printed to this terminal. You can also send bytes back to the
FPGA (e.g. to drive the NEORV32 bootloader) by typing, or upload a binary file.

Run:
    python server.py --host 0.0.0.0 --port 5005

While connected, type at the prompt:
    <any text>        -> sent to the FPGA as-is, plus a newline
    /raw <text>       -> sent without a trailing newline
    /sendfile <path>  -> stream a binary file (e.g. neorv32_exe.bin) to the bootloader
    /quit             -> exit
"""
import argparse
import socket
import sys
import threading

sock_lock = threading.Lock()
client = None


def rx_loop(conn):
    """Print everything the ESP32 forwards from the FPGA UART."""
    while True:
        try:
            data = conn.recv(4096)
        except OSError:
            break
        if not data:
            break
        # NEORV32 output is ASCII; show it, keep unknown bytes visible
        sys.stdout.write(data.decode("utf-8", errors="replace"))
        sys.stdout.flush()
    print("\n[server] client disconnected")


def main():
    global client
    ap = argparse.ArgumentParser()
    ap.add_argument("--host", default="0.0.0.0")
    ap.add_argument("--port", type=int, default=5005)
    args = ap.parse_args()

    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind((args.host, args.port))
    srv.listen(1)
    print(f"[server] listening on {args.host}:{args.port} - waiting for ESP32...")

    conn, addr = srv.accept()
    client = conn
    print(f"[server] ESP32 connected from {addr[0]}:{addr[1]}\n")

    threading.Thread(target=rx_loop, args=(conn,), daemon=True).start()

    try:
        for line in sys.stdin:
            line = line.rstrip("\n")
            if line == "/quit":
                break
            elif line.startswith("/sendfile "):
                path = line[len("/sendfile "):].strip().strip('"')
                try:
                    with open(path, "rb") as f:
                        payload = f.read()
                    with sock_lock:
                        conn.sendall(payload)
                    print(f"[server] sent {len(payload)} bytes from {path}")
                except OSError as e:
                    print(f"[server] file error: {e}")
            elif line.startswith("/raw "):
                with sock_lock:
                    conn.sendall(line[len("/raw "):].encode("utf-8"))
            else:
                with sock_lock:
                    conn.sendall((line + "\n").encode("utf-8"))
    except KeyboardInterrupt:
        pass
    finally:
        conn.close()
        srv.close()
        print("[server] closed")


if __name__ == "__main__":
    main()
