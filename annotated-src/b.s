
; =====================================================================================================================
; B.S -- Boot sector, DOS variables, buffers and the three entry points
; =====================================================================================================================
;
; This file establishes the whole layout of the DOS image. It falls into four parts, each pinned to a fixed address
; by an org/dump pair:
;
;   &4000   the boot sector: the first 510 bytes of the image, which the ROM loads to &8000 and calls
;   &4100   the DOS variables exposed by the DVAR function, printer control codes, and the file name and header
;           buffers that every command works through
;   &4200   the three entry points the ROM calls: hook, syntax and nmi
;   &4220   the syntax handler and the hook dispatcher
;
; ---------------------------------------------------------------------------------------------------------------------
; org, dump and org.adjust
; ---------------------------------------------------------------------------------------------------------------------
;
; The image can be built either as a raw 10000-byte block or with a 9-byte disk file header on the front. The header
; is not wanted for the released binary, so include-header is left undefined and org.adjust is 9: the header bytes
; are not emitted, but the assembly address is advanced past where they would have been, and every later dump
; subtracts org.adjust so the file offsets close the gap again. The result is that addresses are the same in both
; builds while the file is 9 bytes shorter in one of them.
; =====================================================================================================================

; boots at &8000, normally at &4000

               org gnd+&4000
               dump gnd.bank,&0000

; The four WD1772 registers, at consecutive ports. Only the boot sector uses these names directly; the rest of the
; DOS computes the port from dsc, which carries the drive and side selection in its high bits. See commp in c.s.

comm:          equ 224        ; write: command; read: status
trck:          equ 225        ; track register
sect:          equ 226        ; sector register
dtrq:          equ 227        ; data register

if defined (include-header)

    ; disk file header

               defb 3
               defw 0
               defw 0
               defw 0
               defb 0
               defb 0

    org.adjust: equ 0

else

    org.adjust: equ 9

               org $ + org.adjust

endif


; ---------------------------------------------------------------------------------------------------------------------
; The boot sector
;
; The ROM's boot loader reads the first sector of the DOS file to &8000 and calls it. Everything below &8000+510 is
; already in memory; this code reads the remaining sectors of the chain and then hands control back.
;
; Each sector holds 510 bytes of data followed by the track and sector of its successor. Loading starts at &8000+510
; -- the position of that link -- so each sector overwrites the two link bytes of the one before it and the payloads
; end up contiguous. A link of 0,0 ends the chain.
;
; The code is assembled for &4000 but runs at &8000, so every reference to a variable adds &4000 by hand.
;
; Entry:  the first sector of the DOS is at &8000
; Exit:   the DOS is in memory, its page is marked in the ROM's allocation table, and the default device is set
; Errors: the ROM's "Loading error" after disk.retries failed attempts at a sector
; ---------------------------------------------------------------------------------------------------------------------

               ld hl,&8000+disk.sctdata   ; load address: the link bytes of the sector already read
               ld de,&0402                ; track 4, sector 2 -- the second sector of the chain

dos:           xor a
               ld (dct+&4000),a           ; clear the retry count for this sector
               ld (svhl+&4000),hl         ; remember where this sector is to go

               ld a,e
               out (sect),a

; Seek: step in or out one track at a time until the track register matches the wanted track.

dos2:          in a,(comm)
               bit wd.st.busy,a
               jr nz,dos2

               in a,(trck)
               cp d
               jr z,dos4

               ld a,stpout
               jr nc,dos3
               ld a,stpin

dos3:          out (comm),a
               ld b,20
del1:          djnz del1                  ; let the head settle before testing the track again
               jr dos2

; Read the sector, polling the status register: DRQ means a byte is ready, busy means the command is still running.
; ini is used rather than in/ld so that the transfer keeps up with the controller.

dos4:          di
               ld a,drsec
               out (comm),a
               ld b,20
del2:          djnz del2

               ld hl,(svhl+&4000)
               ld bc,dtrq                 ; b = 0, so ini's decrement of b is harmless here
               jr dos6

dos5:          ini

dos6:          in a,(comm)
               bit wd.st2.drq,a
               jr nz,dos5
               bit wd.st.busy,a
               jr nz,dos6

               ei

;CHECK DISC ERR COUNT

               and wd.st.errors
               jr z,dos8

               ld a,(dct+&4000)
               inc a
               ld (dct+&4000),a
               push af
               and 2                      ; reset the controller on every second retry
               jr z,dos7

               ld a,dres
               out (comm),a
               ld b,20
del3:          djnz del3

