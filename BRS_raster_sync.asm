// BackTrak Raster Sync
// Copyright (C) 2026 8BitGuru <the8bitguru@gmail.com>

.filenamespace BRS_raster_sync

// Command line :slide=0 builds without the jitter slide, which the tests use as a control
.var EnableSlide = !cmdLineVars.containsKey("slide") || cmdLineVars.get("slide").asNumber() != 0      // Cancel the delay in taking the IRQ


// Start the raster sync and hand over to the spin loop
initialise_sync:
.pc = * "initialise_sync"
{
			sei												// [2]		disable IRQ
			cld												// [2]		clear Decimal flag so that the arithmetic is binary

			// set the sync IRQ handler (the KERNAL IRQ stub at $FF72 jumps through this vector)
			lda #<service_irq								// [2]		get IRQ handler address lo-byte
			sta vic20.os_vars.IRQVECL						// [4]		set IRQ vector lo-byte
			lda #>service_irq								// [2]		get IRQ handler address hi-byte
			sta vic20.os_vars.IRQVECH						// [4]		set IRQ vector hi-byte

			// check for PAL or NTSC
			lda #1											// [2]		raster compare value (line 2/3, the register counts in twos)
wait2:		cmp vic20.vic.VCRASTER							// [4]		check for raster line
			bne wait2										// [3/2]	loop until we hit it
wait268:	lda vic20.vic.VCRASTER							// [4]		get current raster line
			beq ntsc										// [2/3]	video mode is NTSC if we find line 0 before line 268
			cmp #134										// [2]		look for line 268 for PAL
			bne wait268										// [3/2]	loop until we find 0 or 268
			ldy #0											// [2]		set PAL row offset in the sync values
			beq copy										// [3/3]	.Y = 0 so always taken, skipping the NTSC row offset
ntsc:		ldy #BRS_runtime_constants.ROW_SIZE				// [2]		set NTSC row offset in the sync values

			// copy the sync values for the video standard to zero-page
copy:		ldx #0											// [2]		set zero-page index
copyloop:	lda BRS_static_data.SYNCVALS,y					// [4]		get line delay count, line adjustment and arm cut
			sta BRS_runtime_memory.LINEDLY,x				// [4]		stash in zero-page
			iny												// [2]		increment sync values index
			inx												// [2]		increment zero-page index
			cpx #3											// [2]		check for the three values
			bne copyloop									// [3/2]	loop until done
			lda BRS_static_data.SYNCVALS,y					// [4]		get spin loop outer count
			sta BRS_runtime_memory.OUTERCNT					// [3]		stash in zero-page
			iny												// [2]		increment sync values index
			lda BRS_static_data.SYNCVALS,y					// [4]		get spin loop inner count
			sta BRS_runtime_memory.INNERCNT					// [3]		stash in zero-page
			iny												// [2]		increment sync values index, which now points at the rest of the row

			// initialise the sync state and the VIA
			lda #0											// [2]
			sta BRS_runtime_memory.SYNCSTAT					// [3]		set tracking state
			lda #%01000000									// [2]		b7-6 = %01 T1 free-running without PB7 output, b5 = T2 timed, b4-2 = shift register off, b1-0 = no input latching
			sta vic20.via2.V2ACR							// [4]		set VIA2 auxiliary control
			lda #%11000000									// [2]		b7 = set bits, b6 = T1 interrupt
			sta vic20.via2.V2IER							// [4]		enable VIA2 T1 interrupt

			// sync to the start of raster line 0/1, where $9004 first reads zero
			ldx #0											// [2]		set raster line 0/1
wait0:		cpx vic20.vic.VCRASTER							// [4]		check for raster line
			bne wait0										// [3/2]	loop until we hit it

			// start the timer with a first period shortened by the cut, so that the first IRQ reads $9004 just inside its zero window and backtracking starts at the edge
			sec												// [2]
			lda BRS_static_data.SYNCVALS+2,y				// [4]		get the backtrack timer latch lo-byte
			sbc BRS_static_data.SYNCVALS,y					// [4]		subtract the first period cut
			sta vic20.via2.V2T1LL							// [4]		set VIA2 timer #1 lo-latch
			lda BRS_static_data.SYNCVALS+3,y				// [4]		get the backtrack timer latch hi-byte
			sbc #0											// [2]		subtract the borrow
			sta vic20.via2.V2T1CH							// [4]		set VIA2 timer #1 hi-counter, loading the counter from the latches and starting it

			// restore the backtrack latch for every period after the first (the hi-latch write does not touch the counter)
			lda BRS_static_data.SYNCVALS+2,y				// [4]		get the backtrack timer latch lo-byte
			sta vic20.via2.V2T1LL							// [4]		set VIA2 timer #1 lo-latch
			lda BRS_static_data.SYNCVALS+3,y				// [4]		get the backtrack timer latch hi-byte
			sta vic20.via2.V2T1LH							// [4]		set VIA2 timer #1 hi-latch

			// wait so that the first IRQ lands in the middle of the NOPs in the spin loop, then spin (never returns)
			ldx BRS_static_data.SYNCVALS+1,y				// [4]		get the delay loop count
			cli												// [2]		enable sync IRQ
startloop:	dex												// [2]		decrement delay count
			bne startloop									// [3/2]	loop until done
			jmp wait_for_irq								// [3]		start spinning

			.errorif (>startloop) != (>(*-1)), "The start delay loop crosses a page: its branch would cost an extra cycle"
}


