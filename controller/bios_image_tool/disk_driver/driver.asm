;=====================================================================
; disk_if driver for the FPGA_MSXtR DOS/DOS2 kernel ROM
;
; Replaces the TC8566AF FDC driver and the internal (SRAM disk /
; ROM disk) driver in both driver copies of
; gt_diskrom_fat16_v25_mapfix.rom:
;   bank 0 = DOS2 driver, bank 3 = DOS1 driver.
; Hardware interface: disk_if_spec_v0.2.md (slot 3-2, page-1 window,
; registers at 7FF2h-7FFBh).  Design: DRIVER_DESIGN.md.
; Implementation notes: IMPLEMENTATION.md.
;
; One source, two variants, selected with zma -D defines:
;   A_REGION A_DEFDPB A_DSKIO A_INIHRD A_MTROFF A_DRIVES A_INIENV
;   A_TIMER A_DSKCHG A_GETDPB A_CHOICE A_STUB A_DSKFMT A_END
;   WA_HELPER (4DD8h DOS2 / 5FC2h DOS1: -> IX=HL=own work area)
;   REG_HELPER (4E09h DOS2 / 5FF6h DOS1: timer registration)
;   REG_ADDR (7FD4h DOS2 trampoline / 77B7h DOS1 timer entry)
;   IS_DOS1 (0 = DOS2 copy, 1 = DOS1 copy)
;
; Work area (24 bytes, inside the existing 26/31-byte allocations):
;   +0  FLAGS: bit0 IFPRESENT, bit1 MEDVALID, bit2 FAT16, bit3 HASMBR
;   +1..+4  POFF (partition start LBA, 32-bit LE; 0 = superfloppy)
;   +5  MEDIA (BPB +21)     +6  SPC (BPB +13)
;   +7..+8  RESSEC (BPB +14)        +9  NFATS (BPB +16)
;   +10..+11 ROOTN (BPB +17)        +12..+13 FATSZ (BPB +22)
;   +14..+15 TOT16 (BPB +19)        +16..+19 TOT32 (BPB +32)
;   +20 PHYDRV (always 1 when present)
;   +21 WFLAG (DSKIO: 0=read, 1=write)
;   +22..+23 unused
;=====================================================================

R_STATUS  := 0x7FF2             ; read: STATUS / write: CMD
R_CMD     := 0x7FF2
R_DRIVE   := 0x7FF3
R_MEDIA   := 0x7FF4
R_SECTOR  := 0x7FF5             ; ..7FF8h, 32-bit LE
R_DATA    := 0x7FF9
R_ERRCODE := 0x7FFA
R_IFVER   := 0x7FFB

CMD_RSTPTR := 0x00
CMD_READ   := 0x01
CMD_WRITE  := 0x02
CMD_CLRCHG := 0x10
CMD_ABORT  := 0x80

SECBUF_P  := 0xF34D             ; word: kernel sector buffer pointer
XFER      := 0xF36E             ; kernel: LDIR with page 1 = RAM
JIFFY     := 0xFC9E
EXPTBL    := 0xFCC1
FCC5      := 0xFCC5

        org     A_REGION

;=====================================================================
; BLK0: CHOICE empty string (a single NUL), then pad to DEFDPB.
;=====================================================================
choice_str:
        db      0

        space   (A_DEFDPB - $), 0

;=====================================================================
; DEFDPB: byte-for-byte identical to the stock template (21 bytes).
;=====================================================================
        db      0x00, 0xF9, 0x00, 0x02, 0x0F, 0x04, 0x01, 0x02
        db      0x01, 0x00, 0x02, 0x70, 0x0E, 0x00, 0xCA, 0x02
        db      0x03, 0x07, 0x00, 0xFA, 0x00

;=====================================================================
; BLK1: small shared helpers.
;=====================================================================

;---------------------------------------------------------------------
; ensure_media: CHANGED check + media detection when needed.
; In: IX = work area.  Out: Cy=0 media valid; Cy=1 + A = error code.
; Preserves BC, DE, HL.
;---------------------------------------------------------------------
ensure_media:
        ld      a, [R_STATUS]
        bit     5, a                    ; CHANGED
        jr      z, em_valid
        ld      a, CMD_CLRCHG
        ld      [R_CMD], a              ; CLRCHG (must)
        res     1, [ix+0]               ; MEDVALID = 0
em_valid:
        bit     1, [ix+0]
        jp      z, detect               ; tail call
        or      a, a                    ; Cy=0 (BIT does not touch Cy)
        ret

;---------------------------------------------------------------------
; getb: A = byte at HL+E (E = offset < 256).  Preserves HL, DE, BC.
; (DE is saved/restored: is_boot keeps the low byte of a 16-bit BPB
; field in D across the call for the high byte.  The original code
; zeroed D with LD D,0 and never restored it, so every 16-bit field
; whose high byte is 0 -- reserved=1, root=112, FAT size=3 -- was
; misjudged as 0 and valid FAT12 boot sectors were rejected.
; Fixed in dif4; see FIX_GETB.md.)
;---------------------------------------------------------------------
getb:
        push    hl
        push    de
        ld      d, 0
        add     hl, de
        ld      a, [hl]
        pop     de
        pop     hl
        ret

        space   (A_DSKIO - $), 0

