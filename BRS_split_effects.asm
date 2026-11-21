// BackTrak Raster Sync split screen effect
// Copyright (C) 2026 8BitGuru <the8bitguru@gmail.com>

.filenamespace BRS_raster_effects

// The split screen has two IRQs in every frame: one at the top, and one in the middle of the screen. Each has its own stable point and draws its own
// half of the picture: the top half a red stripe and the bottom half a blue one, both starting on the same cycle of every raster line, so that they make
// one straight vertical line if both IRQs are cycle-exact (a cycle is four pixels wide, so a cycle of error is a step in the line that can be seen).
//
// Each IRQ restarts the timer for the next one. Restarting loads the counter from the latch, so the next underflow is the latch plus RESTART cycles
// after the write that restarts it, and the write is a known number of cycles after the stable point: the interval between stable points is then
// exactly what was asked for, whatever it is. The jitter correction measures an IRQ's lateness against the counter and latch of the timer that raised
// it, so it does not care that the periods are different. The second IRQ puts the locked latch back, so that the timer is a frame again after it, and
// it ends the frame (advance_frame), so the effect can change only between frames.
//
// The routines are placed to fill space that the other effects leave: split_pal in the second half of the page that COSPOS starts, and split_ntsc in the
// space before compose_bars (which is imported after this file)

.label PAL_SPLIT_LINE   = 166       // The raster line of the second IRQ's stable point on PAL (the picture is lines 27 to 310)
.label NTSC_SPLIT_LINE  = 143       // and on NTSC (the picture is lines 27 to 260)
.label PAL_SPLIT_LAST   = 305       // The last raster line of the bottom half on PAL: the next frame's IRQ is taken on line 310
.label NTSC_SPLIT_LAST  = 255       // and on NTSC, where it is taken on line 259
.label SPLIT_WRITE      = 30        // The cycle of a raster line that the stripe starts on
.label SPLIT_WIDTH      = 16        // Cycles in the stripe
.label RESTART          = 3         // Cycles from the write that restarts the timer to the underflow, less the latch (measured with xvic 3.10)
.label STABLE_DELAY     = BRS_runtime_constants.IRQ_ENTRY + BRS_runtime_constants.CORRECT_BODY + BRS_runtime_constants.JITTER_SPAN     // Cycles from an underflow to its stable point (72)
.const SPLIT_TOP        = pair(2)   // The top half's stripe is red
.const SPLIT_BOTTOM     = pair(14)  // and the bottom half's is light blue (with a blue border)

// Cycles to wait after `fixed` cycles of an effect's start, so that the instruction `idx` cycles into the first line's loop is on `cycle` of raster line
// `first`, when the effect starts EFFECT_START cycles after a stable point on raster line `origin`
.function startPadAt(origin, first, line, fixed, idx, cycle)
{
	.var pad = (first - origin) * line + cycle - idx - BRS_runtime_constants.EFFECT_START - fixed
	.errorif pad < 0, "The effect starts too late to draw its first line"
	.errorif pad == 1, "The effect cannot wait one cycle: move the first line"
	.return pad
}

// The latch that restarts the timer so that the next stable point is `interval` cycles after this one. Both stable points are STABLE_DELAY after their
// underflows, so that is the interval between the underflows: from this one to the write that restarts the timer is STABLE_DELAY, EFFECT_START (the routine
// starts that long after the stable point) and `at` (the write is that many cycles into the routine), and then the latch plus RESTART cycles to the next
.function restartLatch(interval, at)
{
	.return interval - STABLE_DELAY - BRS_runtime_constants.EFFECT_START - at - RESTART
}

// The split screen for one video standard: the IRQ at the top of the frame draws the top half and restarts the timer for the second IRQ, and the second
// draws the bottom half, restarts the timer for the next frame's first, and ends the frame. Both draw their stripes with the same loop, which they call
// => line Cycles in a raster line
// => split The raster line of the second IRQ's stable point
// => last The last raster line to draw
// => frame Cycles in a frame
.macro SplitScreen(line, split, last, frame)
{
			lda BRS_runtime_memory.SPLITPH					// [4]		get which IRQ this is
			bne !bottom+									// [2/3]	go to the bottom half if it is the second

			// the top half: restart the timer for the second IRQ
			lda #<restartLatch(split * line, 17)			// [2]		get the latch lo-byte
			sta vic20.via2.V2T1LL							// [4]		set VIA2 timer #1 lo-latch
			lda #>restartLatch(split * line, 17)			// [2]		get the latch hi-byte
			sta vic20.via2.V2T1CH							// [4]		set VIA2 timer #1 hi-counter, which restarts it (this write is 17 cycles into the routine)
			inc BRS_runtime_memory.SPLITPH					// [6]		have the next IRQ be the second
			lda #split - 31									// [2]		get the lines to draw: from the picture's first line to five before the split
			sta BRS_runtime_memory.LINECNT					// [3]		set lines left
			ldx #SPLIT_TOP									// [2]		get the stripe colour
			Wait(startPadAt(0, BRS_runtime_constants.EFFECT_FIRST_LINE, line, 4 + 2 + 12 + 6 + 2 + 3 + 2, 9, SPLIT_WRITE))	// [-]	wait to the first line
			jsr !stripes+									// [6]		draw the top half
			rts												// [6]		return to hold_sync

			// the bottom half: restart the timer for the next frame's first IRQ, and put the locked latch back for every period after that
!bottom:	lda #<restartLatch(frame - split * line, 18)	// [2]		get the latch lo-byte
			sta vic20.via2.V2T1LL							// [4]		set VIA2 timer #1 lo-latch
			lda #>restartLatch(frame - split * line, 18)	// [2]		get the latch hi-byte
			sta vic20.via2.V2T1CH							// [4]		set VIA2 timer #1 hi-counter, which restarts it (this write is 18 cycles into the routine)
			lda #<(frame - 2)								// [2]		get the locked latch lo-byte
			sta vic20.via2.V2T1LL							// [4]		set VIA2 timer #1 lo-latch
			lda #>(frame - 2)								// [2]		get the locked latch hi-byte
			sta vic20.via2.V2T1LH							// [4]		set VIA2 timer #1 hi-latch (the counter is not touched)
			dec BRS_runtime_memory.SPLITPH					// [6]		have the next IRQ be the first
			lda #last - (split + 2) + 1						// [2]		get the lines to draw: from two after the split to the last
			sta BRS_runtime_memory.LINECNT					// [3]		set lines left
			ldx #SPLIT_BOTTOM								// [2]		get the stripe colour
			Wait(startPadAt(split, split + 2, line, 7 + 12 + 12 + 6 + 2 + 3 + 2, 9, SPLIT_WRITE))	// [-]	wait to the first line
			jsr !stripes+									// [6]		draw the bottom half
			jmp advance_frame								// [3]		end the frame

			// draw a stripe on each of the raster lines in LINECNT, in the colour in .X (.Y is the wait's, which would lose it): the first write is 3 cycles into the loop and the second is 19, so the stripe is 16 cycles wide
!stripes:	stx vic20.vic.VCSCRNCO							// [4]		start the stripe
			Pad(SPLIT_WIDTH - 6)							// [-]		hold it
			lda #BRS_runtime_constants.SCREEN_BASE			// [2]		get the screen colour
			sta vic20.vic.VCSCRNCO							// [4]		end the stripe
			dec BRS_runtime_memory.LINECNT					// [5]		decrement lines left
			beq !done+										// [2/3]	exit after the last line
			Wait(line - 30)									// [-]		make the loop take a raster line
			jmp !stripes-									// [3]		draw the next line
!done:		rts												// [6]
}


.label split_resume = *

// The split screen on PAL, in the space that the cosine table leaves
.pc = BRS_static_data.SPLIT_HOLE "split_pal"
split_pal:
{
			SplitScreen(BRS_runtime_constants.PAL_LINE, PAL_SPLIT_LINE, PAL_SPLIT_LAST, BRS_runtime_constants.PAL_FRAME)	// [-]
}
split_pal_end:
.errorif split_pal_end > BRS_static_data.SPLIT_HOLE + 128, "split_pal does not fit in the rest of the page that COSPOS starts: it is " + [split_pal_end - BRS_static_data.SPLIT_HOLE - 128] + " bytes too long"
.errorif (>split_pal) != (>(split_pal_end-1)), "split_pal crosses a page: its branches would cost an extra cycle"


// The split screen on NTSC, in the space before compose_bars
.pc = split_resume "split_ntsc"
split_ntsc:
{
			SplitScreen(BRS_runtime_constants.NTSC_LINE, NTSC_SPLIT_LINE, NTSC_SPLIT_LAST, BRS_runtime_constants.NTSC_FRAME)	// [-]
}
split_ntsc_end:
.errorif (>split_ntsc) != (>(split_ntsc_end-1)), "split_ntsc crosses a page: its branches would cost an extra cycle"
