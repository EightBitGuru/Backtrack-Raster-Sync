# <div><div>BackTrak Raster Sync</div><div>Copyright Â© 2026 [8-Bit Guru](mailto:the8bitguru@gmail.com)</div></div>

BackTrak Raster Sync locks a Commodore VIC-20 program to the raster beam, to the cycle, on both PAL and NTSC machines, and then runs raster effects whose every colour change is on exactly the cycle it was written for. The VIC-20 has no raster interrupt, so the usual tricks (watching the raster counter in a loop, or starting a timer from it) leave several cycles of jitter. BackTrak removes it by *backtracking*, then keeps it removed by measuring how late every IRQ is and sliding by the difference. A few hundred bytes do the locking; your program keeps the rest of the memory and whatever time the raster effects leave.

**To the author's knowledge, this is the first backtracking raster sync for the VIC-20.** The technique, a timer one cycle short of a frame that walks the IRQ back against the raster counter until the beam position is known to the cycle, did not turn up in any earlier VIC-20 routine that a search for prior art found (see [Comparison with other techniques](#comparison-with-other-techniques)), though one routine, Marko Mäkelä's, has yet to be reviewed.

The demo that comes with it draws three raster effects, one after another, while a main program (which knows nothing of the raster) prints the name of the effect on the screen:

* **Copper bars**: three gradient bars (fire, ice, and black and red) that move up and down the whole picture on their own sine waves.
* **Sine ribbon**: a rainbow ribbon whose edges follow a sine wave, to the cycle, on every raster line.
* **Waving flag**: red, white and blue bands that wave along a shallower sine, and fill the width of the picture.

**NOTE:** this is a beta. The lock and the effects are checked in VICE 3.10, and the cycle counts that place them on raster line 0, cycle 0 were measured there. They have not yet been checked on real hardware.

## License

