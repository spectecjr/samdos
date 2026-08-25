
; =====================================================================================================================
; C.S -- The disk driver
; =====================================================================================================================
;
; Everything that touches the WD1772 controller or understands the disk's on-disk structures lives here:
;
;   commp .. commt        addressing the controller's four registers
;   svint / ldint         saving and restoring the interrupt state around a transfer
;   wsad / rsad           write and read one sector, with retries
;   rsadx                 read a directory sector, building the free-sector map as a side effect
;   cdec / ctsl / ctas    error recovery: retry, re-confirm the head position, seek
;   rest / instp / outstp drive positioning
;   sbyt / lbyt           one byte to or from the current file
;   ldblk / svblk         whole blocks, streamed a sector at a time
;   fnfs                  allocate the next free sector
;   fdhr / cknam          scan the directory
;   ofsm / cfsm           open and close a file for writing
;   gtfle                 open a file for reading
;   point / grpnt / ...   the pointer arithmetic all of the above share
;
; ---------------------------------------------------------------------------------------------------------------------
; How a file is stored
; ---------------------------------------------------------------------------------------------------------------------
;
; A file is a chain of sectors. Each holds disk.sctdata bytes of data followed by the track and sector of its
; successor; a link of 0,0 ends the chain. There is no allocation table on the disk: the sectors a file occupies are
; recorded as a bitmap in the file's own directory entry, at de.sam. To find free space, the DOS ORs together the
; bitmaps of every file in the directory -- which is what rsadx does while it reads the directory, at no extra cost.
;
; ---------------------------------------------------------------------------------------------------------------------
; Timing
; ---------------------------------------------------------------------------------------------------------------------
;
; At 250 kbit/s a byte arrives every 32us, which is about 112 T-states. The transfer loops below poll the status
; register six times in a row before testing for the command having finished, so that the data request is noticed as
; soon as possible; a rolled-up loop would spend too much of the budget on the jump back. Interrupts are disabled for
; the whole of a sector transfer, since a single missed byte loses the sector.
; =====================================================================================================================


ftadd:         equ &a280      ; scratch area in the screen page: the format track image, and the sector list a long
                              ; save allocates ahead of itself
rdkey:         equ &0169      ; jump table: read a key as INKEY$ does
clslow:        equ &0151      ; jump table: clear the lower screen


; ---------------------------------------------------------------------------------------------------------------------
; commp / trckp / commr / commt -- reach the controller's registers
;
; dsc holds the base port with the drive and side selection already in its high bits, so the four registers are at
; dsc+0 (command/status), +1 (track), +2 (sector) and +3 (data).
;
; Exit:   commp -- C = the command port, A preserved
;         trckp -- C = the track port
;         commr -- A = the status register, BC preserved
;         commt -- A written to the command register, BC preserved
; ---------------------------------------------------------------------------------------------------------------------

commp:         push af
               ld a,(dsc)
               ld c,a
               pop af
               ret

trckp:         call commp
               inc c
               ret

commr:         push bc
               call commp
               in a,(c)
               pop bc
               ret

commt:         push bc
               call commp
               out (c),a
               pop bc
               ret


; ---------------------------------------------------------------------------------------------------------------------
; ckde -- has the whole block been transferred?
;
; A block length is held as pges1 whole 16K pages plus DE bytes. When DE reaches zero another page is borrowed, so
; the caller can treat DE as a simple countdown.
;
; Exit:   Z if the block is finished, NZ with DE non-zero otherwise
; ---------------------------------------------------------------------------------------------------------------------

ckde:          ld a,d
               or e
               ret nz

               ld a,(pges1)
               and a
               ret z

               dec a
               ld (pges1),a
               ld de,page.size
               jr ckde


; ---------------------------------------------------------------------------------------------------------------------
; svint / ldint -- save and restore the interrupt enable state
;
; LD A,I copies IFF2 into the parity flag, but the instruction is documented as being able to sample it while an
; interrupt is being accepted, giving the wrong answer. The read is therefore done twice when the first result says
; "enabled", which is the standard workaround.
;
; The state is kept in hldi rather than on the stack, so that the two halves can be far apart.
; ---------------------------------------------------------------------------------------------------------------------

;SAVE INTERRUPT STATUS

svint:         push af
               ld a,i
               jp pe,svin1
               ld a,i
svin1:         push af
               di
               ex (sp),hl
               ld (hldi),hl
               pop hl
               pop af
               ret


;LOAD INTERRUPT STATUS

ldint:         push af
               push hl
               ld hl,(hldi)
               ex (sp),hl
               pop af
               jp po,ldin1
               ei
ldin1:         pop af
               ret


; ---------------------------------------------------------------------------------------------------------------------
; precmx / precmp -- decide whether to write with precompensation, then issue the command
;
; The inner tracks of a disk have the highest bit density, so a write there needs its transitions shifted slightly to
; compensate for the way adjacent transitions pull each other apart on readback. The controller does this itself; bit
; 1 of a write command turns it off. It is left off for the outer half of the disk and switched on for the inner half.
;
; Entry:  D = track (bit 7 selects the side); precmp also takes the command in C
; Exit:   the command has been sent -- precmp falls through into sadc
; ---------------------------------------------------------------------------------------------------------------------

;PRECOMPENSATION CALCULATOR

precmx:        ld c,dwsec

precmp:        call tstd      ; a = tracks on this drive, bit 7 set if double sided
               rra
               and &3f        ; a = half the track count
               ld b,a
               ld a,d
               and &7f        ; the track alone, without the side bit
               sub b
               jp c,sadc      ; outer half: leave precompensation disabled
               res 1,c        ; inner half: enable it
               jp sadc


; ---------------------------------------------------------------------------------------------------------------------
; wsad -- write the sector buffer to track D, sector E
;
; Loops until the sector is written or cdec gives up. The exit is unusual: on success cdec discards the return
; address of the call below it and returns to wsad's own caller with HL pointing at the buffer, so the "jr wsa1" is
; only ever reached on a retry.
;
; Entry:  D = track, E = sector, the buffer holding the data
; Exit:   HL = the buffer address
; Errors: err.trkerr after disk.retries attempts, err.wprot if the disk is write protected
; ---------------------------------------------------------------------------------------------------------------------

;WRITE SECTOR AT DE