;=====================================================================
; DSKIO entry (stub to body in BLK12).
;=====================================================================
        jp      dskio_body

;=====================================================================
; BLK3: low-level hardware helpers.
;=====================================================================

;---------------------------------------------------------------------
; wait_busy: poll STATUS.BUSY until it drops.
; Timeout = VDP frame counting (180 frames = 3.0 s @60 Hz,
; 3.6 s @50 Hz): frames are counted both by S#0 F-flag sightings
; (works with interrupts off) and by the BIOS JIFFY counter
; (works when the interrupt handler consumes the F flag first).
; A poll-iteration cap is the final backstop.  On timeout an ABORT
; command is issued.  R#15 is left at 0 (selects S#0), as the BIOS
; interrupt machinery requires.
; Out: Cy=0 done; Cy=1 timeout.  Preserves BC, DE, HL, IX.
;
; The VDP port base byte lives in the BIOS ROM at 0006h and MUST
; be fetched through RDSLT.  A plain LD A,(0006h) is wrong in the
; DOS-kernel context: page 0 then holds the kernel's RAM image,
; whose byte at 0006h is the low operand byte of the BDOS jump
; at 0005h (6Dh on this DOS2 kernel), so the "port" becomes 6Eh
; and every F-flag sighting is a phantom of the open bus -- the
; wait then times out after ~180 poll iterations and aborts
; every transfer.  (Fixed in dif2; see HANG_ANALYSIS2.md.)
;---------------------------------------------------------------------
wait_busy:
        push    bc
        push    de
        push    hl
        ld      a, [EXPTBL]             ; slot 0: expansion flag
        and     a, 0x80                 ; primary 0, secondary 0
        ld      hl, 0x0006
        call    0x000C                  ; RDSLT: A = BIOS port byte
        or      a, a
        jr      z, wb_pdef
        cp      a, 0xFF
        jr      nz, wb_pok
wb_pdef:
        ld      a, 0x98                 ; fallback: standard VDP base
wb_pok:
        inc     a
        ld      c, a                    ; C = 99h (ctrl/status)
        xor     a, a
        out     [c], a
        ld      a, 0x8F
        out     [c], a                  ; R#15 = 0 -> S#0
        ld      a, [JIFFY]
        ld      e, a                    ; E = JIFFY start (low)
        ld      hl, 0                   ; poll counter
        ld      b, 64                   ; wrap budget (backstop)
        ld      d, 0                    ; F sightings
wb_poll:
        ld      a, [R_STATUS]
        bit     7, a                    ; BUSY
        jr      z, wb_ok
        in      a, [c]                  ; S#0
        rlca                            ; F flag -> Cy
        jr      nc, wb_nof
        inc     d
        ld      a, d
        cp      a, 180
        jr      nc, wb_to
wb_nof:
        ld      a, [JIFFY]
        sub     a, e
        cp      a, 180
        jr      nc, wb_to
        inc     hl
        ld      a, h
        or      a, l
        jr      nz, wb_poll
        djnz    wb_poll
wb_to:
        ld      a, CMD_ABORT
        ld      [R_CMD], a
        scf
        jr      wb_ret
wb_ok:
        or      a, a                    ; Cy=0
wb_ret:
        pop     hl
        pop     de
        pop     bc
        ret

;---------------------------------------------------------------------
; xfer_in: copy 512 bytes from the DATA window to (HL).
; HL += 512.  Preserves BC, DE, IX.
; A destination in page 1 (4000h-7FFFh) is staged through the
; kernel sector buffer (SECBUF) and moved with the kernel's XFER
; routine (page-3 LDIR with page 1 switched to RAM), exactly as
; the stock FDC driver does: page 1 must hold this ROM while the
; DATA window is accessed.
;---------------------------------------------------------------------
xfer_in:
        ld      a, h
        and     a, 0xC0
        cp      a, 0x40
        jr      nz, xi_core
        push    bc
        push    de
        push    hl                      ; destination
        ld      hl, [SECBUF_P]
        ld      a, h
        or      a, l
        jr      z, xi_fb                ; no SECBUF: direct (fallback)
        call    xi_core                 ; DATA -> SECBUF
        ld      hl, [SECBUF_P]
        pop     de                      ; DE = destination
        push    de
        ld      bc, 512
        call    XFER                    ; SECBUF -> (DE), page 1 = RAM
        pop     hl
        inc     h
        inc     h                       ; HL = destination + 512
        pop     de
        pop     bc
        ret
xi_fb:
        pop     hl
        pop     de
        pop     bc
xi_core:
        push    bc
        ld      bc, 512
xi_loop:
        ld      a, [R_DATA]
        ld      [hl], a
        inc     hl
        dec     bc
        ld      a, b
        or      a, c
        jr      nz, xi_loop
        pop     bc
        ret

