#!/usr/bin/env python3
r"""Check that the colour bars are cycle-exact, whatever the main program is doing, and take screenshots of them.

    python -I brs_bars.py               # PAL and NTSC, with the sync and with the control build that has no jitter slide
    python -I brs_bars.py pal           # one machine

Each trial builds the sync (or the control, ":slide=0"), runs it in a fresh xvic with the 'random' test program from jitter_main.asm as
the main program (so that the IRQ is taken at every phase of its instructions), and records three frames of the bars. The two
breakpoints for every raster line are barwrite (the STA that starts the stripe) and barend (the INX after the stripe ends). It expects
  * every frame to have BAR_LINES lines, the lines numbered 0, 1, 2 ... in order
  * the STA at the same cycle of every line, in every frame, and the INX at the same cycle of every line
  * every line exactly one raster line of cycles after the last
The control build must fail those checks: if it passed, the test could not tell a stable sync from an unstable one.
A screenshot is taken of each trial, after two whole frames with no breakpoints (stopping the machine mid-frame disturbs how xvic draws
the frame), into tests\build\shots. They show the stripe as a column of colour in the border and screen whose edges are straight if
the sync is stable.
"""
import pathlib
import struct
import sys
import zlib

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))   # python -I does not put the script's folder on the path
import brs_probe as bp
import brs_jitter as bj
from vice_tool import Machine

LINE = {"pal": 71, "ntsc": 65}
LINES = 240                                    # BAR_LINES in BRS_runtime_constants.asm
FRAMES = 3
SHOT_COUNT = 6
BORDER_ROWS = {"pal": 40, "ntsc": 16}          # picture rows from the top, all in the border above the screen, where the stripe is the only change
SHOTS = bp.BUILD / "shots"


