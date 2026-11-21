// BackTrak Raster Sync demo main program
// Copyright (C) 2026 8BitGuru <the8bitguru@gmail.com>

.filenamespace BRS_main_program

.encoding "petscii_upper"

// Draw the screen, set up the raster effects and start the raster sync, which the loader runs once it has moved the program to where it was built to run
initialise_screen:
.pc = * "initialise_screen"
{
			// put the screen where the program expects it: an unexpanded VIC-20 and one with 3K have it at $1E00, and one with 8K or more has it at $1000, where the program runs
			lda #BRS_runtime_constants.SCREEN_PAGE			// [2]		get the page of the screen
			sta vic20.os_vars.SCRNMEMP						// [4]		tell the KERNAL's screen editor
			lda vic20.vic.VCCOLS							// [4]		get the screen address b9 and the number of columns
			ora #%10000000									// [2]		set screen address b9, which also puts the colour RAM at $9600
			sta vic20.vic.VCCOLS							// [4]		set it for the VIC
			lda vic20.vic.VCSCRNAD							// [4]		get the screen address b15+b12-10 and the character generator address
			ora #%11110000									// [2]		set the screen address for $1E00
			sta vic20.vic.VCSCRNAD							// [4]		set it for the VIC
			lda #vic20.screencodes.CRSRHOME					// [2]		get the cursor home character
			jsr vic20.kernal.CHROUT							// [6]		print it, which has the KERNAL work out where the screen and its colour RAM are from its new page

			// set the colours, and the cursor and the effect name that the main program shows
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
.pc = * "NAMES"		// Zero-terminated PETSCII, every one padded to the 12 characters of the longest, so that it covers the name before it (52 bytes)
.text "COPPER BARS "
.byte 0
.text "SINE RIBBON "
.byte 0
.text "WAVING FLAG "
.byte 0
.text "SPLIT SCREEN"
.byte 0

NAMEOFF:				// The offset of each raster effect's name in NAMES
.pc = * "NAMEOFF"		// 13 bytes for each effect (4 bytes)
.byte 0, 13, 26, 39
