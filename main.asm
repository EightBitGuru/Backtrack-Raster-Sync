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

.segment BACKTRAK []
BasicStub(vic20.ram.RAMMAIN+1,code)						// Unexpanded VIC-20

data:
.import source "BRS_static_data.asm"					// Static data structures

code:
.import source "BRS_raster_sync.asm"					// BackTrak raster sync
.import source "BRS_raster_effects.asm"					// BackTrak raster effects, run when locked
code_end:

.errorif code_end > vic20.ram.RAMMAIN + $0E00, "The program runs into the screen at $1E00: it is " + [code_end - vic20.ram.RAMMAIN - $0E00] + " bytes too long"

.print "CODE BYTES: "+[code_end-code]
.print "DATA BYTES: "+[code-data]
.print "TOT. BYTES: "+[code_end-data]
.print "END:        $"+toHexString(code_end)