wsad:          xor a
               ld (dct),a
wsa1:          call ctas
               call svint
               call commp
               push bc
               call gtbuf
               call precmx
               pop bc
               call wsa3
               call cdec
               jr wsa1

; The transfer loop. C addresses the command register, so C+3 is the data register; incrementing and decrementing it
; around the outi is cheaper than keeping a second port number.

wsa2:          inc c
               inc c
               inc c

               outi

               dec c
               dec c
               dec c

wsa3:          in a,(c)
               bit wd.st2.drq,a
               jr nz,wsa2

               in a,(c)
               bit wd.st2.drq,a
               jr nz,wsa2

               in a,(c)
               bit wd.st2.drq,a
               jr nz,wsa2

               in a,(c)
               bit wd.st2.drq,a
               jr nz,wsa2

               in a,(c)
               bit wd.st2.drq,a
               jr nz,wsa2

               in a,(c)
               bit wd.st2.drq,a
               jr nz,wsa2

               bit wd.st.busy,a
               jr nz,wsa3

               call ldint
               bit wd.st2.wprot,a
               ret z
               jp rep23


; ---------------------------------------------------------------------------------------------------------------------
; rsad -- read track D, sector E into the sector buffer
;
; The mirror of wsad, including the same exit through cdec.
;
; Entry:  D = track, E = sector
; Exit:   HL = the buffer address, which now holds the sector
; Errors: err.trkerr after disk.retries attempts
; ---------------------------------------------------------------------------------------------------------------------

;READ SECTOR AT DE

rsad:          xor a
               ld (dct),a
rsa1:          call ctas
               ld c,drsec
               call sadc
               call gtbuf
               call rddata
               call cdec
               jr rsa1


rddata:        call svint
               call commp
               jr rsa3

rsa2:          inc c
               inc c
               inc c

               ini

               dec c
               dec c
               dec c

rsa3:          in a,(c)
               bit wd.st2.drq,a
               jr nz,rsa2

               in a,(c)
               bit wd.st2.drq,a
               jr nz,rsa2

               in a,(c)
               bit wd.st2.drq,a
               jr nz,rsa2

               in a,(c)
               bit wd.st2.drq,a
               jr nz,rsa2

               in a,(c)
               bit wd.st2.drq,a
               jr nz,rsa2

               in a,(c)
               bit wd.st2.drq,a
               jr nz,rsa2

               bit wd.st.busy,a
               jr nz,rsa3

               jp ldint


; =====================================================================================================================
; rsadx -- read a directory sector, accumulating the free-sector map as it goes
; =====================================================================================================================
;
; Used by fdhr in place of rsad. As well as reading the sector, it ORs the bytes of every directory entry that is in
; use into the page at &7700 -- and sam, the global map of sectors in use, is at &770F, which is exactly de.sam bytes
; in. So each file's own sector map lands on top of the global one at the right offset, and by the time the directory
; has been scanned the DOS knows which sectors are free. Building the map costs nothing beyond the OR.
;
; The bytes either side of sam within that page (&7700-&770E and &77D2-&77FF) are padding, and exist so that the rest
; of each entry has somewhere harmless to go.
;
; The mechanism: L' counts bytes within the entry and wraps every de.size bytes, at which point rsadx3 looks at the
; first byte of the new entry -- the type byte -- and sets H' to &77 if the entry is in use or 0 if it is free. When
; H' is 0 the accumulation writes to &00xx, which is ROM, and is discarded.
;
; The polling loop is written with the port numbers patched into the instructions, because there is not enough time
; to keep them in a register and still service the data request.
;
; Entry:  D = track, E = sector
; Exit:   as rsad
; ---------------------------------------------------------------------------------------------------------------------

; called by FILE DIR HAND/ROUT instead of rsad

rsadx:         xor a
               ld (dct),a
rsadx1:        call ctas            ; confirm track and seek
               ld c,drsec
               call sadc            ; send a disk command
               call gtbuf           ; -> hl
               exx
               ld l,255             ; so the first inc l wraps to 0 and takes the rsadx3 path
               ld d,&77             ; the page holding sam
               exx
               push de
               call rsadx2
               call ldint           ; load interrupt status
               pop de
               rlca                 ; undo the rrca in comm.port.2, restoring the status byte
               call cdec            ; check disc err count
               jr rsadx1

rsadx2:        call svint           ; save interrupt status
               call commp           ; put disk command in c
               ld a,c
               ld (comm.port.1+1),a
               ld (comm.port.2+1),a
               add a,3
               ld (dtrq.port+1),a
               ld b,2               ; the data request mask, for the "and b" below
               jr comm.port.2

; The start of a new directory entry: point H' at sam's page if the entry is in use, or at ROM if it is not.

rsadx3:        ld h,d
               and a
               jr nz,rsadx4

               ld h,a
rsadx4:        exx
comm.port.1:   in a,(comm)
               and b
               jr z,comm.port.2

dtrq.port:     in a,(dtrq)
               ld (hl),a
               inc hl
               exx
               inc l
               jr z,rsadx3

               or (hl)
               ld (hl),a
               exx

; One status read serves both tests: the first rotate puts the busy bit in carry, the second the data request.

comm.port.2:   in a,(comm)
               rrca
               ret nc
               rra
               jp nc,comm.port.2

               jp dtrq.port


; ---------------------------------------------------------------------------------------------------------------------
; cdec -- act on the status of a completed transfer
;
; On success the return address of the caller's retry loop is discarded and control goes back to the routine that
; called wsad or rsad, with HL pointing at the buffer.
;
; On failure the retry count is bumped. A record-not-found means the head is not where the DOS thinks it is, so the
; position is re-established from the disk itself; anything else is treated as a soft error and the head is stepped
; back and forth once to reseat it before the caller tries again.
;
; Entry:  A = the controller status
; Errors: err.trkerr once disk.retries attempts have failed
; ---------------------------------------------------------------------------------------------------------------------

;CHECK DISC ERR COUNT

cdec:          and wd.st.errors
               jr nz,cde1
               call clrrpt
               pop hl               ; discard the retry loop's return address
               jp gtbuf             ; return to wsad's or rsad's caller

cde1:          push af
               ld a,(dct)
               inc a
               ld (dct),a
               cp disk.retries
               jp nc,rep4

               pop af
               bit wd.st2.rnf,a
               jr nz,ctsl

               call instp
               call outstp
               call outstp
               jp instp


