#!/usr/bin/env python3
"""Run the comparison test stream in xvic and capture a memory snapshot at each marker.

    vice_run.py --out golden/ntsc --model ntsc --cart fast40.bin --driver build/driver_gold.prg --vs build/driver.vs

Mechanism: xvic is started with -initbreak 0xC474 (BASIC READY) and the remote monitor. Once BASIC reaches READY the
emulator blocks until this script connects. The script then loads the driver (and any --load files) from
the host file system with the monitor 'load' command, sets breakpoints on the driver's 'snapshot' and
'finished' labels, and runs. At each breakpoint it reads memory with the monitor 'm' command.

Each snapshot is one file <name>.bin of 4352 bytes:
    [0000:1000)  $1000-$1FFF   character matrix ($1000-$10EF), spare, bitmap ($1100-$1FFF)
    [1000:10F0)  $9400-$94EF   colour matrix
    [10F0:1100)  $9000-$900F   VIC registers
"""
import argparse
import os
import pathlib
import re
import socket
import subprocess
import sys
import time

XVIC = r"C:\6502\Tools\GTK3VICE-3.10-win64\bin\xvic.exe"
# Set L40_KERNAL to a KERNAL ROM image (for example a JiffyDOS ROM) to run every test with it instead of the stock KERNAL.
KERNAL_ARGS = ["-kernal", str(pathlib.Path(os.environ["L40_KERNAL"]))] if os.environ.get("L40_KERNAL") else []   # VICE needs backslashes
PROMPT = re.compile(rb"\(C:\$[0-9a-fA-F]{4}\) $")
REGIONS = [(0x1000, 0x1FFF), (0x9400, 0x94EF), (0x9000, 0x900F)]


class Monitor:
    def __init__(self, port, verbose):
        self.verbose = verbose
        self.sock = None
        deadline = time.time() + 60
        while time.time() < deadline:
            try:
                self.sock = socket.create_connection(("127.0.0.1", port), timeout=2)
                break
            except OSError:
                time.sleep(0.25)
        if self.sock is None:
            raise RuntimeError("could not connect to the xvic remote monitor")
        self.sock.settimeout(1.0)
        self.read_to_prompt(60)

    def read_to_prompt(self, timeout):
        buf = b""
        deadline = time.time() + timeout
        while time.time() < deadline:
            try:
                chunk = self.sock.recv(65536)
            except socket.timeout:
                continue
            if not chunk:
                raise RuntimeError("monitor connection closed; output so far:\n" + buf.decode("latin1"))
            buf += chunk
            if PROMPT.search(buf):
                break
        else:
            raise RuntimeError("timed out waiting for monitor prompt; output so far:\n" + buf.decode("latin1"))
        text = buf.decode("latin1")
        if self.verbose:
            print(text.rstrip().encode("ascii", "replace").decode()[:600])
        return text

    def cmd(self, line, timeout=30):
        if self.verbose:
            print(f"> {line}")
        self.sock.sendall(line.encode("ascii") + b"\n")
        return self.read_to_prompt(timeout)

    def send_only(self, line):
        if self.verbose:
            print(f"> {line}")
        self.sock.sendall(line.encode("ascii") + b"\n")

    def read_mem(self, lo, hi):
        text = self.cmd(f"m {lo:04x} {hi:04x}")
        data = {}
        for m in re.finditer(r"^>C:([0-9a-fA-F]{4}) {2}((?:[0-9a-fA-F]{2} {1,2}){1,16})", text, re.M):
            addr = int(m.group(1), 16)
            for i, b in enumerate(m.group(2).split()):
                data[addr + i] = int(b, 16)
        missing = [a for a in range(lo, hi + 1) if a not in data]
        if missing:
            raise RuntimeError(f"memory read ${lo:04X}-${hi:04X} incomplete ({len(missing)} bytes missing)\n{text[:400]}")
        return bytes(data[a] for a in range(lo, hi + 1))


def parse_vs(path):
    labels = {}
    for line in pathlib.Path(path).read_text().splitlines():
        m = re.match(r"al C:([0-9a-fA-F]+) \.(\w+)", line)
        if m:
            labels[m.group(2)] = int(m.group(1), 16)
    return labels


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--model", choices=["ntsc", "pal"], default="ntsc")
    ap.add_argument("--cart", help="cartridge image attached at $A000")
    ap.add_argument("--driver", required=True, help="driver .prg (load address in header)")
    ap.add_argument("--vs", required=True, help="driver VICE symbol file")
    ap.add_argument("--load", action="append", default=[], help="extra .prg to load before running")
    ap.add_argument("--snaps", default=str(pathlib.Path(__file__).with_name("snaps.json")))
    ap.add_argument("--expect-vic5", help="hex value $9005 must have at READY (e.g. CC for the original cart)")
    ap.add_argument("--port", type=int, default=6510)
    ap.add_argument("--verbose", action="store_true")
    a = ap.parse_args()

    import json
    snaps = json.loads(pathlib.Path(a.snaps).read_text())
    labels = parse_vs(a.vs)
    out = pathlib.Path(a.out)
    out.mkdir(parents=True, exist_ok=True)

    args = [XVIC, "-default", "-model", "vic20" + a.model, "-memory", "all", "+sound", *KERNAL_ARGS, "-warp", "-windowxpos", "0", "-windowypos", "0",
            "-jamaction", "2", "-initbreak", "0xC474", "-remotemonitor", "-remotemonitoraddress", f"ip4://127.0.0.1:{a.port}"]
    if a.cart:
        args += ["-cartA", a.cart]
    for attempt in range(3):            # xvic occasionally fails to open its monitor; relaunch rather than abort
        proc = subprocess.Popen(args, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        try:
            mon = Monitor(a.port, a.verbose)
            break
        except RuntimeError:
            proc.kill()
            proc.wait()
    else:
        raise RuntimeError("could not connect to the xvic remote monitor after 3 launches")
    try:
        if a.expect_vic5:
            got = mon.read_mem(0x9005, 0x9005)[0]
            if got != int(a.expect_vic5, 16):
                raise RuntimeError(f"$9005 = ${got:02X} at READY, expected ${a.expect_vic5}")
        for f in a.load + [a.driver]:
            text = mon.cmd(f'load "{pathlib.Path(f).resolve().as_posix()}" 0')
            if "rror" in text or "ailed" in text:
                raise RuntimeError(f"load of {f} failed:\n{text}")
        for lab in ("snapshot", "finished"):
            mon.cmd(f"break {labels[lab]:04x}")
        start = labels["start"]
        mon.send_only(f"g {start:04x}")
        for name in snaps + ["<finished>"]:
            text = mon.read_to_prompt(120)
            pc = re.findall(r"\(C:\$([0-9a-fA-F]{4})\) $", text)
            pc = int(pc[-1], 16) if pc else None
            want = labels["finished"] if name == "<finished>" else labels["snapshot"]
            if pc != want:
                raise RuntimeError(f"expected stop at ${want:04X} for '{name}', stopped at {pc}\n{text[-600:]}")
            if name == "<finished>":
                break
            blob = b"".join(mon.read_mem(lo, hi) for lo, hi in REGIONS)
            (out / f"{name}.bin").write_bytes(blob)
            print(f"  {name}")
            mon.send_only("x")
        mon.send_only("quit")
        print(f"{len(snaps)} snapshots -> {out}")
    finally:
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()


if __name__ == "__main__":
    sys.exit(main())
