

; =====================================================================================================================
; H.S -- The hook routines, and file name parsing
; =====================================================================================================================
;
; The routines samhk in b.s dispatches to. Between them they are the whole of the interface the ROM uses to save and
; load files: the ROM parses the command, fills in its header buffer, and then calls the DOS to do the work.
;
;   rxhed / txinf / txhed  move a header between the ROM's buffer and the DOS's
;   hgthd / hgfle          open a file for reading and hand back its header
;   hload / hldbk          load the body
;   hvery                  verify the body against memory
;   hsave / hofle / hsvbk  save
;   heraz                  erase
;   hdir                   catalogue
;   hvar                   the DVAR function
;   hrsad / hwsad / cals   raw sector access
;   init / initx / hauto   boot, and the auto-load file
;   hconr / gtdef / evfile turn a header or a typed name into the DOS's parameter block
;
; hopen, hclos, heof, hptr, hpath, pntp, cops1, cops2 and s are all bare RETs: SAMDOS 2 has no record-structured
; channels, so the ROM's OPEN, CLOSE, EOF, PTR and PATH$ do nothing rather than failing.
; =====================================================================================================================


;HOOK CODE ROUTINES


; ---------------------------------------------------------------------------------------------------------------------
; rxhed -- read the ROM's header buffer into uifa
;
; IX was saved into svhdr when the hook was entered, and points at the ROM's HDR. The buffer lives in the system
; page, so every byte goes through the ROM's read helper.
; ---------------------------------------------------------------------------------------------------------------------

;INPUT A HEADER FROM IX

rxhed:         push bc
               push de
               push hl

               ld hl,(svhdr)
               ld b,hdr.size
               ld de,uifa

rxhd1:         call cmr
               defw nrread
               ld (de),a
               inc hl
               inc de
               djnz rxhd1

               pop hl
               pop de
               pop bc
               jp hconr



; ---------------------------------------------------------------------------------------------------------------------
; txinf / txhed / txrom -- write a header back to the ROM
;
; uifa is the header the caller asked for and goes to the ROM's HDR; difa is the one read from the disk and goes to
; HDL, which is rom.hdl-rom.hdr bytes further on. The ROM then compares the two exactly as it would for a tape file.
; ---------------------------------------------------------------------------------------------------------------------

;OUTPUT DIFA TO ROMUIFA

txinf:         ld a,0
               ld de,uifa
               jr txrom

;OUTPUT DIFA TO ROMDIFA

txhed:         ld a,rom.hdl-rom.hdr
               ld de,difa

;OUTPUT A HEADER

txrom:         ld hl,rom.hdr
               ld b,0
               ld c,a
               add hl,bc
               ld b,hdr.size

txrm1:         ld a,(de)
               call cmr
               defw nrrite
               inc hl
               inc de
               djnz txrm1

               ret


; ---------------------------------------------------------------------------------------------------------------------
; hgthd -- open a file and return its header  (hook code 129)
;
; The length is handed back with bit 15 of its address word set, which is the form the ROM expects for something in
; the &8000 window.
; ---------------------------------------------------------------------------------------------------------------------

hgthd:         call rxhed
               call ckdrv
               call gtixd
               call gtfle
               ld de,(difa+hdr.length+1)
               set 7,d
               ld (difa+hdr.length+1),de
               call txhed
               ret


; ---------------------------------------------------------------------------------------------------------------------
; hload -- load the body of an open file  (hook code 130)
; ---------------------------------------------------------------------------------------------------------------------

hload:         call dschd
               jp ldblk


; ---------------------------------------------------------------------------------------------------------------------
; dschd -- position at the start of the file's data and take the transfer parameters from the hook registers
;
; The nine-byte header at the front of the file is read and discarded; what the caller asked for -- address, length
; and page count -- overrides what the file says, so a file can be loaded somewhere other than where it was saved.
; ---------------------------------------------------------------------------------------------------------------------

dschd:         call gtixd
               ld de,(svde)
               call rsad
               call ldhd

               ld hl,(hkhl)
               ld (hd0d1),hl

               ld bc,(hkbc)
               ld a,c
               ld (pges1),a

               ld de,(hkde)
               res 7,d
               ld (hd0b1),de

               ret


; ---------------------------------------------------------------------------------------------------------------------
; hvery -- verify a file against memory  (hook code 131)
;
; Compares byte by byte rather than loading. The address walks upwards and is wound back from &C000 to &8000 with the
; page bumped, the same fix-up ctas applies during a block transfer.
;
; Errors: err.verify at the first difference
; ---------------------------------------------------------------------------------------------------------------------

;VERIFY FILE

hvery:         call dschd

               ld (ix+rptl),9      ; skip the file's own nine-byte header
hver1:         ld a,d
               or e
               jr nz,hver2

               ld a,c
               and a
               ret z

               dec c
               ld de,page.size

