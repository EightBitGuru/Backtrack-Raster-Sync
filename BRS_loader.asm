// BackTrak Raster Sync loader
// Copyright (C) 2026 8BitGuru <the8bitguru@gmail.com>

.filenamespace BRS_loader

// The loader moves the program to the addresses it was built for, whatever the memory configuration loaded it at, and starts it
// BASIC loads the file at the start of BASIC, which depends on the memory fitted: $1001 on an unexpanded VIC-20, $0401 with 3K of expansion and $1201 with 8K or more
// (the build is for $1001). The BASIC line works out where the loader is from the start of BASIC (SYS PEEK(43)+256*PEEK(44)+offset), and BASIC leaves that address in
// INTVAL, so the loader knows where it and the program are. Every instruction here is position independent: nothing jumps or reads an address in the file until the program has been moved
// The program is everything after the BASIC line (the data label) up to code_end, which includes the loader

// Move the program to where it was built to run, and run it
// Does not return: it ends by jumping to the start of the program
move_program:
.pc = * "move_program"
{
			// stop the cursor and the KERNAL's IRQ, which write to the screen (the program is about to be moved over the screen on a machine with 8K or more)
			lda #1											// [2]		get any non-zero value
			sta vic20.os_zpvars.CRSRMODE					// [3]		turn the cursor flash off
			lda #vic20.screencodes.CRSRHOME					// [2]		get the cursor home character
			jsr vic20.kernal.CHROUT							// [6]		print it, which puts back the character under the cursor if it is showing
			sei												// [2]		stop the KERNAL's IRQ

			// find out where this code is: BASIC's SYS leaves the address it ran in INTVAL (a JSR would not do, because it holds the address the file was built for)
			lda vic20.os_zpvars.INTVAL						// [3]		get where this code is, lo-byte
			sta BRS_runtime_memory.MOVEDSTL					// [3]		stash it
			lda vic20.os_zpvars.INTVAL + 1					// [3]		get where this code is, hi-byte
			sta BRS_runtime_memory.MOVEDSTH					// [3]		stash it

			// copy the copier to the cassette buffer, which no configuration of memory has the program or its screen on
			clc												// [2]
			lda BRS_runtime_memory.MOVEDSTL					// [3]		get where this code is
			adc #<(copier_image - move_program)				// [2]		add the offset of the copier
			sta BRS_runtime_memory.MOVESRCL					// [3]		set the address of the copier lo-byte
			lda BRS_runtime_memory.MOVEDSTH					// [3]
			adc #>(copier_image - move_program)				// [2]
			sta BRS_runtime_memory.MOVESRCH					// [3]		set the address of the copier hi-byte
			ldy #copier_end - copier_image - 1				// [2]		set the last byte of the copier
copyloop:	lda (BRS_runtime_memory.MOVESRCL),y				// [5]		get a byte of the copier
			sta vic20.os_vars.CASSBUFF,y					// [5]		set it in the cassette buffer
			dey												// [2]		next byte
			bpl copyloop									// [3/2]	loop until done

			// point at the program as it was loaded, and run the copier
			clc												// [2]
			lda BRS_runtime_memory.MOVEDSTL					// [3]		get where this code is
			adc #<((data - move_program) & $FFFF)			// [2]		add the offset of the program (which is before this code, so it wraps)
			sta BRS_runtime_memory.MOVESRCL					// [3]		set the address of the program lo-byte
			lda BRS_runtime_memory.MOVEDSTH					// [3]
			adc #>((data - move_program) & $FFFF)			// [2]
			sta BRS_runtime_memory.MOVESRCH					// [3]		set the address of the program hi-byte
			jmp vic20.os_vars.CASSBUFF						// [3]		run the copier
}