dos7:          pop af
               cp disk.retries
               jr c,dos2

               rst 8
               defb romerr.loading

; Follow the link at the end of the sector just read. It is stored track first, and hl is left pointing at it, which
; is where the next sector's data will be loaded.

dos8:          dec hl
               ld e,(hl)
               dec hl
               ld d,(hl)
               ld a,d
               or e
               jr nz,dos

; The image is complete. Work out which pages it and the screen occupy, tell the ROM the DOS is resident, claim the
; page in the ROM's allocation table, and default the device to drive 1 of "D".

               ld a,(ramtopp) ;page
               ld (port2+&4000),a
               dec a
               ld (snprt2+&4000),a
               dec a
               ld (dosflg),a  ;dosflg

               ld h,alloct/256
               ld l,a         ;dsc use
               ld (hl),page.dos

               ld hl,&0144    ;device
               ld (devl),hl   ; l -> devl = "D", h -> devn = 1

               ret

               org $ - &4000


; =====================================================================================================================
; The DOS variables, at &4100
; =====================================================================================================================
;
; dvar is the base of the block the DVAR function reads: DVAR 0 is rbcc, DVAR 1 traks1, and so on. A program can poke
; these to change the DOS's behaviour -- the number of tracks the formatter writes, the step rate, the character DIR
; substitutes for a space, and so on. See hvar in h.s.
; ---------------------------------------------------------------------------------------------------------------------

dvar:          equ $

rbcc:          defb 7         ; border colour flashed during disk access; zero disables the effect
traks1:        defb 128+80    ; drive 1: 80 tracks, bit 7 set for double sided
traks2:        defb 0         ; drive 2: not present
stprat:        defb 0         ; drive 1 step rate, in units of the stpdel delay loop
stprt2:        defb 0         ; drive 2 step rate
chdir:         defb &20       ; the character DIR prints in place of a space in a file name
nstat:         defb 1         ; network station number
vers:          defb 20        ; DOS version, 2.0

size1:         defb 80        ; printer page length
size2:         defb 0
szea:          defb 12
lfeed:         defb 1         ; printer line feed
lmarg:         defb 0         ; printer left margin
graph:         defb 1         ; printer graphics mode
               defb 0
               defb 0
               defb 0
               defb 0
               defb 0
               defb 0
               defb 0
               defb 0

; The external command vector. syntax calls extadd when it does not recognise a command, so a program can extend the
; DOS by poking its own address into onerr. The default is a RET, which reports the error unchanged.

extadd:        call cmr
onerr:         defw 0
               ret

; Stack pointer saved on entry to a hook, so an error can unwind to the caller rather than to the command loop.

hksp:          defw 0
               defw 0


;PRINTER INITIALISE
; The printer control sequences below are all unreferenced: SAMDOS 2 has no printer driver, and these are the
; remains of one. &80 pads each sequence out to four bytes.

pcc1:          defb &0d,&80,&80,&80

;CHARACTER PITCH

pcc2:          defb &1b,&4d,&80,&80

;LINE SPACING CODES

pcc3:          defb &1b,&41,&80,&80

;PIN GRAPHICS CODES

pcc4:          defb &1b,&2a,&05,&80

;ANY OTHER INITIALISE

pcc5:          defb &80,&80,&80,&80

;SPECIAL GRAPHIC CODES
; Bitmaps for characters an Epson-compatible printer would not have had.

pound:         defb &18,&20,&20,&78
               defb &20,&20,&7c,&00

hash:          defb &00,&24,&7e,&24
               defb &24,&7e,&24,&00

crite:         defb &7e,&81,&bd,&a1
               defb &a1,&bd,&81,&7e

gcc1:          defb &1b,&2a,&05,&40
               defb &02,&80,&80,&80

; <noise>
; Fragments of an assembler's own memory, left in the released image. See the repository README.
               defm "UTPUT DIFA TO ROMUIFA"
               defb &00,&00,&00,&80,&30,&00
; </noise>

               org gnd + &0100
               dump gnd.bank,&0100 - org.adjust

; The name the ROM's BOOT command looks for, terminated by setting bit 7 of the last character.

               defm "BOO"
               defb "T"+&80

entsp:         defw &7ffa     ; SP on entry to a command, restored when the command ends or an error unwinds
snprt0:        defb &1f       ; LMPR, HMPR and VMPR of the interrupted machine, saved by the NMI snapshot code
snprt1:        defb 2
snprt2:        defb &1e
snpsva:        defb 0