; ---------------------------------------------------------------------------------------------------------------------
; ctsl -- re-establish where the head actually is
;
; Reads the next ID field to pass under the head and copies the track number it finds into the controller's track
; register, so that the next seek is measured from the truth rather than from the DOS's belief. Failing that, the
; head is stepped in, or the drive restored, and the read tried again.
;
; Errors: err.fmtlost after eight attempts
; ---------------------------------------------------------------------------------------------------------------------

;CONFIRM TRACK/SECTOR LOCATION

ctsl:          ld c,radd
               call sadc
               ld hl,dst
               call rddata
               and wd.st.errors
               jr nz,cts1
               call trckp
               ld a,(dst)
               out (c),a
               ret

cts1:          ld a,(dct)
               inc a
               ld (dct),a
               cp 8
               jp nc,rep5

               and 2                ; on every second attempt, restore the drive completely
               jr z,cts2

               push de
               call restx
               pop de
               jr ctsl

cts2:          call instp
               jr ctsl


; ---------------------------------------------------------------------------------------------------------------------
; ctas -- select the drive and side, then seek to track D
;
; A track/sector of 0,0 is the end-of-chain marker rather than a real address; reaching it while reading a file is
; the end of the file, which is an error only if the caller was not expecting it.
;
; Stepping is done by hand rather than with the controller's seek command, so that the DOS can watch for the address
; crossing &C000 -- see below.
;
; Entry:  D = track, E = sector
; Errors: err.eof if D and E are both zero and bit f3.block is not set
; ---------------------------------------------------------------------------------------------------------------------

;CONFIRM TRACK AND SEEK

ctas:          ld a,d
               or e
               jr nz,cta1
               call bitf2
               jp z,rep27

               ld sp,(entsp)
               xor a
               ld e,a
               ret

cta1:          call seld
               ld a,(dsc)
               inc a
               inc a
               ld c,a
               out (c),e            ; sector register
               call bcc

cta2:          ld a,d
               and &7f              ; the track alone, without the side bit
               ld b,a
               call busy
               call trckp
               in a,(c)
               cp b
               ret z


; A block transfer walks HL upwards through memory. When it reaches &C000 the address has run off the end of the
; section the page is mapped into, so the page is bumped and HL wound back to &8000. Doing it here, between steps,
; keeps it out of the transfer loop.

;CHECK IF PAGE OVER C000h

               push af

               call bitf6
               jr z,cta3

               ld hl,(svhl)
               ld a,h
               cp &c0
               jr c,cta3
               res 6,h              ; &C000 -> &8000
               ld (svhl),hl
               in a,(port.hmpr)
               push af
               and page.other
               ld b,a
               pop af
               inc a
               and page.mask
               or b
               ld (port1),a
               out (port.hmpr),a

cta3:          pop af
               call nc,outstp
               call c,instp
               jr cta2


; ---------------------------------------------------------------------------------------------------------------------
; stpdel -- wait for the head to settle after a step
;
; The delay is taken from stprat or stprt2 according to which drive is selected, so a slower drive can be given more
; time by poking the DOS variables. A value of zero means no delay at all.
; ---------------------------------------------------------------------------------------------------------------------

;STEP DELAY ROUTINE

stpdel:        push hl
               ld hl,stprat
               ld a,(dsc)
               bit 4,a              ; set for drive 2
               jr z,stpd1
               inc hl
stpd1:         ld a,(hl)
               pop hl
               and a

stpd2:         ret z

stpd3:         push af
               ld bc,150
stpd4:         dec bc
               ld a,b
               or c
               jr nz,stpd4
               pop af
               dec a
               jr stpd2


; ---------------------------------------------------------------------------------------------------------------------
; rest / restx -- move the head to track 0
;
; Rather than use the controller's restore command, this waits for the index hole to be seen going both ways -- which
; proves the disk is actually turning -- and then steps out until the track 0 signal appears. A disk that is not
; spinning fails the index test and reports "Check disk in drive" instead of hanging.
;
; restx exists only so that the routine has a second entry point one byte earlier; the nop is a placeholder.
; ---------------------------------------------------------------------------------------------------------------------

;RESTORE DISC DRIVE

restx:         nop

rest:          ld de,&0001
               call seld

;RESET DISC CHIP

               ld c,&d0             ; force interrupt, terminating anything in progress
               call sdcx
               ld b,0
rslp1:         djnz rslp1

;TEST FOR INDEX HOLE

               ld hl,0              ; timeout counter, shared by both index tests
rslp2:         call commr
               bit wd.st1.index,a
               call nz,rslpx
               jr nz,rslp2

rslp3:         call commr
               cpl
               bit wd.st1.index,a
               call nz,rslpx
               jr nz,rslp3

;TEST FOR TRACK 00

rslp4:         call commr
               bit wd.st1.track0,a
               jr nz,busy

;STEP OUT ONE TRACK

               call outstp
               jr rslp4

;TEST FOR CHIP BUSY

busy:          call commr
               bit wd.st.busy,a
               ret z
               call brktst
               jr busy

rslpx:         dec hl
               ld a,h
               or l
               ret nz

               jp rep6


; ---------------------------------------------------------------------------------------------------------------------
; sadc / sdcx -- send a command to the controller
;
; sadc waits for the previous command to finish first. The delay afterwards covers the controller's own latency in
; raising the busy flag, so that a status read taken immediately after does not see the previous command's result.
;
; Entry:  C = the command
; ---------------------------------------------------------------------------------------------------------------------

;SEND A DISC COMMAND

sadc:          call busy
sdcx:          ld a,c
               call commt
               ld b,20
sdc1:          djnz sdc1
               ret


; ---------------------------------------------------------------------------------------------------------------------
; ckdrv / ckdrx -- validate and select a drive number
;
; Drive 2 is only accepted if traks2 says one is fitted.
;
; Entry:  ckdrv takes the drive from dstr1; ckdrx takes it in A
; Errors: err.nodrive
; ---------------------------------------------------------------------------------------------------------------------

;CHECK DRIVE NUMBER

ckdrv:         ld a,(dstr1)