// The copier, which runs in the cassette buffer: move the program from where it was loaded (MOVESRCL/H) to where it was built, and run it
// The move is forwards if the program was loaded above where it was built (the 8K and larger expansions, and the unexpanded VIC-20, where it was loaded at the
// address it was built for), and backwards if it was loaded below that (the 3K expansion), so that the move never overwrites what it has still to read
// Position independent: it uses zero page, immediate values and relative branches
copier_image:
.pc = * "copier_image"
{
			// set where it goes
			lda #<data										// [2]		get where the program was built to run
			sta BRS_runtime_memory.MOVEDSTL					// [3]		set the address to copy to lo-byte
			lda #>data										// [2]
			sta BRS_runtime_memory.MOVEDSTH					// [3]		set the address to copy to hi-byte

			// compare the addresses: Carry is clear if the program was loaded below where it goes
			lda BRS_runtime_memory.MOVESRCH					// [3]		get the hi-byte of where it is
			cmp BRS_runtime_memory.MOVEDSTH					// [3]		compare it with the hi-byte of where it goes
			bne compared									// [3/2]	done if they differ
			lda BRS_runtime_memory.MOVESRCL					// [3]		get the lo-byte of where it is
			cmp BRS_runtime_memory.MOVEDSTL					// [3]		compare it with the lo-byte of where it goes
compared:	bcc backwards									// [2/3]	move backwards if the program is below where it goes

			// move forwards: whole pages, and then the bytes that are left
			ldx #>(code_end - data)							// [2]		get the whole pages to move
			ldy #0											// [2]
fwdloop:	lda (BRS_runtime_memory.MOVESRCL),y				// [5]		get a byte
			sta (BRS_runtime_memory.MOVEDSTL),y				// [6]		set it
			iny												// [2]		next byte
			bne fwdloop										// [3/2]	loop until the page is done
			inc BRS_runtime_memory.MOVESRCH					// [5]		next page to read
			inc BRS_runtime_memory.MOVEDSTH					// [5]		next page to write
			dex												// [2]		next page
			bne fwdloop										// [3/2]	loop until the pages are done
fwdrest:	cpy #<(code_end - data)							// [2]		check for the last byte
			beq done										// [2/3]	start the program if there are no more
			lda (BRS_runtime_memory.MOVESRCL),y				// [5]		get a byte
			sta (BRS_runtime_memory.MOVEDSTL),y				// [6]		set it
			iny												// [2]		next byte
			bne fwdrest										// [3/3]	loop until done, which is always taken because the count of bytes is below 256

			// move backwards: put both addresses at the page of the bytes that are left, move those, and then the whole pages from the last
backwards:	lda BRS_runtime_memory.MOVESRCH					// [3]		get the hi-byte of where the program is
			clc												// [2]
			adc #>(code_end - data)							// [2]		add the whole pages
			sta BRS_runtime_memory.MOVESRCH					// [3]		set the page of the bytes that are left
			lda BRS_runtime_memory.MOVEDSTH					// [3]		get the hi-byte of where it goes
			clc												// [2]
			adc #>(code_end - data)							// [2]		add the whole pages
			sta BRS_runtime_memory.MOVEDSTH					// [3]		set the page of the bytes that are left
			ldx #>(code_end - data)							// [2]		get the whole pages to move
			ldy #<(code_end - data)							// [2]		get the bytes that are left
			beq bwdpage										// [2/3]	go to the pages if there are none
bwdrest:	dey												// [2]		previous byte
			lda (BRS_runtime_memory.MOVESRCL),y				// [5]		get a byte
			sta (BRS_runtime_memory.MOVEDSTL),y				// [6]		set it
			cpy #0											// [2]		check for the first byte
			bne bwdrest										// [3/2]	loop until done
bwdpage:	dec BRS_runtime_memory.MOVESRCH					// [5]		previous page to read
			dec BRS_runtime_memory.MOVEDSTH					// [5]		previous page to write
bwdloop:	dey												// [2]		previous byte (.Y wraps to $FF for the first)
			lda (BRS_runtime_memory.MOVESRCL),y				// [5]		get a byte
			sta (BRS_runtime_memory.MOVEDSTL),y				// [6]		set it
			cpy #0											// [2]		check for the first byte
			bne bwdloop										// [3/2]	loop until the page is done
			dex												// [2]		next page
			bne bwdpage										// [3/2]	loop until the pages are done

done:		jmp BRS_main_program.initialise_screen			// [3]		start the program, which never returns
}
copier_end:
