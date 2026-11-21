// BackTrak Raster Sync for VIC-20
// Copyright (C) 2026 8BitGuru <the8bitguru@gmail.com>

.import source "kickass_scripts.asm"					// KickAssembler scripts
.import source "vic20_system_constants.asm"				// VIC-20 system constants
.import source "vic20_system_memory.asm"				// VIC-20 system memory labels

.import source "BRS_runtime_memory.asm"					// BackTrak runtime memory labels
.import source "BRS_runtime_constants.asm"				// BackTrak runtime constants and cycle model

.disk [filename="BackTrak.d64", name="BACKTRAK (C) 8BG", id="2026"]
{
    [name="BACKTRAK", type="prg", segments="BACKTRAK"]
}

.label LOADER_OFFSET = 2800								// Offset of the loader from the start of the file, which the BASIC line adds to the start of BASIC (checked below)

.segment BACKTRAK []
BasicStub(vic20.ram.RAMMAIN+1,LOADER_OFFSET)			// Built for an unexpanded VIC-20, and the BASIC line finds the loader wherever BASIC is loaded

data:
.import source "BRS_static_data.asm"					// Static data structures

code:
.import source "BRS_main_program.asm"					// BackTrak demo main program, which the BASIC stub runs
.import source "BRS_raster_sync.asm"					// BackTrak raster sync
.import source "BRS_raster_effects.asm"					// BackTrak raster effects, run when locked
.import source "BRS_loader.asm"							// BackTrak loader, which moves the program to where it was built to run (sits in the space before the next page)
.import source "BRS_split_effects.asm"					// BackTrak split screen effect (split_pal is placed in the space after COSPOS, and split_ntsc follows the loader)
.import source "BRS_copper_bars.asm"					// BackTrak copper bar drawing, which has to start on a page
code_end:

.errorif code_end > BRS_runtime_memory.COPBUF, "The program runs into the copper bar line buffer at $1D00: it is " + [code_end - BRS_runtime_memory.COPBUF] + " bytes too long"

.errorif BRS_loader.move_program - [vic20.ram.RAMMAIN+1] != LOADER_OFFSET, "Set LOADER_OFFSET in main.asm to "+[BRS_loader.move_program - [vic20.ram.RAMMAIN+1]]
.errorif [BRS_loader.copier_end - BRS_loader.copier_image] > 128, "The copier is too long for the loader's copy loop"
.errorif floor([code_end - data] / 256) == 0, "The program is under a page, which the copier's page count does not allow"
.errorif (>BRS_copper_bars.compose_bars) != (>(BRS_raster_effects.split_ntsc_end - 1)) + 1, "The loader and split_ntsc run past the page before compose_bars: compose_bars has been pushed a page on, which the program has no room for"

.print "CODE BYTES: "+[code_end-code]
.print "DATA BYTES: "+[code-data]
.print "TOT. BYTES: "+[code_end-data]
.print "END:        $"+toHexString(code_end)