// Start the spin loop on the next page if it would otherwise cross one, because its branches must not cost an extra cycle
.if ((* & $FF) > 256 - BRS_runtime_constants.SPIN_BYTES)
{
	.align 256
}


// Spin until the IRQ fires, always in the NOPs at the end of the loop
// => OUTERCNT Spin loop outer count
// => INNERCNT Spin loop inner count
wait_for_irq:
.pc = * "wait_for_irq"
{
			ldx BRS_runtime_memory.OUTERCNT					// [3]		get outer count
outerloop:	ldy BRS_runtime_memory.INNERCNT					// [3]		get inner count
innerloop:	dey												// [2]		decrement inner count
			bne innerloop									// [3/2]	loop until the inner count is done
			nop												// [2]		outer loop payload (BRS_runtime_constants.SPIN_PAYLOAD cycles)
			dex												// [2]		decrement outer count
			bne outerloop									// [3/2]	loop until the outer count is done

			// every IRQ lands in these NOPs, so the CPU always completes a two-cycle instruction
			.fill BRS_runtime_constants.SPIN_NOPS, $EA		// [2]		NOP (BRS_runtime_constants.SPIN_NOPS times)
			jmp wait_for_irq								// [3]		start another pass, which takes the timer period less the tracking IRQ

			.errorif BRS_runtime_constants.SPIN_PAYLOAD != 2, "The outer loop payload is a NOP: change it or SPIN_PAYLOAD"
			.errorif (*-wait_for_irq) != BRS_runtime_constants.SPIN_BYTES, "wait_for_irq is not SPIN_BYTES long: change SPIN_BYTES"
			.errorif (>wait_for_irq) != (>(*-1)), "wait_for_irq crosses a page: its branches would cost an extra cycle"
}


// Run the main program, which the arm state starts and every later IRQ interrupts
main_loop:
.pc = * "main_loop"
{
			jmp main_loop									// [3]		idle until a main program replaces this
}


// Acknowledge the IRQ, cancel the delay in taking it, then run the sync state routine
// => SYNCSTAT Sync state
service_irq:
.pc = * "service_irq"
{
			// the KERNAL IRQ stub at $FF72 has pushed .A, .X and .Y and jumped through $0314, IRQ_ENTRY cycles after the VIA IRQ plus the 1 to 8 cycles the interrupted instruction took to finish
			lda vic20.via2.V2T1CL							// [4]		acknowledge IRQ and read how far the timer has counted since it reloaded
			cld												// [2]		clear Decimal flag so that the arithmetic is binary whatever the interrupted code did
			sec												// [2]		set Carry for the subtraction
			sbc vic20.via2.V2T1LL							// [4]		subtract the latch lo-byte (reading it has no side effects), leaving minus the elapsed cycles with Carry clear
			.if (EnableSlide) adc #BRS_runtime_constants.CORRECT_X	// [2]	add the elapsed cycles of the latest IRQ response, leaving the slide of 0 to 7 cycles
			.if (!EnableSlide) and #0						// [2]		build without the slide: nothing is taken up (the control for the tests)

			// slide for the number of cycles in A, bit by bit: each bit takes a branch that costs 1, 2 or 4 cycles more when it is set
slide1:		lsr												// [2]		move slide bit 0 to Carry
			bcs slide2										// [2/3]	take one more cycle if the bit is set

slide2:		lsr												// [2]		move slide bit 1 to Carry
			bcc slide4										// [3/2]	skip the 2 cycles if the bit is clear
			bit $00											// [3]		take 2 more cycles than the branch skipped (2 + 3 against 3)

slide4:		lsr												// [2]		move slide bit 2 to Carry
			bcc stable										// [3/2]	skip the 4 cycles if the bit is clear
			nop												// [2]
			bit $00											// [3]		take 4 more cycles than the branch skipped (2 + 5 against 3)

			// the stable point: from here every IRQ is the same number of cycles after the timer underflow
stable:		ldx BRS_runtime_memory.SYNCSTAT					// [3]		get sync state
			lda BRS_static_data.STATEJMP.hi,x				// [4]		get state routine address hi-byte (minus one)
			pha												// [3]		push hi-byte
			lda BRS_static_data.STATEJMP.lo,x				// [4]		get state routine address lo-byte (minus one)
			pha												// [3]		push lo-byte
			rts												// [6]		dispatch to the state routine

			.errorif (>service_irq) != (>(*-1)), "service_irq crosses a page: its branches would cost an extra cycle"
}