ckdrx:         cp 1
               jr z,ckdv1
               cp 2
               jp nz,rep22
               ld a,(rbcc+2) ; traks2
               cp 0
               jp z,rep22
               ld a,2
ckdv1:         ld (drive),a
               ret


; ---------------------------------------------------------------------------------------------------------------------
; seld -- build the controller's base port for the selected drive and side
;
; The drive select and side select lines are decoded from the high bits of the port address, so choosing a drive is a
; matter of choosing which port to talk to.
;
; Entry:  D = track, with bit 7 set for side 2
; Exit:   dsc holds the base port
; ---------------------------------------------------------------------------------------------------------------------

;SELECT DISC AND SIDE

seld:          ld a,(drive)
               cp 2
               ld b,%11100000
               jr nz,sel1
               ld b,%11110000

sel1:          ld a,d
               and disk.side2
               jr z,sel2
               ld a,%00000100
sel2:          or b
               ld (dsc),a
               ret


; ---------------------------------------------------------------------------------------------------------------------
; conm -- the position of a directory entry, as DIR prints it
;
; Entries are numbered from 1 across the whole directory: twenty to a track, two to a sector.
;
; Entry:  D = track, E = sector, (ix+rpth) = which of the two entries in the sector
; Exit:   A = the entry number
; ---------------------------------------------------------------------------------------------------------------------

;CONVERT DE INTO NUMBER

conm:          push de
               pop bc
               xor a
               dec b
               jp m,con2
con1:          add 10
               dec b
               jp p,con1
con2:          ld b,a
               sla b                ; 20 per track
               sla c
               dec c                ; 2 per sector, counting from 1
               ld a,(ix+rpth)
               add c
               add b
               ret


; ---------------------------------------------------------------------------------------------------------------------
; tfbf -- has the pointer reached the end of the sector's data area?
;
; The last two bytes of a sector are the link to the next one, so the data area is full when the pointer reaches
; disk.sctdata -- &01FE, tested as C = 254 and B = 1.
;
; Exit:   Z if the buffer is full, HL pointing at the current byte
; ---------------------------------------------------------------------------------------------------------------------

;TEST FOR BUFFER FULL

tfbf:          call grpnt
               ld a,c
               cp 254
               ret nz

tfbf1:         ld a,b
               cp 1
               ret

; ---------------------------------------------------------------------------------------------------------------------
; sbyt -- append one byte to the file being written  (hook code 148)
;
; When the buffer fills, a sector is allocated, its address written into the link bytes, and the buffer flushed.
;
; Entry:  A = the byte
; ---------------------------------------------------------------------------------------------------------------------

;SAVE A BYTE ON DISC

sbyt:          push bc
               push de
               push hl
               push af
               call tfbf
               jr nz,sbt1
sbt2:          call fnfs
               ld (hl),d
               inc hl
               ld (hl),e
               ex de,hl
               call swpnsr
               call wsad
sbt1:          pop af
               ld (hl),a
               pop hl
               pop de
               pop bc
               jp incrpt



; ---------------------------------------------------------------------------------------------------------------------
; lbyt -- read one byte from the file being read  (hook code 159)
;
; When the buffer is exhausted, the link at its end gives the next sector to read.
;
; Exit:   A = the byte
; ---------------------------------------------------------------------------------------------------------------------

;LOAD BYTE FROM DISC

lbyt:          push bc
               push de
               push hl
               call tfbf
               jr nz,lbt1
               ld d,(hl)
               inc hl
               ld e,(hl)
               call rsad
lbt1:          ld a,(hl)
               pop hl
               pop de
               pop bc
               jp incrpt


; =====================================================================================================================
; ldblk -- load a block from the open file  (hook code 161)
; =====================================================================================================================
;
; Two paths. While fewer than a sector's worth of bytes remain, or the buffer holds part of a sector already, bytes
; are moved one at a time through the buffer. Once at least disk.sctdata bytes are wanted, the sector is read
; straight into the caller's memory instead, which avoids copying it twice.
;
; The direct path still has to put the two link bytes somewhere. It uses both register sets: the main set holds the
; destination and a count of disk.sctdata, the alternate set the buffer and a count of 2, and the transfer loop
; switches between them with exx when the first count runs out. One loop, two destinations.
;
; Entry:  svhl = destination, DE = bytes wanted, pges1 = whole pages on top of that
; ---------------------------------------------------------------------------------------------------------------------

;LOAD BLOCK DATA from disc

ldblk:         call setf6
               jp lblok


ldb1:          ld a,(hl)
               call incrpt
               ld hl,(svhl)
               ld (hl),a
               inc hl
               dec de
lblok:         ld (svhl),hl
               call ckde
               ret z

ldb2:          call tfbf
               jr nz,ldb1

               ld (svde),de
               ld d,(hl)
               inc hl
               ld e,(hl)
               call svint

ldb3:          call ccnt
               jp c,ldb8            ; less than a whole sector left: finish byte by byte

               inc hl
               ld (svde),hl
               xor a
               ld (dct),a
               call svnsr
ldb4:          call ctas
               ld c,drsec
               call sadc
               exx
               call commp
               ld de,2              ; the alternate set takes the two link bytes
               call gtbuf
               exx
               call commp
               ld de,disk.sctdata   ; the main set takes the data
ldb4a:         ld hl,(svhl)
               jr ldb6

ldb5:          inc c
               inc c
               inc c
               ini
               dec c
               dec c
               dec c

               dec de
               ld a,d
               or e
               jr nz,ldb6
               exx                  ; this count is finished; switch to the other destination

ldb6:          in a,(c)
               bit wd.st2.drq,a
               jr nz,ldb5

               in a,(c)
               bit wd.st2.drq,a
               jr nz,ldb5

               in a,(c)
               bit wd.st2.drq,a
               jr nz,ldb5

               in a,(c)
               bit wd.st2.drq,a
               jr nz,ldb5

               in a,(c)
               bit wd.st2.drq,a
               jr nz,ldb5

               in a,(c)
               bit wd.st2.drq,a
               jr nz,ldb5

               bit wd.st.busy,a
               jr nz,ldb6

               and wd.st.errors
               jr z,ldb7

               call gtnsr
               call cde1
               jr ldb4

ldb7:          ld (svhl),hl
               call gtbuf
               ld d,(hl)
               inc hl
               ld e,(hl)
               jp ldb3

