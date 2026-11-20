// BackTrak Raster Sync runtime constants and cycle model
// Copyright (C) 2026 8BitGuru <the8bitguru@gmail.com>

.filenamespace BRS_runtime_constants

// Video standards
.label PAL_FRAME        = 22152     // PAL cycles per frame (312 lines of 71 cycles)
.label NTSC_FRAME       = 16965     // NTSC cycles per frame (261 lines of 65 cycles)
.label PAL_LINE         = 71        // PAL cycles per raster line
.label NTSC_LINE        = 65        // NTSC cycles per raster line
.label ROW_SIZE         = 9         // Bytes in a PAL or NTSC row of the sync values table

// The sync is a closed loop of exact cycle counts. While backtracking, VIA2 T1 free-runs with a period of one cycle less than a
// frame (the latch is two less than the period, because the 6522 reloads in N+2 cycles), so each IRQ lands one cycle earlier
// against the raster than the one before. The IRQ always interrupts the same NOP of the spin loop because, per IRQ,
//
//     spin loop period + IRQ cycles = timer period
//
// where the IRQ cycles run from the end of the interrupted instruction to the end of the RTI. The timer is never held while an IRQ
// is handled.
//
// Once locked, the IRQ interrupts any instruction of the main program, which delays it until that instruction has finished. The
// handler cancels this: reading the timer's low byte as the acknowledge says how late the IRQ was, and a slide of 0 to 7 cycles takes
// up the difference, so the stable point after the slide is always the same number of cycles after the timer underflow. The slide
// has room for a delay of 1 to 8 cycles. In xvic 3.10 the delay is 1 to 7 (a slide of 7 down to 1, tested against every phase of 7
// cycle instructions), so slide 0 is spare, at the late end where a surprise is possible: an IRQ cannot be taken before the end of
// the instruction it interrupts, so the early end is a hard limit.
.label IRQ_ENTRY        = 36        // VIA IRQ to the handler's first instruction: 7 (IRQ response) + 29 (KERNAL stub at $FF72 up to JMP ($0314))
.label JITTER_SPAN      = 8         // Cycles between the earliest and the latest IRQ response (the slide takes up 0 to JITTER_SPAN - 1)
.label CORRECT_BODY     = 28        // Jitter correction before the slide: LDA (4), CLD (2), SEC (2), SBC (4), ADC (2), then the three stages (LSR, BCS/BCC) with no delay (14)
.label CORRECT_X        = 47        // Elapsed timer cycles at the read when the IRQ is as late as the slide allows: the slide is this less the elapsed cycles
.label DISPATCH         = 23        // LDX state (3), LDA hi (4), PHA (3), LDA lo (4), PHA (3), RTS (6)
.label IRQ_EXIT         = 22        // PLA TAY PLA TAX PLA RTI, restoring the registers the KERNAL stub pushed
.label TRACK_BODY       = 22        // Cycles in every tracking state routine, including its JMP to the exit
.label LOCKSTEP_SLIDE   = 7         // Cycles of slide taken in every IRQ while the spin loop is running (it is always the same)
.label HANDLER_TRACK    = IRQ_ENTRY + CORRECT_BODY + LOCKSTEP_SLIDE + DISPATCH + TRACK_BODY + IRQ_EXIT   // Cycles of a tracking IRQ

// Stack page offsets, from the stack pointer, of the interrupted code's return address in a service routine (above .Y .X .A and the flags)
.label RETURN_PCL       = $0105     // Return address lo-byte
.label RETURN_PCH       = $0106     // Return address hi-byte

// Spin loop: LDX outer, then (LDY inner, DEY/BNE, payload, DEX/BNE) repeated, then NOPs, then JMP back to the top
.label SPIN_PAYLOAD     = 2         // Cycles in the outer loop payload (a NOP)
.label SPIN_NOPS        = 12        // NOPs at the end of the spin loop, where every IRQ lands
.label SPIN_BYTES       = 14 + SPIN_NOPS    // Bytes in the spin loop, which must not cross a page
// Lock timing. The timer starts with a first period shortened by FIRST_CUT, so that the first IRQ reads $9004 just inside its zero window
// (143 cycles on PAL, only 88 on NTSC in xvic 3.10) and backtracking has only a few cycles to go to the edge. When the raster is first
// seen to move on, the next IRQ restarts the timer with a first period shortened by ARM_CUT, so that the stable point of every IRQ after
// it is at raster line 0, cycle 0 as VICE counts them. The first read of $9004 that is not zero is at beam position -1 on PAL but -5 on
// NTSC (xvic 3.10), which is why the standards have different cuts. The cuts were measured with testsrs_probe.py.
.label PAL_FIRST_CUT    = 115       // PAL cycles to shorten the first period of the timer by, at start-up
.label NTSC_FIRST_CUT   = 113        // NTSC cycles to shorten the first period of the timer by, at start-up
.label PAL_ARM_CUT      = 93        // PAL cycles to shorten the first period of the timer by, at the arm state
.label NTSC_ARM_CUT     = 89        // NTSC cycles to shorten the first period of the timer by, at the arm state