;---------------------------------------------------------------------
; xfer_out: copy 512 bytes from (HL) to the DATA window.
; HL += 512.  Preserves BC, DE, IX.  Page-1 sources are staged
; through SECBUF with XFER like xfer_in.
;---------------------------------------------------------------------
xfer_out:
        ld      a, h
        and     a, 0xC0
        cp      a, 0x40
        jr      nz, xo_core
        push    bc
        push    de
        push    hl                      ; source
        ld      de, [SECBUF_P]
        ld      a, d
        or      a, e
        jr      z, xo_fb                ; no SECBUF: direct (fallback)
        ld      bc, 512
        call    XFER                    ; (HL) -> SECBUF, page 1 = RAM
        ld      hl, [SECBUF_P]
        call    xo_core                 ; SECBUF -> DATA
        pop     hl
        inc     h
        inc     h                       ; HL = source + 512
        pop     de
        pop     bc
        ret
xo_fb:
        pop     hl
        pop     de
        pop     bc
xo_core:
        push    bc
        ld      bc, 512
xo_loop:
        ld      a, [hl]
        ld      [R_DATA], a
        inc     hl
        dec     bc
        ld      a, b
        or      a, c
        jr      nz, xo_loop
        pop     bc
        ret

        space   (A_INIHRD - $), 0

;=====================================================================
; INIHRD entry: nothing to initialize (the interface is always
; ready; media state is handled lazily).  RET only.
;=====================================================================
        ret

        space   (A_MTROFF - $), 0

;=====================================================================
; MTROFF entry: no motor.  RET only.
;=====================================================================
        ret

;=====================================================================
; BLK5: DRIVES body.
; Contract: preserves AF and BC; returns L = number of logical
; drives.  The entry Z flag carries the CONTROL-key state
; (Z = held): with one physical drive, L = 2 normally, L = 1
; with CONTROL.
;
; Without the interface (IFVER /= 01h) DRIVES returns L = 0:
; this ROM then contributes no drives at all.  (Validated in
; the fork openMSX splice environment on the bootable V9
; kernel build: the machine reaches Disk BASIC with 0 drives
; registered.  The deliverable's own base ROM cannot boot in
; the fork for an unrelated, pre-existing reason -- its EM
; FAT16 kernel hangs there even unmodified; see
; IMPLEMENTATION.md.)
;=====================================================================
drives_body:
        push    bc
        push    af                      ; entry AF (incl. Z)
        call    WA_HELPER               ; IX = work area
        ld      a, [R_IFVER]
        cp      a, 1
        jr      z, drv_present
        pop     af
        ld      l, 0
        pop     bc
        ret
drv_present:
        ld      [ix+20], 1              ; PHYDRV = 1
        pop     af
        ld      l, 1
        jr      z, drv_ret              ; CONTROL held -> L = 1
        inc     l                       ; L = 2
drv_ret:
        pop     bc
        ret

        space   (A_DRIVES - $), 0

;=====================================================================
; DRIVES entry (stub).
;=====================================================================
        jp      drives_body

;=====================================================================
; BLK6: INIENV body.  Zero the work area, note interface presence,
; register the (RET-only) timer routine exactly like the stock
; driver (HL = REG_ADDR, tail jump to REG_HELPER).
;=====================================================================
inienv_body:
        ld      a, 1
        ld      [0xF30D], a
        call    WA_HELPER               ; IX = HL = work area
        ld      b, 24
        xor     a, a
ie_zero:
        ld      [hl], a
        inc     hl
        djnz    ie_zero
        ld      a, [R_IFVER]
        cp      a, 1
        jr      nz, ie_reg
        set     0, [ix+0]               ; IFPRESENT = 1
ie_reg:
        ld      hl, REG_ADDR
        jp      REG_HELPER

        space   (A_INIENV - $), 0

;=====================================================================
; INIENV entry (stub).
;=====================================================================
        jp      inienv_body

        space   (A_TIMER - $), 0

;=====================================================================
; Timer routine entry: nothing to do (no motor).  RET only.
;=====================================================================
        ret

        space   (A_DSKCHG - $), 0

;=====================================================================
; DSKCHG entry (stub).
;=====================================================================
        jp      dskchg_body

;=====================================================================
; BLK9: DSKCHG body.
; Out: B = 0FFh changed (CLRCHG issued, media invalidated),
;      B = 01h not changed; Cy=1 + A = 2 when the interface is
;      not ready (error return is part of the DSKCHG contract).
;      Without the interface: B = 01h, registers untouched.
;=====================================================================
dskchg_body:
        ei
        push    ix
        push    hl                      ; stock driver keeps HL, C
        push    bc
        push    af
        call    WA_HELPER               ; IX = work area (A, BC, HL lost)
        pop     af                      ; A = local drive
        pop     bc
        pop     hl
        cp      a, 2
        jr      nc, chg_same
        bit     0, [ix+0]
        jr      z, chg_same             ; absent: B = 01h
        ld      a, [R_STATUS]
        bit     4, a                    ; READY
        jr      z, chg_err
        bit     5, a                    ; CHANGED
        jr      z, chg_same
        ld      a, CMD_CLRCHG
        ld      [R_CMD], a              ; CLRCHG (must)
        res     1, [ix+0]               ; MEDVALID = 0
        ld      b, 0xFF
        pop     ix
        or      a, a                    ; Cy=0
        ret
