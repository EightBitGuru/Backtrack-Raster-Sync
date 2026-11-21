// BackTrak Raster Sync demo main loop
// Copyright (C) 2026 8BitGuru <the8bitguru@gmail.com>

.filenamespace BRS_main_program

// This is part of the demo main program (BRS_main_program.asm) but is imported by BRS_raster_effects.asm, to fill the space that copper_ntsc leaves

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
