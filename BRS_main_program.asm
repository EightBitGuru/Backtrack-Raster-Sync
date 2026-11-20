// BackTrak Raster Sync demo main program
// Copyright (C) 2026 8BitGuru <the8bitguru@gmail.com>

.filenamespace BRS_main_program

.encoding "petscii_upper"

// Draw the screen, set up the raster effects and start the raster sync, which the BASIC stub runs
initialise_screen:
.pc = * "initialise_screen"
{
			lda #BRS_runtime_constants.SCREEN_BASE			// [2]		get the screen colour
			sta vic20.vic.VCSCRNCO							// [4]		set screen and border colour
			lda #1											// [2]		get any non-zero value
			sta vic20.os_zpvars.CRSRMODE					// [3]		turn the cursor flash off
			lda #$FF										// [2]		get a value that is not an effect
			sta BRS_runtime_memory.SHOWN					// [4]		have main_loop show the effect name

			// print the title
			ldx #0											// [2]		set title index
titleloop:	lda TITLE,x										// [4]		get title character
			beq titledone									// [2/3]	done at the end of the title
			jsr vic20.kernal.CHROUT							// [6]		print it
			inx												// [2]		increment title index
			bne titleloop									// [3/2]	loop until done

titledone:	jsr BRS_raster_effects.initialise_effects		// [6]		set up the raster effects
			jmp BRS_raster_sync.initialise_sync				// [3]		start the sync, which never returns
}


// Run the program: put the name of the raster effect on the screen when it changes, which the first locked IRQ starts and every IRQ interrupts
// Takes whatever time the raster effects leave in each frame, and cannot tell that it is interrupted
main_loop:
.pc = * "main_loop"
{
waitloop:	lda BRS_runtime_memory.EFFECT					// [4]		get raster effect
			cmp BRS_runtime_memory.SHOWN					// [4]		check for the effect on the screen
			beq waitloop									// [3/2]	loop until it changes
			sta BRS_runtime_memory.SHOWN					// [4]		set the effect on the screen

			// put the cursor after the title's effect label and print the name
			ldx #4											// [2]		set row
			ldy #8											// [2]		set column
			clc												// [2]		set Carry to set the cursor position rather than get it
			jsr vic20.kernal.PLOT							// [6]		move the cursor
			ldy BRS_runtime_memory.EFFECT					// [4]		get raster effect
			lda NAMEOFF,y									// [4]		get the offset of its name
			sta BRS_runtime_memory.NAMEIDX					// [3]		set name index
nameloop:	ldx BRS_runtime_memory.NAMEIDX					// [3]		get name index
			lda NAMES,x										// [4]		get name character
			beq waitloop									// [3/2]	go back to waiting at the end of the name
			jsr vic20.kernal.CHROUT							// [6]		print it
			inc BRS_runtime_memory.NAMEIDX					// [5]		increment name index
			bne nameloop									// [3/2]	loop until done
}


TITLE:					// The title that initialise_screen prints: clear the screen and white text
.pc = * "TITLE"		// Zero-terminated PETSCII (91 bytes)
.byte vic20.screencodes.CLRSCRN, vic20.screencodes.WHITE
.text "BACKTRAK RASTER SYNC"
.byte vic20.screencodes.CR, vic20.screencodes.CR
.text "CYCLE-EXACT EFFECTS"
.byte vic20.screencodes.CR, vic20.screencodes.CR
.text "EFFECT:"
.byte vic20.screencodes.CR
.fill 17, vic20.screencodes.CRSRDOWN		// Down to the last row of the screen
.text " (C) 2026 8-BIT GURU"
.byte 0

NAMES:					// The names of the raster effects that main_loop prints
.pc = * "NAMES"		// Zero-terminated PETSCII, 12 bytes each (36 bytes)
.text "COPPER BARS"
.byte 0
.text "SINE RIBBON"
.byte 0
.text "WAVING FLAG"
.byte 0

NAMEOFF:				// The offset of each raster effect's name in NAMES
.pc = * "NAMEOFF"		// 12 bytes for each effect (3 bytes)
.byte 0, 12, 24
