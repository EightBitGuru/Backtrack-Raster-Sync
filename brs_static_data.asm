// BackTrak Raster Sync static data structures
// Copyright (C) 2026 8BitGuru <the8bitguru@gmail.com>

.filenamespace brs_static_data

Backtrack_Timer_Values:     // Frame cycle counts for VIA timer
.pc = * "Backtrack Timer Values"
.word 22128                 // PAL backtrack cycles
.word 22112                 // PAL raster lock cycles
.word 16941                 // NTSC backtrack cycles
.word 16925                 // NTSC raster lock cycles