hver2:         call lbyt

               cp (hl)
               jp nz,rep12

               dec de
               inc hl
               ld a,h
               cp &c0
               jr c,hver1
               res 6,h
               in a,(port.hmpr)
               push af
               and page.other
               ld b,a
               pop af
               inc a
               and page.mask
               or b
               out (port.hmpr),a
               jr hver1


; ---------------------------------------------------------------------------------------------------------------------
; hsave -- save a file  (hook code 132)
;
; The page the data lives in comes from the header, so the caller's paging is saved, the data's page mapped in for
; the transfer, and the caller's restored afterwards.
; ---------------------------------------------------------------------------------------------------------------------

hsave:         call setf3
               call rxhed
               call ckdrv

               in a,(port.hmpr)
               ld (port3),a
               and page.other
               ld b,a
               ld a,(uifa+hdr.start)
               and page.mask
               or b
               out (port.hmpr),a

               call gtixd
               call ofsm
               jr c,hsave1         ; the user declined to overwrite
               call svhd
               ld hl,(hd0d1)
               ld de,(hd0b1)
               call svblk
               call cfsm

hsave1:        ld a,(port3)
               out (port.hmpr),a
               ret

hdir:          call rxhed
               ld a,(hka)
               jp pcat

hopen:         ret

hclos:         ret

heof:          ret

hptr:          ret

hpath:         ret


; ---------------------------------------------------------------------------------------------------------------------
; hvar -- the DVAR function  (hook code 139)
;
; Returns the address of DOS variable n, so that a program can PEEK and POKE the block at dvar in b.s.
;
; The answer has to be a full linear address -- the DOS's page times the page size, plus the offset -- which does not
; fit in sixteen bits, so it is stacked as a floating-point number. The value is normalised by shifting A:HL left
; until its top bit is set, decrementing the exponent each time; starting the exponent at &96 makes the arithmetic
; come out at exactly the address.
; ---------------------------------------------------------------------------------------------------------------------

hvar:          call cmr
               defw getint
               ld hl,dvar
               add hl,bc
               call nrrd
               defw dosflg
               inc a               ; the page the DOS occupies
               add hl,hl
               add hl,hl           ; the offset within it, scaled to line up with the page number
               ld b,&96

hvar1:         dec b
               add hl,hl
               rla
               bit 7,a
               jr z,hvar1

               res 7,a             ; the leading bit is implicit in the ROM's number format
               ld e,a
               ld a,b
               ld d,h
               ld c,l
               ld b,0
               call cmr
               defw stkstr

               ret


; The file name the auto-load hook looks for, laid out as a ready-made parameter block so that a single copy sets up
; drive, device, type and name together.

autnam:        defb 1
               defb &ff
               defb &ff
               defb "D"
               defb ft.basic
               defm "AUTO*     "
               defm "    "
               defb 0
               defw &ffff
               defw &ffff
               defw &ffff
               defw &ffff


; ---------------------------------------------------------------------------------------------------------------------
; init / initx -- boot, and load the auto-load file  (hook codes 128 and 136)
;
; init falls straight through into initx, so both do the same thing. The ROM's idea of the command in progress is
; set to LOAD, because what follows behaves exactly as though the user had typed one.
; ---------------------------------------------------------------------------------------------------------------------

init:          nop
initx:         ld a,lodtok   ; LOAD
               call nrwr
               defw curcmd ; Current Basic command.


;LOOK FOR AN AUTO FILE


hauto:         ld hl,autnam
               ld de,dstr1
               ld bc,28            ; the size of one parameter block: dstr1 through page1
               ldir
               call gtdef
               call ckdrv
               call gtixd

               ld a,1<<fdh.name
               call fdhr
               jp nz,rep20

               call gtflx
               jp autox


; ---------------------------------------------------------------------------------------------------------------------
; The remaining hooks, each a thin wrapper on a routine in c.s
; ---------------------------------------------------------------------------------------------------------------------

;HOOK OPEN FILE

hofle:         call rxhed
               call ofsm
               ret c
               call svhd
               ret


hsvbk:         jp svblk


hgfle:         call rxhed
               call gtfle
               ld de,(svde)
               call rsad
               call ldhd
               ret

hldbk:         jp ldblk


heraz:         call rxhed
               call ckdrv
               call findc
               jp nz,rep26
               ld (hl),0
               jp wsad


; ---------------------------------------------------------------------------------------------------------------------
; hrsad / hwsad -- read and write a sector at a given address  (hook codes 160 and 149)
;
; The transfer goes through the DOS's own buffer and is then copied to or from the caller's memory, because the
; caller's address may be in a page that cannot be mapped at the same time as the DOS.
;
; Entry:  hka = drive, hkde = track and sector, hkhl = the caller's address
; ---------------------------------------------------------------------------------------------------------------------

;HOOK READ SECTOR AT DE

