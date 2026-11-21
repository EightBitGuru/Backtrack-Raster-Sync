// BackTrak Raster Sync copper bar drawing
// Copyright (C) 2026 8BitGuru <the8bitguru@gmail.com>

.filenamespace BRS_copper_bars

// Command line :still=1 stops the animation (the same flag as BRS_raster_effects has), so the bars are still
.var StillFrame = cmdLineVars.containsKey("still") && cmdLineVars.get("still").asNumber() != 0      // Do not animate

.align 256     // Start on a new page: its loops must not cross one, because the routine is counted to the cycle (COMPOSE_CYCLES)
// Draw the copper bars in the line buffer, where each is on its own sine wave
// Takes COMPOSE_CYCLES whatever the phases, so that the copper bars' loop starts its first line on the right cycle
compose_bars:
.pc = * "compose_bars"
{
			// erase the bars where they were
			ldy #2											// [2]		set bar
eraseloop:	ldx BRS_runtime_memory.COPOLD0,y				// [4]		get the bar's first entry
			lda #BRS_runtime_constants.SCREEN_BASE			// [2]		get the screen colour
	.for (var line = 0; line < BRS_runtime_constants.COPPER_HEIGHT; line++)
	{
			sta BRS_runtime_memory.COPBUF + line,x			// [5]		clear an entry of the bar
	}
			dey												// [2]		next bar
			bpl eraseloop									// [3/2]	loop until done

			// then move each bar along its sine wave and draw it
			ldy #2											// [2]		set bar
drawloop:
	.if (!StillFrame)
	{
			lda BRS_runtime_memory.COPPH0,y					// [4]		get the bar's phase
			clc												// [2]
			adc BRS_static_data.COPSPEED,y					// [4]		move the bar's phase on
			sta BRS_runtime_memory.COPPH0,y					// [5]		set the bar's phase
	}
	else
	{
			Pad(15)											// [15]		take the cycles that moving the phase on takes
	}
			lda BRS_runtime_memory.COPPH0,y					// [4]		get the bar's phase
			bpl !first+										// [3/2]	go on if it is in the first half of the wave
			eor #$FF										// [2]		reverse the second half, which is the first half backwards
			jmp !second+									// [3]
!first:
			nop												// [2]		take the cycles that reversing takes
			nop												// [2]
!second:
			tax												// [2]		get the table index
			lda BRS_static_data.COSPOS,x					// [4]		get the bar's first entry
			ldx BRS_runtime_memory.VIDEOFLG					// [3]		get the video standard
			bne !ntsc+										// [3/2]	NTSC has fewer entries and uses the first entry as it is

			// PAL has a quarter as many entries again, so the first entry is 1.25 times as far
			pha												// [3]		stash the first entry
			lsr												// [2]
			lsr												// [2]		get a quarter of it
			sta BRS_runtime_memory.COPOLD0,y				// [5]		stash that
			pla												// [4]		get the first entry
			clc												// [2]
			adc BRS_runtime_memory.COPOLD0,y				// [4]		add a quarter of it
			jmp !done+										// [3]
!ntsc:
			Pad(24)											// [24]		take the cycles that scaling takes on PAL
!done:
			sta BRS_runtime_memory.COPOLD0,y				// [5]		stash the first entry to erase the bar next frame
			tax												// [2]
			sty BRS_runtime_memory.BARIDX					// [3]		stash the bar
			lda BRS_static_data.COPOFFS,y					// [4]		get the offset of the bar's colours
			tay												// [2]
	.for (var line = 0; line < BRS_runtime_constants.COPPER_HEIGHT; line++)
	{
			lda BRS_static_data.COPSHAPE + line,y			// [4]		get the colour of an entry of the bar
			sta BRS_runtime_memory.COPBUF + line,x			// [5]		draw an entry of the bar
	}
			ldy BRS_runtime_memory.BARIDX					// [3]		get the bar
			dey												// [2]		next bar
			bmi !end+										// [3/2]	exit after the last bar (the loop is too long for a branch back)
			jmp drawloop									// [3]		draw the next bar
!end:
			rts												// [6]

			.errorif (>compose_bars) != (>(*-1)), "compose_bars crosses a page: its branches would cost an extra cycle"
}