ldb8:          call ldint
               call rsad
               ld de,(svde)
               jp ldb2


; ---------------------------------------------------------------------------------------------------------------------
; ccnt -- is there at least a whole sector still to transfer?
;
; Exit:   NC and HL = what is left after this sector, or CY if fewer than disk.sctdata bytes remain
; ---------------------------------------------------------------------------------------------------------------------

;CALCULATE COUNT

ccnt:          ld hl,(svde)
               ld bc,disk.sctdata
ccnta:         scf
               sbc hl,bc
               ret nc
               ld a,(pges1)
               and a
               jr nz,ccnt1
               scf
               ret

ccnt1:         dec a
               ld (pges1),a
               ld hl,(svde)
               ld bc,page.size
               add hl,bc
               ld (svde),hl
               jr ccnt


; ---------------------------------------------------------------------------------------------------------------------
; getscr / putscr -- borrow the screen page as scratch memory
;
; A long save allocates all of its sectors up front and needs somewhere to keep the list. The screen page is large
; and, during a save, not being written to, so it is used as the list buffer. port1 remembers the caller's paging.
; ---------------------------------------------------------------------------------------------------------------------

;GET SCREEN MEMORY AND POINTER

getscr:        in a,(port.hmpr)
               ld (port1),a
               ld a,(port2)
               out (port.hmpr),a
               ld hl,(ptrscr)
               ret

;PUT SCREEN MEMORY AND POINTER

putscr:        ld (ptrscr),hl
               ld a,(port1)
               out (port.hmpr),a
               ret


; =====================================================================================================================
; svblk -- save a block to the open file  (hook code 150)
; =====================================================================================================================
;
; The mirror of ldblk, with one addition. Writing a sector needs its successor's address in the link bytes before the
; sector can be written, so the sectors cannot be allocated one at a time while streaming. Instead, once a whole
; sector's worth of data is available, every sector the rest of the block will need is allocated in advance and the
; addresses recorded in the screen page; the data is then written out against that list.
;
; Entry:  svhl = source, DE = bytes to write, pges1 = whole pages on top of that
; ---------------------------------------------------------------------------------------------------------------------

;SAVE DATA BLOCK ON DISC

svblk:         call setf6
               jp sblok

svb1:          ld (hl),d
               call incrpt
               ld hl,(svhl)
               inc hl
               pop de
               dec de

;TEST FOR ZERO BLOCK COUNT

sblok:         call ckde
               ret z

;SAVE CHAR IN REGISTER D

               push de
               ld d,(hl)
               ld (svhl),hl

;TEST FOR BUFFER FULL

               call tfbf
               jr nz,svb1

;SAVE BUFFER TO DISC

               pop de
               ld (svde),de
               call fnfs
               ld (hl),d
               inc hl
               ld (hl),e
               ex de,hl
               call swpnsr
               call wsad

               call svint
               call ccnt
               jp c,svb8

               call getscr
               ld hl,ftadd
               ld bc,0
               jr svb2a

; Allocate every sector the rest of the block needs, writing each track/sector pair into the screen page and
; counting them in svcnt.

svb2:          push hl
               call ccnt
               push hl
               pop de
               pop hl
               jr c,svb3
               inc de
               ld (svde),de
               call fnfs
               ld (hl),d
               inc hl
               ld (hl),e
               inc hl
               ld bc,(svcnt)
               inc bc
svb2a:         ld (svcnt),bc
               jr svb2

svb3:          ld hl,ftadd
               call putscr

; Write the data out. As in ldblk the two register sets carry two destinations: the alternate set feeds the two link
; bytes from the pre-allocated list in the screen page, the main set the data from the caller's memory.

svb3a:         xor a
               ld (dct),a
               call gtnsr

svb4:          call ctas
               call precmx
               exx
               ld hl,(ptrscr)
               ld de,2
               call commp
               exx
               ld hl,(svhl)
               ld de,disk.sctdata
svb4a:         call commp
               jr svb6

svb5:          inc c
               inc c
               inc c

               outi

               dec c
               dec c
               dec c

               dec de
               ld a,d
               or e
               jr nz,svb6

               exx                  ; switch to the link bytes, which live in the screen page
               ld a,(port2)
               out (port.hmpr),a

svb6:          in a,(c)
               bit wd.st2.drq,a
               jr nz,svb5

               in a,(c)
               bit wd.st2.drq,a
               jr nz,svb5

               in a,(c)
               bit wd.st2.drq,a
               jr nz,svb5

               in a,(c)
               bit wd.st2.drq,a
               jr nz,svb5

               in a,(c)
               bit wd.st2.drq,a
               jr nz,svb5

               in a,(c)
               bit wd.st2.drq,a
               jr nz,svb5

               bit wd.st.busy,a
               jr nz,svb6

               push af
               ld a,(port1)
               out (port.hmpr),a
               pop af

               and wd.st.errors
               jr z,svb7

               call gtnsr
               call cde1
               jr svb4

svb7:          ld (svhl),hl

               exx
               ld a,(port2)
               out (port.hmpr),a
               ld (ptrscr),hl
               dec hl
               ld e,(hl)
               dec hl
               ld d,(hl)
               ld a,(port1)
               out (port.hmpr),a
               call svnsr
               exx

               ld bc,(svcnt)
               dec bc
               ld (svcnt),bc
               ld a,b
               or c
               jp nz,svb3a

svb8:          call ldint
               call clrrpt
               ld de,(svde)
               ld hl,(svhl)
               jp svblk


; ---------------------------------------------------------------------------------------------------------------------
; fnfs -- allocate the next free sector
;
; Walks the global sector map a byte at a time, tracking the track and sector each bit stands for. A byte of &FF is
; eight used sectors and is skipped wholesale, with the track and sector advanced by eight. The first free bit found
; is claimed in both the global map and the file's own map, and the file's sector count is bumped.
;
; Exit:   D = track, E = sector of the sector just claimed
; Errors: err.nospace when the map runs past the last track
; ---------------------------------------------------------------------------------------------------------------------

;FIND NEXT FREE SECTOR

fnfs:          push hl
               push bc
               ld hl,sam
               ld de,disk.dirtrks*256+1   ; the first sector after the directory
               ld c,0