The BackTrak Raster Sync project is hosted on [GitHub](https://github.com/EightBitGuru/Backtrack-Raster-Sync).

Creation of modified or derivative works using, in whole or in part, any sourcecode, assets, or binary artifact originating from this project is subject to the following:

* **Free for non-commercial use** (you must clearly include a credit link to this project within your project).

* **Commercial use is expressly forbidden** except by explicit consent from the copyright holder.

## Quickstart

**BackTrak.d64** holds the demo, built from the sources in this folder. Start ***xvic*** with it, on an unexpanded machine (see [Memory](#memory)):

    xvic.exe -model vic20pal -memory none -autostart BackTrak.d64
    xvic.exe -model vic20ntsc -memory none -autostart BackTrak.d64

VICE loads and runs it. The screen goes black, the title appears, and in about a third of a second the sync is locked and the first effect starts. The effects change every 256 frames (about five seconds), and the main program puts the name of each on the screen as it changes. To look at the sync itself, open the VICE monitor and break at the `stable` label (see `main.vs` for the address): the register line shows `LIN 0 CYC 0` on every hit once the sync state (`$FD`) is 2.

Run/Stop-Restore does nothing: the program switches the RESTORE key off (see [Programming caveats](#programming-caveats)). Reset the machine to leave it.

## Memory

**The minimum is an unexpanded VIC-20**, which has 5K of RAM: 1K at `$0000-$03FF` and 4K at `$1000-$1FFF`, of which `$1E00-$1FFF` is the screen. No expansion is needed. **The sync itself takes about 420 bytes of it, which leaves about 3,160 bytes (3.1K) free for your own code and data on an unexpanded VIC-20.**

**Which memory configurations it works with.** The KERNAL decides where the screen and BASIC go from the RAM that is fitted (measured in VICE):

| Configuration | Screen | BASIC starts | The program as built |
|---|---|---|---|
| Unexpanded (5K) | `$1E00` | `$1001` | **Works.** It is the configuration the program is built for, on PAL and NTSC. |
| +3K (`$0400-$0FFF`) | `$1E00` | `$0401` | **Works, if loaded to `$1001`**: the program does not move, and the screen is where it expects. BASIC starts at `$0401`, so `RUN` does not find the stub: `LOAD` it with `,8,1` and `SYS` to the address in its BASIC line. |
| +8K, +16K, +24K or more (`$2000` up) | `$1000` | `$1201` | **Does not work as built**: the screen is on top of the program. It needs moving (see below). |

| | Bytes | Where |
|---|---:|---|
| BASIC stub that starts the program | 116 | `$1001-$1074` |
| The sync: start-up, spin loop, IRQ handler, the three states, exit | 282 | |
| The sync's tables (`SYNCVALS` and `STATEJMP`) | 22 | |
| **The sync-lock sequence, all told** | **about 420** | **`$1001-$11A4`** |
| **Left for your code and data** | **about 3,160** | **`$11A5-$1DFF`** |

That is the core: lock the raster, detect PAL or NTSC, cancel the IRQ jitter, and leave your main program running with a stable IRQ at raster line 0, cycle 0. Take out `BRS_raster_effects.asm` and `BRS_main_program.asm` (`hold_sync` calls `run_raster_effects`, so give it an `rts` of its own, and `arm_sync` sends your program to `main_loop`) and about 3.1 KB of the on-board RAM is yours, along with all of the zero page except `$03-$04` and `$FB-$FD`, the stack (the IRQ uses at most eight bytes of it), and `$0200-$0258` and `$033C-$03FB` (the BASIC input buffer and the cassette buffer, which nothing here uses).

**The demo as built uses nearly all of it.** The effects, their tables and the main program take the program to `$1CDC`, and the copper bars' line buffer is the page at `$1D00-$1DF9`, so only about 35 bytes are left (`$1CDD-$1CFF`). To write your own program, replace the demo and you are back to the 3.1 KB above.

**Memory expansions.** The sync does not depend on how much RAM there is: it uses no screen memory, and RAM expansion does not change any cycle count. Only the layout of the demo is tied to the unexpanded machine, because it expects the screen at `$1E00` and BASIC at `$1001`. With 8K or more of RAM at `$2000` the KERNAL moves the screen to `$1000` and BASIC to `$1201`, which is on top of the program (the first thing the demo does is clear that screen). Memory you add at `$0400` (3K) is where your code can go if the on-board RAM is not enough. To run on a machine with more at `$2000` the program and the screen have to be moved apart: the addresses to change are the stub's (`BasicStub(...)` in `main.asm`), the `$1D00` line buffer (a whole page, which has to stay page-aligned), and the screen at `$1E00`, which the demo's title and main program write to through the KERNAL. A version built that way has not been tried.

## How it works

The whole of it rests on one fact about the VIC-20's chips: the VIA timer and the VIC are driven from the same clock, so a timer that is set to exactly one frame of cycles stays at the same place in the frame for ever. The work is getting it to the right place, to the cycle, and keeping it there whatever the CPU was doing when it fired. That takes four phases. The cycle counts are in `BRS_runtime_constants.asm`.

| | PAL | NTSC |
|---|---:|---:|
| Cycles in a raster line | 71 | 65 |
| Raster lines in a frame | 312 | 261 |
| Cycles in a frame (F) | 22,152 | 16,965 |

### Phase 0: start-up

The BASIC stub runs `initialise_screen`, which turns the screen black, prints the title, sets up the effects and falls into `initialise_sync`. That:

1. Disables IRQs and the Decimal flag.
2. Switches off VIA #1's interrupts and points the NMI vector at a bare `RTI` (see [Programming caveats](#programming-caveats)).
3. Points the IRQ vector at `service_irq`. The KERNAL's IRQ routine at `$FF72` pushes `.A`, `.X` and `.Y` and jumps through `$0314`, so the handler is entered 36 cycles after the VIA's interrupt (7 for the 6502's response, 29 for the KERNAL).
4. Tells PAL from NTSC. The raster counter in `$9004` holds the line number divided by two. The code waits for it to read 1, then watches it: an NTSC machine wraps to 0 (it has 261 lines) before it can reach 134, and a PAL machine (312 lines) reaches 134, which is line 268, first.
5. Copies the values for the video standard into zero page: the arm cut, the video standard and the spin loop counts.
6. Sets VIA #2's timer 1 to free-run and enables its interrupt.
7. Waits for the start of the zero window of `$9004`, where it first reads 0, which is the beam on lines 0 and 1. It waits for the counter to leave zero first, because the code might arrive part-way through the window.

### Phase 1: tracking (backtracking)

VIA #2's timer 1 is started and reloads itself every period. The 6522 counts N+2 cycles for a latch of N, so the backtracking latch is F-3, for a period of **F-1 cycles, one cycle less than a frame**. Every IRQ is therefore one cycle earlier against the raster than the one before it.

The timer is not held while an IRQ is handled, so the handler's length makes no difference to the period. What it does decide is where in the main code the IRQ lands, and the design needs it to land on the same instruction every time. The main code is a spin loop whose last instructions are 12 two-cycle NOPs, and the loop and the handler together take exactly the timer period:

    spin loop period + IRQ cycles = timer period

The handler takes 138 cycles (36 for the KERNAL and the 6502, 28 for the jitter correction, 7 for the slide, 23 for the dispatch, 22 for the state routine and 22 to leave through the KERNAL's register restore), so the spin loop takes F-1-138: 22,013 cycles on PAL and 16,826 on NTSC. KickAssembler solves the loop's two counts at build time, and stops the build if there is no solution or if a loop would cross a page (a taken branch that crosses one costs an extra cycle). Because the IRQ lands in the NOPs, the CPU always finishes a two-cycle instruction, so the delay in taking the IRQ is the same every time, and the lockstep holds.

The timer's first period is made shorter than the others: the start-up code writes a shortened latch, starts the timer, and puts the normal latch back with a write to `$9127`, which changes only the latch. That makes the first IRQ read `$9004` about 14 cycles inside the zero window (the window is 143 cycles on PAL but only 88 on NTSC, so the first IRQ has to be aimed), and backtracking has only a few cycles to go.

Each tracking IRQ runs `track_sync`, which reads `$9004` at the same cycle every time. While it reads 0 the beam is on line 0 or 1 and the IRQ is early by one more cycle each frame. The first time it does not read 0, the read has just slid across the start of the window, which fixes the beam to a single cycle. That takes about 12 to 20 IRQs, a third of a second.

### Phase 2: arming

The next IRQ runs `arm_sync`. It knows exactly where in the frame it is (one cycle past the edge), so it restarts the timer with a first period shortened by the arm cut, **93 cycles on PAL and 89 on NTSC**, which moves the next IRQ to the place in the frame that puts its stable point (below) at raster line 0, cycle 0. It then puts in the **locked latch**, F-2, which makes the period exactly **F cycles**, again with a write that leaves the counter alone. Last, it replaces its return address on the stack with the address of your `main_loop`, so that the main program takes over from the spin loop, and sets the state to locked. The cuts differ between the standards because the VIC's raster counter first reads non-zero 1 cycle before line 0 on PAL but 5 on NTSC, in VICE.

### Phase 3: locked

From here the timer fires every F cycles, always at the same place in the frame, and your main program runs between IRQs. The CPU takes the IRQ only when the instruction it is on has finished, so with ordinary code the handler would start anywhere from 1 to 8 cycles late, and that is the jitter that ruins raster effects. `service_irq` takes it out:

1. Its first instruction reads the timer's low byte as the acknowledge. The counter has been running since it reloaded, so the value says exactly how late the IRQ was.
2. It subtracts that from a constant (`CORRECT_X`, which is how far the counter has run when the IRQ is as late as it can be) to get a number of cycles between 0 and 7.
3. It burns that many cycles with a three-stage slide: each bit of the number takes a branch that costs 1, 2 or 4 cycles more when the bit is set, so the time it takes is exact whatever the number is.

After the slide the handler is always **72 cycles after the timer underflowed**: 36 for the KERNAL and the 6502, 28 for the correction, and 8 for the slide plus the delay in taking the IRQ, which always add up to 8. This is the **stable point**, the `stable` label, and it is at raster line 0, cycle 0. The dispatch (`SYNCSTAT`) then runs `hold_sync`, which calls `run_raster_effects` 23 cycles later, so an effect starts at line 0 cycle 60. When the effect is done the handler leaves through `exit_irq`, which restores the registers the way the KERNAL's own exit does.

| State (`$FD`) | Runs | Moves on when |
|---|---|---|
| 0 tracking | `track_sync` | `$9004` is no longer 0 |
| 1 arming | `arm_sync` | at once, to locked |
| 2 locked | `hold_sync` | never |

## Comparison with other techniques

Cycle-stable raster work on the VIC-20 has been done before, mostly on the [Denial forum](https://www.sleepingelephant.com/~sleeping/ipw-web/bulletin/bb/). The routines below are the ones that a search for prior art turned up. They are described as their authors posted them: BackTrak has not run any of them, and the details come from reading the posts, so check the sources before relying on a detail. A search of one forum and the general web is not a survey. It found no description of the approach used here, a timer one cycle short of a frame so that each IRQ lands a cycle earlier against the raster counter than the last, with the main code in lockstep with the IRQ so that it always lands on the same instruction, but that is not proof that nobody has used it. If you know of an earlier use, please say.

| | Getting the first sync | Taking out the IRQ delay | Notes |
|---|---|---|---|
| **BackTrak** (this project) | Backtracking: the timer drifts a cycle a frame against `$9004`, and the first non-zero read fixes the beam to a cycle. About 12 to 20 IRQs. | Reads the timer's low byte as the acknowledge and burns the difference with a 3-stage slide. | Needs a spin loop in lockstep with the IRQ while it tracks, then releases it. Checked in VICE only. |
| **Cycle-exact routine** by Mike (Herr VC), Denial forum 2020 and 2023 ([2020](https://www.sleepingelephant.com/~sleeping/ipw-web/bulletin/bb/viewtopic.php?p=108884), [2023](https://sleepingelephant.com/ipw-web/bulletin/bb/viewtopic.php?p=119629)) | A foreground start-up of raster-counter checks, each narrowing the uncertainty (7 cycles, then 3, 1 and 0), with calibrated delays between them, then the timer is started on the exact cycle. | Reads the timer's low byte at `$9124` and branches (self-modified) into a NOP slide. | Latch is the period less 2, `$5686` PAL and `$4243` NTSC. Its author's caveats: keep the branches in one page, bracket the code with `SEI` and `CLI`, and mind NMIs. |
| **Timer split** by tlr, Denial forum 2020 ([thread](https://www.sleepingelephant.com/~sleeping/ipw-web/bulletin/bb/viewtopic.php?p=109062)) | Waits for the raster counter to leave zero and return to it, then starts timer 1 with a calibrated first period. The author says he chose not to make the start-up stable. | None described. | Reloads the latches in the IRQ from a table of periods, so a frame can have several splits. |
| **`InstallRaterSplit`** by beamrider, Denial forum 2020 ([thread](https://www.sleepingelephant.com/~sleeping/ipw-web/bulletin/bb/viewtopic.php?p=108884)) | Polls `$9004`, then a second check with a delay; its comments put the inaccuracy at 7 cycles. | Starts VIA #1's timer 1 shortly after VIA #2's as a reference, reads it and pads with compare and branch. | Posted by its author as untested. |
| **rnmi library** by Zagon, Denial forum 2009, with fixes in 2019 ([thread](https://www.sleepingelephant.com/~sleeping/ipw-web/bulletin/bb/viewtopic.php?p=45098)) | Not described on the pages read (the source is an attachment). | Not described on the pages read. | Reprograms the one-shot timer of the NMI VIA to fake raster interrupts, and says cycle-stable routines are possible. In 2019 the author reports the fixed version breaks the first-run sync on NTSC in xvic, and a hardware test found the bars right only on the first run. |

A routine by Marko Mäkelä, whose source was not in those pages and has not yet been reviewed here, is also named in the first thread, where beamrider reports four stable IRQs from it with no polling. A technique of the same family exists on another machine: [hexwab's stable raster for the BBC Micro](https://kieranhj.github.io/llm-beeb-wiki/techniques/hexwab-stable-raster) starts a VIA timer and spends the slack in a delay loop, so that the code always ends at the same cycle (this link is a wiki's summary of the original post).

**What BackTrak shares with them.** The jitter correction is the same idea as Mike's: the timer's low byte says how late the IRQ was, and a variable delay takes up the difference. BackTrak's slide is three binary stages instead of a branch into a NOP slide, but the idea is his, and it was published first. The latch convention is the same too: the 6522 counts the latch plus 2 cycles, so the locked latch here is the frame less 2 (22,150 on PAL and 16,963 on NTSC), the values in Mike's routine.

**What is different.** The others reach the first sync by polling the raster counter in foreground code and counting cycles, either with a calibrated chain of checks that reduces the uncertainty a step at a time, or by accepting the uncertainty a polling loop leaves (7 cycles for a `cmp`/`bne` loop). BackTrak lets the timer's own drift do the measuring instead: the IRQ is a cycle earlier each frame, so the frame in which `$9004` first changes is the frame in which the beam position is known, whatever cycle the start-up code began on and with no delay to calibrate beyond the fixed cost of the handler. The price is time and structure. It needs about a third of a second of frames to find the position (the others do their syncing in start-up code, in a fixed number of cycles), and while it tracks, the main code must be a spin loop whose period, with the handler's, is the timer's period, so that every IRQ lands on the same instruction. The spin loop is dropped as soon as the sync is locked. One thing is unproven here that others have done: BackTrak has not run on a real VIC-20. The posts above include reports of first-run sync problems in xvic and on hardware (in the rnmi thread), so the cycle cuts in particular need checking on a real machine.

## How to use it

### Your main program

The sync runs under your program, not the other way round. When it locks, the IRQ returns to the label `main_loop` in `BRS_main_program.asm`, and from then on your code is interrupted once a frame, at any instruction, and cannot tell: the registers and flags come back as they were (the handler clears the Decimal flag for its own arithmetic, and the interrupted code gets its own back). Replace the demo's `main_loop` with your own. A few rules:

* Leave VIA #2's timer 1, its interrupt enable, and the IRQ vector at `$0314` alone, and do not disable IRQs for more than a frame, or the lock is lost.
* Leave zero page `$03-$04` and `$FB-$FD` alone. They hold the video standard, the arm cut, the spin loop counts and the state. `$05-$06` and `$FE`, `$0200-$020A` and `$1D00-$1DF9` are used by the demo, and are yours if you drop it.
* The KERNAL IRQ is gone, so there is no jiffy clock, keyboard scan or cursor flash. Read the keys from VIA #2 yourself. The KERNAL's screen output (`CHROUT` and `PLOT`, which the demo's main program uses) still works.
* **You get what the effects leave.** The IRQ handler, with the effects inside it, is most of every frame. The copper bars draw the whole picture and leave a main program only about 100 cycles of a PAL frame (22,152) and about 150 of an NTSC frame (16,965), as measured; the sine ribbon and the waving flag leave about 2,000 and 1,050. A main program that does not need the raster, or an effect that draws fewer lines (see below), leaves more.

### Writing your own raster effect

An effect is a routine that `run_raster_effects` jumps to from `hold_sync`. It is entered at the stable point plus 60 cycles (`EFFECT_START`), which is raster line 0, cycle 60, with the sync locked. It can use all three registers and the flags, and finishes with `jmp advance_frame` (which updates the demo's counters and ends with an `rts` to `hold_sync`; replace it with an `rts` of your own if you do not want them). It has until the next IRQ is due, which is the next frame's stable point less 72 cycles, and the handler needs another 22 to leave. While it runs the IRQ is held off, so it does not have to worry about being interrupted: it owns the machine for the frame.

A raster effect is a **loop of exactly one raster line**: the instructions in it add up to 71 cycles on PAL and 65 on NTSC, so the writes to the VIC are on the same cycle of every line. The usual writes are to `$900F` (the screen and border colours) or `$9000-$9003` (where the screen is). Two things set where on the screen a write lands, and both are exact:

* **The raster line** is the line the write is in. The stable point is line 0 cycle 0 (as VICE's monitor shows them in `LIN` and `CYC`), and the picture begins at raster line 27 on both standards (PAL to line 310, NTSC to line 260).
* **The cycle** is how far across the line the write is. A cycle is four VIC pixels, and the left edge of the picture is at about cycle 3.

The macros in `kickass_scripts.asm` make exact timing a matter of arithmetic:

* `Pad(n)` burns `n` cycles (0, or 2 and up) in a few NOPs. `Delay(n)` burns `n` (6 and up) in a loop on `.Y`. `Wait(n)` chooses between them, and loops again for a long wait.
* `Slide(bits)` burns the number in `.A`, a bit at a time, in `4 + 5 * (bits - 1)` cycles plus the number.
* `startPad(line, fixed, idx, cycle)` (in `BRS_raster_effects.asm`) is the wait before an effect's first line: it works out how long to wait after `fixed` cycles of set-up so that the instruction `idx` cycles into the first pass of the loop is on `cycle` of the first line of the picture.

This is a whole effect: a red bar, 10 cycles wide, at the same place on every raster line. It is written as a macro because it is needed twice, once for each line length, and the macro works out the padding for each.

    // A red bar, 10 cycles wide, at the same place on every raster line
    .macro RedBarLines(lines, line)
    {
                lda #lines                                  // [2]      get the lines to draw
                sta BRS_runtime_memory.LINECNT              // [3]      set lines left
                Wait(startPad(line, 5, 5, 20))              //          wait for the first line, so that the first write is on cycle 20 of it
    !loop:      lda #pair(2)                                // [2]      get red (pair() makes the $900F value for a colour)
                sta vic20.vic.VCSCRNCO                      // [4]      start the bar: the write is 5 cycles into the loop
                Pad(4)                                      // [4]      make the bar 10 cycles wide
                lda #BRS_runtime_constants.SCREEN_BASE      // [2]      get the screen colour
                sta vic20.vic.VCSCRNCO                      // [4]      end the bar
                dec BRS_runtime_memory.LINECNT              // [5]      decrement lines left
                beq !done+                                  // [2/3]    exit after the last line
                Wait(line - 26)                             //          make the pass exactly one raster line: 26 cycles are the instructions above and below
                jmp !loop-                                  // [3]      draw the next line
    !done:      jmp advance_frame                           // [3]
    }

    .align 128                                              // keep the routine, which must be under 128 bytes, inside a page: a taken branch that crosses one costs a cycle
    red_pal:
    {
                RedBarLines(BRS_runtime_constants.PAL_LINES, BRS_runtime_constants.PAL_LINE)
    }

    .align 128
    red_ntsc:
    {
                RedBarLines(BRS_runtime_constants.NTSC_LINES, BRS_runtime_constants.NTSC_LINE)
    }

To put it in the program, add `red_pal` and `red_ntsc` to the `EFFECTS` list in `BRS_static_data.asm` (the effect number times two, plus the video standard, indexes it), and one to `EFFECT_COUNT` in `BRS_runtime_constants.asm`. The build option `:effect=N`, below, starts on it. Some things to keep in mind:

* **Add up the cycles.** The sum of the instructions in the loop, with the padding, must be the line length, on every pass. The assembler works out `Wait(line - 26)`, but only you know that 26 is right. Write the cycles of every instruction in the comments, as the demo's code does, and check the total. A branch that crosses a page costs a cycle, and so does an indexed read that does (`lda table,x` with the table not page-aligned), so keep loops inside a page and tables on a page boundary. The demo's tables are laid out for it, and its `.errorif` lines stop the build if one moves.
* **Moving the writes along the line** takes a variable delay. The sine ribbon and the waving flag do it with a trick: instead of making every pass exactly one line, a pass takes a line less 3 cycles plus a number from a table (0 to 7), taken up by a `Slide(3)`. The table holds 3 plus how far the wave moves between the two lines, so the position of the write on each line follows the wave to the cycle. `waveStep()` and `wave()` in `BRS_static_data.asm` make the tables, and `RibbonLines` in `BRS_raster_effects.asm` is the loop. A wave can move the write by up to 3 cycles less or 4 cycles more from line to line.
* **How many lines.** The picture is lines 27 to 310 on PAL (284 lines) and 27 to 260 on NTSC (234), the rest of the frame, and the IRQ must be left before the next one is due, 72 cycles before the next frame's stable point. The copper bars draw the whole picture on PAL and all but its last 2 lines on NTSC. The sine ribbon and the waving flag count their lines in one register, so they stop at 255 on PAL and are set to 216 on NTSC. Draw fewer lines and the main program gets more time.
* **Work between frames** goes before the first line, where there are 27 lines of nothing visible to spend it in: the effects wait that long (`startPad`), and it is 1,917 cycles on PAL and 1,755 on NTSC. The copper bars draw themselves into their line buffer there, in `compose_bars`, which takes exactly 949 cycles (`COMPOSE_CYCLES`) whatever the bars' positions, because the loop that follows is timed from its end: that is why its tables are page-aligned and why it takes the same cycles with and without animation. Work that is not counted to the cycle goes after the last line, as `advance_frame` does.
* **Beyond `$900F`.** Anything the VIC does at a known cycle can be done this way: moving the screen sideways on each line (`$9000`), changing the character set, or the sound registers. How early in a line a register must be written for it to take effect on that line is the VIC's business, so find it by looking at the result.

### Tuning for your machine

The cycle counts that place the stable point on raster line 0, cycle 0 were measured in VICE 3.10. If the lock is not at line 0, cycle 0 on your machine, the numbers to change are in `BRS_runtime_constants.asm`:

* `PAL_ARM_CUT` and `NTSC_ARM_CUT`: add the number of cycles late the stable point is, or subtract the number of cycles early it is.
* `PAL_FIRST_CUT` and `NTSC_FIRST_CUT` only decide how soon the lock is found. They aim the first IRQ about 14 cycles inside the zero window of `$9004`. Increase one to aim earlier; a first IRQ outside the window locks onto the wrong edge.

To see where the stable point is, break at the `stable` label in the VICE monitor: the register line gives `LIN` and `CYC`, which should be 0 and 0 when the sync is locked.

## Building

Tools: [KickAssembler 5.25](https://theweb.dk/KickAssembler/Main.html#frontpage) (needs Java), and [VICE 3.10](https://vice-emu.sourceforge.io/) to run it.

    java -jar KickAss.jar main.asm -vicesymbols       builds BackTrak.d64 and main.vs

The build works out its own timing: it solves the spin loop counts for PAL and NTSC, and stops with a message if a loop would cross a page, if a table would, if the program would run into the line buffer at `$1D00`, or if a change to a cycle count leaves no solution.

There are three build options, given on the command line after the file name:

    :effect=N       start on raster effect N (0 copper bars, 1 sine ribbon, 2 waving flag)
    :still=1        do not animate, and do not change effect: every frame is the same
    :slide=0        build without the jitter slide

`:slide=0` is for seeing what the slide does. Without it the effects are drawn in the right shape but the whole picture jumps sideways by a few cycles from frame to frame, because the IRQ is taken at whatever point the main program had reached.

## Compatibility

The program is for an unexpanded VIC-20 (see [Memory](#memory)), PAL or NTSC (detected at run time). It starts from a BASIC stub at `$1001`. It uses only documented NMOS 6502 opcodes.

## Programming caveats

* The program takes over the IRQ vector (`$0314`), VIA #2 timer 1 and the NMI vector (`$0318`), so the KERNAL's jiffy clock, keyboard scan and cursor flash stop. It never returns to BASIC.
* **NMIs and the RESTORE key.** The RESTORE key is VIA #1's CA1 input, which VIA #1 turns into an NMI, and an NMI cannot be masked. The KERNAL's NMI handler (`$FEAD`) runs the jiffy clock, scans for an autostart cartridge and scans the STOP key; if STOP is down (Run/Stop-Restore) it restores the default I/O vectors, which include the IRQ vector, re-initialises the chips and jumps into BASIC. That ends the program, and even a plain RESTORE would cost a few hundred cycles of some frame. `initialise_sync` therefore disables every VIA #1 interrupt (RESTORE is the only one that was enabled) and points the NMI vector at an `RTI`, which also covers anything on the expansion port that pulls the NMI line itself (such an NMI still costs about 27 cycles of the frame it lands in). Reset the machine to leave the program.
* It uses zero-page locations `$03-$04` and `$FB-$FD`, and the demo uses `$05-$06`, `$FE`, `$0200-$020A` and the page at `$1D00`. A main program must leave all of them alone.
* The timing depends on the KERNAL IRQ stub at `$FF72` (it adds 36 cycles between the VIA interrupt and the program's handler, and the handler leaves with the same register restore as the KERNAL exit at `$EB15`). A different KERNAL (JiffyDOS, for example) needs its entry cost re-measured: see `IRQ_ENTRY` in `BRS_runtime_constants.asm`.
* The jitter correction covers an IRQ that is taken 1 to 8 cycles late, which is every instruction the 6502 has. A main program that disables interrupts for more than a frame, or that changes VIA #2 timer 1, will lose the lock.
* The cycle cuts for the two standards differ because the VIC's raster counter reads zero from a slightly different beam position on each, in VICE. See [Tuning for your machine](#tuning-for-your-machine) if the lock is not at line 0, cycle 0 on real hardware.

## Release history

### Beta 5 (20th November 2026)
* Added three raster effects as a demonstration: copper bars (three gradient bars, one of them black and red, that move on their own sine waves over the whole picture, drawn into a line buffer in the invisible lines at the top of the frame), a sine ribbon, and a red, white and blue waving flag that fills the width of the picture (both of which follow a sine wave to the cycle on every raster line), with a variable delay for each line made by a slide
* Added a demo main program that prints the title (with the copyright line) and the name of the current effect, and that the IRQ interrupts at any instruction, and moved `main_loop` into it
* Added the macros `Wait` and `Slide` and the function `pair` to `kickass_scripts.asm`, and the build options `:effect=N` and `:still=1`
* Added the switching off of VIA #1's interrupts and an `RTI` for the NMI vector, so that the RESTORE key and Run/Stop-Restore cannot disturb the sync or return to BASIC
* Fixed a bug where the NTSC sync could start its timer in the middle of the zero window of `$9004` instead of at its start, because the code only waited for the window if it was not already in it
* Removed the line values from the sync values table: each effect now has its own routines for PAL and NTSC with the padding worked out when it is built

### Beta 4 (20th November 2026)
* Tweaked the lock to take about 17 IRQs (a third of a second) instead of about 200 on PAL and 100 on NTSC: the timer starts with a shortened first period, so that backtracking starts at the edge of the zero window of the raster counter instead of 105 cycles from it, and the arm state restarts the timer with a shortened first period instead of waiting for backtracking to move the IRQ into place
* Removed the settle and release states and the timer values in zero-page: the arm state works the shortened and locked latches out from the latch the timer is using, and starts the main program itself

### Beta 3 (20th November 2026)
* Added colour bars as the first raster effect: a 16-cycle stripe on each of 240 raster lines, with every write on the same cycle of its line for both PAL (71 cycles a line) and NTSC (65), from the IRQ's stable point

### Beta 2 (20th November 2026)
* Added jitter cancellation: the IRQ handler reads the timer to find how late the IRQ was taken and slides by the difference, so its stable point is the same cycle whatever instruction the main program was running
* Added the release of the spin loop: when the lock is made the IRQ returns to `main_loop`, and every later IRQ interrupts the main program
* Added a hook, `run_raster_effects`, which the locked state calls at the stable point
* Fixed a bug where the NTSC sync started its timer too late to read `$9004` inside its zero window, which is 88 cycles on NTSC against 143 on PAL (xvic 3.10), so each standard now starts the timer on its own raster line

### Beta 1 (20th November 2026)
* Added backtracking raster sync for PAL and NTSC, locking every IRQ handler to raster line 0, cycle 0
* Added build-time solving of the spin loop counts from the cycle model, with checks that stop the build if a loop crosses a page or the program is too long
* Fixed a bug where the VIA timer was never started, because the sync wrote the timer latch rather than the counter
* Fixed a bug where the NTSC flag was never set
* Fixed a bug where the lock state and the timer value shared a zero-page location
* Tweaked the timer values and loop lengths to include the cost of the KERNAL IRQ stub
* Refactored the code and names to the 6502 coding standards, with the project files renamed to the `BRS_` prefix
* Removed the Common-VIC20 submodule reference, because the common files are now part of the project

# Who is 8-Bit Guru?

8-Bit Guru (also: Eight-Bit Guru, 8BitGuru, 8BG) is the *nom de guerre* of Mark Johnson. I'm a professional coder from the UK who has been telling computers what to do since 1981. My day job is all about C# and Azure, whilst my hobby projects mostly involve writing 6502 machine code for the Commodore VIC-20.
