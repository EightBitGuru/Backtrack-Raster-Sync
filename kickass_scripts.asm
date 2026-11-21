// KickAssembler scripts
// Copyright (C) 2026 8BitGuru <the8bitguru@gmail.com>

// BASIC stub macro
// A BASIC line that runs code at the same place in the program wherever BASIC loads it: SYS PEEK(43)+256*PEEK(44)+offset, where PEEK(43) and PEEK(44)
// are the start of BASIC ($1001 on an unexpanded VIC-20, $0401 with 3K of expansion and $1201 with 8K or more) and the offset is that of the code from base
// base is the address the file is built to load at, which is the start of BASIC on an unexpanded VIC-20
// offset is a number, not a label, so that the size of the stub is known in the first pass
.macro BasicStub(base,offset)
{
        * = base "stub"
        .word end                           // Line link pointer
        .word 0                             // Line number
        .byte $9e                           // SYS
        .byte $c2                           // PEEK
        .text "(43)"                        // Start of BASIC lo-byte
        .byte $aa                           // +
        .text "256"
        .byte $ac                           // *
        .byte $c2                           // PEEK
        .text "(44)"                        // Start of BASIC hi-byte
        .byte $aa                           // +
        .text toIntString(offset,3)         // Offset of the code (as digits)
        .byte $3a,$8f                       // :REM
        .fill 34,vic20.screencodes.DELETE   // Message to hide BASIC line when LISTed (the 34 characters that LIST prints for it)
        .byte vic20.screencodes.RVSON
        .fill 22,vic20.screencodes.SPACE
        .text " BACKTRAK RASTER SYNC "
        .text " (C) 2026  8-BIT GURU "
        .fill 22,vic20.screencodes.SPACE
        .byte 0                             // End-of-Line marker
end:    .word 0                             // End-of-Program marker
        .pc = * "stub_end"
}


// Burn an exact number of cycles (0, or 2 and up) without touching a register: NOPs, and one BIT zero-page for an odd count
// Bytes: cycles / 2 (rounded down for an odd count, which uses BIT for 3 cycles). Flags: N, V and Z change if BIT is used
.macro Pad(cycles)
{
	.errorif (cycles < 0) || (cycles == 1), "Pad cannot burn " + cycles + " cycles"
	.if (mod(cycles, 2) == 1)
	{
		bit $00															// [3]		read zero-page (no side effects)
	}
	.fill floor((cycles - 3 * mod(cycles, 2)) / 2), $EA					// [2]		NOP
}


// Burn an exact number of cycles (6 and up) with a DEY/BNE loop and Pad
// Bytes: 5 + the Pad. Changes .Y and the flags. The loop must not cross a page, or each taken branch costs an extra cycle
.macro Delay(cycles)
{
	.var count = floor((cycles - 1) / 5)
	.var rest = cycles - (5 * count + 1)
	.if (rest == 1)
	{
		.eval count = count - 1
		.eval rest = rest + 5
	}
	.errorif (count < 1) || (count > 256), "Delay cannot burn " + cycles + " cycles"
			ldy #(count & $FF)											// [2]		set loop count
!loop:		dey															// [2]		decrement loop count
			bne !loop-													// [3/2]	loop until done
	.errorif (>!loop-) != (>(*-1)), "Delay loop crosses a page: its branches would cost an extra cycle"
	Pad(rest)
}


// Burn an exact number of cycles (0, or 2 and up), choosing Pad or Delay, and Delay again as often as it takes for a long wait
// Changes .Y and the flags if the count is 6 or more
.macro Wait(cycles)
{
	.var rest = cycles
	.while (rest > 1200)
	{
		Delay(1000)
		.eval rest = rest - 1000
	}
	.if (rest >= 6)
	{
		Delay(rest)
	}
	else
	{
		Pad(rest)
	}
}


