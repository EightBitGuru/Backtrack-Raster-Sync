// BackTrak Raster Sync static data structures
// Copyright (C) 2026 8BitGuru <the8bitguru@gmail.com>

.filenamespace BRS_static_data

SYNCVALS:				// Sync values for each video standard, copied to zero-page or read by initialise_sync
.pc = * "SYNCVALS"		// PAL row then NTSC row of: arm cut, video standard, spin loop outer count, inner count, first period cut, start delay count, backtrack timer latch (word) (16 bytes)
.byte BRS_runtime_constants.PAL_ARM_CUT, 0											// PAL arm cut and video standard flag
.byte BRS_runtime_constants.PAL_OUTER, BRS_runtime_constants.PAL_INNER				// PAL spin loop counts
.byte BRS_runtime_constants.PAL_FIRST_CUT, BRS_runtime_constants.PAL_START_CNT		// PAL first period cut and start delay count
.word BRS_runtime_constants.PAL_FRAME - 3											// PAL backtrack timer latch (a period of latch + 2, one cycle less than a frame)
.byte BRS_runtime_constants.NTSC_ARM_CUT, 1											// NTSC arm cut and video standard flag
.byte BRS_runtime_constants.NTSC_OUTER, BRS_runtime_constants.NTSC_INNER			// NTSC spin loop counts
.byte BRS_runtime_constants.NTSC_FIRST_CUT, BRS_runtime_constants.NTSC_START_CNT	// NTSC first period cut and start delay count
.word BRS_runtime_constants.NTSC_FRAME - 3											// NTSC backtrack timer latch
.errorif * - SYNCVALS != 2 * BRS_runtime_constants.ROW_SIZE, "SYNCVALS rows are not ROW_SIZE bytes: change ROW_SIZE"
.errorif (>SYNCVALS) != (>(*-1)), "SYNCVALS crosses a page: the reads in initialise_sync would cost an extra cycle"


.var STATES = List().add(BRS_raster_sync.track_sync, BRS_raster_sync.arm_sync, BRS_raster_sync.hold_sync)
.pc = * "STATEJMP"		// Sync state routine addresses minus one for the RTS dispatch, lo-bytes then hi-bytes (6 bytes)
STATEJMP:				// Sync state routine addresses, indexed by SYNCSTAT
.lohifill STATES.size(), STATES.get(i) - 1
.errorif (>STATEJMP) != (>(*-1)), "STATEJMP crosses a page: the dispatch would cost an extra cycle"


// Raster effect routines indexed by EFFECT * 2 + VIDEOFLG, minus one for the RTS dispatch
.var EFFECTS = List().add(BRS_raster_effects.copper_pal, BRS_raster_effects.copper_ntsc, BRS_raster_effects.ribbon_pal, BRS_raster_effects.ribbon_ntsc, BRS_raster_effects.flag_pal, BRS_raster_effects.flag_ntsc, BRS_raster_effects.split_pal, BRS_raster_effects.split_ntsc)
.pc = * "EFFJMP"		// Raster effect routine addresses minus one, lo-bytes then hi-bytes (16 bytes)
EFFJMP:					// Raster effect routine addresses
.lohifill EFFECTS.size(), EFFECTS.get(i) - 1
.errorif (>EFFJMP) != (>(*-1)), "EFFJMP crosses a page: the effect dispatch would cost an extra cycle"


// A wave, 0 to twice the amplitude, of the given period in raster lines
.function wave(line, period, amplitude)
{
	.return floor(amplitude + amplitude * sin(2 * PI * mod(line, period) / period) + 0.5)
}

// Cycles a raster line takes, less 3, plus the number of cycles the stripe moves from line to line (the wave's step) plus 3: the delay for
// the loop to take on the line, in the range 0 to 7 that the slide can take up
.function waveStep(line, period, amplitude)
{
	.return 3 + wave(line + 1, period, amplitude) - wave(line, period, amplitude)
}

.var PALETTE = List().add(2, 8, 9, 7, 15, 13, 5, 3, 11, 1, 14, 6, 12, 4, 10, 2)
.function ribbonColour(line)
{
	.return pair(PALETTE.get(mod(floor(line / 2), 16)))
}

.var BAR_FIRE = List().add(2, 10, 8, 9, 7, 15, 1, 1)          // Copper bar colours, edge to middle: red, pink, orange, light orange, yellow, light yellow, white
.var BAR_ICE = List().add(6, 14, 14, 3, 11, 11, 1, 1)          // blue, light blue, cyan, light cyan, white
.var BAR_VIOLET = List().add(4, 4, 12, 12, 10, 10, 15, 1)       // purple, light purple, pink, light yellow, white
.var BARS = List().add(BAR_FIRE, BAR_ICE, BAR_VIOLET)

COPSHAPE:				// The colours of the lines of each copper bar
.pc = * "COPSHAPE"		// COPPER_HEIGHT $900F values for each of the three bars, up to the middle then back down (36 bytes)
.for (var bar = 0; bar < 3; bar++)
{
	.for (var line = 0; line < BRS_runtime_constants.COPPER_HEIGHT; line++)
	{
		.byte pair(BARS.get(bar).get(line < BRS_runtime_constants.COPPER_HEIGHT / 2 ? line : BRS_runtime_constants.COPPER_HEIGHT - 1 - line))
	}
}

COPOFFS:				// The offset in COPSHAPE of each copper bar's colours
.pc = * "COPOFFS"		// COPPER_HEIGHT for each bar (3 bytes)
.fill 3, i * BRS_runtime_constants.COPPER_HEIGHT

COPSPEED:				// How far each copper bar's phase moves on each frame
.pc = * "COPSPEED"		// Phase steps of 1/256 of the wave: the bars move up to 2, 4 and 2 lines a frame (3 bytes)
.byte 1, 2, 1
.errorif (>COPSHAPE) != (>(COPSPEED + 2)), "COPSHAPE, COPOFFS and COPSPEED cross a page: drawing the copper bars would take a different number of cycles"

// The 128-byte tables start on a half page, so that none of them crosses a page (the effects read them at a fixed cycle)
.align 128
FLAGPOS:				// Cycles the waving flag is across for a phase
.pc = * "FLAGPOS"		// 0 to 24 (128 bytes)
.fill 128, wave(i, 128, 12)
.errorif (>FLAGPOS) != (>(*-1)), "FLAGPOS crosses a page: the first read of the waving flag would cost an extra cycle"

RIBBONPOS:				// Cycles the sine ribbon is across for a phase
.pc = * "RIBBONPOS"		// 0 to 16 (64 bytes)
.fill 64, wave(i, 64, 8)
.errorif (>RIBBONPOS) != (>(*-1)), "RIBBONPOS crosses a page: the first read of the sine ribbon would cost an extra cycle"

// Start on a new page, so that reading COSPOS takes the same cycles whatever the phase (the copper bars are drawn in dead time that is counted to the cycle)
.align 256
COSPOS:				// First entry of a copper bar in the line buffer for the first half of a phase (an entry is two raster lines)
.pc = * "COSPOS"		// 1 to 101 along half a cosine (the PAL bars scale it by 1.25 to 126): the bar's phase 0 to 255 is folded into 0 to 127 by reading the second half backwards (128 bytes)
.fill 128, floor(51 - 50 * cos(2 * PI * (i + 0.5) / 256) + 0.5)
SPLIT_HOLE:				// The rest of the page, which split_pal is placed in (BRS_split_effects.asm)
.pc = * + 128 "SPLIT_HOLE"	// 128 bytes

// Page-aligned tables, which the effects read with .X as the index
.align 256
RIBBONSTEP:				// How many cycles the sine ribbon's line takes to draw over the usual, for the slide, for each line
.pc = * "RIBBONSTEP"	// 3 + the ribbon's step to the next line, which is -3 to +3 (256 bytes)
.fill 256, waveStep(i, 64, 8)

RIBBONCOL:				// The sine ribbon's colour for each line
.pc = * "RIBBONCOL"		// $900F values cycling through a palette every 32 lines (256 bytes)
.fill 256, ribbonColour(i)

FLAGSTEP:				// How many cycles the waving flag's line takes to draw over the usual less one, for the slide, for each line
.pc = * "FLAGSTEP"		// 1 + the flag's step to the next line, which is -1 to +1 (256 bytes)
.fill 256, 1 + wave(i + 1, 128, 12) - wave(i, 128, 12)

.for (var line = 0; line < 256; line++)
{
	.errorif (waveStep(line, 64, 8) < 0) || (waveStep(line, 64, 8) > 7), "The sine ribbon moves too far between lines for the slide: lower its amplitude or lengthen its period"
	.errorif (1 + wave(line + 1, 128, 12) - wave(line, 128, 12) < 0) || (1 + wave(line + 1, 128, 12) - wave(line, 128, 12) > 3), "The waving flag moves too far between lines for its slide of 2 bits: lower its amplitude or lengthen its period"
}