chg_same:
        ld      b, 0x01
        pop     ix
        or      a, a                    ; Cy=0
        ret
chg_err:
        pop     ix
        ld      a, 2
        scf
        ret

        space   (A_GETDPB - $), 0

;=====================================================================
; GETDPB entry (stub).
;=====================================================================
        jp      getdpb_body

        space   (A_CHOICE - $), 0

;=====================================================================
; CHOICE entry: no format choices (empty string).
;=====================================================================
        ld      hl, choice_str
        ret

        space   (A_STUB - $), 0

;=====================================================================
; Preserved stub block: referenced by absolute jumps from Disk
; BASIC (785Dh page 0 / 7863h page 3 in the stock ROM).  These
; 20 bytes are copied byte-for-byte from the stock driver
; (SCF; RET; FDC command fragments -- never called on MSXtR,
; but the jump targets must keep their addresses and content).
;=====================================================================
        db      0x37, 0xC9, 0x3E, 0x20, 0x18, 0x0A, 0x3E, 0x30
        db      0x18, 0x06, 0x3E, 0x04, 0x32, 0xF2, 0x7F, 0xC9
        db      0x32, 0xF3, 0x7F, 0xC9

;=====================================================================
; BLK12: the public-entry bodies and media detection.
;=====================================================================

;---------------------------------------------------------------------
; dskio_body: DSKIO implementation.
; In: Cy = write, A = local drive (0/1 -> DRIVE 0), B = sectors,
;     C = media ID, DE = first logical sector, HL = transfer addr.
; Out: Cy=0 success (B = 0); Cy=1 + A = error code,
;      B = unprocessed sectors (including the failed one).
;---------------------------------------------------------------------
dskio_body:
        ei
        push    ix
        push    hl                      ; transfer address
        push    bc                      ; B = sectors, C = media ID
        push    af                      ; entry AF (drive + Cy)
        cp      a, 2
        jr      nc, dio_bad
        call    WA_HELPER               ; IX = work area (A, BC, HL lost)
        pop     af                      ; A = drive, Cy = write
        pop     bc
        pop     hl
        ld      a, 0
        jr      nc, dio_nw
        inc     a
dio_nw:
        ld      [ix+21], a              ; WFLAG
        bit     0, [ix+0]
        jr      z, dio_err2             ; interface absent
        call    ensure_media            ; Cy=1 + A = error on failure
        jr      c, dio_out
if IS_DOS1
        bit     2, [ix+0]
        jr      nz, dio_err2            ; FAT16: hidden from DOS1
endif
        ld      a, [R_STATUS]
        bit     4, a                    ; READY
        jr      z, dio_err2
        ld      a, [ix+21]
        or      a, a
        jr      z, dio_loop
        ld      a, [R_STATUS]
        bit     3, a                    ; WPROT
        jr      nz, dio_err0
dio_loop:
        xor     a, a
        ld      [R_DRIVE], a            ; DRIVE = 0
        ld      a, c
        ld      [R_MEDIA], a            ; MEDIA = entry media ID
        ld      a, [ix+1]               ; SECTOR = POFF + DE (32-bit)
        add     a, e
        ld      [R_SECTOR+0], a
        ld      a, [ix+2]
        adc     a, d
        ld      [R_SECTOR+1], a
        ld      a, [ix+3]
        adc     a, 0
        ld      [R_SECTOR+2], a
        ld      a, [ix+4]
        adc     a, 0
        ld      [R_SECTOR+3], a
        ld      a, [ix+21]
        or      a, a
        jr      nz, dio_wr
        call    raw_read                ; HL = destination
        jr      dio_next
dio_wr:
        call    raw_write               ; HL = source
dio_next:
        jr      c, dio_out              ; A = error, B = remaining
        inc     de
        djnz    dio_loop
        pop     ix
        or      a, a                    ; Cy=0
        ret
dio_err0:
        xor     a, a                    ; A = 0 (write protected)
        jr      dio_err
dio_err2:
        ld      a, 2                    ; not ready
dio_err:
        scf
dio_out:
        pop     ix
        ret
dio_bad:
        pop     af                      ; balance
        pop     bc
        pop     hl
        pop     ix
        ld      a, 2
        scf
        ret

;---------------------------------------------------------------------
; getdpb_body: GETDPB implementation.  Builds the 18-byte DPB at
; (HL)+1 from the cached real BPB (the stock media table is not
; used).  Fails (Cy=1) when: interface absent, drive invalid,
; media detection fails, requested media /= actual media,
; FATSZ > 255, ROOTN > 255 (1-byte DPB fields), clusters > 65535,
; or (DOS1 copy) the volume is FAT16.
;---------------------------------------------------------------------
getdpb_body:
        push    ix
        push    hl                      ; DPB address
        push    bc                      ; B = requested media byte
        push    af                      ; A = local drive
        call    WA_HELPER               ; IX = work area
        pop     af
        cp      a, 2
        jp      nc, gdp_fail3
        bit     0, [ix+0]
        jp      z, gdp_fail3
        call    ensure_media
        jp      c, gdp_fail3
