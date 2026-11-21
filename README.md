# <div><div>BackTrak Raster Sync</div><div>Copyright © 2026 [8-Bit Guru](mailto:the8bitguru@gmail.com)</div></div>

BackTrak Raster Sync locks a Commodore VIC-20 program to the raster beam, to the cycle, on both PAL and NTSC machines, and then runs raster effects whose every colour change is on exactly the cycle it was written for. The VIC-20 has no raster interrupt, so the simple tricks (watching the raster counter in a loop, or starting a timer from it) leave up to 7 cycles of jitter unless the polling is made cycle-exact. BackTrak removes it by *backtracking*, then keeps it removed by measuring how late every IRQ is and sliding by the difference. A few hundred bytes do the locking; your program keeps the rest of the memory and whatever time the raster effects leave.

**Backtracking itself is not new.** Marko Mäkelä published a polled form of it in 1995: in the VIC-20 routine in his article "Making stable raster routines" ([C=Hacking issue 10](https://c128.ca/cbm/64-128/misc/issue10), printed under the name Marko Makela), a CPU loop one cycle short of the two-line period of `$9004` walks its read back one cycle per pass until it lands on the change. **What BackTrak adds, to the author's knowledge, is doing it with a timer interrupt**: a timer one cycle short of a frame walks the IRQ back against the raster counter, from any starting cycle, until `$9004` actually changes (so it checks that it has found the beam), and the same timer's counter then measures the IRQ's delay. See [Comparison with other techniques](#comparison-with-other-techniques) for what each does and what each costs.

The demo that comes with it draws four raster effects, one after another, while a main program (which knows nothing of the raster) prints the name of the effect on the screen:

* **Copper bars**: three gradient bars (fire, ice and violet) that move up and down the whole picture on their own waves.
* **Sine ribbon**: a rainbow ribbon whose edges follow a sine wave, to the cycle, on every raster line.
* **Waving flag**: red, white and blue bands that wave along a shallower sine, and fill the width of the picture.
* **Split screen**: two raster IRQs in every frame, at different lines, that draw a red stripe in the top half and a blue one in the bottom half on exactly the same cycles, so that they make one straight vertical line (see [Splitting the frame](#splitting-the-frame)).

**NOTE:** the lock and the effects are checked in VICE 3.10, and the cycle counts that place them on raster line 0, cycle 0 were measured there. They have not yet been checked on real hardware.

## License

The BackTrak Raster Sync project is hosted on [GitHub](https://github.com/EightBitGuru/Backtrack-Raster-Sync).

Creation of modified or derivative works using, in whole or in part, any sourcecode, assets, or binary artifact originating from this project is subject to the following:

* **Free for non-commercial use** (you must clearly include a credit link to this project within your project).

* **Commercial use is expressly forbidden** except by explicit consent from the copyright holder.

## Quickstart

**BackTrak.d64** holds the demo, already built from the sources in this folder, so you do not need an assembler to run it. **To build it yourself you need [KickAssembler 5.25](https://theweb.dk/KickAssembler/Main.html#frontpage)** (see [Building](#building)). Start ***xvic*** with it, on any memory configuration (see [Memory](#memory)), for example unexpanded, and with 8K or more:

    xvic.exe -model vic20pal -memory none -autostart BackTrak.d64
    xvic.exe -model vic20ntsc -memory none -autostart BackTrak.d64
    xvic.exe -model vic20pal -memory 8k -autostart BackTrak.d64
    xvic.exe -model vic20ntsc -memory all -autostart BackTrak.d64

VICE loads and runs it (on a real VIC-20, `LOAD "BACKTRAK",8` and `RUN`; see [Memory](#memory)). The screen goes black, the title appears, and in about a third of a second the sync is locked and the first effect starts. The effects change every 256 frames (about five seconds), and the main program puts the name of each on the screen as it changes. To look at the sync itself, open the VICE monitor and break at the `stable` label (see `main.vs` for the address): the register line shows `LIN 0 CYC 0` on every hit once the sync state (`$FD`) is 2.

Run/Stop-Restore does nothing: the program switches the RESTORE key off (see [Programming caveats](#programming-caveats)). Reset the machine to leave it.

## Memory

**It runs on every VIC-20 memory configuration**: unexpanded, with 3K, and with 8K, 16K, 24K or more, on PAL and NTSC. The program is built for the 5K of an unexpanded VIC-20, 1K at `$0000-$03FF` and 4K at `$1000-$1FFF`, and that is all it needs: it does not use expansion RAM. The sync itself takes **304 bytes** of it, so on any VIC-20 about **2,970 bytes (2.9K)** of the program area are free for your own code and data (about 3,260 in a build for an unexpanded machine only, which needs no loader and a shorter BASIC line).

The KERNAL decides where the screen and BASIC go from the RAM that is fitted (measured in VICE), so the file is loaded at a different address on each:

| Configuration | Screen | BASIC starts | What happens |
|---|---|---|---|
| Unexpanded (5K) | `$1E00` | `$1001` | Loaded at `$1001`, where the program was built to run, so it does not move. |
| +3K (`$0400-$0FFF`) | `$1E00` | `$0401` | Loaded at `$0401` and moved up to `$1001`. |
| +8K, +16K, +24K or more (`$2000` up) | `$1000` | `$1201` | Loaded at `$1201` and moved down to `$1001`, which is on top of the screen the KERNAL has put at `$1000`. The program then moves the screen to `$1E00`. |

Two things make that work. The BASIC line is `SYS PEEK(43)+256*PEEK(44)+offset`, which adds the loader's offset in the file to wherever BASIC starts, and a small **loader** moves the rest of the file to the addresses it was built for (a forwards or backwards copy, whichever cannot overwrite what it has still to read, run from the cassette buffer so that it is not overwritten itself). Then `initialise_screen` puts the screen at `$1E00` on every machine, which is RAM on all of them and is where an unexpanded VIC-20 has it already. Every address in the program after that is the one it was built for.

Load it with `LOAD "BACKTRAK",8` and `RUN`: that puts the file at the start of BASIC, which is what the BASIC line expects. (`,8,1` loads it at `$1001` whatever machine it is, which is where only an unexpanded one has BASIC, so `RUN` will not find it elsewhere.) VICE's `-autostart` does the first, on all of the configurations above.

| | Bytes | Where |
|---|---:|---|
| The sync: start-up, spin loop, IRQ handler, the three states, exit | 282 | |
| The sync's tables (`SYNCVALS` and `STATEJMP`) | 22 | |
| **The sync-lock sequence** | **304** | |
| BASIC line that starts the program (and hides itself when listed) | 153 | `$1001-$1099` |
| Loader (runs once; the copier it runs in the cassette buffer is 97 of its bytes) | 154 | |
| **The sync, the BASIC line and the loader, all told** | **611** | |
| **Left for your code and data, from `$1001` to `$1DFF`** | **about 2,970** | |

That is the core: lock the raster, detect PAL or NTSC, cancel the IRQ jitter, and leave your main program running with a stable IRQ at raster line 0, cycle 0. Take out `BRS_raster_effects.asm` (which imports `BRS_main_loop.asm`), `BRS_split_effects.asm`, `BRS_copper_bars.asm` and `BRS_main_program.asm` (`hold_sync` calls `run_raster_effects`, so give it an `rts` of its own, and `arm_sync` sends your program to `main_loop`) and about 2.9 KB of the on-board RAM is yours, along with all of the zero page except `$03-$04` and `$FB-$FD` (and `$14-$15`, which BASIC sets and the loader reads), the stack (the IRQ uses at most eight bytes of it), and `$0200-$0258` and `$033C-$03FB` (the BASIC input buffer and the cassette buffer, which nothing here uses, apart from the loader's copier at the start).

**The demo as built uses nearly all of it.** The effects, their tables, the loader and the main program take the program to `$1CE6`, and the copper bars' line buffer is the page at `$1D00-$1DF9`, so only about 25 bytes are left (`$1CE7-$1CFF`). To write your own program, replace the demo and you are back to the 2.9 KB above.

**Expansion memory** is yours, and the program does not touch it: after the move, the loaded copy of the program (at `$0401` with 3K, at `$1201` with 8K or more) is not used again. The sync does not depend on how much RAM there is, and RAM expansion does not change any cycle count. A program that only needs to run on an unexpanded VIC-20 can drop the loader and use a short BASIC line with a plain `SYS`.


## How it works

The whole of it rests on one fact about the VIC-20's chips: the VIA timer and the VIC are driven from the same clock, so a timer that is set to exactly one frame of cycles stays at the same place in the frame for ever. The work is getting it to the right place, to the cycle, and keeping it there whatever the CPU was doing when it fired. That takes four phases. The cycle counts are in `BRS_runtime_constants.asm`.

| | PAL | NTSC |
|---|---:|---:|
| Cycles in a raster line | 71 | 65 |
| Raster lines in a frame | 312 | 261 |
| Cycles in a frame (F) | 22,152 | 16,965 |

### Phase 0: Start-up

The BASIC line runs the loader, which moves the program to the addresses it was built for (see [Memory](#memory)) and jumps to `initialise_screen`. That puts the screen at `$1E00`, turns it black, prints the title, sets up the effects and jumps to `initialise_sync`. That:

1. Disables IRQs and the Decimal flag.
2. Switches off VIA #1's interrupts and points the NMI vector at a bare `RTI` (see [Programming caveats](#programming-caveats)).
3. Points the IRQ vector at `service_irq`. The KERNAL's IRQ routine at `$FF72` pushes `.A`, `.X` and `.Y` and jumps through `$0314`, so the handler is entered 36 cycles after the VIA's interrupt (7 for the 6502's response, 29 for the KERNAL).
4. Checks for PAL or NTSC. The raster counter in `$9004` holds the line number divided by two. The code waits for it to read 1, then watches it: an NTSC machine wraps to 0 (it has 261 lines) before it can reach 134, and a PAL machine (312 lines) reaches 134, which is line 268, first.
5. Copies the values for the video standard into zero page: the arm cut, the video standard and the spin loop counts.
6. Sets VIA #2's timer 1 to free-run and enables its interrupt.
7. Waits for the start of the zero window of `$9004`, where it first reads 0, which is the beam on lines 0 and 1. It waits for the counter to leave zero first, because the code might arrive part-way through the window.

### Phase 1: Backtracking

VIA #2's timer 1 is started and reloads itself every period. The 6522 counts N+2 cycles for a latch of N, so the backtracking latch is F-3, for a period of **F-1 cycles, one cycle less than a frame**. Every IRQ is therefore one cycle earlier against the raster than the one before it.

The timer is not held while an IRQ is handled, so the handler's length makes no difference to the period. What it does decide is where in the main code the IRQ lands, and the design needs it to land on the same instruction every time. The main code is a spin loop whose last instructions are 12 two-cycle NOPs, and the loop and the handler together take exactly the timer period:

    spin loop period + IRQ cycles = timer period

The handler takes 138 cycles (36 for the KERNAL and the 6502, 28 for the jitter correction, 7 for the slide, 23 for the dispatch, 22 for the state routine and 22 to leave through the KERNAL's register restore), so the spin loop takes F-1-138: 22,013 cycles on PAL and 16,826 on NTSC. KickAssembler solves the loop's two counts at build time, and stops the build if there is no solution or if a loop would cross a page (a taken branch that crosses one costs an extra cycle). Because the IRQ lands in the NOPs, the CPU always finishes a two-cycle instruction, so the delay in taking the IRQ is the same every time, and the lockstep holds.

The timer's first period is made shorter than the others: the start-up code writes a shortened latch, starts the timer, and puts the normal latch back with a write to `$9127`, which changes only the latch. That makes the first IRQ read `$9004` about 14 cycles inside the zero window (the window is 143 cycles on PAL but only 88 on NTSC, so the first IRQ has to be aimed), and backtracking has only a few cycles to go.

Each tracking IRQ runs `track_sync`, which reads `$9004` at the same cycle every time. While it reads 0 the beam is on line 0 or 1 and the IRQ is early by one more cycle each frame. The first time it does not read 0, the read has just slid across the start of the window, which fixes the beam to a single cycle. That takes about 12 to 20 IRQs, a third of a second.

### Phase 2: Arming

The next IRQ runs `arm_sync`. It knows exactly where in the frame it is (one cycle past the edge), so it restarts the timer with a first period shortened by the arm cut, **93 cycles on PAL and 89 on NTSC**, which moves the next IRQ to the place in the frame that puts its stable point (below) at raster line 0, cycle 0. It then puts in the **locked latch**, F-2, which makes the period exactly **F cycles**, again with a write that leaves the counter alone. Last, it replaces its return address on the stack with the address of your `main_loop`, so that the main program takes over from the spin loop, and sets the state to locked. The cuts differ between the standards because the VIC's raster counter first reads non-zero 1 cycle before line 0 on PAL but 5 on NTSC, in VICE.

### Phase 3: Locked

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

Cycle-stable raster work on the VIC-20 has been done before. The routines below are the ones that a search for prior art turned up. They are described as their authors published them: the details come from reading the posts and, for Mäkelä's, the listing in the article, so check the sources before relying on a detail. A search of one forum and the general web is not a survey. It found no description of the way BackTrak does it, a timer interrupt one cycle short of a frame so that each IRQ lands a cycle earlier against the raster counter than the last, with the main code in lockstep with the IRQ so that it always lands on the same instruction, but that is not proof that nobody has used it. It did find the same one-cycle-per-pass principle in a polling loop, in Marko Mäkelä's 1995 routine, which is the earliest of them. If you know of an earlier use, please say.

| | Getting the first sync | Taking out the IRQ delay | Notes |
|---|---|---|---|
| **BackTrak** (this project) | Backtracking: the timer drifts a cycle a frame against `$9004`, and the first non-zero read fixes the beam to a cycle. About 12 to 20 IRQs. | Reads the timer's low byte as the acknowledge and burns the difference with a 3-stage slide. | Needs a spin loop in lockstep with the IRQ while it tracks, then releases it. Checked in VICE only. |
| **Raster demo** by Marko Mäkelä, article "Making stable raster routines (C64 and VIC-20)", [C=Hacking issue 10](https://c128.ca/cbm/64-128/misc/issue10), June 1995 | A coarse poll of `$9004` for a line (which leaves up to 7 cycles of uncertainty), then nine passes of a loop of exactly two raster lines, the period of `$9004`, that takes one cycle less on any pass in which `$9004` changed between its two reads. Each such pass walks the read back a cycle until it sits on the change. Done in start-up code in about a frame. | A second VIA's timer 1, started about 55 cycles after the IRQ's timer and with the same period, is read in the IRQ. Its low byte (0 to 15) picks the delays of 8, 4, 2 and 1 cycles. | Latch is the frame less 2. Switches off the RESTORE key's NMI (`$911E`) and chains to the KERNAL's IRQ (`jmp $EABF`), so BASIC carries on. Tested by its author on a PAL VIC-20. On NTSC, one owner's second VIA was broken, another reported it "almost worked", and the author expects the effect to be off position. |
| **Cycle-exact routine** by Mike, Denial forum 2020 and 2023 ([2020](https://www.sleepingelephant.com/~sleeping/ipw-web/bulletin/bb/viewtopic.php?p=108884), [2023](https://sleepingelephant.com/ipw-web/bulletin/bb/viewtopic.php?p=119629)) | A foreground start-up of raster-counter checks, each narrowing the uncertainty (7 cycles, then 3, 1 and 0), with calibrated delays between them, then the timer is started on the exact cycle. | Reads the timer's low byte at `$9124` and branches (self-modified) into a NOP slide. | Latch is the period less 2, `$5686` PAL and `$4243` NTSC. Its author's caveats: keep the branches in one page, bracket the code with `SEI` and `CLI`, and mind NMIs. |
| **Timer split** by tlr, Denial forum 2020 ([thread](https://www.sleepingelephant.com/~sleeping/ipw-web/bulletin/bb/viewtopic.php?p=109062)) | Waits for the raster counter to leave zero and return to it, then starts timer 1 with a calibrated first period. The author says he chose not to make the start-up stable. | None described. | Reloads the latches in the IRQ from a table of periods, so a frame can have several splits. |
| **`InstallRaterSplit`** by beamrider, Denial forum 2020 ([thread](https://www.sleepingelephant.com/~sleeping/ipw-web/bulletin/bb/viewtopic.php?p=108884)) | Polls `$9004`, then a second check with a delay; its comments put the inaccuracy at 7 cycles. | Starts VIA #1's timer 1 shortly after VIA #2's as a reference, reads it and pads with compare and branch. | Posted by its author as untested. |
| **rnmi library** by Zagon, Denial forum 2009, with fixes in 2019 ([thread](https://www.sleepingelephant.com/~sleeping/ipw-web/bulletin/bb/viewtopic.php?p=45098)) | Not described on the pages read (the source is an attachment). | Not described on the pages read. | Reprograms the one-shot timer of the NMI VIA to fake raster interrupts, and says cycle-stable routines are possible. In 2019 the author reports the fixed version breaks the first-run sync on NTSC in xvic, and a hardware test found the bars right only on the first run. |

beamrider's thread also names Marko Mäkelä's routine, which is the one in the table above. A technique of the same family exists on another machine: [hexwab's stable raster for the BBC Micro](https://kieranhj.github.io/llm-beeb-wiki/techniques/hexwab-stable-raster) starts a VIA timer and spends the slack in a delay loop, so that the code always ends at the same cycle (this link is a wiki's summary of the original post).

**What BackTrak shares with them.** The jitter correction is the same idea in all of them, and Mäkelä's came first: a timer's low byte says how late the IRQ was, and a variable delay takes up the difference. His reads a second VIA's timer that was started a fixed number of cycles after the first, and says in the article that the first timer could be read instead, which is what Mike's routine and BackTrak do. BackTrak's slide is three binary stages (1, 2 and 4 cycles) where Mäkelä's has four (8, 4, 2 and 1) and Mike's is a branch into a NOP slide. The latch convention is the same in all three: the 6522 counts the latch plus 2 cycles, so the locked latch here is the frame less 2 (22,150 on PAL and 16,963 on NTSC). The first sync, too, shares its principle with Mäkelä's: step the read one cycle at a time against the raster counter until `$9004` changes, which pins the beam to the cycle. The RESTORE key is switched off the same way (`$911E`), and BackTrak also swallows the NMI in case one gets through.

**What is different.** Every other routine reaches the first sync by polling the raster counter in foreground code and counting cycles: with a calibrated chain of checks that reduces the uncertainty a step at a time (Mike), by accepting the uncertainty a polling loop leaves (7 cycles for a `cmp`/`bne` loop), or by a loop that is a cycle short of the counter's period and so walks onto the change (Mäkelä). BackTrak takes the same walk out of the CPU loop and gives it to the timer: the IRQ is a cycle earlier each frame, so the frame in which `$9004` first changes is the frame in which the beam position is known, whatever cycle the start-up code began on. Mäkelä's loop needs a coarse poll first that leaves no more than 7 cycles to walk, so it depends on the cycle counts between the poll and the loop. BackTrak's result has no such dependency: it keeps stepping until `$9004` changes, whatever cycle it began on, where a loop with a fixed number of passes does not check that it has arrived. What BackTrak's start-up calibrates (the shortened first period, `FIRST_CUT`) only decides how soon that happens: about 17 IRQs with it, and about 200 on PAL and 100 on NTSC without. The price is time and structure. It needs about a third of a second of frames to find the position, where Mäkelä's start-up code takes about a frame (and the others a fixed number of cycles), and while it tracks, the main code must be a spin loop whose period, with the handler's, is the timer's period, so that every IRQ lands on the same instruction. The spin loop is dropped as soon as the sync is locked. BackTrak also takes the machine over (the effects and a main program replace BASIC), where Mäkelä's demo chains to the KERNAL's IRQ and returns to BASIC. One thing is unproven here that others have done: BackTrak has not run on a real VIC-20. Mäkelä tested his on a PAL VIC-20, and the posts above include reports of first-run sync problems in xvic and on hardware (in the rnmi thread), so the cycle cuts in particular need checking on a real machine.

**Size.** Mäkelä's sync is small. Assembled for PAL from his listing, without his demo effect and his BASIC line, it is 124 bytes (93 of start-up code, 28 to correct the IRQ and 3 to leave through the KERNAL's IRQ), and 126 on NTSC, where he builds for one standard at a time. BackTrak's is 304 bytes (282 of code and 22 of tables), about two and a half times as much. Most of the difference is what the extra bytes do: one binary for PAL and NTSC, with the standard detected and both sets of constants held (BackTrak's start-up code is 140 bytes, where his is 93), the tracking, arming and locked states that find the beam from any starting cycle (74 bytes), and the NMI guard. The IRQ handler's correction is 35 bytes against his 28. The BASIC line and loader add 153 and 154 bytes to BackTrak so that it runs on every memory configuration (his BASIC line is 12 bytes, and his routine is for an unexpanded VIC-20).

## Independent development, and where it fits

**BackTrak was developed independently of Marko Mäkelä's routine, and for a different reason.** The author knew that Mäkelä's routine existed and that it needs two VIA timers, but had never analysed its code. The reason for making BackTrak was to have a sync that needs **only one timer**: the IRQ's own timer, whose counter also measures how late the IRQ was. The search for prior art and the review of his listing came afterwards, and they are why the comparison above credits him with the earliest jitter correction and the earliest first sync that walks back a cycle at a time. One timer is not new in itself (his article says that the first timer could be read instead, and Mike's routine does so), so what BackTrak offers is the combination: one timer, a first sync found by the timer's own drift, and a lock that checks itself. That its first sync comes to the same principle as his, walking the sample point back a cycle at a time until `$9004` changes, follows from the same facts: `$9004` changes only every two raster lines, and a 6522 timer can be given a period one cycle off from the raster's. What differs is what each builds around the principle.

**Mäkelä's routine is the better choice for most jobs.** It is a third of the size (124 bytes against BackTrak's 304), it locks in about a frame where BackTrak takes about a third of a second, it needs no spin loop while it locks, its slide covers a longer IRQ delay (15 cycles, where BackTrak covers 8), it chains to the KERNAL's IRQ so that BASIC carries on, and it has run on real hardware. If one IRQ per frame is all that is wanted, and VIA #1's timer 1 is not needed, use it.

**What BackTrak is for.** There is one advantage that matters, and it follows from the single timer:

* **The jitter correction does not depend on the IRQ's period.** BackTrak measures how late an IRQ was against the counter of the timer that raised it, which has been counting since that timer reloaded, whatever its period was. A reference timer that free-runs at one fixed period, as Mäkelä's does, is a fixed distance from the IRQ timer only while the IRQ timer's period stays the same. In the jitter check the timer's period was raised from a frame to a frame plus 15 cycles, six IRQs at a time, with the main program interrupted at every phase of its loops, and every period came out exactly as set. A program that wants several raster splits in a frame, at different lines, needs IRQs at different intervals. I expect Mäkelä's scheme to need both of its timers reloaded together to do that, but that is from reading his listing, and has not been tried here. BackTrak's split screen demo (see [Splitting the frame](#splitting-the-frame)) does it: two IRQs in every frame, at different lines, each on exactly the cycle it was meant for.
* **VIA #1 is left free.** The sync uses only timer 1 of VIA #2. VIA #1's timers and its interrupts belong to the program (its interrupts are masked, and the NMI vector points at an `RTI`, so the RESTORE key and Run/Stop-Restore do nothing). Mäkelä's reference timer takes VIA #1's timer 1.

**Smaller points, which are conveniences and not advantages of the technique.** One binary detects PAL or NTSC at run time and holds both sets of constants (it costs about 100 bytes more than building for one). The tracking state keeps stepping until `$9004` changes, whatever cycle it began on, where a loop with a fixed number of passes assumes that its coarse poll left the uncertainty it was built for (which the poll does, in practice). The stable point is raster line 0, cycle 0, which the effects' `startPad` is written against, but any routine could be tuned to a fixed position. The effects and their framework are not part of the sync, and would work on Mäkelä's.

Neither routine has been seen to work on an NTSC VIC-20: Mäkelä reports that an early version of his almost did, and BackTrak's NTSC lock and effects are checked in VICE only. BackTrak has not run on a real VIC-20 at all.

## Splitting the frame

A frame with more than one raster IRQ needs an IRQ at each of several lines, which is a timer with a different period before each, and each IRQ still has to be on the right cycle. The fourth effect of the demo does it with two IRQs, one at the top of the frame and one in the middle of the picture, and draws a stripe in each half: red in the top half and light blue in the bottom half, both starting on the same cycle of every raster line. If both IRQs are cycle-exact the two stripes make one straight vertical line through the screen, and a cycle of error (four pixels) is a visible step in it. They do, on PAL and on NTSC. (`:effect=3` starts on it, and `:still=1` keeps it.)

**How it works.** Every IRQ restarts the timer for the next one. A write to the timer's high counter loads the counter from the latch, so the next underflow is the latch plus 3 cycles after that write (`RESTART`, measured in VICE), and the write is a known number of cycles after the IRQ's stable point, so the interval between the two stable points is whatever the latch is chosen to make it:

    latch = interval - STABLE_DELAY - EFFECT_START - at - RESTART

where `STABLE_DELAY` is the 72 cycles from an underflow to the stable point, `EFFECT_START` is the 60 from the stable point to the effect's first instruction, and `at` is how many cycles into the effect the restarting write is. The first IRQ (at the top of the frame, line 0) restarts the timer for an interval to the split line (166 on PAL, 143 on NTSC), and the second restarts it for the rest of the frame, puts the locked latch back so that the timer is a frame again after it, and ends the frame, so the demo can change effect only between frames. The jitter correction does not change: it measures how late an IRQ was against the counter and latch of the timer that raised it, whatever the period was, and takes up the difference with the same slide. Both halves draw their stripes with the same loop, which they call.

**Measured in VICE 3.10**, with the main program replaced by one that the IRQ interrupts at every kind of instruction: from the lock, 144 IRQs on PAL and 143 on NTSC alternated between line 0 and the split line, every one with its stable point on cycle 0, and the intervals between them were exactly 11,786 and 10,366 cycles on PAL (166 and 146 lines of 71) and 9,295 and 7,670 on NTSC. With the animation running, the effect was made to change from the waving flag to the split screen and on to the copper bars, and every IRQ before, during and after was on the cycle it should be.

**What it does and does not show.** It shows that the single-timer correction holds with IRQs at different intervals, which was the claim above. It does not show that a design with a second, free-running timer cannot do the same: that is still a reading of its listing. The limits are the ordinary ones. Each handler must be finished (registers restored, `RTI` taken) before the next IRQ's underflow, so the top half stops five lines before the split and the bottom half stops short of the end of the frame. `RESTART` is a property of the 6522 as VICE models it. The two IRQs belong together, so `EFFECT` must change only between frames while the split screen is on: the demo changes it at the end of the second IRQ (in `advance_frame`), and a program that wrote it between the two would run the wrong effect on the second and leave the timer on the split screen's latch.

**Fitting it in.** The demo's program area was full, and the split screen needed about 215 bytes. They came from three changes, none of which alters what the other effects do. The copper bars' sine table is now half a cosine (128 bytes, where a whole sine was 256), which the drawing routine folds with a branch that takes the same cycles either way (`COMPOSE_CYCLES` is 27 more); `split_pal` sits in the other half of that page. `split_ntsc` sits in the space before `compose_bars`, which the loader leaves. The demo's main loop moved into the space that `copper_ntsc` leaves in its half page, to make room for the names.

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
* **Work between frames** goes before the first line, where there are 27 lines of nothing visible to spend it in: the effects wait that long (`startPad`), and it is 1,917 cycles on PAL and 1,755 on NTSC. The copper bars draw themselves into their line buffer there, in `compose_bars`, which takes exactly 976 cycles (`COMPOSE_CYCLES`) whatever the bars' positions, because the loop that follows is timed from its end: that is why its tables are page-aligned and why it takes the same cycles with and without animation. Work that is not counted to the cycle goes after the last line, as `advance_frame` does.
* **Beyond `$900F`.** Anything the VIC does at a known cycle can be done this way: moving the screen sideways on each line (`$9000`), changing the character set, or the sound registers. How early in a line a register must be written for it to take effect on that line is the VIC's business, so find it by looking at the result.

### Tuning for your machine

The cycle counts that place the stable point on raster line 0, cycle 0 were measured in VICE 3.10. If the lock is not at line 0, cycle 0 on your machine, the numbers to change are in `BRS_runtime_constants.asm`:

* `PAL_ARM_CUT` and `NTSC_ARM_CUT`: add the number of cycles late the stable point is, or subtract the number of cycles early it is.
* `PAL_FIRST_CUT` and `NTSC_FIRST_CUT` only decide how soon the lock is found. They aim the first IRQ about 14 cycles inside the zero window of `$9004`. Increase one to aim earlier; a first IRQ outside the window locks onto the wrong edge.

To see where the stable point is, break at the `stable` label in the VICE monitor: the register line gives `LIN` and `CYC`, which should be 0 and 0 when the sync is locked.

## Building

**To build from source you need [KickAssembler 5.25](https://theweb.dk/KickAssembler/Main.html#frontpage)**, the cross-assembler that all of the sources are written for (it is a Java program, so it needs Java). The sources use its directives, macros and functions, and no other assembler will build them. [VICE 3.10](https://vice-emu.sourceforge.io/) is only needed to run the result.

    java -jar KickAss.jar main.asm -vicesymbols       builds BackTrak.d64 and main.vs

The build works out its own timing: it solves the spin loop counts for PAL and NTSC, and stops with a message if a loop would cross a page, if a table would, if the program would run into the line buffer at `$1D00`, or if a change to a cycle count leaves no solution.

There are three build options, given on the command line after the file name:

    :effect=N       start on raster effect N (0 copper bars, 1 sine ribbon, 2 waving flag, 3 split screen)
    :still=1        do not animate, and do not change effect: every frame is the same
    :slide=0        build without the jitter slide

`:slide=0` is for seeing what the slide does. Without it the effects are drawn in the right shape but the whole picture jumps sideways by a few cycles from frame to frame, because the IRQ is taken at whatever point the main program had reached.

## Compatibility

The program runs on any VIC-20 memory configuration (see [Memory](#memory)), PAL or NTSC (detected at run time). It starts from a BASIC line that finds the loader wherever BASIC is. It uses only documented NMOS 6502 opcodes.

## Programming caveats

* The program takes over the IRQ vector (`$0314`), VIA #2 timer 1 and the NMI vector (`$0318`), so the KERNAL's jiffy clock, keyboard scan and cursor flash stop. It never returns to BASIC.
* **NMIs and the RESTORE key.** The RESTORE key is VIA #1's CA1 input, which VIA #1 turns into an NMI, and an NMI cannot be masked. The KERNAL's NMI handler (`$FEAD`) runs the jiffy clock, scans for an autostart cartridge and scans the STOP key; if STOP is down (Run/Stop-Restore) it restores the default I/O vectors, which include the IRQ vector, re-initialises the chips and jumps into BASIC. That ends the program, and even a plain RESTORE would cost a few hundred cycles of some frame. `initialise_sync` therefore disables every VIA #1 interrupt (RESTORE is the only one that was enabled) and points the NMI vector at an `RTI`, which also covers anything on the expansion port that pulls the NMI line itself (such an NMI still costs about 27 cycles of the frame it lands in). Reset the machine to leave the program.
* It uses zero-page locations `$03-$04` and `$FB-$FD`, and the demo uses `$05-$06`, `$FE`, `$0200-$020A` and the page at `$1D00`. A main program must leave all of them alone.
* The timing depends on the KERNAL IRQ stub at `$FF72` (it adds 36 cycles between the VIA interrupt and the program's handler, and the handler leaves with the same register restore as the KERNAL exit at `$EB15`). A different KERNAL (JiffyDOS, for example) needs its entry cost re-measured: see `IRQ_ENTRY` in `BRS_runtime_constants.asm`.
* The jitter correction covers an IRQ that is taken 1 to 8 cycles late, which is every instruction the 6502 has. A main program that disables interrupts for more than a frame, or that changes VIA #2 timer 1, will lose the lock.
* The cycle cuts for the two standards differ because the VIC's raster counter reads zero from a slightly different beam position on each, in VICE. See [Tuning for your machine](#tuning-for-your-machine) if the lock is not at line 0, cycle 0 on real hardware.

## Release history

### Release 1.0 (21st November 2026)
* Added a backtracking raster sync for the VIC-20 that needs only one timer, VIA #2's timer 1: a period one cycle short of a frame walks the IRQ back against the raster counter until the beam position is known to the cycle, in about a third of a second, on PAL and on NTSC (detected at run time)
* Added jitter cancellation: every IRQ measures how late it was against the counter of the timer that raised it and slides by the difference, so its stable point is always raster line 0, cycle 0, whatever instruction the main program was in
* Added a loader and a BASIC line (`SYS PEEK(43)+256*PEEK(44)+offset`) so that the program runs on every memory configuration, from an unexpanded VIC-20 to one with 24K or more, with the screen at `$1E00` on all of them
* Added protection from the RESTORE key and Run/Stop-Restore, which cannot disturb the lock
* Added four cycle-exact raster effects as a demonstration: copper bars (fire, ice and violet, over the whole picture), a sine ribbon, a red, white and blue waving flag, and a split screen with two IRQs in every frame
* Added a split screen that restarts the timer from each IRQ, to show the correction holding when the IRQs are at different intervals
* Added build options `:effect=N`, `:still=1` and `:slide=0`, and assembly-time checks for the layouts that the timing relies on (page crossings, alignment and the space each routine has)
* Added a sync of 304 bytes (282 of code and 22 of tables) that leaves about 2.9 KB of an unexpanded VIC-20's RAM for the program, with the demo's effects and tables in the rest


# Who is 8-Bit Guru?

8-Bit Guru (also: Eight-Bit Guru, 8BitGuru, 8BG) is the *nom de guerre* of Mark Johnson. I'm a professional coder from the UK who has been telling computers what to do since 1981. My day job is all about C# and Azure, whilst my hobby projects mostly involve writing 6502 machine code for the Commodore VIC-20.
