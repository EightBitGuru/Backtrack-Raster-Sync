#!/usr/bin/env python3
r"""Helpers for driving xvic from Python: start a machine, load programs, run to a label and read or write memory.

    from vice_tool import Machine, assemble
    prg, labels = assemble("mytest.asm", base=0x4000)          # KickAssembler, returns the PRG path and VICE labels
    with Machine("ntsc") as m:                                  # boots to BASIC READY, then the monitor has control
        m.load(package_prg)
        m.load(prg)
        m.run_to(labels["done"], start=labels["start"])
        data = m.read(0x1000, 0x1FFF)

Built on vice_run.Monitor. The machine has all RAM blocks present (-memory all) unless memory= says otherwise (for example memory="8k" for an 8K expander), no sound, warp speed.
"""
import importlib.util
import os
import pathlib
import re
import subprocess
import sys
import socket
import tempfile
import time

HERE = pathlib.Path(__file__).resolve().parent
BUILD = HERE / "build"
KICK = r"C:\6502\Tools\KickAssembler-5.25\KickAss.jar"

_spec = importlib.util.spec_from_file_location("vice_run", HERE / "vice_run.py")
vr = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(vr)


def _free_port():
    """A TCP port that nothing is listening on, so that machines started by test runs in parallel cannot choose the same one."""
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def assemble(source, out=None, defs=(), odir=None, libdir=None, cwd=None):
    """Assemble with KickAssembler. defs are NAME=value strings (decimal values). Returns (prg path, {label: address})."""
    source = pathlib.Path(source)
    cwd = pathlib.Path(cwd) if cwd else source.parent
    odir = pathlib.Path(odir) if odir else BUILD
    odir.mkdir(parents=True, exist_ok=True)
    out = pathlib.Path(out) if out else odir / (source.stem + ".prg")
    cmd = ["java", "-jar", KICK, str(source.resolve()), "-o", str(out.resolve()), "-vicesymbols", "-odir", str(odir.resolve())]
    if libdir:
        cmd += ["-libdir", str(pathlib.Path(libdir).resolve())]
    cmd += [f":{d}" for d in defs]
    r = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)
    if r.returncode:
        raise RuntimeError(f"assembly of {source} failed:\n{r.stdout}\n{r.stderr}")
    vs = odir / (source.stem + ".vs")
    return out, (vr.parse_vs(vs) if vs.exists() else {}), r.stdout


class Machine:
    def __init__(self, model="ntsc", kernal=None, verbose=False, extra_args=(), memory="all"):
        self.verbose = verbose
        self.proc = None
        for attempt in range(3):          # xvic occasionally fails to open its monitor; relaunch (on a new port) rather than abort
            self.port = _free_port()
            args = [vr.XVIC, "-default", "-model", "vic20" + model, "-memory", str(memory), "+sound", "-warp", "-windowxpos", "0", "-windowypos", "0",
                    "-jamaction", "2", "-initbreak", "0xC474", "-remotemonitor", "-remotemonitoraddress", f"ip4://127.0.0.1:{self.port}"]
            if kernal:
                args += ["-kernal", str(kernal)]
            args += list(extra_args)
            self.proc = subprocess.Popen(args, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            try:
                self.mon = vr.Monitor(self.port, verbose)
                break
            except RuntimeError:
                self.proc.kill()
                self.proc.wait()
        else:
            raise RuntimeError("could not connect to the xvic remote monitor after 3 launches")

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        self.close()

    def close(self):
        try:
            self.mon.send_only("quit")
        except Exception:
            pass
        try:
            self.proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            self.proc.kill()

    # --- loading and running -------------------------------------------------------------------
    def load(self, path):
        text = self.mon.cmd(f'load "{pathlib.Path(path).resolve().as_posix()}" 0')
        if "rror" in text or "ailed" in text:
            raise RuntimeError(f"load of {path} failed:\n{text}")

    def run_to(self, *stops, start=None, timeout=600):
        """Set breakpoints on the given addresses, run (from start, or from the current PC) and return the one hit."""
        for s in stops:
            self.mon.cmd(f"break {s:04x}")
        self.mon.send_only(f"g {start:04x}" if start is not None else "x")
        text = self.mon.read_to_prompt(timeout)
        pcs = re.findall(r"\(C:\$([0-9a-fA-F]{4})\) $", text)
        pc = int(pcs[-1], 16) if pcs else None
        if pc not in stops:
            raise RuntimeError(f"stopped at {pc}, expected one of {[hex(s) for s in stops]}\n{text[-500:]}")
        return pc

    def resume(self, *stops, timeout=600):
        """Continue after a breakpoint (the breakpoints stay set)."""
        self.mon.send_only("x")
        text = self.mon.read_to_prompt(timeout)
        pcs = re.findall(r"\(C:\$([0-9a-fA-F]{4})\) $", text)
        pc = int(pcs[-1], 16) if pcs else None
        if stops and pc not in stops:
            raise RuntimeError(f"stopped at {pc}, expected one of {[hex(s) for s in stops]}\n{text[-500:]}")
        return pc

    def delete_breaks(self):
        self.mon.cmd("delete")

    # --- memory ---------------------------------------------------------------------------------
    def read(self, lo, hi):
        return self.mon.read_mem(lo, hi)

    def write(self, addr, data):
        for i in range(0, len(data), 16):
            chunk = data[i:i + 16]
            self.mon.cmd(f"> {addr + i:04x} " + " ".join(f"{b:02x}" for b in chunk))

    def registers(self):
        text = self.mon.cmd("r")
        m = re.search(r"\.;([0-9a-fA-F]{4}) ([0-9a-fA-F]{2}) ([0-9a-fA-F]{2}) ([0-9a-fA-F]{2}) ([0-9a-fA-F]{2}) ([0-9a-fA-F]{2})", text)
        if not m:
            raise RuntimeError("could not parse the register line:\n" + text)
        pc, a, x, y, sp, _ = (int(g, 16) for g in m.groups())
        return {"pc": pc, "a": a, "x": x, "y": y, "sp": sp}

    def dump64k(self, path):
        """Save all 64 KB (as the CPU sees it) to a host file with the monitor's save command."""
        path = pathlib.Path(path)
        if path.exists():
            path.unlink()
        self.mon.cmd(f'save "{path.resolve().as_posix()}" 0 0000 ffff', timeout=120)
        return path.read_bytes()[2:]            # skip the 2-byte PRG load address

    def stopwatch(self):
        m = re.search(r"Stopwatch:\s+(\d+)", self.mon.cmd("stopwatch"))
        return int(m.group(1))


if __name__ == "__main__":
    sys.exit("import this module")