if IS_DOS1
        bit     2, [ix+0]
        jp      nz, gdp_fail3           ; FAT16: hidden from DOS1
endif
        pop     bc                      ; B = requested media
        ld      a, b
        cp      a, [ix+5]               ; /= cached MEDIA ?
        jr      nz, gdp_fail2
        ld      a, [ix+13]              ; FATSZ high byte
        or      a, a
        jr      nz, gdp_fail2
        ld      a, [ix+11]              ; ROOTN high byte
        or      a, a
        jr      nz, gdp_fail2
        pop     hl                      ; DPB address
        inc     hl
        ex      de, hl                  ; DE = write pointer (DPB+1)
        ld      a, [ix+5]               ; +1 media ID
        ld      [de], a
        inc     de
        xor     a, a                    ; +2/+3 sector size 512
        ld      [de], a
        inc     de
        ld      a, 2
        ld      [de], a
        inc     de
        ld      a, 0x0F                 ; +4 directory mask
        ld      [de], a
        inc     de
        ld      a, 4                    ; +5 directory shift
        ld      [de], a
        inc     de
        ld      a, [ix+6]               ; +6 cluster mask = SPC-1
        dec     a
        ld      [de], a
        inc     de
        ld      a, [ix+6]               ; +7 sectors per cluster
        ld      [de], a
        inc     de
        ld      a, [ix+7]               ; +8/+9 first FAT sector
        ld      [de], a
        inc     de
        ld      a, [ix+8]
        ld      [de], a
        inc     de
        ld      a, [ix+9]               ; +10 number of FATs
        ld      [de], a
        inc     de
        ld      a, [ix+10]              ; +11 root entries (low)
        ld      [de], a
        inc     de
        call    dpb_datastart           ; HL = data start, BC = root start
        ld      a, l                    ; +12/+13 first data sector
        ld      [de], a
        inc     de
        ld      a, h
        ld      [de], a
        inc     de
        push    bc                      ; root start
        push    de                      ; write pointer
        call    calc_clusters           ; B:C:HL = clusters
        pop     de
        jr      c, gdp_failb
        ld      a, b
        or      a, c
        jr      nz, gdp_failb           ; clusters > 65535
        inc     hl                      ; max cluster = clusters + 1
        ld      a, l                    ; +14/+15 max cluster
        ld      [de], a
        inc     de
        ld      a, h
        ld      [de], a
        inc     de
        ld      a, [ix+12]              ; +16 FAT sectors (low)
        ld      [de], a
        inc     de
        pop     bc                      ; root start
        ld      a, c                    ; +17/+18 first root sector
        ld      [de], a
        inc     de
        ld      a, b
        ld      [de], a
        pop     ix
        or      a, a                    ; Cy=0
        ret
gdp_failb:                              ; stack: ix, root start
        pop     bc
        pop     ix
        scf
        ret
gdp_fail2:                              ; stack: ix, DPB address
        pop     hl
        pop     ix
        scf
        ret
gdp_fail3:                              ; stack: ix, DPB address, BC
        pop     bc
        pop     hl
        pop     ix
        scf
        ret

;---------------------------------------------------------------------
; detect: media detection (design section 6).  Reads physical
; sector 0; superfloppy if it is a valid boot sector, else scans
; the MBR partition table for the first FAT12/16 partition and
; validates its boot sector.  Caches the BPB in the work area
; and sets MEDVALID + FAT16 flag.
; In: IX = work area.  Out: Cy=0 ok; Cy=1 + A = error code.
; Preserves BC, DE, HL.
;---------------------------------------------------------------------
detect:
        push    bc
        push    de
        push    hl
        ld      hl, [SECBUF_P]
        ld      a, h
        or      a, l
        jp      z, det_fail2            ; no sector buffer: cannot run
        ld      a, [R_STATUS]
        bit     4, a                    ; READY
        jp      z, det_fail2
        xor     a, a
        ld      [R_DRIVE], a
        ld      [R_MEDIA], a
        ld      [R_SECTOR+0], a
        ld      [R_SECTOR+1], a
        ld      [R_SECTOR+2], a
        ld      [R_SECTOR+3], a
        ld      hl, [SECBUF_P]
        call    raw_read                ; physical sector 0 -> SECBUF
        jp      c, det_out              ; A = hardware error
        ld      hl, [SECBUF_P]
        call    is_boot
        jr      c, det_mbr
        xor     a, a                    ; superfloppy: POFF = 0
        ld      [ix+1], a
        ld      [ix+2], a
        ld      [ix+3], a
        ld      [ix+4], a
        res     3, [ix+0]               ; HASMBR = 0
        call    cache_bpb
        jp      c, det_fail2
        jp      det_ok