def read_png(path):
    """Decodes an 8-bit RGBA PNG (what xvic writes). Returns (width, height, rows of bytes, 4 bytes a pixel)."""
    data = pathlib.Path(path).read_bytes()
    pos, idat, width, height = 8, b"", 0, 0
    while pos < len(data):
        length, kind = struct.unpack(">I4s", data[pos:pos + 8])
        body = data[pos + 8:pos + 8 + length]
        if kind == b"IHDR":
            width, height, depth, colour = struct.unpack(">IIBB", body[:10])
            if (depth, colour) != (8, 6):
                raise RuntimeError("expected an 8-bit RGBA picture")
        elif kind == b"IDAT":
            idat += body
        pos += 12 + length
    raw = zlib.decompress(idat)
    stride, rows, prev = width * 4, [], bytearray(width * 4)
    for y in range(height):
        kind, line = raw[y * (stride + 1)], bytearray(raw[y * (stride + 1) + 1:(y + 1) * (stride + 1)])
        for i in range(stride):
            a = line[i - 4] if i >= 4 else 0
            b, c = prev[i], (prev[i - 4] if i >= 4 else 0)
            if kind == 1:
                line[i] = (line[i] + a) & 255
            elif kind == 2:
                line[i] = (line[i] + b) & 255
            elif kind == 3:
                line[i] = (line[i] + (a + b) // 2) & 255
            elif kind == 4:
                pa, pb, pc = abs(b - c), abs(a - c), abs(a + b - 2 * c)
                line[i] = (line[i] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
        rows.append(bytes(line))
        prev = line
    return width, height, rows


def stripe_edges(path, rows_to_check):
    """The (left, right) pixel columns of the stripe on each of the top rows_to_check rows of the picture, for the rows where it shows
    (a row whose stripe colour is the border colour has no visible stripe)."""
    width, height, rows = read_png(path)
    edges = []
    for y in range(rows_to_check):
        row = rows[y]
        pixels = [row[x * 4:x * 4 + 3] for x in range(width)]
        changed = [x for x in range(width) if pixels[x] != pixels[0]]
        if changed:
            edges.append((changed[0], changed[-1] + 1))
    return edges


def run_trial(model, control=False, shot=None):
    """Returns the rows (pc, line, cycle, stopwatch) of FRAMES frames of bars, and the stripe edges of SHOT_COUNT screenshots (the first
    is kept as the file `shot`, the others are temporary)."""
    prg, labels, _ = bp.build(["slide=0"] if control else [], "build_noslide" if control else "build")
    test_prg, test_labels = bj.build_test_programs()
    start, end = labels["barwrite"], labels["barend"]
    rows = []
    with Machine(model) as m:
        m.load(prg)
        m.load(test_prg)
        target = test_labels["random"]
        m.write(labels["main_loop"] + 1, bytes([target & 0xFF, target >> 8]))
        pc = m.run_to(start, end, start=labels["initialise_sync"])
        while len(rows) < FRAMES * LINES * 2:
            reg = bp.registers(m)
            rows.append((pc, reg["lin"], reg["cyc"], reg["watch"]))
            pc = m.resume(start, end)
        m.delete_breaks()
        m.run_to(labels["stable"])
        edges = []
        for n in range(SHOT_COUNT):
            m.run_to(labels["stable"])            # a whole frame with nothing stopping the machine, ending at the next frame's stable point
            path = pathlib.Path(shot) if n == 0 else SHOTS / "temporary.png"
            m.mon.cmd(f'screenshot "{path.as_posix()}" 2')
            edges.append(stripe_edges(path, BORDER_ROWS[model]))
        (SHOTS / "temporary.png").unlink(missing_ok=True)
    return rows, edges


def judge(model, rows, edges):
    """Returns (ok, message): the bars are cycle-exact in every frame, and the picture has one pair of straight edges."""
    line = LINE[model]
    bad = []
    starts = rows[0::2]                         # barwrite and barend alternate, starting with barwrite
    ends = rows[1::2]
    for n, (a, b) in enumerate(zip(starts, ends)):
        frame, k = divmod(n, LINES)
        if a[1] != k:
            bad.append("frame %d: line %d came as line %d" % (frame, k, a[1]))
        if a[2] != starts[0][2]:
            bad.append("frame %d line %d: stripe starts at cycle %d, not %d" % (frame, k, a[2], starts[0][2]))
        if b[2] != ends[0][2] or b[1] != a[1]:
            bad.append("frame %d line %d: stripe ends at line %d cycle %d, not cycle %d" % (frame, k, b[1], b[2], ends[0][2]))
        if k and a[3] - starts[n - 1][3] != line:
            bad.append("frame %d line %d: %d cycles after the last line, not %d" % (frame, k, a[3] - starts[n - 1][3], line))
    columns = set(edge for frame in edges for edge in frame)
    if bad:
        return False, "%d deviations in %d lines, first: %s; picture edges %s" % (len(bad), len(starts), bad[0], sorted(columns))
    if len(columns) != 1:
        return False, "the cycles are exact but the picture has %d different pairs of stripe edges: %s" % (len(columns), sorted(columns))
    return True, "%d frames of %d lines: stripe from cycle %d to cycle %d of every line, %d cycles a line; in %d pictures the stripe is always at pixel columns %d-%d" % (
        FRAMES, LINES, starts[0][2], ends[0][2], line, SHOT_COUNT, *list(columns)[0])


def main():
    models = [sys.argv[1]] if len(sys.argv) > 1 else ["pal", "ntsc"]
    SHOTS.mkdir(exist_ok=True)
    failures = 0
    for model in models:
        rows, edges = run_trial(model, shot=SHOTS / f"bars_{model}.png")
        ok, msg = judge(model, rows, edges)
        failures += not ok
        print(f"{model:4} sync     {'ok  ' if ok else 'FAIL'} {msg}", flush=True)
        rows, edges = run_trial(model, control=True, shot=SHOTS / f"bars_{model}_control.png")
        ok, msg = judge(model, rows, edges)
        failures += ok                          # the control has no jitter slide, so it must fail
        print(f"{model:4} control  {'ok  ' if not ok else 'FAIL'} {'(fails as it should) ' if not ok else '(passed, which it must not) '}{msg}", flush=True)
    print("ALL OK" if not failures else f"{failures} FAILED")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
