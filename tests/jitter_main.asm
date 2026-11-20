// BackTrak Raster Sync jitter test main programs
// Copyright (C) 2026 8BitGuru <the8bitguru@gmail.com>

// Four main programs that the sync's IRQ can interrupt at any instruction, for brs_jitter.py to patch into main_loop. The IRQ handler
// takes the same number of cycles every time, and the CPU resumes at an instruction boundary, so the IRQ lands at the same place in a
// loop that is the same every pass: 'mixed', 'sevens' and 'twos' test the worst instruction lengths at a few fixed phases, and 'random'
// runs a different mix of 2 to 7 cycle instructions every pass (chosen by a 255-step LFSR) so that the IRQ lands at every phase.
// They write only to $0200-$02FF and zero-page $08-$09 (the sync owns $03-$06 and $FB-$FE).

.pc = $1400 "mixed"			// Instructions of 7, 6, 5, 4, 3, 2 and 7 cycles then the JMP: 37 cycles
mixed:
			ldx #0
mixedloop:	inc $0200,x											// [7]
			inc $0200											// [6]
			inc $08												// [5]
			lda $0200											// [4]
			lda $08												// [3]
			nop													// [2]
			inc $0200,x											// [7]
			jmp mixedloop										// [3]

.pc = $1500 "sevens"		// Ten 7-cycle instructions then the JMP: 73 cycles, so the IRQ lands on the last cycle of one then runs the next
sevens:
			ldx #0
sevensloop:	.for (var i = 0; i < 10; i++)
			{
				inc $0200,x										// [7]
			}
			jmp sevensloop										// [3]

.pc = $1600 "twos"			// 35 NOPs then the JMP: 73 cycles, which is what the spin loop's NOPs give
twos:
twosloop:	.fill 35, $EA										// [2]
			jmp twosloop										// [3]

.pc = $1700 "random"		// A different length every pass: 8 stages, each runs one instruction if its bit of the LFSR is set
random:
			ldx #0
			lda #$A5
			sta $08												// LFSR seed
randomloop:	lda $08												// [3]
			asl													// [2]		Galois LFSR, polynomial $1D
			bcc nofeed											// [3/2]
			eor #$1D											// [2]
nofeed:		sta $08												// [3]
			.for (var b = 0; b < 8; b++)
			{
				lda $08											// [3]
				and #(1 << b)									// [2]
				beq !skip+										// [3/2]
				.if (b == 0) { inc $0200,x }					// [7]
				.if (b == 1) { inc $0200 }						// [6]
				.if (b == 2) { inc $09 }						// [5]
				.if (b == 3) { lda $0200 }						// [4]
				.if (b == 4) { lda $09 }						// [3]
				.if (b == 5) { nop }							// [2]
				.if (b == 6) { inc $0200,x }					// [7]
				.if (b == 7) { inc $0200,x }					// [7]
!skip:
			}
			jmp randomloop										// [3]
