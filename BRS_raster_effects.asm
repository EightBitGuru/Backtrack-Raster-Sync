// BackTrak Raster Sync raster effects
// Copyright (C) 2026 8BitGuru <the8bitguru@gmail.com>

.filenamespace BRS_raster_effects

// Command line :still=1 stops the animation and the change of effect, and :effect=N starts on effect N, which the tests use
.var StillFrame = cmdLineVars.containsKey("still") && cmdLineVars.get("still").asNumber() != 0      // Do not animate or change effect
.var FirstEffect = cmdLineVars.containsKey("effect") ? cmdLineVars.get("effect").asNumber() : 0     // Raster effect to start on

// The cycle of a raster line that each effect's first write of the line is on (the effects write at the same cycle of every line, apart
// from the waves, which move by the cycles of their wave)
.label COPPER_WRITE     = 0         // Copper bars: the colour changes at the start of the line, so the whole line has it
.label RIBBON_WRITE     = 24        // Sine ribbon: the ribbon's left edge when the wave is at its lowest (the wave takes it 16 cycles on)
.label PAL_FLAG_BASE    = 6         // Waving flag on PAL: the cycle of the picture's left edge, where the flag's left edge is when the wave is at its lowest (the wave takes it 24 cycles on)
.label NTSC_FLAG_BASE   = 5         // and on NTSC, where the picture's left edge is a cycle earlier
.label PAL_FLAG_BAND    = 15        // Cycles in a band of the waving flag on PAL: 45 across with the 24 of the wave is 69, and the picture is 71
.label NTSC_FLAG_BAND   = 13        // and on NTSC: 39 and 24 is 63, and the picture is 65

.const FLAG_RED = pair(2)           // Waving flag colours, left to right: red
.const FLAG_WHITE = pair(1)         // white
.const FLAG_BLUE = pair(14)         // and light blue (with a blue border)

// Cycles to wait after `fixed` cycles of an effect's start, so that the instruction `idx` cycles into the first line's loop is on `cycle` of the
// picture's first raster line (the effect starts EFFECT_START cycles after the stable point, which is line 0 cycle 0)
.function startPad(line, fixed, idx, cycle)
{
	.var pad = BRS_runtime_constants.EFFECT_FIRST_LINE * line + cycle - idx - BRS_runtime_constants.EFFECT_START - fixed
	.errorif pad < 0, "The effect starts too late to draw the first line of the picture"
	.if (pad == 1)
	{
		.eval pad = pad + 1
	}
	.return pad
}

// The copper bars: every two raster lines have the screen colour from the line buffer, so the loop is a load and a store (the colour stays until
// the next write). The bars are drawn in the line buffer first, while the first lines of the frame, which are not on the picture, go by
// => lines Raster lines to draw, which is twice the entries of the line buffer
// => line Cycles in a raster line
.macro CopperLines(lines, line)
{
			jsr compose_bars								// [6]		draw the bars in the line buffer (COMPOSE_CYCLES, which includes its RTS)
			ldx #0											// [2]		set first line
			lda #lines / 2									// [2]		get the pairs of lines to draw
			sta BRS_runtime_memory.LINECNT					// [3]		set pairs of lines left
			Wait(startPad(line, 6 + BRS_runtime_constants.COMPOSE_CYCLES + 7, 7, COPPER_WRITE))	// [-]	wait to the first line
!loop:
			lda BRS_runtime_memory.COPBUF,x					// [4]		get the screen colour for the pair of lines
			sta vic20.vic.VCSCRNCO							// [4]		set screen and border colour (the write is 7 cycles into the line's loop)
			inx												// [2]		increment pair of lines
			dec BRS_runtime_memory.LINECNT					// [5]		decrement pairs of lines left
			beq !done+										// [2/3]	exit after the last pair
			Wait(2 * line - 20)								// [-]		make the loop take two raster lines
			jmp !loop-										// [3]		draw the next line
!done:
			jmp advance_frame								// [3]
}


// The sine ribbon: a rainbow ribbon 16 cycles wide whose edges follow a sine wave. The wave moves the ribbon along by up to 16 cycles, and
// only needs the loop to take 3 cycles less or more than a line (the wave's step from one line to the next), taken up by a slide, so the
// edges are on the right cycle on every line
// => lines Raster lines to draw
// => line Cycles in a raster line
.macro RibbonLines(lines, line)
{
			lda #lines										// [2]		get the lines to draw
			sta BRS_runtime_memory.LINECNT					// [3]		set lines left
			ldx BRS_runtime_memory.RIBBONPH					// [4]		get the wave phase, which is also the first line's index in the tables
			lda BRS_static_data.RIBBONPOS,x					// [4]		get how far along the wave is on the first line
			Slide(5)										// [-]		move the start of the first line along by that many cycles
			Wait(startPad(line, 5 + 4 + 4 + (4 + 5 * 4), 7, RIBBON_WRITE))	// [-]	wait to the first line
!loop:
			lda BRS_static_data.RIBBONCOL,x					// [4]		get the ribbon colour for the line
			sta vic20.vic.VCSCRNCO							// [4]		start the ribbon (the write is 7 cycles into the line's loop)
			Pad(10)											// [10]		make the ribbon 16 cycles wide
			lda #BRS_runtime_constants.SCREEN_BASE			// [2]		get the screen colour
			sta vic20.vic.VCSCRNCO							// [4]		end the ribbon
			lda BRS_static_data.RIBBONSTEP,x				// [4]		get 3 plus the cycles the ribbon moves on to the next line
			inx												// [2]		increment line (and the index into the tables)
			Slide(3)										// [14+]	make the line take that many cycles more than a line less 3
			dec BRS_runtime_memory.LINECNT					// [5]		decrement lines left
			beq !done+										// [2/3]	exit after the last line
			Wait(line - 57)									// [-]		make the loop take a raster line less 3 plus the slide
			jmp !loop-										// [3]		draw the next line
!done:
			jmp advance_frame								// [3]
}


// The waving flag: three bands of colour that move along a slow, shallow sine wave in the same way as the ribbon. The wave only moves a band
// by 1 cycle less or more from one line to the next, so a slide of 2 bits does, and the instructions that the loop needs after the bands
// (the wave's step, the line counter) are in the spare cycles between the writes, which leaves room for bands that fill the picture
// => lines Raster lines to draw
// => line Cycles in a raster line
// => band Cycles in a band, which makes the flag 3 times as wide, plus the 24 cycles of its wave (at most the line less 21 / 3)
// => base The cycle of the first line at which the first band starts when the wave is at its lowest
.macro FlagLines(lines, line, band, base)
{
	.var gap = band - 6
	.errorif (gap < 7) || (gap == 8), "The flag's bands are too narrow for the instructions between the writes"
	.errorif (line - 21 - 3 * band < 0) || (line - 21 - 3 * band == 1), "The flag's bands are too wide for the raster line"
			lda #lines										// [2]		get the lines to draw
			sta BRS_runtime_memory.LINECNT					// [3]		set lines left
			ldx BRS_runtime_memory.FLAGPH					// [4]		get the wave phase, which is also the first line's index in the tables
			lda BRS_static_data.FLAGPOS,x					// [4]		get how far along the wave is on the first line
			Slide(5)										// [-]		move the start of the first line along by that many cycles
			Wait(startPad(line, 5 + 4 + 4 + (4 + 5 * 4), 5, base))	// [-]	wait to the first line
!loop:
			lda #FLAG_RED									// [2]		get the first band's colour
			sta vic20.vic.VCSCRNCO							// [4]		start the first band (the write is 5 cycles into the line's loop)
			ldy BRS_static_data.FLAGSTEP,x					// [4]		get 1 plus the cycles the flag moves on to the next line
			Pad(gap - 4)									// [-]		wait for the second band
			lda #FLAG_WHITE									// [2]		get the second band's colour
			sta vic20.vic.VCSCRNCO							// [4]		start the second band
			inx												// [2]		increment line (and the index into the tables)
			Pad(gap - 2)									// [-]		wait for the third band
			lda #FLAG_BLUE									// [2]		get the third band's colour
			sta vic20.vic.VCSCRNCO							// [4]		start the third band
			dec BRS_runtime_memory.LINECNT					// [5]		decrement lines left
			beq !done+										// [2/3]	exit after the last line
			Pad(gap - 7)									// [-]		wait for the end of the third band
			lda #BRS_runtime_constants.SCREEN_BASE			// [2]		get the screen colour
			sta vic20.vic.VCSCRNCO							// [4]		end the third band
			tya												// [2]		get the step
			Slide(2)										// [9+]		make the line take that many cycles more than a line less 1
			Wait(line - 21 - 3 * band)						// [-]		make the loop take a raster line less 1 plus the slide
			jmp !loop-										// [3]		draw the next line
!done:
			lda #BRS_runtime_constants.SCREEN_BASE			// [2]		get the screen colour
			sta vic20.vic.VCSCRNCO							// [4]		end the third band
			jmp advance_frame								// [3]
}


