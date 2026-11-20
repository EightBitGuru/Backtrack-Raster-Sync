#!/usr/bin/env python3
r"""Drive the BackTrak raster sync in xvic and record what each IRQ handler entry sees.

    python -I brs_probe.py pal 300          # build, run 300 IRQs in a PAL machine, print a table
    python -I brs_probe.py ntsc 300

At the stable point of service_irq (a breakpoint before its first instruction, after the jitter slide) the monitor gives the raster line and cycle (LIN, CYC) and
the CPU cycle stopwatch; the harness also reads the sync state and the return address that the IRQ pushed (so which
NOP of the spin loop was interrupted). From those it prints the cycles since the last IRQ and the raster position, which is what
shows whether the sync backtracks one cycle a frame, locks, and then enters the handler at the same raster cycle every frame.
"""
import pathlib
import re
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
PROJECT = HERE.parent
BUILD = HERE / "build"
KICK = r"C:\6502\Tools\KickAssembler-5.25\KickAss.jar"
C1541 = r"C:\6502\Tools\GTK3VICE-3.10-win64\bin\c1541.exe"
sys.path.insert(0, str(HERE))
from vice_tool import Machine  # noqa: E402
import vice_run as vr  # noqa: E402

REG = re.compile(r"\.;([0-9a-fA-F]{4}) ([0-9a-fA-F]{2}) ([0-9a-fA-F]{2}) ([0-9a-fA-F]{2}) ([0-9a-fA-F]{2}) [0-9a-fA-F]{2} [0-9a-fA-F]{2} [01]{8} (\d+) (\d+)\s+(\d+)")


def build(defs=(), name="build"):
    """Assemble main.asm into tests/<name> and extract the program from the disk image. defs are NAME=value strings for the assembler
    (for example "slide=0" builds the control without the jitter slide). Returns (prg path, labels, assembler output)."""
    odir = HERE / name
    odir.mkdir(exist_ok=True)
    r = subprocess.run(["java", "-jar", KICK, "main.asm", "-odir", str(odir), "-vicesymbols"] + [":" + d for d in defs], cwd=PROJECT,
                       capture_output=True, text=True)
    if r.returncode:
        raise SystemExit(r.stdout + r.stderr)
    prg = odir / "backtrak.prg"
    if prg.exists():
        prg.unlink()
    subprocess.run([C1541, "-attach", str(odir / "BackTrak.d64"), "-read", "backtrak", str(prg)], capture_output=True, check=True)
    return prg, vr.parse_vs(odir / "main.vs"), r.stdout


def registers(m):
    text = m.mon.cmd("r")
    g = REG.search(text)
    if not g:
        raise RuntimeError("cannot parse registers:\n" + text)
    pc, a, x, y, sp, lin, cyc, watch = g.groups()
    return {"pc": int(pc, 16), "a": int(a, 16), "x": int(x, 16), "sp": int(sp, 16), "lin": int(lin), "cyc": int(cyc), "watch": int(watch)}


def sample(model, frames, extra=None):
    """Run the build in a machine of this video standard and record the first `frames` IRQ handler entries."""
    prg, labels, _ = build()
    rows = []
    with Machine(model) as m:
        m.load(prg)
        entry = labels["stable"]
        m.run_to(entry, start=labels["initialise_sync"])
        for n in range(frames):
            reg = registers(m)
            stack = m.read(0x0100 + reg["sp"] + 1, 0x0100 + reg["sp"] + 6)       # .Y .X .A flags return-lo return-hi
            zp = m.read(0x00FB, 0x00FE)
            row = {"n": n, "lin": reg["lin"], "cyc": reg["cyc"], "watch": reg["watch"], "ret": stack[4] | (stack[5] << 8),
                   "state": zp[2]}
            if extra:
                row.update(extra(m, labels))
            rows.append(row)
            m.resume(entry)
    return rows, labels


def report(rows, labels, frame):
    spin = labels["wait_for_irq"]
    print(f"{'n':>4} {'st':>2} {'LIN':>4} {'CYC':>4} {'dCyc':>6} {'ret':>5} {'nop':>4}")
    prev = None
    for i, r in enumerate(rows):
        d = "" if prev is None else r["watch"] - prev["watch"]
        # show the first and last rows, every row where something changes, and every 25th
        interesting = (prev is None or i == len(rows) - 1 or i % 25 == 0 or r["state"] != prev["state"] or r["ret"] != prev["ret"]
                       or d not in (frame - 1, frame) or (prev["state"] >= 1 and (r["lin"], r["cyc"]) != (prev["lin"], prev["cyc"])))
        if interesting:
            print(f"{r['n']:>4} {r['state']:>2} {r['lin']:>4} {r['cyc']:>4} {d:>6} {r['ret']:04X} {r['ret'] - spin:>4}")
        prev = r


if __name__ == "__main__":
    model = sys.argv[1] if len(sys.argv) > 1 else "pal"
    frames = int(sys.argv[2]) if len(sys.argv) > 2 else 200
    rows, labels = sample(model, frames)
    report(rows, labels, 22152 if model == "pal" else 16965)