svhdr:         defw &4b00     ; IX on entry to a hook: the ROM's header buffer
cchad:         defw &9f34     ; chadd saved on entry to syntax, so it can be restored for an external command
cnt:           defw &0058     ; running total of sectors used, accumulated by DIR

dsc:           defb rtrk      ; base port of the WD1772, with drive and side selection in bits 7-4
dct:           defb 0         ; retry count for the sector in progress
dst:           defb 0         ; track read back by "read address" when confirming the head position
               defb &80,&32,&00,&02,&4c,&44,&07
nbot:          defb 0         ;                                                       (unused)
rcmr:          defb 0         ;                                                       (unused)
count:         defb 0
sva:           defb 13        ; one-byte scratch, used to carry a value across a call that corrupts A
svc:           defb 0         ; page of the string returned by getstr
samcnt:        defb 0         ;                                                       (unused)
rmse:          defb 0         ;                                                       (unused)
smse:          defb 0         ;                                                       (unused)

svdpt:         defw 0         ; directory entry index during a find, and the column counter during DIR !
svtrs:         defw 0         ; track/sector during a find
svbuf:         defw 0         ; sector buffer address saved across a disk copy
svcnt:         defw 0         ; sectors still to transfer in the current block
hldi:          defw &0044     ; interrupt state saved by svint and restored by ldint
ptrscr:        defw ftadd     ; pointer into the screen memory used as a large disk buffer

port1:         defb 0         ; HMPR on entry, restored after a transfer
port2:         defb &1f       ; HMPR value that maps the screen used as a buffer
port3:         defb 0         ; HMPR saved across a hook save


; ---------------------------------------------------------------------------------------------------------------------
; The command parameter block
;
; Every command parses its arguments into this block, and resreg resets it to &FF -- "not given" -- before parsing
; starts. The layout is duplicated: dstr1 to page1 describe the first file, dstr2 to page2 the second, and exdat in
; f.s swaps the two blocks so that commands taking two files (COPY, RENAME, FORMAT TO) can run the same code twice.
;
; The names follow a pattern: d = drive, f = file number, s = stream, l = device letter, n = name, hd = header.
; ---------------------------------------------------------------------------------------------------------------------

cstr1:         defb &1d       ; the command token being executed
tstr1:         defb &ff       ; first byte cleared by resreg
               defb &ff
               defb &ff
hstr1:         defb &ff       ; the hide/protect bit mask, or the TO token in FORMAT

dstr1:         defb 1         ; drive number
fstr1:         defb &ff       ; file number, or &FF for "by name"
sstr1:         defb &ff       ; stream number
lstr1:         defb "D"       ; device letter
nstr1:         defb &13       ; file type, followed by the ten-character name
               defm "samdos2       "
hd001:         defb &13       ; the 9-byte header written to and read from the directory
hd0b1:         defw &2710     ; length
hd0d1:         defw &8009     ; start address
hd0f1:         defw &ffff     ; execution address
pges1:         defb 0         ; whole 16K pages remaining in the transfer
page1:         defb &7d       ; page of the transfer address

dstr2:         defb &ff       ; the same block again, for the second file of COPY, RENAME and FORMAT TO
fstr2:         defb &ff
sstr2:         defb &ff
lstr2:         defb &ff
nstr2:         defb &ff
               defb &ff,&ff,&ff,&ff,&ff,&ff,&ff,&ff,&ff,&ff,&ff,&ff,&ff,&ff
hd002:         defb &ff
hd0b2:         defw &ffff
hd0d2:         defw &ffff
hd0f2:         defw &ffff
pges2:         defb &ff
page2:         defb &ff

nstr3:         defb &ff       ; the wildcard pattern COPY matches against, kept while nstr1 holds each match
               defb &ff,&ff,&ff,&ff,&ff,&ff,&ff,&ff,&ff,&ff,&ff,&ff,&ff,&ff


; ---------------------------------------------------------------------------------------------------------------------
; The header buffers
;
; uifa is the header the caller asked for and difa the one read from the disk -- the same distinction the ROM makes
; between its HDR and HDL buffers, which is what txinf and txhed in h.s copy them to. Both are hdr.size bytes and use
; the layout given by the hdr.* equates in a.s.
; ---------------------------------------------------------------------------------------------------------------------

uifa:          defb &13
               defm "samdos2                  "
               defb &ff,&ff,&ff,&ff,&ff
               defb &7d
               defb &09
               defb &80
               defb &00
               defb &10
               defb &27
               defb &ff
               defb &ff
               defb &ff
               defb &00,&00,&00,&00,&00,&00,&00,&00