// Run the raster effect for the frame, which is what hold_sync calls at the stable point
// => EFFECT Raster effect
// => VIDEOFLG Video standard
run_raster_effects:
.pc = * "run_raster_effects"
{
			lda BRS_runtime_memory.EFFECT					// [4]		get raster effect
			asl												// [2]		two routines for each effect
			ora BRS_runtime_memory.VIDEOFLG					// [3]		add the video standard
			tax												// [2]
			lda BRS_static_data.EFFJMP.hi,x					// [4]		get effect routine address hi-byte (minus one)
			pha												// [3]		push hi-byte
			lda BRS_static_data.EFFJMP.lo,x					// [4]		get effect routine address lo-byte (minus one)
			pha												// [3]		push lo-byte
			rts												// [6]		dispatch to the effect routine, which returns to hold_sync

			.errorif (>run_raster_effects) != (>(*-1)), "run_raster_effects crosses a page: nothing in it would be slower, but keep the effect dispatch the cycles it is"
}


.align 128     // Start on a half page, so that the routine (under 128 bytes) does not cross a page, because its branches must not cost an extra cycle
// The copper bars on PAL
copper_pal:
.pc = * "copper_pal"
{
			CopperLines(BRS_runtime_constants.PAL_COPPER_LINES, BRS_runtime_constants.PAL_LINE)	// [-]
}
copper_pal_end:
.errorif (>copper_pal) != (>(copper_pal_end-1)), "copper_pal crosses a page: its branches would cost an extra cycle"


.align 128     // Start on a half page, so that the routine (under 128 bytes) does not cross a page, because its branches must not cost an extra cycle
// The copper bars on NTSC
copper_ntsc:
.pc = * "copper_ntsc"
{
			CopperLines(BRS_runtime_constants.NTSC_COPPER_LINES, BRS_runtime_constants.NTSC_LINE)	// [-]
}
copper_ntsc_end:
.errorif (>copper_ntsc) != (>(copper_ntsc_end-1)), "copper_ntsc crosses a page: its branches would cost an extra cycle"


.align 128     // Start on a half page, so that the routine (under 128 bytes) does not cross a page, because its branches must not cost an extra cycle
// The sine ribbon on PAL
ribbon_pal:
.pc = * "ribbon_pal"
{
			RibbonLines(BRS_runtime_constants.PAL_LINES, BRS_runtime_constants.PAL_LINE)	// [-]
}
ribbon_pal_end:
.errorif (>ribbon_pal) != (>(ribbon_pal_end-1)), "ribbon_pal crosses a page: its branches would cost an extra cycle"


.align 128     // Start on a half page, so that the routine (under 128 bytes) does not cross a page, because its branches must not cost an extra cycle
// The sine ribbon on NTSC
ribbon_ntsc:
.pc = * "ribbon_ntsc"
{
			RibbonLines(BRS_runtime_constants.NTSC_LINES, BRS_runtime_constants.NTSC_LINE)	// [-]
}
ribbon_ntsc_end:
.errorif (>ribbon_ntsc) != (>(ribbon_ntsc_end-1)), "ribbon_ntsc crosses a page: its branches would cost an extra cycle"