det_mbr:
        ld      hl, [SECBUF_P]
        ld      de, 510
        add     hl, de
        ld      a, [hl]
        cp      a, 0x55
        jp      nz, det_def
        inc     hl
        ld      a, [hl]
        cp      a, 0xAA
        jp      nz, det_def
        ld      hl, [SECBUF_P]
        ld      de, 446
        add     hl, de                  ; HL = partition entry 0
        ld      b, 4
det_scan:
        push    hl
        ld      de, 4
        add     hl, de
        ld      a, [hl]                 ; partition type
        pop     hl
        cp      a, 0x01
        jr      z, det_pt
        cp      a, 0x04
        jr      z, det_pt
        cp      a, 0x06
        jr      z, det_pt
        cp      a, 0x0E
        jr      z, det_pt
        jr      det_next
det_pt:
        push    hl
        ld      de, 8
        add     hl, de                  ; start LBA
        ld      a, [hl]
        ld      [ix+1], a
        inc     hl
        ld      a, [hl]
        ld      [ix+2], a
        inc     hl
        ld      a, [hl]
        ld      [ix+3], a
        inc     hl
        ld      a, [hl]
        ld      [ix+4], a
        pop     hl
        ld      a, [ix+1]
        or      a, [ix+2]
        or      a, [ix+3]
        or      a, [ix+4]
        jr      nz, det_found           ; LBA /= 0
det_next:
        ld      de, 16
        add     hl, de
        djnz    det_scan
        jr      det_fail2
det_found:
        set     3, [ix+0]               ; HASMBR = 1
        xor     a, a
        ld      [R_DRIVE], a
        ld      [R_MEDIA], a
        ld      a, [ix+1]
        ld      [R_SECTOR+0], a
        ld      a, [ix+2]
        ld      [R_SECTOR+1], a
        ld      a, [ix+3]
        ld      [R_SECTOR+2], a
        ld      a, [ix+4]
        ld      [R_SECTOR+3], a
        ld      hl, [SECBUF_P]
        call    raw_read                ; partition boot sector
        jr      c, det_out
        ld      hl, [SECBUF_P]
        call    is_boot
        jp      c, det_fail2
        call    cache_bpb
        jp      c, det_fail2
det_ok:
        set     1, [ix+0]               ; MEDVALID = 1
        or      a, a                    ; Cy=0
        jr      det_ret
det_fail2:
        ld      a, 2
        scf
det_out:                                ; Cy=1, A = error (from raw_read)
det_ret:
        pop     hl
        pop     de
        pop     bc
        ret

; Sector 0 is neither a boot sector nor an MBR (e.g. a game disk
; with a custom loader): like the stock FDC driver, assume a
; standard 2DD (F9h) superfloppy.  SD cards that are not FAT12/16
; never get here: the Pico reports them as not READY.
det_def:
        push    ix
        pop     hl
        ld      de, 5
        add     hl, de
        ex      de, hl                  ; DE = IX+5 (MEDIA..TOT32)
        ld      hl, def_bpb
        ld      bc, 15
        ldir
        xor     a, a
        ld      [ix+1], a               ; POFF = 0
        ld      [ix+2], a
        ld      [ix+3], a
        ld      [ix+4], a
        res     3, [ix+0]               ; HASMBR = 0
        res     2, [ix+0]               ; FAT12
        jp      det_ok

; Work-area image of +5..+19 for a 2DD disk.
def_bpb:
        db      0xF9                    ; MEDIA
        db      0x02                    ; SPC
        db      0x01, 0x00              ; RESSEC
        db      0x02                    ; NFATS
        db      0x70, 0x00              ; ROOTN = 112
        db      0x03, 0x00              ; FATSZ = 3
        db      0xA0, 0x05              ; TOT16 = 1440
        db      0x00, 0x00, 0x00, 0x00  ; TOT32

        space   (A_DSKFMT - $), 0

;=====================================================================
; DSKFMT entry: formatting is not supported.
;=====================================================================
        ld      a, 12                   ; other error
        scf
        ret

;=====================================================================
; BLK13: raw sector I/O, boot-sector validation, BPB cache,
; cluster computation, DPB geometry helper.
;=====================================================================

;---------------------------------------------------------------------
; raw_read: read one sector (DRIVE/MEDIA/SECTOR registers preset)
; to (HL).  The data is copied BEFORE the error judgment, as the
; spec requires (error-file reproduction).  HL += 512 always.
; Out: Cy=0 ok; Cy=1 + A = ERRCODE (or 2 on timeout).
; Preserves BC, DE, IX.
;---------------------------------------------------------------------
raw_read:
        ld      a, CMD_READ
        ld      [R_CMD], a
        call    wait_busy               ; Cy=1: timeout (ABORT sent)
        push    af
        call    xfer_in                 ; DATA -> (HL), always
        pop     af
        jr      c, rr_to
        ld      a, [R_STATUS]
        bit     6, a                    ; ERROR
        ret     z                       ; Cy=0
        ld      a, [R_ERRCODE]
        scf
        ret
