// KickAssembler scripts
// Copyright (C) 2026 8BitGuru <the8bitguru@gmail.com>

// BASIC stub macro
.macro BasicStub(base,code)
{
        * = base "stub"
        .word end                           // Line link pointer
        .word 0                             // Line number
        .byte $9e                           // SYS
        .text toIntString(code,4)           // SYS address (as digits)
        .byte $3a,$8f                       // :REM
        .fill 13,vic20.screencodes.DELETE   // Message to hide BASIC line when LISTed
        .byte vic20.screencodes.RVSON                   
        .fill 22,vic20.screencodes.SPACE
        .text " BACKTRAK RASTER SYNC "
        .text " (C) 2026  8-BIT GURU "
        .fill 22,vic20.screencodes.SPACE
        .byte 0                             // End-of-Line marker
end:    .word 0                             // End-of-Program marker
        * = base+116 "stub_end"
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