fns1:          ld a,(hl)
               cp &ff
               jr nz,fns3
               ld a,e
               add 8
               ld e,a
fns1a:         sub disk.sectors
fns1b:         jr c,fns2
               jr z,fns2
               ld e,a
               call fns5
fns2:          inc c
               inc hl
               jr fns1

fns3:          ld b,1
fns4:          ld a,(hl)
               and b
               jr z,fns6
               call isect
               call z,fns5
               rlc b
               jr fns4

fns5:          inc d
               call tstd
               cp d
               call z,decsam
               jp z,rep24
               and &7f
               cp d
               ret nz
               ld d,disk.side2      ; off the end of side 1: continue at track 0 of side 2
               ret

fns6:          ld a,(hl)
               or b
               ld (hl),a
               ld a,b
               ld b,0
               push ix
               add ix,bc
               or (ix+fsam)
               ld (ix+fsam),a
               pop ix
               inc (ix+cntl)
               jr nz,fns7
               inc (ix+cnth)
fns7:          pop bc
               pop hl
               ret


; ---------------------------------------------------------------------------------------------------------------------
; tstd -- how many tracks the selected drive has
;
; Exit:   A = the track count, with bit 7 set if the drive is double sided
; ---------------------------------------------------------------------------------------------------------------------

;TEST TRACKS ON DISC

tstd:          push hl
               ld hl,traks1
               ld a,(dsc)
               bit 4,a              ; set for drive 2
               jr z,tsd1
               inc hl
tsd1:          ld a,(hl)
               pop hl
               ret


; ---------------------------------------------------------------------------------------------------------------------
; pfnme -- print the file name of the directory entry in the buffer
;
; Spaces are printed as chdir, so a program can make the padding visible by poking that variable.
; ---------------------------------------------------------------------------------------------------------------------

;PRINT FILE NAME

pfnme:         ld (ix+rptl),de.name
               call grpnt
               ld b,de.namelen
pfnm1:         ld a,(hl)
               cp " "
               jr nz,pfnm2
               ld a,(chdir)
pfnm2:         call pnt
               inc hl
               djnz pfnm1
               ret


; =====================================================================================================================
; fdhr -- scan the directory
; =====================================================================================================================
;
; The one routine behind DIR, file lookup, and finding a free slot. What it does is selected by the mode byte, which
; is kept at (ix+4) so that the inner code can test it without reloading: see the fdh.* equates in a.s.
;
; The scan covers tracks 0 to disk.dirtrks-1 of side 1, ten sectors to a track and two entries to a sector. It reads
; through rsadx rather than rsad, so the free-sector map is rebuilt as a side effect.
;
; Entry:  A = the mode byte
; Exit:   Z if the entry sought was found, with IX addressing it; NZ at the end of the directory
; ---------------------------------------------------------------------------------------------------------------------

;FILE DIR HAND/ROUT.

fdhr:          ld ix,dchan
               ld (ix+4),a
               xor a
               ld (svdpt),a
               call rest
fdh1:          call rsadx
fdh2:          call point
               ld a,(hl)
               and a
               jp z,fdhf            ; a free entry

;TEST FOR 'P' NUMBER

               bit fdh.number,(ix+4)
               jr z,fdh3
               call conm
               ld b,a
               ld a,(fstr1)
               cp b
               ret z
               jp fdhd

;GET TRACK AND SECTOR COUNT

fdh3:          bit fdh.compact,(ix+4)
               jr nz,fdh4
               bit fdh.list,(ix+4)
               jp z,fdh9
fdh4:          ld (ix+rptl),de.count
               call grpnt
               ld b,(hl)
               inc hl
               ld c,(hl)
               ld (svbc),bc
               ld hl,(cnt)
               add hl,bc
               ld (cnt),hl          ; running total of sectors, for the free space figure

;TEST IF WE SHOULD PRINT NAME

               bit de.hidebit,a
               jp nz,fdhd           ; hidden files are not listed

               call cknam
               jp nz,fdhd
               bit fdh.compact,(ix+4)
               jr nz,fdh5

               call point
               ld a,(hl)
               bit de.protectbit,a
               jr z,fdh4a
               call spc
               ld a,"*"             ; protected files show a star in place of their number
               call pnt
               call spc
               jr fdh5

fdh4a:         call conm
               push de
               ld h,0
               ld l,a
               ld a," "
               call pnum2
               pop de
               call spc

;PRINT FILE NAME

fdh5:          call pfnme

;FORMAT FOR ! PRINTOUT
; DIR ! prints names only, in as many columns as the screen mode allows: three normally, six in the 32-column mode.

               bit fdh.compact,(ix+4)
               jr z,fdh7
               ld b,3
               in a,(port.vmpr)
               and %01100000
               cp %01000000
               jr nz,fdh6a
               sla b
               dec b
fdh6a:         ld a,(svdpt)
               inc a
               cp b
               jr z,fdh6b
               ld (svdpt),a
               ld a,32
               jr fdh6c

fdh6b:         xor a
               ld (svdpt),a
               ld a,13
fdh6c:         call pnt
               jr fdhd

;PRINT SECTOR COUNT

fdh7:          push de
               ld hl,(svbc)
               ld a," "
               call pnum3
               call spc

;PRINT TYPE OF FILE

               call point
               ld a,(hl)
               call pntyp
               pop de
               jr fdhd

;TEST FOR SPECIFIC FILE NAME

fdh9:          bit fdh.wild,(ix+4)
               jr nz,fdha

;TEST FOR FILE NAME ONLY

               bit fdh.name,(ix+4)
               jr z,fdhb

fdha:          call cknam
               ret z

;LOAD SAM FROM FILES USED
; Once done here, entry by entry. rsadx now accumulates the map during the read instead, so nothing is left to do.

fdhb:          nop

;CALCULATE NEXT DIRECTORY ENTRY

fdhd:          ld a,(ix+rpth)
fdhd1:         cp 1
fdhd2:         jr z,fdhe
               call clrrpt
               inc (ix+rpth)
               jp fdh2

fdhe:          call isect
               jp nz,fdh1
               inc d
               ld a,d
               cp disk.dirtrks
               jp nz,fdh1
               and a                ; a = disk.dirtrks, so this leaves NZ: end of directory
               ret