rr_to:
        ld      a, 2
        scf
        ret

;---------------------------------------------------------------------
; raw_write: write one sector from (HL) (registers preset).
; HL += 512.  Out: Cy=0 ok; Cy=1 + A = ERRCODE (or 2 on timeout).
; Preserves BC, DE, IX.
;---------------------------------------------------------------------
raw_write:
        xor     a, a
        ld      [R_CMD], a              ; RSTPTR
        call    xfer_out                ; (HL) -> DATA
        ld      a, CMD_WRITE
        ld      [R_CMD], a
        call    wait_busy
        jr      c, rr_to                ; A = 2, Cy=1
        ld      a, [R_STATUS]
        bit     6, a                    ; ERROR
        ret     z                       ; Cy=0
        ld      a, [R_ERRCODE]
        scf
        ret

;---------------------------------------------------------------------
; is_boot: validate a boot sector at (HL).
; Out: Cy=0 valid; Cy=1 invalid.  Preserves HL, BC.
; Clobbers A, D, E (D = 16-bit field accumulator, E = getb offset);
; the sole caller (detect) saves DE, so this is safe by design.
; Checks: jump (EB xx or E9), bytes/sector = 512, SPC a power
; of two, reserved >= 1, NFATS >= 1, root entries >= 16 and a
; multiple of 16, total (16 or 32) /= 0, media >= F8h,
; FAT size 16 /= 0 (rejects FAT32).
;---------------------------------------------------------------------
is_boot:
        ld      e, 0
        call    getb
        cp      a, 0xEB
        jr      z, ib_2
        cp      a, 0xE9
        jp      nz, ib_ng
ib_2:
        ld      e, 11                   ; sector length = 512
        call    getb
        or      a, a
        jp      nz, ib_ng
        ld      e, 12
        call    getb
        cp      a, 2
        jp      nz, ib_ng
        ld      e, 13                   ; SPC: power of two, /= 0
        call    getb
        or      a, a
        jp      z, ib_ng
        ld      d, a
        dec     a
        and     a, d
        jp      nz, ib_ng
        ld      e, 14                   ; reserved sectors /= 0
        call    getb
        ld      d, a
        ld      e, 15
        call    getb
        or      a, d
        jp      z, ib_ng
        ld      e, 16                   ; NFATS /= 0
        call    getb
        or      a, a
        jp      z, ib_ng
        ld      e, 17                   ; root entries: multiple
        call    getb                    ; of 16 and /= 0
        and     a, 0x0F
        jp      nz, ib_ng
        ld      e, 17
        call    getb
        ld      d, a
        ld      e, 18
        call    getb
        or      a, d
        jp      z, ib_ng
        ld      e, 19                   ; total16 /= 0 -> ok
        call    getb
        ld      d, a
        ld      e, 20
        call    getb
        or      a, d
        jr      nz, ib_tot
        ld      e, 32                   ; else total32 /= 0
        call    getb
        ld      d, a
        ld      e, 33
        call    getb
        or      a, d
        ld      e, 34
        call    getb
        or      a, d
        ld      e, 35
        call    getb
        or      a, d
        jp      z, ib_ng
ib_tot:
        ld      e, 21                   ; media >= F8h
        call    getb
        cp      a, 0xF8
        jp      c, ib_ng
        ld      e, 22                   ; FAT size 16 /= 0
        call    getb
        ld      d, a
        ld      e, 23
        call    getb
        or      a, d
        jp      z, ib_ng
        or      a, a                    ; Cy=0
        ret
ib_ng:
        scf
        ret

;---------------------------------------------------------------------
; cache_bpb: copy the BPB fields from the boot sector at (HL)
; into the work area and determine the FAT type.
; Out: Cy=0 ok; Cy=1 invalid arithmetic.  Preserves IX.
; Clobbers A, B, C, D, E, H, L (E = getb offset; the rest via
; calc_clusters); the sole caller (detect) saves BC, DE, HL.
;---------------------------------------------------------------------
cache_bpb:
        ld      e, 13
        call    getb
        ld      [ix+6], a               ; SPC
        ld      e, 14
        call    getb
        ld      [ix+7], a               ; RESSEC low
        ld      e, 15
        call    getb
        ld      [ix+8], a               ; RESSEC high
        ld      e, 16
        call    getb
        ld      [ix+9], a               ; NFATS
        ld      e, 17
        call    getb
        ld      [ix+10], a              ; ROOTN low
        ld      e, 18
        call    getb
        ld      [ix+11], a              ; ROOTN high
        ld      e, 19
        call    getb
        ld      [ix+14], a              ; TOT16 low
        ld      e, 20
        call    getb
        ld      [ix+15], a              ; TOT16 high
        ld      e, 21
        call    getb
        ld      [ix+5], a               ; MEDIA
        ld      e, 22
        call    getb
        ld      [ix+12], a              ; FATSZ low
        ld      e, 23
        call    getb
        ld      [ix+13], a              ; FATSZ high
        ld      e, 32
        call    getb
        ld      [ix+16], a              ; TOT32 b0
        ld      e, 33
        call    getb
        ld      [ix+17], a              ; TOT32 b1
        ld      e, 34
        call    getb
        ld      [ix+18], a              ; TOT32 b2
        ld      e, 35
        call    getb
        ld      [ix+19], a              ; TOT32 b3
        call    calc_clusters           ; A = 0 FAT12 / 1 FAT16
        ret     c                       ; invalid arithmetic
        res     2, [ix+0]
        or      a, a
        ret     z                       ; FAT12 (Cy=0)
        set     2, [ix+0]               ; FAT16
        or      a, a                    ; Cy=0
        ret

;---------------------------------------------------------------------
; calc_clusters: clusters = (total - reserved) / SPC from the
; cached BPB.  Out: B:C:HL = cluster count (32-bit);
; A = 0 when clusters < 4085 (FAT12), 1 when >= 4085;
; Cy=1 when reserved > total (invalid BPB).
; Clobbers A, B, C, D, E, H, L.  Preserves IX.
;---------------------------------------------------------------------
calc_clusters:
        ld      l, [ix+14]
        ld      h, [ix+15]
        ld      a, l
        or      a, h
        jr      nz, cc_t16
        ld      l, [ix+16]
        ld      h, [ix+17]
        push    hl                      ; total low (from TOT32)
        ld      l, [ix+18]
        ld      h, [ix+19]
        push    hl                      ; total high
        jr      cc_prod
cc_t16:
        push    hl                      ; total low (TOT16)
        ld      hl, 0
        push    hl                      ; total high = 0
cc_prod:
        ld      e, [ix+12]              ; DE = FATSZ
        ld      d, [ix+13]
        ld      hl, 0                   ; product -> C:HL (24-bit)
        ld      c, 0
        ld      a, [ix+9]               ; NFATS
        or      a, a
        jr      z, cc_pdone
        ld      b, a
cc_mul:
        add     hl, de
        jr      nc, cc_mn
        inc     c
cc_mn:
        djnz    cc_mul
cc_pdone:
        ld      e, [ix+7]               ; reserved += RESSEC
        ld      d, [ix+8]
        add     hl, de
        jr      nc, cc_r1
        inc     c
cc_r1:
        ld      e, [ix+10]              ; reserved += ROOTN / 16
        ld      d, [ix+11]
        srl     d
        rr      e
        srl     d
        rr      e
        srl     d
        rr      e
        srl     d
        rr      e
        add     hl, de
        jr      nc, cc_r2
        inc     c
cc_r2:
        ld      a, c                    ; A = reserved byte 2
        pop     bc                      ; BC = total high
        ex      [sp], hl                ; HL = total low
        pop     de                      ; DE = reserved low
        or      a, a
        sbc     hl, de                  ; HL = data low
        ld      e, a                    ; E = reserved byte 2 (flags kept)
        ld      a, c
        sbc     a, e                    ; data byte 2
        ld      c, a
        ld      a, b
        sbc     a, 0                    ; data byte 3
        ld      b, a
        jr      c, cc_invalid           ; reserved > total
        ld      a, [ix+6]               ; clusters = data >> log2(SPC)
        ld      d, -1
cc_lg:
        inc     d
        srl     a
        jr      nz, cc_lg
        ld      a, d
        or      a, a
        jr      z, cc_cmp
cc_shr:
        srl     b
        rr      c
        rr      h
        rr      l
        dec     a
        jr      nz, cc_shr
cc_cmp:
        ld      a, b
        or      a, c
        jr      nz, cc_f16              ; clusters >= 65536
        ld      a, l
        sub     a, 0xF5                 ; 4085 = 0x0FF5
        ld      a, h
        sbc     a, 0x0F
        jr      nc, cc_f16
        xor     a, a                    ; A = 0, Cy=0 (FAT12)
        ret
cc_f16:
        ld      a, 1
        or      a, a                    ; Cy=0
        ret
cc_invalid:
        scf
        ret

;---------------------------------------------------------------------
; dpb_datastart: geometry for GETDPB.
; Out: HL = first data sector, BC = first root-directory sector.
; Preserves DE, IX.
;---------------------------------------------------------------------
dpb_datastart:
        push    de
        ld      e, [ix+12]              ; DE = FATSZ (<= 255 here)
        ld      d, 0
        ld      hl, 0                   ; HL = NFATS * FATSZ
        ld      a, [ix+9]
        or      a, a
        jr      z, dd_md
        ld      b, a
dd_mul:
        add     hl, de
        djnz    dd_mul
dd_md:
        ld      e, [ix+7]               ; HL += RESSEC -> root start
        ld      d, [ix+8]
        add     hl, de
        push    hl                      ; root start
        ld      e, [ix+10]              ; DE = ROOTN / 16
        ld      d, [ix+11]
        srl     d
        rr      e
        srl     d
        rr      e
        srl     d
        rr      e
        srl     d
        rr      e
        add     hl, de                  ; HL = data start
        pop     bc                      ; BC = root start
        pop     de
        ret

        space   (A_END - $), 0
