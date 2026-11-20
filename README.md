# <div><div>BackTrak Raster Sync</div><div>Copyright © 2026 [8-Bit Guru](mailto:the8bitguru@gmail.com)</div></div>

BackTrak Raster Sync locks a Commodore VIC-20 program to the raster beam, to the cycle, on both PAL and NTSC machines. The VIC-20 has no raster interrupt, so the usual tricks (watching the raster counter in a loop, or starting a timer from it) leave several cycles of jitter. BackTrak removes it by *backtracking*:

1. A free-running VIA #2 timer interrupts once per frame, but with a period one cycle short of a whole frame, so each IRQ lands one cycle earlier against the raster than the one before. The first period is made shorter still, so that the first IRQ lands just inside the zero window of the raster counter and backtracking starts close to its edge.
2. The program spins in a loop of exact length, so that every IRQ interrupts the same instruction and the CPU's instruction-completion delay is the same every time.
3. The IRQ handler reads the raster counter. The first time it is no longer on line 0/1 the sync has backtracked across the start of the frame, which pins the beam position to a single cycle.
4. The next IRQ restarts the timer, with a first period shortened by a calibrated number of cycles and then on a period of exactly one frame, so that every IRQ from then on is at the same place in the frame.
5. The program's main loop now takes over from the spin loop. Whichever instruction it is running when the IRQ arrives, the handler reads how late the IRQ was from the timer, and slides by the difference, so that from a fixed point in the handler (the *stable point*) every IRQ is at raster line 0, cycle 0.