// Burn the number of cycles in .A (0 to 2^bits - 1) plus 4 + 5 * (bits - 1), one bit at a time: each bit takes a branch that costs 1, 2, 4 ...
// cycles more when it is set. The jitter slide in service_irq is this with 3 bits, written out. Destroys .A and the flags
.macro Slide(bits)
{
			lsr															// [2]		move bit 0 to Carry
			bcs !next+													// [2/3]	take one more cycle if the bit is set
!next:
	.for (var bit = 1; bit < bits; bit++)
	{
			lsr															// [2]		move the bit to Carry
			bcc !skip+													// [3/2]	skip the extra cycles if the bit is clear
			Pad((1 << bit) + 1)											// [2^bit + 1]	take 2^bit more cycles than the branch skipped
!skip:
	}
}


// A $900F value for a colour: background b7-4 = the colour, b3 = normal (not reverse), border b2-0 = the colour (so the border of a light
// colour is the dark colour it is the light version of)
.function pair(colour)
{
	.return (colour << 4) | 8 | (colour & 7)
}


// Generate bit7-terminated strings from list
.macro TerminatedStringBlock(list)
{
	.for(var i=0; i<list.size(); i++)
	{
		.var item = list.get(i)
		.var first = item.substring(0, item.size()-1)
		.var last = item.charAt(item.size()-1)
		.text first
		.byte last.number()+$80
	}
}


// Generate address offsets to bit7-terminated strings from list
.macro TerminatedStringOffsets(list,address)
{
	.var itemAddress = address
	.for(var i=0; i<list.size(); i++)
	{
		.byte itemAddress
		.eval itemAddress = itemAddress + list.get(i).size()
	}
}

// Custom OpCode pseudocommands
.pseudocommand hlt													// Halt (JAM/KIL)
{
			.byte $02												// [0]		Kill CPU by breaking internal T-state register
}

.pseudocommand dop operand											// Double-byte NOP (SKB)
{
			.if (operand.getType()==AT_IMMEDIATE)
				.byte $80											// [2]		Skip byte
			.if (operand.getType()==AT_ABSOLUTE)
				.byte $03											// [3]		Skip byte
			.if (operand.getType()==AT_IZEROPAGEX)
				.byte $14											// [4]		Skip byte
}

.pseudocommand isb operand											// Increment and Subtract (INS)
{
			.if (operand.getType()==AT_ABSOLUTE)
				.byte $E7											// [5]		INCremment memory and SBC	ZP
			.if (operand.getType()==AT_IZEROPAGEY)
				.byte $F3											// [8]		INCremment memory and SBC	(ZP),y
			.byte operand.getValue()
}

.pseudocommand zax													// Zero .A and .X
{
			.word $00AB												// [2]		LAX Immediate #$00 (Load .A and .X with zero, unstable with non-zero operands)
}

/*.pseudocommand aac												// AND A and set Carry (ANC)
{
			.byte $0B												// [2]
}
*/

/*.pseudocommand aso												// ASL and OR with .A (SLO)
{
			.byte $07												// [5]
			.byte $17												// [6]
			.byte $0F												// [6]
			.byte $1F												// [7]
			.byte $1B												// [7]
			.byte $03												// [8]
			.byte $13												// [8]
}
*/

/*.pseudocommand axs												// Subtract from .A AND .X (SBX)
{
			.byte $CB												// [2]
}
*/

/*.pseudocommand dcm												// Decrement and CMP .A (DCP)
{
			.byte $C7												// [5]
			.byte $D7												// [6]
			.byte $CF												// [6]
			.byte $DF												// [7]
			.byte $DB												// [7]
			.byte $C3												// [8]
			.byte $D3												// [8]
}
*/

/*.pseudocommand lse												// LSR and OR .A (SRE)
{
			.byte $07												// [5]
			.byte $17												// [6]
			.byte $0F												// [6]
			.byte $1F												// [7]
			.byte $1B												// [7]
			.byte $03												// [8]
			.byte $13												// [8]
}
*/

/*.pseudocommand oal												// OR .A and AND (LXA)
{
			.byte $AB												// [2]
}
*/

/*.pseudocommand xaa												// TXA and AND .A (ANE)
{
			.byte $8B												// [2]
}
*/

/*.pseudocommand xas												// Transfer .A AND .X to .SP (SHS)
{
			.byte $9B												// [2]
}
*/