difa:          defb 0
               defb &00,&80,&43,&00,&02,&4c,&44,&03,&42,&2c,&30,&00,&80,&44,&00,&02
               defb &4c,&44,&03,&43,&2c,&41,&00,&80,&45,&00,&03,&41,&44,&44,&05,&48
               defb &4c,&2c,&42,&43,&00,&80,&46,&00,&02,&4c,&44,&04,&42,&2c,&34

; The registers a hook was called with, saved by hook so the routine can pick its arguments out of them.

hka:           defb &44
hkhl:          defw &4b1f
hkde:          defw &4b25
hkbc:          defw &0202

; The directory entry the NMI snapshot code writes. The name is completed with the drive and page numbers at the
; moment the snapshot is taken -- see snap5 in d.s.

snme:          defb &13
               defm "SNAP          "
               defb &13
snlen:         defw 49152
snadd:         defw 16384
               defw 0
               defw &ffff

; <noise>
               defm "CALL"
; </noise>

; Length of the region smchk and chksm checksum. Both are unreferenced, which is as well: the expression adds &0220
; where it should subtract it, so the count runs &440 bytes past the end of the image.

size:          equ zzend-gnd+&0220


; =====================================================================================================================
; The entry points, at &4200
; =====================================================================================================================
;
; The ROM calls the DOS at three fixed addresses in its page: hook for an RST &08 hook code, syntax for a command it
; does not recognise, and nmi when the NMI button is pressed. Nothing else about the DOS's internals is published.
; ---------------------------------------------------------------------------------------------------------------------

               org gnd + &0200
               dump gnd.bank,&0200 - org.adjust

               jp hook

               jp syntax

               jp nmi

; <noise>
               defm "DEFW"
               defb &06
               defm "NR"
; </noise>

               org gnd + &0210
               dump gnd.bank,&0210 - org.adjust

; The address of the DOS's error message table, which the ROM reads when reporting an error code of 81 or more. The
; &4000 is added because the ROM reads it with the DOS paged in at &8000.

               defw errtbl+&4000

; <noise>
               defm "TE"
               defb &00,&80
               defm "Q"
               defb &00,&03
               defm "INC"
               defb &02
               defm "HL"
               defb &00
; </noise>

               org gnd + &0220
               dump gnd.bank,&0220 - org.adjust


; ---------------------------------------------------------------------------------------------------------------------
; syntax -- handle a command the ROM did not recognise
;
; The ROM calls here with the error code it was about to report. Code 29 is "Not understood", which is the ROM's way
; of saying the command token is one of those reserved for a DOS; anything else is passed straight back.
;
; chadd is rewound to the start of the statement, because the ROM has already advanced it past the token, and the
; original value is kept in cchad so it can be restored if the command turns out not to be ours after all.
;
; Entry:  A = the error code the ROM is reporting
; Exit:   E = 0, and the command has been executed; or E = 0 with the error unchanged if it was not a DOS command
; ---------------------------------------------------------------------------------------------------------------------

;TEST FOR CODE ON ERROR

syntax:        ld (entsp),sp

               cp 29          ;notund
               jp nz,synt3

synt1:         ld (cstr1),a
               call setbit
               call resreg

               ld hl,0
               ld (hksp),hl   ; no hook stack to unwind to: errors go back to BASIC
               xor a
               ld (flag3),a
               ld ix,dchan

;GET CHADD AND SAVE IT

               call nrrdd
               defw chadd
               ld (cchad),bc

;GET START OF STATEMENT

               call nrrdd
               defw cstat

               call nrwrd
               defw chadd

               call gchr

               cp dirtok      ;dir
               jp z,dir

               cp fmttok      ;format
               jp z,wfod

               cp erztok      ;erase
               jp z,eraz

               cp wrttok      ;write
               jp z,write

               cp lodtok      ;load
               jp z,load

               cp rdtok       ;read
               jp z,read

               cp cpytok      ;copy
               jp z,copy

               cp rnmtok      ;rename
               jp z,renam

               cp caltok      ;call
               jp z,calll

               cp prttok      ;protect
               jp z,prot

               cp hidtok      ;hide
               jp z,hide


;CHECK EXTERNAL SYNTAX VECTOR

               ld bc,(cchad)
               call nrwrd
               defw chadd

               ld hl,(onerr)
               ld a,h
               or l
               ld a,(cstr1)
               call nz,extadd

synt3:         ld e,0

               ret