hrsad:         ld a,(hka)
               call ckdrx
               call gtixd
               ld de,(hkde)
               call rsad
               ld de,dram
               ld bc,disk.sctsize
hrsd1:         ld hl,(hkhl)
               call cals
               ex de,hl
               ldir
               ld a,(port1)
               out (port.hmpr),a
               ret



;HOOK WRITE SECTOR AT DE

hwsad:         ld a,(hka)
               call ckdrx
               ld de,dram
               ld bc,disk.sctsize
hwsd1:         ld hl,(hkhl)
               call cals
               ldir
               ld a,(port1)
               out (port.hmpr),a
               call gtixd
               ld de,(hkde)
               call wsad
               ret


; ---------------------------------------------------------------------------------------------------------------------
; cals -- map the caller's address into the &8000 window
;
; Splits the address into the page it falls in and an offset within the &8000-&BFFF window, maps that page, and
; returns the offset in HL. An address below &4000 has no page of its own and is rejected.
;
; Exit:   HL = the address to use, port1 = the caller's paging
; Errors: err.nonsense for an address below &4000
; ---------------------------------------------------------------------------------------------------------------------

;CALCULATE ADDRESS SECTION

cals:          in a,(port.hmpr)
               ld (port1),a
               ld a,h
               and %11000000
               jp z,rep0
               sub %01000000
               rlca
               rlca
               out (port.hmpr),a
               ld a,h
               and %00111111
               or %10000000
               ld h,a
               ret


pntp:          ret

cops1:         ret

cops2:         ret

s:             ret



; ---------------------------------------------------------------------------------------------------------------------
; hconr -- turn the header the ROM supplied into the DOS's parameter block
;
; The ROM's header carries the name, type, start and length; the DOS needs them spread across nstr1, hd001, page1,
; pges1 and the rest. evfile is called first, which also strips any drive prefix from the name.
; ---------------------------------------------------------------------------------------------------------------------

;CONVERT NEW HDR TO OLD

hconr:         call resreg

               ld hl,uifa+hdr.name

               call evfile

               ld a,(uifa+hdr.type)
               ld (nstr1),a
               ld (hd001),a

               ld a,(uifa+hdr.start)
               ld (page1),a

               ld hl,(uifa+hdr.start+1)
               ld (hd0d1),hl

               ld a,(uifa+hdr.length)
               and page.mask
               ld (pges1),a

               ld hl,(uifa+hdr.length+1)
               res 7,h
               ld (uifa+hdr.length+1),hl
               ld (hd0b1),hl

               ret


; ---------------------------------------------------------------------------------------------------------------------
; gtdef -- take the default device and drive from the ROM's variables
;
; These are what DEVICE sets, so a program can change the drive every command uses without naming it each time.
; ---------------------------------------------------------------------------------------------------------------------

;GET DEFAULTS IN VARIABLE AREA

gtdef:         call nrrd
               defw devl
               ld (lstr1),a
               call nrrd
               defw devn
               ld (dstr1),a
               ret


; ---------------------------------------------------------------------------------------------------------------------
; evfile -- strip a device and drive prefix from a file name
;
; Accepts "d:name", "d1:name" and "d12:name", where the letter is the device and the digits the drive; anything that
; does not fit is taken to be part of the name, and the defaults stand. The name is then shuffled down over the
; prefix in place and padded with spaces.
;
; Entry:  HL = the name, in the nstr1 buffer
; Errors: err.baddev if the device is not "D"
; ---------------------------------------------------------------------------------------------------------------------

;EVALUATE FILE INFORMATION

evfile:        call gtdef

               ld (svhl),hl
               ld a,(hl)
               and &df             ; force the device letter to upper case

;CHECK FOR FIRST DIGIT

evfl1:         ld c,a
               inc hl
               ld a,(hl)
               cp ":"
               jr z,evfl3          ; "d:" -- device only
               sub "0"
               cp 10
               jr nc,evfl4

;CHECK FOR SECOND DIGIT

               ld d,a
               inc hl
               ld a,(hl)
               cp ":"
               jr z,evfl2          ; "d1:"
               sub "0"
               cp 10
               jr nc,evfl4

;EVALUATE NUMBER

               ld e,a

               ld a,d
               add a,a
               add a,a
               add a,d
               add a,a
               add a,e             ; a = d*10 + e
               ld d,a
               inc hl

;CHECK FOR ':'

               ld a,(hl)
               cp ":"
               jr nz,evfl4

evfl2:         ld a,d
               ld (dstr1),a
evfl3:         ld a,c
               ld (lstr1),a
               inc hl
               jr evfl5

evfl4:         ld hl,(svhl)        ; no prefix after all: start again from the first character

;FILE NAME START

evfl5:         ld bc,de.namelen
               ld de,nstr1+1

evfl6:         ldir

               ld b,4
               call lcnta

               ld a,(lstr1)
               cp "D"
               ret z
               jp rep10

zzend:         equ $
