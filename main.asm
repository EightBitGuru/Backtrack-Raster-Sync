// BackTrak Raster Sync for VIC-20
// Copyright (C) 2026 8BitGuru <the8bitguru@gmail.com>

#import "..\Common-VIC20\kickass_scripts.asm"		    // KickAssembler scripts
#import "..\Common-VIC20\vic20_system_constants.asm"	// VIC-20 system constants
#import "..\Common-VIC20\vic20_system_memory.asm"		// VIC-20 system memory labels

#import "brs_runtime_memory.asm"				        // BackTrack runtime memory labels

.disk [filename="BackTrak.d64", name="BACKTRAK (C) 8BG", id="2026"]
{
    [name="BACKTRAK", type="prg", segments="BACKTRAK"]
}

.segment BACKTRAK []
BasicStub(vic20.ram.RAMMAIN+1,code)                     // Unexpanded VIC-20

data:
#import "brs_static_data.asm"	        				// Static data structures

code:
#import "brs_raster_sync.asm"			            	// Backtrack raster sync
#import "brs_raster_effects.asm"			         	// Do synced raster effects

.print "CODE BYTES: "+[*-code]
.print "DATA BYTES: "+[code-data]
.print "TOT. BYTES: "+[*-data]
