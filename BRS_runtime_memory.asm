// BackTrak Raster Sync runtime RAM labels
// Copyright (C) 2026 8BitGuru <the8bitguru@gmail.com>

.filenamespace BRS_runtime_memory

// Zero-page - 4-byte unused block at $03-$06 (BASIC USR conversion vectors), set at start-up
.label LINEDLY          = $0003     // Raster line delay loop count for the colour bars (PAL or NTSC)
.label LINEADJ          = $0004     // Raster line adjustment for the colour bars (0=PAL, !0=NTSC)
.label ARMCUT           = $0005     // Cycles to shorten the first period of the timer by when it is restarted to lock (PAL or NTSC)
// $0006 is spare

// Zero-page - 4-byte unused block at $FB-$FE
.label OUTERCNT         = $00FB     // Spin loop outer count (PAL or NTSC)
.label INNERCNT         = $00FC     // Spin loop inner count (PAL or NTSC)
.label SYNCSTAT         = $00FD     // Sync state (0=tracking, 1=arming, 2=locked)
// $00FE is spare
