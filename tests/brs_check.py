#!/usr/bin/env python3
r"""Check that the BackTrak raster sync locks, and stays locked, whatever the raster phase it starts at.

    python -I brs_check.py              # PAL and NTSC, several start phases, then the real BASIC autostart, then a long soak
    python -I brs_check.py quick        # PAL and NTSC, two start phases

Each trial runs the sync in a fresh xvic and expects, once the state reaches 3 (locked):
  * every IRQ's stable point (after the jitter slide) at raster line 0, cycle 0, as the monitor counts them
  * the cycles between IRQs exactly one frame (22152 PAL, 16965 NTSC)
  * the same NOP of the spin loop interrupted every time
The start phase is varied by single-stepping a different number of BASIC instructions before the program starts.
"""
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))   # python -I does not put the script's folder on the path
import brs_probe as bp
from vice_tool import Machine

FRAME = {"pal": 22152, "ntsc": 16965}


def run_trial(model, steps=0, autostart=False, frames=270):
    prg, labels, _ = bp.build()
    rows = []
    with Machine(model, memory="none" if autostart else "all") as m:       # the program is for an unexpanded VIC-20, where BASIC starts at $1001
        entry = labels["stable"]
        m.load(prg)
        if autostart:                              # start the way a user does: BASIC runs the program and SYSes into the stub's address
            m.write(0x0277, bytes([0x52, 0x55, 0x4E, 0x0D]))   # "RUN" and RETURN in the keyboard buffer
            m.write(0x00C6, bytes([4]))
            m.mon.cmd(f"break {entry:04x}")
            for _ in range(5):                     # the initbreak at BASIC READY stops once more before RUN is processed
                m.mon.send_only("x")
                stop = m.mon.read_to_prompt(60)
                if f"(C:${entry:04x})" in stop:
                    break
            else:
                raise RuntimeError("BASIC never ran the program into the stable point")
        else:
            if steps:
                m.mon.cmd(f"z {steps}")
            m.run_to(entry, start=labels["initialise_sync"])
        for n in range(frames):
            reg = bp.registers(m)
            zp = m.read(0x00FB, 0x00FE)
            stack = m.read(0x0100 + reg["sp"] + 1, 0x0100 + reg["sp"] + 6)
            rows.append({"n": n, "lin": reg["lin"], "cyc": reg["cyc"], "watch": reg["watch"], "state": zp[2], "ret": stack[4] | (stack[5] << 8)})
            m.resume(entry)
    return rows


def judge(model, rows):
    """Returns (ok, message) for the rows of one trial."""
    frame = FRAME[model]
    locked = [i for i, r in enumerate(rows) if r["state"] >= 2]
    if not locked:
        return False, "never locked in %d IRQs" % len(rows)
    first = locked[0]                              # the first IRQ after the arm state, whose period is the shortened first period
    tail = rows[first + 1:]
    bad = []
    for prev, r in zip(rows[first:], tail):
        if (r["lin"], r["cyc"]) != (0, 0):
            bad.append("stable point at LIN %d CYC %d" % (r["lin"], r["cyc"]))
        if r["watch"] - prev["watch"] != frame:
            bad.append("spacing %d" % (r["watch"] - prev["watch"]))
        if r["ret"] != tail[0]["ret"]:
            bad.append("interrupted %04X not %04X" % (r["ret"], tail[0]["ret"]))
    if (rows[first]["lin"], rows[first]["cyc"]) != (0, 0):
        bad.append("first locked stable point at LIN %d CYC %d" % (rows[first]["lin"], rows[first]["cyc"]))
    if bad:
        return False, "locked at IRQ %d but %d deviations, first: %s" % (first, len(bad), bad[0])
    return True, "locked at IRQ %d, then %d IRQs all at LIN 0 CYC 0, %d apart, main loop %04X" % (first, len(tail), frame, tail[0]["ret"])


def main():
    quick = len(sys.argv) > 1 and sys.argv[1] == "quick"
    failures = 0
    for model in ("pal", "ntsc"):
        for steps in ((0, 5) if quick else (0, 1, 2, 3, 5, 8, 13, 21)):
            ok, msg = judge(model, run_trial(model, steps))
            failures += not ok
            print(f"{model:4} start phase steps={steps:<3} {'ok  ' if ok else 'FAIL'} {msg}", flush=True)
    if not quick:
        for model in ("pal", "ntsc"):
            ok, msg = judge(model, run_trial(model, autostart=True))
            failures += not ok
            print(f"{model:4} BASIC RUN        {'ok  ' if ok else 'FAIL'} {msg}", flush=True)
        for model in ("pal", "ntsc"):
            ok, msg = judge(model, run_trial(model, frames=1000))
            failures += not ok
            print(f"{model:4} soak 1000 IRQs   {'ok  ' if ok else 'FAIL'} {msg}", flush=True)
    print("ALL OK" if not failures else f"{failures} FAILED")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
