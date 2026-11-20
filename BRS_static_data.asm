// BackTrak Raster Sync static data structures
// Copyright (C) 2026 8BitGuru <the8bitguru@gmail.com>

.filenamespace BRS_static_data

SYNCVALS:				// Sync values for each video standard, copied to zero-page or read by initialise_sync
.pc = * "SYNCVALS"		// PAL row then NTSC row of: line delay count, line adjustment, arm cut, spin loop outer count, inner count, first period cut, start delay count, backtrack timer latch (word) (18 bytes)
.byte BRS_runtime_constants.PAL_LINE_DLY, 0, BRS_runtime_constants.PAL_ARM_CUT		// PAL colour bar line delay count and adjustment (branch taken), and arm cut
.byte BRS_runtime_constants.PAL_OUTER, BRS_runtime_constants.PAL_INNER				// PAL spin loop counts
.byte BRS_runtime_constants.PAL_FIRST_CUT, BRS_runtime_constants.PAL_START_CNT		// PAL first period cut and start delay count
.word BRS_runtime_constants.PAL_FRAME - 3											// PAL backtrack timer latch (a period of latch + 2, one cycle less than a frame)
.byte BRS_runtime_constants.NTSC_LINE_DLY, 1, BRS_runtime_constants.NTSC_ARM_CUT	// NTSC colour bar line delay count and adjustment (branch not taken), and arm cut
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


// The $900F value for a stripe of the given line: bars of three lines, cycling through colours 2-15
.function barColour(line)
{
	.var colour = 2 + mod(floor(line / 3), 14)
	.return (colour << 4) | 8 | (colour & 7)    // b7-4 = background, b3 = normal (not reverse), b2-0 = border
}

// Start on a new page if the table would cross one, so that the indexed read in the colour bar loop takes its base cycle count
.if ((* & $FF) > 256 - BRS_runtime_constants.BAR_LINES)
{
	.align 256
}
BARCOL:					// Colour bar $900F value for each raster line
.pc = * "BARCOL"		// One value for each of the first BAR_LINES raster lines (240 bytes)
.fill BRS_runtime_constants.BAR_LINES, barColour(i)
.errorif (>BARCOL) != (>(*-1)), "BARCOL crosses a page: the colour bar loop would take an extra cycle"