// Look for the raster moving off line 0/1, one cycle further back each frame
track_sync:
.pc = * "track_sync"
{
			// both paths take TRACK_BODY cycles
			lda vic20.vic.VCRASTER							// [4]		get raster line (b8-1)
			beq tracking									// [3/2]	keep tracking while still on line 0/1

			// the raster has moved on: the next IRQ arms the lock
			inc BRS_runtime_memory.SYNCSTAT					// [5]		set arming state
			Pad(BRS_runtime_constants.TRACK_BODY - 14)		// [8]		make the cycle count the same as the other path
			jmp exit_irq									// [3]

tracking:
			Pad(BRS_runtime_constants.TRACK_BODY - 10)		// [12]		make the cycle count the same as the other path
			jmp exit_irq									// [3]

			.errorif (>track_sync) != (>(*-1)), "track_sync crosses a page: its branch would cost an extra cycle"
}


// Restart the timer with a shortened first period so that the stable point of every IRQ from here is at raster line 0, cycle 0
// => ARMCUT Cycles to shorten the first period by (PAL or NTSC)
arm_sync:
.pc = * "arm_sync"
{
			// the raster is a known number of cycles late, so restart the timer with a first period that many cycles short, from the backtrack latch the timer has been using
			ldx vic20.via2.V2T1LL							// [4]		get the backtrack timer latch lo-byte
			ldy vic20.via2.V2T1LH							// [4]		get the backtrack timer latch hi-byte
			txa												// [2]
			sec												// [2]
			sbc BRS_runtime_memory.ARMCUT					// [3]		subtract the arm cut
			sta vic20.via2.V2T1LL							// [4]		set VIA2 timer #1 lo-latch
			tya												// [2]
			sbc #0											// [2]		subtract the borrow
			sta vic20.via2.V2T1CH							// [4]		set VIA2 timer #1 hi-counter, restarting the timer on the shortened first period

			// the locked latch, one more than the backtrack latch, is for every period after the first (the hi-latch write does not touch the counter)
			txa												// [2]
			clc												// [2]
			adc #1											// [2]		add one to the lo-byte
			sta vic20.via2.V2T1LL							// [4]		set VIA2 timer #1 lo-latch
			tya												// [2]
			adc #0											// [2]		add the carry
			sta vic20.via2.V2T1LH							// [4]		set VIA2 timer #1 hi-latch

			// hand the CPU to the main program, which no longer has to stay in step with the IRQ
			tsx												// [2]		get stack pointer
			lda #<main_loop									// [2]		get main loop address lo-byte
			sta BRS_runtime_constants.RETURN_PCL,x			// [5]		replace the return address lo-byte
			lda #>main_loop									// [2]		get main loop address hi-byte
			sta BRS_runtime_constants.RETURN_PCH,x			// [5]		replace the return address hi-byte
			inc BRS_runtime_memory.SYNCSTAT					// [5]		set locked state
			jmp exit_irq									// [3]
}


// Hold the lock and run the raster effects for the frame
hold_sync:
.pc = * "hold_sync"
{
			jsr BRS_raster_effects.run_raster_effects		// [6]		run the raster effects, which start at the stable point
// Fall-through into exit_irq
}


// Leave the IRQ, restoring the registers pushed by the KERNAL IRQ stub
exit_irq:
.pc = * "exit_irq"
{
			// the same sequence as the KERNAL IRQ exit at $EB15
			pla												// [4]		pull .Y
			tay												// [2]
			pla												// [4]		pull .X
			tax												// [2]
			pla												// [4]		pull .A
			rti												// [6]		return to the interrupted code
}
