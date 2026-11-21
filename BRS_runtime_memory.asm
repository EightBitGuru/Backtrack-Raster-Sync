// BackTrak Raster Sync runtime RAM labels
// Copyright (C) 2026 8BitGuru <the8bitguru@gmail.com>

.filenamespace BRS_runtime_memory

// Zero-page - 4-byte unused block at $03-$06 (BASIC USR conversion vectors), set at start-up
.label ARMCUT           = $0003     // Cycles to shorten the first period of the timer by when it is restarted to lock (PAL or NTSC)
.label VIDEOFLG         = $0004     // Video standard (0=PAL, 1=NTSC)
.label NAMEIDX          = $0005     // Demo main program: offset of the next character of the raster effect's name
.label BARIDX           = $0006     // Copper bars: the bar being drawn, while .Y is the offset of its colours

// Zero-page - 4-byte unused block at $FB-$FE, which the loader uses before the sync sets any of the labels that share them
.label MOVESRCL         = $00FB     // Loader: address to move the program from, lo-byte (the same byte as OUTERCNT, which is set after the move)
.label MOVESRCH         = $00FC     // Loader: address to move the program from, hi-byte (the same byte as INNERCNT)
.label MOVEDSTL         = $00FD     // Loader: address to move the program to, lo-byte (the same byte as SYNCSTAT, which is set after the move)
.label MOVEDSTH         = $00FE     // Loader: address to move the program to, hi-byte (the same byte as LINECNT)
.label OUTERCNT         = $00FB     // Spin loop outer count (PAL or NTSC)
.label INNERCNT         = $00FC     // Spin loop inner count (PAL or NTSC)
.label SYNCSTAT         = $00FD     // Sync state (0=tracking, 1=arming, 2=locked)
.label LINECNT          = $00FE     // Raster lines left to draw in the raster effect for the frame

// RAM - $0200-$0258 is the BASIC input buffer, which the program does not use
.label FRAMECNT         = $0200     // Frame counter, which changes the raster effect every 256 frames
.label EFFECT           = $0201     // Raster effect (0=copper bars, 1=sine ribbon, 2=waving flag, 3=split screen)
.label SHOWN            = $0202     // Raster effect whose name the main program has put on the screen
.label RIBBONPH         = $0203     // Sine ribbon wave phase (0-63)
.label FLAGPH           = $0204     // Waving flag wave phase (0-127)
.label COPPH0           = $0205     // Copper bar 0 phase (0-255)
.label COPPH1           = $0206     // Copper bar 1 phase (0-255)
.label COPPH2           = $0207     // Copper bar 2 phase (0-255)
.label COPOLD0          = $0208     // Copper bar 0 first line in the line buffer, as drawn last frame
.label COPOLD1          = $0209     // Copper bar 1 first line in the line buffer, as drawn last frame
.label COPOLD2          = $020A     // Copper bar 2 first line in the line buffer, as drawn last frame
.label SPLITPH          = $020B     // Split screen: which IRQ is next (0=the one at the top of the frame, 1=the one at the split)

// RAM - $1D00-$1DFF, the screen colour for each raster line of the copper bars effect: the last page before the screen at $1E00
.label COPBUF           = $1D00     // Copper bar line buffer (up to 256 lines)
