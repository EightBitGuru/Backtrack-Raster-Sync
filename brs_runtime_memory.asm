// BackTrak Raster Sync runtime RAM labels
// Copyright (C) 2026 8BitGuru <the8bitguru@gmail.com>

.filenamespace brs_runtime_memory

// Zero-page - 4-byte unused block at $03-$06
.label Backtrack_Lock_State          = $0003                // Sync lock state indicator
.label Backtrack_IRQ_Timer_Lo        = $0003                // Sync IRQ timer lo-byte
.label Backtrack_IRQ_Timer_Hi        = $0004                // Sync IRQ timer hi-byte
.label Backtrack_Lock_Timer_Lo       = $0005                // Sync lock timer lo-byte
.label Backtrack_Lock_Timer_Hi       = $0006                // Sync lock timer hi-byte
.label Backtrack_Video_Flag          = $00FB                // Sync PAL/NTSC video flag
.label Backtrack_Loop_Counter        = $00FC                // Sync loop counter
