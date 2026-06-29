#!/usr/bin/env python3
"""
Upload a NEORV32 executable (neorv32_exe.bin) to the bootloader over a serial port
(through the ESP32-C6 UART bridge). Aborts auto-boot, runs 'u', streams the binary,
then 'e' to execute, and prints the program output.

Usage:
    python upload.py --port COM7 --file ../sw/mac_demo/neorv32_exe.bin
"""
import argparse
import sys
import time
import serial


def read_until(ser, marker, timeout):
    end = time.time() + timeout
    buf = b""
    while time.time() < end:
        b = ser.read(256)
        if b:
            buf += b
            if marker in buf:
                return buf
    return buf


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", default="COM7")
    ap.add_argument("--baud", type=int, default=19200)
    ap.add_argument("--file", required=True)
    ap.add_argument("--run-secs", type=float, default=6.0)
    ap.add_argument("--log", default=None, help="save raw received bytes to this file")
    args = ap.parse_args()

    # never crash on non-ASCII terminal noise
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass
    log_bytes = bytearray()

    with open(args.file, "rb") as f:
        payload = f.read()
    print(f"[upload] {args.file}: {len(payload)} bytes")

    ser = serial.Serial(args.port, args.baud, timeout=0.3)
    time.sleep(0.3)

    # force a clean restart and wait for the actual bootloader prompts
    ser.reset_input_buffer()
    ser.write(b"r")                                    # restart command (works at CMD prompt)
    out = read_until(ser, b"abort", 6.0)               # wait for the auto-boot countdown banner
    log_bytes.extend(out)
    sys.stdout.write(out.decode("ascii", "replace"))
    time.sleep(0.2)
    ser.write(b" ")                                    # any key -> abort the 8s countdown
    out = read_until(ser, b"CMD:>", 6.0)               # land at the command prompt
    log_bytes.extend(out)
    sys.stdout.write(out.decode("ascii", "replace"))

    # request upload, wait until the bootloader is actually awaiting the binary
    ser.reset_input_buffer()
    ser.write(b"u")
    out = read_until(ser, b"Awaiting", 4.0)
    log_bytes.extend(out)
    sys.stdout.write(out.decode("ascii", "replace"))
    if b"Awaiting" not in out:
        print("\n[upload] ERROR: bootloader not in upload mode; aborting.")
        ser.close()
        return

    # stream the binary (small chunks to stay comfortable at 19200 baud)
    for i in range(0, len(payload), 64):
        ser.write(payload[i:i + 64])
        ser.flush()
        time.sleep(0.01)
    out = read_until(ser, b"CMD:>", 6.0)
    log_bytes.extend(out)
    sys.stdout.write("\n" + out.decode("ascii", "replace"))

    if b"OK" not in out:
        print("\n[upload] WARNING: did not see 'OK' after upload (signature/checksum?).")

    # execute
    ser.write(b"e")
    time.sleep(args.run_secs)
    out = ser.read(20000)
    log_bytes.extend(out)
    sys.stdout.write(out.decode("ascii", "replace"))
    ser.close()

    if args.log:
        with open(args.log, "wb") as f:
            f.write(bytes(log_bytes))
        print(f"\n[upload] raw output saved to {args.log}")
    print("[upload] done")


if __name__ == "__main__":
    main()