; A free entry. With fdh.free set this is what the caller wanted, so return Z. Otherwise it is a deleted file: the
; scan continues, unless the second byte is zero too, which marks an entry that has never been used and therefore
; the end of the directory.

;TEST FOR FREE DIRECTORY SPACE

fdhf:          ld a,(ix+4)
               cpl
               bit fdh.free,a
               ret z

               inc hl
               ld a,(hl)
               and a
               jr nz,fdhd
               inc a
               ret


; ---------------------------------------------------------------------------------------------------------------------
; cknam -- compare the name in the directory entry with the one in nstr1
;
; The comparison covers the type byte and the ten name characters, and ignores case by masking bit 5. With fdh.wild
; set, "?" matches any single character and "*" matches everything up to a "." -- so "*.bak" works, and a bare "*"
; matches every file.
;
; Exit:   Z if the names match
; ---------------------------------------------------------------------------------------------------------------------

;CHECK FILE NAME IN DIR

cknam:         push ix
               call point
               ld b,de.namelen+1    ; the type byte and the name
               bit fdh.wild,(ix+4)
               ld ix,nstr1
               jr z,cknm2

cknm1:         ld a,(ix)
               cp "*"
               jr z,cknm5
               cp "?"
               jr z,cknm2
               xor (hl)
               and &df              ; ignore the case bit
               jr nz,cknm4
cknm2:         inc ix
               inc hl
               djnz cknm1
cknm3:         xor a
cknm4:         pop ix
               ret

cknm5:         inc ix
               inc hl
               ld a,(ix)
               cp "."
               jr nz,cknm3          ; "*" with nothing after it matches the rest of the name
cknm6:         ld a,(hl)            ; "*." skips forward to the "." in the entry
               cp "."
               jr z,cknm2
               inc hl
               djnz cknm6
               jr cknm4


; ---------------------------------------------------------------------------------------------------------------------
; ofsm -- open a file for writing
;
; Clears the global sector map, then scans the directory: that rebuilds the map from every file present and, if a
; file of the same name is found, offers to overwrite it. The offer is skipped when SAVE OVER was used, in which
; case the old entry is simply deleted.
;
; Once a free entry is found, the entry image is cleared and filled in with the name and the header, and the file's
; first sector is allocated.
;
; Exit:   NC and the file is open; CY if the user declined to overwrite
; Errors: err.dirfull indirectly, through the caller
; ---------------------------------------------------------------------------------------------------------------------

;OPEN FILE SECTOR ADDRESS MAP

ofsm:          push ix
               ld hl,sam
               ld b,disk.sammax
ofm1:          ld (hl),0
               inc hl
               djnz ofm1
               ld a,1<<fdh.name | 1<<5

ofm2:          call fdhr
               jr nz,ofm4

;FILE NAME ALREADY USED

               push de
               call nrrd
               defw overf
               and a
               jr z,ofm3            ; SAVE OVER: delete the old file without asking

               push ix
               call cmr
               defw clslow
               call pmo5
               pop ix

               push ix
               call pfnme
               call pmo7
               call cyes
               pop ix
               jr z,ofm3

               pop de
               pop ix
               scf
               ret

ofm3:          pop de
               call point
               ld (hl),0
               call wsad
               pop ix
               jr ofsm              ; rescan, so the map no longer includes the deleted file

;NOW CLEAR FILE SECTOR AREA

ofm4:          pop ix

               push ix
               ld b,0               ; 256 iterations: the whole entry image
ofm5:          ld (ix+ffsa),0
               inc ix
               djnz ofm5
               pop ix

               push ix
               ld hl,nstr1
               ld b,de.namelen+1
               call ofm6
               pop ix

               push ix
               ld bc,de.tail
               add ix,bc
               ld hl,uifa+hdr.flags
               ld b,hdr.size-hdr.flags
               call ofm6
               pop ix

               call fnfs
               call svnsr
               ld (ix+ftrk),d
               ld (ix+fsct),e
               call clrrpt
               xor a
               ret

ofm6:          ld a,(hl)
               ld (ix+ffsa),a
               inc hl
               inc ix
               djnz ofm6
               ret

; Placeholder for releasing sectors back to the map. Never did anything, and is called only where the disk is
; already known to be full.

decsam:        ret


; ---------------------------------------------------------------------------------------------------------------------
; cyes -- wait for a yes or no answer
;
; Exit:   Z if the key was Y in either case
; ---------------------------------------------------------------------------------------------------------------------

;COMPARE FOR Y or N

cyes:          call beep
cyes1:         call cmr
               defw rdkey
               jr nc,cyes1
               and &df
               cp "Y"
               push af
cyes2:         call cmr
               defw rdkey
               jr c,cyes2           ; wait for the key to be released
               call cmr
               defw clslow
               pop af
               ret

beep:          push hl
               push de
               push bc
               push ix
               ld hl,&036a
               ld de,&0085
               call cmr
               defw beepr
               pop ix
               pop bc
               pop de
               pop hl
               ret


; ---------------------------------------------------------------------------------------------------------------------
; cfsm -- close the file being written  (hook code 152)
;
; The remainder of the buffer is zeroed and written out with a link of 0,0 to end the chain, then the directory entry
; built up in the entry image is written into the free slot found earlier.
;
; Errors: err.dirfull if no free entry can be found
; ---------------------------------------------------------------------------------------------------------------------

;CLOSE FILE SECTOR MAP

cfsm:          call grpnt
               ld a,c
               and a
               jr nz,cfm1
               ld a,b
cfsm1:         cp 2
cfsm2:         jr z,cfm2
cfm1:          ld (hl),0
               call incrpt
               jr cfsm

cfm2:          call gtnsr
               call wsad
               call decsam
               push ix
               ld a,1<<fdh.free
               call fdhr

               jp nz,rep25

;UPDATE DIRECTORY

               call point
               ld (svix),ix
               pop ix
               push ix

               ld b,0               ; 256 bytes: the whole entry
cfm3:          ld a,(ix+ffsa)
               ld (hl),a
               inc ix
               inc hl
               djnz cfm3

               ld ix,(svix)
               call wsad
               pop ix
               ret