.align 128     // Start on a half page, so that the routine (under 128 bytes) does not cross a page, because its branches must not cost an extra cycle
// The waving flag on PAL
flag_pal:
.pc = * "flag_pal"
{
			FlagLines(BRS_runtime_constants.PAL_LINES, BRS_runtime_constants.PAL_LINE, PAL_FLAG_BAND, PAL_FLAG_BASE)	// [-]
}
flag_pal_end:
.errorif (>flag_pal) != (>(flag_pal_end-1)), "flag_pal crosses a page: its branches would cost an extra cycle"


.align 128     // Start on a half page, so that the routine (under 128 bytes) does not cross a page, because its branches must not cost an extra cycle
// The waving flag on NTSC
flag_ntsc:
.pc = * "flag_ntsc"
{
			FlagLines(BRS_runtime_constants.NTSC_LINES, BRS_runtime_constants.NTSC_LINE, NTSC_FLAG_BAND, NTSC_FLAG_BASE)	// [-]
}
flag_ntsc_end:
.errorif (>flag_ntsc) != (>(flag_ntsc_end-1)), "flag_ntsc crosses a page: its branches would cost an extra cycle"


// Set up the raster effects
initialise_effects:
.pc = * "initialise_effects"
{
			lda #FirstEffect								// [2]		get the raster effect to start on
			sta BRS_runtime_memory.EFFECT					// [4]		set raster effect
			lda #0											// [2]
			sta BRS_runtime_memory.FRAMECNT					// [4]		set frame counter
			sta BRS_runtime_memory.RIBBONPH					// [4]		set sine ribbon phase
			sta BRS_runtime_memory.FLAGPH					// [4]		set waving flag phase
			sta BRS_runtime_memory.COPPH0					// [4]		set copper bar 0 phase
			sta BRS_runtime_memory.COPOLD0					// [4]		set copper bar 0 first line
			sta BRS_runtime_memory.COPOLD1					// [4]		set copper bar 1 first line
			sta BRS_runtime_memory.COPOLD2					// [4]		set copper bar 2 first line
			lda #85											// [2]		get a third of a wave
			sta BRS_runtime_memory.COPPH1					// [4]		set copper bar 1 phase
			lda #170										// [2]		get two thirds of a wave
			sta BRS_runtime_memory.COPPH2					// [4]		set copper bar 2 phase

			// clear the copper bar line buffer to the screen colour
			lda #BRS_runtime_constants.SCREEN_BASE			// [2]		get the screen colour
			ldx #0											// [2]		set line
clearloop:	sta BRS_runtime_memory.COPBUF,x					// [5]		clear a line
			inx												// [2]		increment line
			bne clearloop									// [3/2]	loop until done
			rts												// [6]
}


// Finish the frame: change the effect every 256 frames and move the waves on
advance_frame:
.pc = * "advance_frame"
{
	.if (!StillFrame)
	{
			inc BRS_runtime_memory.FRAMECNT					// [6]		increment frame counter
			bne waves										// [3/2]	change the effect every 256 frames
			inc BRS_runtime_memory.EFFECT					// [6]		next raster effect
			lda BRS_runtime_memory.EFFECT					// [4]
			cmp #BRS_runtime_constants.EFFECT_COUNT			// [2]		check for the last effect
			bcc waves										// [3/2]	keep it if there is another
			lda #0											// [2]		go back to the first effect
			sta BRS_runtime_memory.EFFECT					// [4]

waves:		lda BRS_runtime_memory.RIBBONPH					// [3]		get the sine ribbon phase
			clc												// [2]
			adc #1											// [2]		move the wave on a line
			and #63											// [2]		keep it in the wave's 64 lines
			sta BRS_runtime_memory.RIBBONPH					// [4]		set the sine ribbon phase
			lda BRS_runtime_memory.FLAGPH					// [4]		get the waving flag phase
			clc												// [2]
			adc #1											// [2]		move the wave on a line
			and #127										// [2]		keep it in the wave's 128 lines
			sta BRS_runtime_memory.FLAGPH					// [4]		set the waving flag phase
	}

			rts												// [6]		return to hold_sync
}



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
			ldx BRS_runtime_memory.COPPH0,y					// [4]		get the bar's phase
			lda BRS_static_data.SINEPOS,x					// [4]		get the bar's first entry
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
