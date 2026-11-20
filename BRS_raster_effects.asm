// BackTrak Raster Sync locked raster effects
// Copyright (C) 2026 8BitGuru <the8bitguru@gmail.com>

.filenamespace BRS_raster_effects

// Start the colour bar routine on the next page if it would otherwise cross one, because its branches must not cost an extra cycle
.if ((* & $FF) > 256 - BRS_runtime_constants.BAR_BYTES)
{
	.align 256
}


// Draw a stripe of colour on each of the first BAR_LINES raster lines, each starting and ending on the same cycle of its line
// => LINEDLY Raster line delay loop count (PAL or NTSC)
// => LINEADJ Raster line adjustment (0=PAL, !0=NTSC)
run_raster_effects:
.pc = * "run_raster_effects"
{
			// every pass of the loop is one raster line, so the stripe starts and ends at the same place on every line
			ldx #0											// [2]		set first raster line
barloop:	lda BRS_static_data.BARCOL,x					// [4]		get stripe colour for the line
barwrite:	sta vic20.vic.VCSCRNCO							// [4]		start the stripe (set background and border colour)
			Pad(BRS_runtime_constants.BAR_PAD)				// [10]		make the stripe the same width on every line
			lda #BRS_runtime_constants.BAR_BASE				// [2]		get the screen colour
			sta vic20.vic.VCSCRNCO							// [4]		end the stripe
barend:		inx												// [2]		increment raster line
			cpx #BRS_runtime_constants.BAR_LINES			// [2]		check for the last line
			beq done										// [2/3]	exit after the last line

			// pad the line out to its length for the video standard
			lda BRS_runtime_memory.LINEADJ					// [3]		get line adjustment
			beq adjust										// [3/2]	the branch costs a cycle more on PAL than NTSC, which is the odd cycle of the six they differ by
adjust:		ldy BRS_runtime_memory.LINEDLY					// [3]		get line delay count
delayloop:	dey												// [2]		decrement delay count
			bne delayloop									// [3/2]	loop until the line is done
			jmp barloop										// [3]		draw the next line

done:		rts												// [6]

			.errorif (*-run_raster_effects) != BRS_runtime_constants.BAR_BYTES, "run_raster_effects is not BAR_BYTES long: change BAR_BYTES"
			.errorif (>run_raster_effects) != (>(*-1)), "run_raster_effects crosses a page: its branches would cost an extra cycle"
}