; ---------------------------------------------------------------------------------------------------------------------
; hook -- handle an RST &08 hook code from the ROM
;
; The alternate register set is saved along with the main one, because the ROM's save and load code passes arguments
; in both. The code is turned into an index into samhk and the routine is entered with a return address of rfhk
; already stacked, so it can simply RET when it is done.
;
; Entry:  A = the hook code, IX = the ROM's header buffer, other registers as the individual hook requires
; Errors: err.badcode if the code is below hook.first
; Notes:  There is no upper bound check. A code above 168 indexes past the end of samhk.
; ---------------------------------------------------------------------------------------------------------------------

;SAMDOS HOOK CODE ROUTINE

hook:          ld (entsp),sp
               ld (svhdr),ix
               exx
               ex af,af'
               ld (hka),a
               ld (hkhl),hl
               ld (hkde),de
               ld (hkbc),bc
               ex af,af'
               exx
               call setbit
               ld hl,0
               ld (hksp),hl
               scf
               sbc hook.first-1           ; carry is set, so this is a - hook.first
               jp c,rep17

               add a,a
               ld l,a
               ld h,0
               ld de,samhk
               add hl,de
               ld e,(hl)
               inc hl
               ld d,(hl)
               ld hl,rfhk
               push hl
               push de
               xor a
               ld (flag3),a
               ld a,(hka)
               ret            ; enter the hook routine, which returns to rfhk


;RETURN FROM HOOK CODE O.K

rfhk:          xor a
               ld e,a
               call nrwr
               defw dosact
               jp bcr


; ---------------------------------------------------------------------------------------------------------------------
; resreg -- reset the command parameter block
;
; Fills everything from tstr1 to the start of uifa with &FF, so that a command can tell which arguments were given.
; ---------------------------------------------------------------------------------------------------------------------

;RESET ALL REGISTERS

resreg:        ld hl,tstr1
               ld bc,uifa-tstr1
resr1:         ld (hl),&ff
               inc hl
               dec bc
               ld a,b
               or c
               jr nz,resr1
               ret


; ---------------------------------------------------------------------------------------------------------------------
; samhk -- the hook code dispatch table
;
; Indexed by hook code minus hook.first. Codes 128 to 142 are the set the ROM publishes; the rest are SAMDOS's own,
; called by the ROM's save and load code once a file is open. s is a bare RET, used for every code that is either
; reserved or belongs to a DOS with more features than this one.
; ---------------------------------------------------------------------------------------------------------------------

;COMMAND CODE TABLE

samhk:         defw init      ;128  BTHK   boot
               defw hgthd     ;129  FOPHK  open a file and return its header
               defw hload     ;130  LDHK   load the file body
               defw hvery     ;131  VFYHK  verify the file body against memory
               defw hsave     ;132  SVHK   save header and body
               defw s         ;133
               defw hopen     ;134  OSHK   open a stream onto a DOS channel
               defw hclos     ;135  CSHK   close a stream
               defw initx     ;136  ALHK   load and run the auto-load file
               defw hdir      ;137  DIRHK  directory listing
               defw s         ;138
               defw hvar      ;139  DVHK   the DVAR function
               defw heof      ;140  EOFHK  the EOF function
               defw hptr      ;141  PTRHK  the PTR function
               defw hpath     ;142  PATHHK the PATH$ function
               defw s         ;143
               defw s         ;144
               defw s         ;145
               defw s         ;146
               defw hofle     ;147  open a file for writing
               defw sbyt      ;148  save one byte
               defw hwsad     ;149  write a sector
               defw hsvbk     ;150  save a block
               defw s         ;151
               defw cfsm      ;152  close the file being written
               defw s         ;153
               defw pntp      ;154
               defw cops1     ;155
               defw cops2     ;156
               defw s         ;157
               defw hgfle     ;158  open a file for reading
               defw lbyt      ;159  load one byte
               defw hrsad     ;160  read a sector
               defw hldbk     ;161  load a block
               defw s         ;162
               defw s         ;163
               defw rest      ;164  restore the drive to track 0
               defw pcat      ;165  print the catalogue
               defw heraz     ;166  erase a file
               defw s         ;167
               defw s         ;168


; ---------------------------------------------------------------------------------------------------------------------
; setbit -- tell the ROM a DOS operation is in progress
;
; The ROM tests this while an error is being reported, so that a DOS error is looked up in the DOS's message table
; rather than its own. rfhk and ends clear it again.
; ---------------------------------------------------------------------------------------------------------------------

setbit:        push af
               ld a,1
               call nrwr
               defw dosact
               pop af
               ret