// The wait between starting the timer and the spin loop puts the first IRQ in the middle of the NOPs. Counted from the timer start it is
// LDA (4) STA (4) LDA (4) STA (4) to restore the latch, LDX (4), CLI (2), the loop (5 a pass less 1) and JMP (3), and it must be
// HANDLER_TRACK + 3 + SPIN_NOPS less the first period cut, to the nearest five cycles (the NOPs are 24 cycles wide).
.label PAL_START_CNT    = floor((HANDLER_TRACK + 3 + SPIN_NOPS - 24 - PAL_FIRST_CUT + 2) / 5)       // PAL start delay loop count
.label NTSC_START_CNT   = floor((HANDLER_TRACK + 3 + SPIN_NOPS - 24 - NTSC_FIRST_CUT + 2) / 5)      // NTSC start delay loop count
.errorif (PAL_START_CNT < 1) || (PAL_START_CNT > 255) || (NTSC_START_CNT < 1) || (NTSC_START_CNT > 255), "The first period cut leaves no start delay loop count: change a FIRST_CUT"

.errorif CORRECT_X >= ((NTSC_FRAME - 3) & $FF), "The timer low byte could wrap before the jitter read, so the correction would see the wrong elapsed time"

// Cycles of a spin loop with the given outer and inner counts
.function spinCycles(outer, inner)
{
	.return 3 + outer * (3 + 5 * inner - 1 + SPIN_PAYLOAD + 2 + 3) - 1 + 2 * SPIN_NOPS + 3
}

// Counts [outer, inner] for a spin loop of exactly this many cycles, or an empty list
.function solveSpin(cycles)
{
	.var found = List()
	.for (var outer = 1; outer < 256; outer++)
	{
		.for (var inner = 1; inner < 256; inner++)
		{
			.if (found.size() == 0 && spinCycles(outer, inner) == cycles)
				.eval found.add(outer, inner)
		}
	}
	.return found
}

// Spin loop counts so that the loop period is the timer period less the tracking IRQ, for each standard
.var palSpin = solveSpin(PAL_FRAME - 1 - HANDLER_TRACK)
.var ntscSpin = solveSpin(NTSC_FRAME - 1 - HANDLER_TRACK)
.errorif palSpin.size() == 0, "No PAL spin loop counts give " + (PAL_FRAME - 1 - HANDLER_TRACK) + " cycles: change TRACK_BODY, SPIN_NOPS or SPIN_PAYLOAD"
.errorif ntscSpin.size() == 0, "No NTSC spin loop counts give " + (NTSC_FRAME - 1 - HANDLER_TRACK) + " cycles: change TRACK_BODY, SPIN_NOPS or SPIN_PAYLOAD"
.label PAL_OUTER        = palSpin.get(0)    // PAL spin loop outer count
.label PAL_INNER        = palSpin.get(1)    // PAL spin loop inner count
.label NTSC_OUTER       = ntscSpin.get(0)   // NTSC spin loop outer count
.label NTSC_INNER       = ntscSpin.get(1)   // NTSC spin loop inner count

// Colour bars: each of the first BAR_LINES raster lines has a stripe of colour that starts and ends on the same cycle of the line, so
// its edges are straight if the sync is stable. A line is a loop of exactly one raster line: LDA col,X (4), STA (4), Pad, LDA # (2),
// STA (4), INX (2), CPX # (2), BEQ (2), LDA adjust (3), BEQ (3 on PAL, 2 on NTSC), LDY count (3), DEY/BNE (5 per count less 1), JMP (3)
.label BAR_LINES        = 240       // Raster lines with a stripe (the colour table length, up to 255)
.label BAR_PAD          = 10        // Cycles of padding between the two writes, which with the STA and LDA makes the stripe 16 cycles wide
.label BAR_BYTES        = 31 + BAR_PAD / 2  // Bytes in the colour bar routine, which must not cross a page
.label BAR_BASE         = $1B       // The screen colour that ends each stripe: white screen, normal characters, cyan border
.label PAL_LINE_DLY     = (PAL_LINE - 31 - BAR_PAD) / 5     // PAL line delay loop count
.label NTSC_LINE_DLY    = (NTSC_LINE - 30 - BAR_PAD) / 5    // NTSC line delay loop count
.errorif mod(PAL_LINE - 31 - BAR_PAD, 5) != 0, "The PAL line is not a whole number of delay loops: change BAR_PAD"
.errorif mod(NTSC_LINE - 30 - BAR_PAD, 5) != 0, "The NTSC line is not a whole number of delay loops: change BAR_PAD"
.errorif BAR_LINES > 255, "BAR_LINES must fit the .X counter"