**NOTE:** this is a beta. The lock is verified in VICE 3.10 (see [Building](#building)), and the cycle cuts that place it at raster line 0, cycle 0 were measured there. It has not yet been checked on real hardware.

## License

The BackTrak Raster Sync project is hosted on [GitHub](https://github.com/EightBitGuru/Backtrack-Raster-Sync).

Creation of modified or derivative works using, in whole or in part, any sourcecode, assets, or binary artifact originating from this project is subject to the following:

* **Free for non-commercial use** (you must clearly include a credit link to this project within your project).

* **Commercial use is expressly forbidden** except by explicit consent from the copyright holder.

## Quickstart

**BackTrak.d64** holds the program, built from the sources in this folder. Start ***xvic*** with it:

    xvic.exe -model vic20pal -autostart BackTrak.d64
    xvic.exe -model vic20ntsc -autostart BackTrak.d64

VICE loads and runs it. The program locks the raster (in about a third of a second) and then draws a column of colour bars down the screen: a stripe of colour 16 cycles wide that starts and ends on the same cycle of every raster line, a new colour every three lines. If the sync is stable the edges of the column are straight and do not move from frame to frame; a sync with jitter makes them shake. The bars are drawn by `run_raster_effects` in `BRS_raster_effects.asm`, from the IRQ's stable point. To look at the sync itself, use the test scripts described in [Building](#building), or open the VICE monitor and break at the `stable` label (see `main.vs` for the address): the register line shows `LIN 0 CYC 0` on every hit once the sync state (`$FD`) is 4.

## Building

Tools: [KickAssembler 5.25](https://theweb.dk/KickAssembler/Main.html#frontpage) (needs Java), and [VICE 3.10](https://vice-emu.sourceforge.io/) to run it. Python 3 is needed for the tests.

    java -jar KickAss.jar main.asm -vicesymbols       builds BackTrak.d64 and main.vs

The build checks its own timing: it solves the spin loop counts for PAL and NTSC, and stops with a message if a loop would cross a page, if the program would run into the screen at `$1E00`, or if a change to a cycle count leaves no solution.

The tests drive ***xvic*** through its remote monitor. They are in `tests\` and use the paths at the top of `brs_probe.py` and `vice_tool.py`:

    python -I tests\brs_probe.py pal 260               prints, for each IRQ, the sync state, the raster line and cycle, the cycles since the last IRQ and the interrupted instruction
    python -I tests\brs_check.py                       checks the lock on PAL and NTSC from several start phases, from BASIC, and over 1000 IRQs
    python -I tests\brs_check.py quick                 the same, shortened
    python -I tests\brs_jitter.py                      checks that the stable point does not move whatever instructions the main program is running
    python -I tests\brs_jitter.py pal random           one machine and one test program, with the last rows of the table
    python -I tests\brs_bars.py                        checks that every stripe of the colour bars starts and ends on the same cycle of its line in every frame while the main program is interrupted at every phase, and measures the stripe's edges in six screenshots (tests\build\shots). It also builds a control without the jitter slide (the command line option `:slide=0`), which must fail

## Compatibility

The program is for an unexpanded VIC-20, PAL or NTSC (detected at run time). It starts from a BASIC stub at `$1001`, and the build stops if the program would reach the screen at `$1E00`. It uses only documented NMOS 6502 opcodes.

## Programming caveats

* The program takes over the IRQ vector (`$0314`) and VIA #2 timer 1, so the KERNAL's jiffy clock, keyboard scan and cursor flash stop. It never returns to BASIC.
* It uses zero-page locations `$03-$05` and `$FB-$FD` (`$06` and `$FE` are spare). `$03` and `$04` hold the line values for the colour bars. A main program must leave all of them alone.
* The timing depends on the KERNAL IRQ stub at `$FF72` (it adds 36 cycles between the VIA interrupt and the program's handler, and the handler leaves with the same register restore as the KERNAL exit at `$EB15`). A different KERNAL (JiffyDOS, for example) needs its entry cost re-measured: see `IRQ_ENTRY` in `BRS_runtime_constants.asm`.
* Once locked, the main program is whatever `main_loop` jumps to (it is a `JMP` to itself until you change it). The IRQ may interrupt any instruction of it. The handler clears the Decimal flag; the interrupted code gets its flags back.
* The IRQ handler's stable point is 72 cycles after the timer underflow, and the state routines (`hold_sync`, and so the raster effects) start from there. The jitter cancellation covers an IRQ response of 1 to 8 cycles, which is every 6502 instruction. A main program that disables interrupts for longer than a frame, or that changes VIA #2 timer 1, will lose the lock.
* The colour bars take most of each frame inside the IRQ handler: about 17,000 cycles of a PAL frame and 15,700 of an NTSC one (240 raster lines). That leaves the main program about 5,000 cycles a PAL frame and 1,300 an NTSC frame. Reduce `BAR_LINES` in `BRS_runtime_constants.asm` for more.
* The cycle cuts differ between the two standards because the VIC's raster counter reads zero from a slightly different beam position on each, in VICE. If the lock is not at line 0, cycle 0 on real hardware, `PAL_ARM_CUT` and `NTSC_ARM_CUT` in `BRS_runtime_constants.asm` are the values to tune: add the number of cycles late that `brs_probe.py` shows, or the number of cycles to the line if the stable point is early. `PAL_FIRST_CUT` and `NTSC_FIRST_CUT` only affect how quickly the lock is found (they aim the first IRQ about 14 cycles inside the zero window, and must not put it outside).

## Release history

### Beta 4 (20th November 2026)
* Tweaked the lock to take about 17 IRQs (a third of a second) instead of about 200 on PAL and 100 on NTSC: the timer starts with a shortened first period, so that backtracking starts at the edge of the zero window of the raster counter instead of 105 cycles from it, and the arm state restarts the timer with a shortened first period instead of waiting for backtracking to move the IRQ into place
* Removed the settle and release states and the timer values in zero-page: the arm state works the shortened and locked latches out from the latch the timer is using, and starts the main program itself

### Beta 3 (20th November 2026)
* Added colour bars as the first raster effect: a 16-cycle stripe on each of 240 raster lines, with every write on the same cycle of its line for both PAL (71 cycles a line) and NTSC (65), from the IRQ's stable point
* Added `tests\brs_bars.py`, which checks the cycle of every stripe write in three frames while a random main program is interrupted at every phase, measures the stripe edges in six screenshots, and runs a control build without the jitter slide that must fail (the build option `:slide=0`)
* Tweaked the sync values table to hold the line values for the bars, which `initialise_sync` copies over the timer values once the timer has started

### Beta 2 (20th November 2026)
* Added jitter cancellation: the IRQ handler reads the timer to find how late the IRQ was taken and slides by the difference, so its stable point is the same cycle whatever instruction the main program was running
* Added the release of the spin loop: when the lock is made the IRQ returns to `main_loop`, and every later IRQ interrupts the main program
* Added `tests\brs_jitter.py`, which runs four test programs (a random mix of 2 to 7 cycle instructions, and fixed loops of mixed, 7-cycle and 2-cycle instructions with the timer period stepped to move the IRQ through every phase) and checks the stable point
* Added a hook, `run_raster_effects`, which the locked state calls at the stable point
* Fixed a bug where the NTSC sync started its timer too late to read `$9004` inside its zero window, which is 88 cycles on NTSC against 143 on PAL (xvic 3.10), so each standard now starts the timer on its own raster line
* Tweaked the PAL and NTSC settle counts for the new handler timing (PAL 81 and NTSC 77 frames)

### Beta 1 (20th November 2026)
* Added backtracking raster sync for PAL and NTSC, locking every IRQ handler to raster line 0, cycle 0
* Added build-time solving of the spin loop counts from the cycle model, with checks that stop the build if a loop crosses a page or the program is too long
* Added `tests`, which drive ***xvic*** to check the lock from several start phases, from BASIC and over 1000 IRQs
* Fixed a bug where the VIA timer was never started, because the sync wrote the timer latch rather than the counter
* Fixed a bug where the NTSC flag was never set
* Fixed a bug where the lock state and the timer value shared a zero-page location
* Tweaked the timer values and loop lengths to include the cost of the KERNAL IRQ stub
* Refactored the code and names to the 6502 coding standards, with the project files renamed to the `BRS_` prefix
* Removed the Common-VIC20 submodule reference, because the common files are now part of the project

# Who is 8-Bit Guru?

8-Bit Guru (also: Eight-Bit Guru, 8BitGuru, 8BG) is the *nom de guerre* of Mark Johnson. I'm a professional coder from the UK who has been telling computers what to do since 1981. My day job is all about C# and Azure, whilst my hobby projects mostly involve writing 6502 machine code for the Commodore VIC-20.