; =====================================================================================================================
; gtfle -- open a file for reading
; =====================================================================================================================
;
; Finds the file, either by the number DIR would print or by name, and unpacks its directory entry into the header
; buffers. Types below 16 are Spectrum files: they are renumbered into the SAM range and flagged so that the loader
; knows to treat them differently.
;
; The requested and stored types must agree, with one exception: code and SCREEN$ are interchangeable, so a screen
; can be loaded as code and vice versa. The ROM's tape loader makes the same allowance.
;
; Errors: err.notfound, err.badtype
; ---------------------------------------------------------------------------------------------------------------------

;GET A FILE FROM DISC

gtfle:         ld a,(fstr1)

;TEST FOR FILE NUMBER

               cp &ff
               jr z,gtfl3

               ld a,1<<fdh.number
               call fdhr
               jp nz,rep26

gtflx:         call point
               ld a,(hl)
               and de.typemask
               cp ft.basic
               jr nc,gtfl1
               dec a
               or ft.basic          ; a Spectrum type: move it into the SAM range
               call setf7

gtfl1:         ld (hl),a
               ld de,nstr1
               ld bc,de.namelen+1
               ldir
               ld b,4
               ld a,0
               call lcntb

               ld (ix+rptl),de.hdr
               call grpnt
               ld bc,9
               ldir

               call point
               ld de,uifa
               ld bc,de.namelen+1
               ldir

               ld b,15
               call lcnta

               ld b,hdr.size-26
               ld a,&ff
               call lcntb

               jr gtfl4

gtfl3:         ld a,1<<fdh.name
               call fdhr
               jp nz,rep26

gtfl4:         call point
               ld a,(hl)
               and de.typemask
               cp ft.basic
               jr nc,gtfl5
               dec a
               or ft.basic
               call setf7

; Code and SCREEN$ are treated as the same type for the purpose of the check below.

gtfl5:         ld (hl),a
               ld a,(nstr1)
               cp ft.code
               jr nz,gtfl5a
               ld a,(hl)
               cp ft.screen
               jr nz,gtfl5c
               dec a
               jr gtfl5b

gtfl5a:        cp ft.screen
               jr nz,gtfl5c
               ld a,(hl)
               cp ft.code
               jr nz,gtfl5c
               inc a
gtfl5b:        ld (hl),a

gtfl5c:        ld a,(nstr1)
               cp (hl)
               jp nz,rep13

               ld de,hd002
               ld (ix+rptl),de.hdr
               call grpnt
               ld bc,9
               ldir

               ld de,str-20
               ld bc,22
               ldir

               call point
               ld de,difa
               ld bc,de.namelen+1
               ldir
               ld b,4
               call lcnta

               call bitf7
               jr z,gtfl7

; A Spectrum file: its length and start are plain 16-bit numbers, so convert them to the page form the rest of the
; DOS works in.

               ld b,de.namelen+1
               call lcnta

               ld b,hdr.size-26
               ld a,&ff
               call lcntb

               ld hl,(hd0b2)
               call conp
               ld (difa+34),a
               ld (pges2),a
               ld (difa+35),hl
               ld (hd0b2),hl

               ld hl,(hd0d2)
               call conp
               dec a
               and page.mask
               ld (difa+31),a
               ld (page2),a
               set 7,h
               ld (difa+32),hl
               ld (hd0d2),hl

               jr gtfl8

gtfl7:         ld (ix+rptl),de.tail
               call grpnt
               ld bc,hdr.size-hdr.flags
               ldir

gtfl8:         ld (ix+rptl),de.track
               call grpnt
               ld d,(hl)
               inc hl
               ld e,(hl)
               ld (svde),de
               ret

; ---------------------------------------------------------------------------------------------------------------------
; conp -- split a 16-bit address into a page number and an offset within it
;
; Exit:   A = whole pages, HL = the remainder
; ---------------------------------------------------------------------------------------------------------------------

;CONVERT TO REAL PAGE AND MOD

conp:          xor a
               rl h
               rla
               rl h
               rla
               rr h
               rr h
               ret


; ---------------------------------------------------------------------------------------------------------------------
; lcnta / lcntb -- fill B bytes at DE, with a space or with the value in A
; ---------------------------------------------------------------------------------------------------------------------

;LOAD DE WITH COUNT B

lcnta:         ld a," "

lcntb:         ld (de),a
               inc de
               djnz lcntb
               ret


; ---------------------------------------------------------------------------------------------------------------------
; The pointer arithmetic every routine above shares
;
; gtixd   point IX at the channel record and the buffer at dram
; clrrpt  reset the pointer to the start of the buffer
; gtbuf   HL = the buffer address
; point   reset the low byte of the pointer and return HL pointing at the current directory entry
; grpnt   HL = buffer + pointer, BC = the pointer
; incrpt  advance the pointer by one
; ---------------------------------------------------------------------------------------------------------------------

;GET BUFFER ADDRESS

gtixd:         ld ix,dchan
               ld hl,dram
               ld (buf),hl

;CLEAR RAM POINTER

clrrpt:        ld (ix+rptl),0
               ld (ix+rpth),0
               ret


gtbuf:         ld l,(ix+bufl)
               ld h,(ix+bufh)
               ret


;GET RAM AND POINTER TO BUFFER

point:         ld (ix+rptl),0

grpnt:         call gtbuf
               ld b,(ix+rpth)
               ld c,(ix+rptl)
               add hl,bc
               ret


;INCREMENT RAM POINTER

incrpt:        inc (ix+rptl)
               ret nz
               inc (ix+rpth)
               ret


; ---------------------------------------------------------------------------------------------------------------------
; gtnsr / svnsr / swpnsr -- the link to the next sector of the file
; ---------------------------------------------------------------------------------------------------------------------

;GET THE NEXT TRACK/SECTOR

gtnsr:         ld d,(ix+nsrh)
               ld e,(ix+nsrl)
               ret

;SAVE THE NEXT TRACK/SECTOR

svnsr:         ld (ix+nsrh),d
               ld (ix+nsrl),e
               ret

;SWAP THE NEXT TRACK/SECTOR

swpnsr:        call gtnsr
               ld (ix+nsrh),h
               ld (ix+nsrl),l
               ret


; ---------------------------------------------------------------------------------------------------------------------
; instp / outstp -- step the head one track, waiting for it to settle
; ---------------------------------------------------------------------------------------------------------------------

outstp:        ld c,stpout
               jr step

instp:         ld c,stpin

step:          call sadc
               jp stpdel
