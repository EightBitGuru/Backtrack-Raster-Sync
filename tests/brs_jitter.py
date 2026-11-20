#!/usr/bin/env python3
r"""Check that the sync's jitter cancellation holds whatever instruction the IRQ interrupts.

    python -I brs_jitter.py             # PAL and NTSC, four main programs each
    python -I brs_jitter.py pal mixed   # one machine and one program, with the table of values

Each trial builds the sync, assembles jitter_main.asm, runs the sync in a fresh xvic and patches the JMP in main_loop to the chosen
test program, which the arm state then starts. Two breakpoints are used for every IRQ:
  slide1  the first instruction of the slide: .A is the number of cycles the slide is about to take up (it must be 0-7), and the raster
          position here is where the IRQ really was, with the jitter still in it
  stable  the stable point after the slide: this must be raster line 0, cycle 0 every time, wherever the IRQ landed
It expects, from the first IRQ after the release:
  * the stable point at LIN 0 CYC 0 every IRQ, and the IRQs exactly one frame apart (the 'random' program)
  * every slide value between 0 and 7, and 1 to 7 all seen in the 'random' program and in the scan of 'sevens' (a late IRQ takes 1 to 7
    cycles to be taken in the model, so slide 0 is a spare for an IRQ that is later still: see CORRECT_X)
  * (for the loops that are the same every pass) the timer period raised from the frame to the frame plus 15 cycles, six IRQs at a time,
    and every period exactly what was set: that is the cancellation holding whatever phase the loop was interrupted at
"""
import pathlib
import subprocess
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))   # python -I does not put the script's folder on the path
import brs_probe as bp
from vice_tool import Machine

FRAME = {"pal": 22152, "ntsc": 16965}
PROGRAMS = ("random", "mixed", "sevens", "twos")
SCANNED = ("mixed", "sevens", "twos")        # these loops are the same every pass, so the timer period is stepped to move the IRQ through them


def build_test_programs():
    """Assemble jitter_main.asm. Returns (prg path, labels)."""
    out = bp.BUILD / "jitter_main.prg"
    r = subprocess.run(["java", "-jar", bp.KICK, "jitter_main.asm", "-o", str(out), "-odir", str(bp.BUILD), "-vicesymbols"], cwd=bp.HERE,
                       capture_output=True, text=True)
    if r.returncode:
        raise SystemExit(r.stdout + r.stderr)
    return out, bp.vr.parse_vs(bp.BUILD / "jitter_main.vs")


def run_trial(model, program, irqs=400, scan=0):
    """Run the sync with this test program as its main program and record the IRQs up to `irqs` after the release. Returns a list of rows.

    With scan = N, the harness also lengthens the timer period by 0, 1, 2 ... N-1 cycles, six IRQs at a time (the latch is written at an
    IRQ, which makes the period after the next one that much longer). That moves the IRQ against a loop that is the same every pass,
    one cycle further each step, so the loop is interrupted at every phase of its instructions."""
    prg, labels, _ = bp.build()
    test_prg, test_labels = build_test_programs()
    slide, stable = labels["slide1"], labels["stable"]
    rows = []
    first_locked = None
    with Machine(model) as m:
        m.load(prg)
        m.load(test_prg)
        target = test_labels[program]
        m.write(labels["main_loop"] + 1, bytes([target & 0xFF, target >> 8]))      # the operand of main_loop's JMP
        pc = m.run_to(slide, stable, start=labels["initialise_sync"])
        row = {}
        while len(rows) < 800 and (first_locked is None or len(rows) - first_locked < irqs):
            reg = bp.registers(m)
            if pc == slide:
                row = {"slide": reg["a"], "pre_lin": reg["lin"], "pre_cyc": reg["cyc"]}
            else:
                zp = m.read(0x00FB, 0x00FE)
                row.update({"lin": reg["lin"], "cyc": reg["cyc"], "watch": reg["watch"], "state": zp[2]})
                if zp[2] == 2 and first_locked is None:
                    first_locked = len(rows)
                    latch = m.read(0x9126, 0x9126)[0]
                row["i"] = None if first_locked is None else len(rows) - first_locked
                if scan and first_locked is not None and row["i"] % 6 == 0 and row["i"] // 6 < scan:
                    m.write(0x9126, bytes([latch + row["i"] // 6]))
                rows.append(row)
                row = {}
            pc = m.resume(slide, stable)
    return rows


def judge(model, program, rows, scan=0):
    """Returns (ok, message) for the rows of one trial."""
    frame = FRAME[model]
    after = [i for i, r in enumerate(rows) if r.get("state") == 2]
    if not after:
        return False, "the sync never reached the locked state"
    rows = rows[after[0]:]                      # from the first IRQ that interrupts the main program
    bad = []
    slides = set()
    for prev, r in zip(rows, rows[1:]):
        slides.add(r["slide"])
        if scan:
            # the period after the IRQ numbered k is frame + (k - 1) // 6 cycles (the latch written at IRQ 6j takes effect a period later)
            expected = frame + min(max((prev["i"] - 1) // 6, 0), scan - 1)
            if r["watch"] - prev["watch"] != expected:
                bad.append("IRQ %d to IRQ %d took %d cycles, not %d (slide %d)" % (prev["i"], r["i"], r["watch"] - prev["watch"], expected, r["slide"]))
        else:
            if (r["lin"], r["cyc"]) != (0, 0):
                bad.append("stable point at LIN %d CYC %d (slide %d)" % (r["lin"], r["cyc"], r["slide"]))
            if r["watch"] - prev["watch"] != frame:
                bad.append("spacing %d" % (r["watch"] - prev["watch"]))
        if r["slide"] > 7:
            bad.append("slide %d out of range" % r["slide"])
    # raster position of the slide's first instruction, in cycles from the line 0 start, to see the jitter the slide took up
    line = 71 if model == "pal" else 65
    lines = frame // line
    pre = [(r["pre_lin"] if r["pre_lin"] < lines // 2 else r["pre_lin"] - lines) * line + r["pre_cyc"] for r in rows[1:]]
    spread = max(pre) - min(pre)
    if bad:
        return False, "%d deviations in %d IRQs, first: %s; slides %s" % (len(bad), len(rows) - 1, bad[0], "".join(str(v) for v in sorted(slides)))
    if program in ("random", "sevens") and not slides >= set(range(1, 8)):
        return False, "stable, but the test did not exercise every slide: only %s" % "".join(str(v) for v in sorted(slides))
    what = "each period exactly as set (frame plus 0 to %d), " % (scan - 1) if scan else "stable point always LIN 0 CYC 0, %d apart, " % frame
    return True, "%d IRQs, %sslides %s" % (len(rows) - 1, what, "".join(str(v) for v in sorted(slides)))


def main():
    models = [sys.argv[1]] if len(sys.argv) > 1 else ["pal", "ntsc"]
    programs = [sys.argv[2]] if len(sys.argv) > 2 else PROGRAMS
    failures = 0
    for model in models:
        for program in programs:
            scan = 16 if program in SCANNED else 0
            rows = run_trial(model, program, irqs=6 * scan + 6 if scan else 400, scan=scan)
            ok, msg = judge(model, program, rows, scan)
            failures += not ok
            print(f"{model:4} {program:7} {'ok  ' if ok else 'FAIL'} {msg}", flush=True)
            if len(sys.argv) > 2:
                for r in rows[-40:]:
                    print("   ", r)
    print("ALL OK" if not failures else f"{failures} FAILED")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
