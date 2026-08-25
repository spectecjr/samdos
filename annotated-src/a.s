
; =====================================================================================================================
; A.S -- Equates: hardware, ROM interface, disk format and DOS data structures
; =====================================================================================================================
;
;(C) SAM Computers Limited
;
;     COPYRIGHT 1990
;
;     SAMDOS Ver 1.2
;
;     BRUCE B GORDON
;
;     START 29.11.89
;
;     DATE  24.01.90
;
;
;     DATE  10.07.91
;
; ---------------------------------------------------------------------------------------------------------------------
; What SAMDOS is, and where it lives
; ---------------------------------------------------------------------------------------------------------------------
;
; SAMDOS is not part of the SAM Coupe ROM. It is a 10000-byte image loaded from the first two tracks of a disk into a
; 16K RAM page, where it occupies &4000-&7FFF (section B of the Z80 address space). The ROM knows nothing about disks:
; it forwards every disk operation to whatever DOS is resident, through three fixed entry points at the base of that
; page plus RST &08 hook codes. See docs/machine-code-interface.md in the samrom repository for the ROM's side.
;
; Because the DOS and the ROM's own system variables both want to live at &4000-&7FFF, the DOS cannot simply read a
; system variable: it has to ask the ROM to map the system page first. That is what the cmr / nrread / nrwr family
; below is for, and it explains the shape of a great deal of this code.
;
; ---------------------------------------------------------------------------------------------------------------------
; Note on the equates in this file
; ---------------------------------------------------------------------------------------------------------------------
;
; Rather more than half of the original definitions here are never referenced by any of the seven source files --
; leftovers from the network (SNOS) and Master DOS variants that share this source lineage. They are kept, and marked
; "unused", because their presence is itself a record of what the code once did.
;
; Definitions added by this annotation are grouped in their own sections at the end and follow the naming convention
; already used by the original source (dotted lowercase, as in gnd.bank and org.adjust).
; =====================================================================================================================


; ---------------------------------------------------------------------------------------------------------------------
; Where the DOS is assembled to run
;
; gnd ("ground") is the base of the DOS page. Everything in the image is assembled relative to it. The boot sector is
; an exception: it is read to &8000 by the ROM's boot loader and relocates itself, which is why b.s begins with
; "org gnd+&4000" -- the same code seen at &8000 during boot and at &4000 afterwards.
; ---------------------------------------------------------------------------------------------------------------------

gnd:           equ &4000
gnd.bank:      equ 1


; ---------------------------------------------------------------------------------------------------------------------
; ROM system variables
;
; var2 is the second block of system variables, at &5A00 in the system page. The first block is the ZX-compatible one
; at &5C00. Both are only reachable with the system page mapped -- see nrrd / nrwr in d.s.
; ---------------------------------------------------------------------------------------------------------------------

var2:          equ &5a00
chadd:         equ var2+&97   ; (2) address of the character being interpreted
cstat:         equ var2+&7b   ; (2) address of the start of the current statement
nrread:        equ &00ac      ; ROM: LD A,(HL) / RET -- read a byte with the system page mapped
nrrite:        equ &000d      ; ROM: LD (HL),A / RET -- write a byte with the system page mapped
beepr:         equ &016f      ; jump table: sound DE-1 cycles at a half period of HL units of 8T
flags:         equ &5c3b      ; bit 7 set while running, clear while syntax-checking
bordcr:        equ &5c4b      ; border colour
cmr:           equ &0103      ; jump table: call the routine whose address follows, with the system page mapped
xptr:          equ var2+&a3   ; (2) address of the error marker
curcmd:        equ var2+&174  ; code of the command being executed
stream:        equ &0112      ; jump table: select the stream in A
devl:          equ var2+&06   ; default device letter
devn:          equ var2+&07   ; default device number
pomsg:         equ &0115      ; jump table: print message A from the list at DE       (unused)
expnum:        equ &0118      ; jump table: evaluate a numeric expression at (chadd)
expstr:        equ &011b      ; jump table: evaluate a string expression at (chadd)
expexp:        equ &011e      ; jump table: evaluate an expression of either type     (unused)
getint:        equ &0121      ; jump table: pop the calculator stack as an integer into BC
getstr:        equ &0124      ; jump table: pop a string descriptor -- A = page, DE = start, BC = length
stkstr:        equ &0127      ; jump table: push a 5-byte number from A, E, D, C, B
progp:         equ var2+&9f   ; page containing the BASIC program
prog:          equ progp+1    ; (2) address of the BASIC program
elinp:         equ var2+&93   ; page containing the edit line
eline:         equ elinp+1    ; (2) address of the edit line
dosflg:        equ var2+&1c2  ; page number of the resident DOS, or zero if none is loaded

lodtok:        equ &95        ; LOAD
newtok:        equ &af        ; NEW                                                   (unused)
savtok:        equ &94        ; SAVE                                                  (unused)
dirtok:        equ &90        ; DIR
ovrtok:        equ &a6        ; OVER
cmdv:          equ &5af4      ;                                                       (unused)
overf:         equ &5bb9      ; "SAVE OVER" flag: zero for SAVE OVER, otherwise non-zero
comad:         equ &5bda      ;                                                       (unused)
insbf:         equ &4f00      ; ROM's code buffer                                     (unused)

; The following ZX-compatible system variables are all unused by SAMDOS 2. They are inherited from the source's
; Spectrum-derived ancestry.

lastk:         equ &5c08      ;                                                       (unused)
defadd:        equ &5c54      ;                                                       (unused)
tvdata:        equ var2+&01c0 ;                                                       (unused)
errnr:         equ &5c3a      ;                                                       (unused)
errsp:         equ &5c3d      ;                                                       (unused)
newppc:        equ &5c42      ;                                                       (unused)
nsppc:         equ &5c44      ;                                                       (unused)
chans:         equ &5c4f      ;                                                       (unused)
curchl:        equ &5c51      ;                                                       (unused)

vars:          equ 23627      ;                                                       (unused)
datadd:        equ 23639      ;                                                       (unused)
worksp:        equ 23649      ;                                                       (unused)
stkbot:        equ 23651      ;                                                       (unused)
stkend:        equ 23653      ;                                                       (unused)
flagx:         equ 23665      ;                                                       (unused)
tadl:          equ 23668      ;                                                       (unused)
attrp:         equ 23693      ;                                                       (unused)
attrt:         equ 23695      ;                                                       (unused)
membot:        equ 23698      ;                                                       (unused)
trap:          equ 23728      ;                                                       (unused)
dstr1m:        equ 23766      ;                                                       (unused)
nstr1m:        equ 23770      ;                                                       (unused)
nstr2m:        equ 23778      ;                                                       (unused)


; ---------------------------------------------------------------------------------------------------------------------
; Channel record offsets -- all unused
;
; These describe a per-channel record belonging to a variant of the DOS that supported record-structured files.
; SAMDOS 2 has no such channels: hopen, hclos, heof and hptr in h.s are all bare RETs.
; ---------------------------------------------------------------------------------------------------------------------

chbtlo:        equ 11         ;                                                       (unused)
chbthi:        equ 12         ;                                                       (unused)
chrec:         equ 13         ;                                                       (unused)
chname:        equ 14         ;                                                       (unused)
chflag:        equ 24         ;                                                       (unused)
chdriv:        equ 25         ;                                                       (unused)
recflg:        equ 67         ;                                                       (unused)
recnum:        equ 68         ;                                                       (unused)
rclnlo:        equ 69         ;                                                       (unused)
rclnhi:        equ 70         ;                                                       (unused)


; ---------------------------------------------------------------------------------------------------------------------
; WD1772 floppy disk controller commands
;
; The controller has four registers, selected by the low two bits of the port address; the base address is held in
; dsc and carries the drive and side selection in its high bits, so the port number is computed rather than fixed.
; See commp in c.s.
;
; Bit 0 of a command is the "h" (head load) or "a0" (data address mark) flag, bit 1 is the disable-spin-up flag,
; and for type I commands bits 1-0 select the stepping rate.
; ---------------------------------------------------------------------------------------------------------------------

dres:          equ %00001001  ; force interrupt / restore, used to reset the controller
seek:          equ %00011011  ; seek to the track in the data register              (unused)
stpin:         equ %01011011  ; step in one track, updating the track register
stpout:        equ %01111011  ; step out one track, updating the track register

drsec:         equ %10000000  ; read sector
dwsec:         equ %10100010  ; write sector
radd:          equ %11000000  ; read address (the next ID field to pass the head)
rtrk:          equ %11100000  ; read track
wtrk:          equ %11110000  ; write track -- used only by the formatter


; ---------------------------------------------------------------------------------------------------------------------
; I/O ports
; ---------------------------------------------------------------------------------------------------------------------

resp:          equ 233        ; printer status/control                               (unused)
pport:         equ 232        ; printer data                                         (unused)
ula:           equ 254        ; border colour and other ULA outputs


; ---------------------------------------------------------------------------------------------------------------------
; Offsets within the disk channel record addressed by IX
;
; IX points at dchan throughout the file handling code, so the whole of the DOS's per-operation state is reachable as
; (ix+n). The record continues past fsa into the 256-byte image of the directory entry being built or read, which is
; why the offsets run so far beyond the record's own fields.
; ---------------------------------------------------------------------------------------------------------------------

mdrv:          equ 11         ;                                                       (unused; = drive)
mflg:          equ 12         ;                                                       (unused; = flag3)
rptl:          equ 13         ; low byte of the pointer into the sector buffer
rpth:          equ 14         ; high byte -- 0 or 1, selecting which directory entry of the two in a sector
bufl:          equ 15         ; low byte of the sector buffer address
bufh:          equ 16         ; high byte
nsrl:          equ 17         ; sector of the next track/sector link
nsrh:          equ 18         ; track of the next track/sector link
ffsa:          equ 19         ; first byte of the directory entry image
name:          equ 20         ; file name within that image
rtyp:          equ 30         ;                                                       (unused)
cnth:          equ 30         ; high byte of the file's sector count
cntl:          equ 31         ; low byte
ftrk:          equ 32         ; track of the file's first sector
fsct:          equ 33         ; sector of the file's first sector
fsam:          equ 34         ; start of the file's sector address map
rram:          equ 39         ;                                                       (unused)
wtyp:          equ 230        ;                                                       (unused)
wram:          equ 275        ;                                                       (unused)


; ---------------------------------------------------------------------------------------------------------------------
; Fixed data areas within the DOS page
;
; str is the top of the DOS's private stack; the snapshot code saves the interrupted machine's registers in the 20
; bytes immediately below it. sam is the disk's sector address map -- one bit per sector of the whole disk -- and
; dchan the disk channel record described above.
; ---------------------------------------------------------------------------------------------------------------------

str:           equ gnd+&3efe  ; &7EFE -- stack top; str-20 upwards holds saved registers during a snapshot

sam:           equ gnd+&370f  ; &770F -- sector address map: 195 bytes, one bit per sector

dchan:         equ sam+241    ; &7800 -- the disk channel record
svbc:          equ dchan      ; (2) saved BC
svde:          equ dchan+2    ; (2) saved DE, usually a track/sector pair
rfdh:          equ dchan+4    ; the fdhr mode byte                                    (unused by name; see ix+4)
svhl:          equ dchan+5    ; (2) saved HL, usually the current transfer address
svix:          equ dchan+7    ; (2) saved IX
reg1:          equ dchan+9    ; (2)                                                   (unused)
drive:         equ dchan+11   ; drive number, 1 or 2
flag3:         equ dchan+12   ; the DOS's flag byte -- see the setf/bitf routines in d.s
rpt:           equ dchan+13   ; (2) pointer into the sector buffer                    (unused by name; see ix+rptl)
buf:           equ dchan+15   ; (2) address of the 512-byte sector buffer
nsr:           equ dchan+17   ; (2) next track/sector link                            (unused by name; see ix+nsrl)
fsa:           equ dchan+19   ; the 256-byte image of a directory entry

dram:          equ fsa+256    ; &7913 -- the sector buffer proper

fndfr:         equ dram+1024  ; directory entry index (0 or 1) during a find
fndts:         equ fndfr+1    ; (2) track/sector during a find
next:          equ fndts+2    ;                                                       (unused)


; =====================================================================================================================
; Definitions added by this annotation
; =====================================================================================================================


; ---------------------------------------------------------------------------------------------------------------------
; Paging ports
;
; The SAM divides the 64K address space into four 16K sections. LMPR selects the pages at &0000 and &4000 and controls
; ROM visibility; HMPR selects those at &8000 and &C000; VMPR selects the page the video hardware displays.
; ---------------------------------------------------------------------------------------------------------------------

port.status:   equ 249        ; keyboard bits 7-5 and the interrupt status register
port.lmpr:     equ 250        ; low memory page register
port.hmpr:     equ 251        ; high memory page register
port.vmpr:     equ 252        ; video memory page register

page.mask:     equ %00011111  ; page number field of LMPR / HMPR
page.other:    equ %11100000  ; the remaining bits, which must be preserved when changing the page


; ---------------------------------------------------------------------------------------------------------------------
; WD1772 status register bits
;
; The meaning of bits 1 and 2 depends on the command that was issued: type I commands (restore, seek, step) report
; drive state, while type II and III commands (read/write sector, read address, read/write track) report the data
; transfer. Both sets are given here, since this code uses both.
; ---------------------------------------------------------------------------------------------------------------------

wd.st.busy:    equ 0          ; both types: a command is still running

wd.st1.index:  equ 1          ; type I: the index hole is passing
wd.st1.track0: equ 2          ; type I: the head is over track 0
wd.st1.seek:   equ 4          ; type I: seek error

wd.st2.drq:    equ 1          ; type II/III: the data register needs servicing
wd.st2.lost:   equ 2          ; type II/III: data lost -- the transfer did not keep up
wd.st2.crc:    equ 3          ; type II/III: CRC error
wd.st2.rnf:    equ 4          ; type II/III: record not found
wd.st2.wprot:  equ 6          ; type II/III: the disk is write protected

wd.st.errors:  equ %00011100  ; mask of lost data, CRC error and record not found


; ---------------------------------------------------------------------------------------------------------------------
; Disk format
;
; 80 tracks per side, two sides, 10 sectors of 512 bytes per track: 800K unformatted, 780K usable. A file is a chain
; of sectors, each holding 510 bytes of data followed by the track and sector of its successor; a link of 0,0 ends
; the chain. Tracks 0 to 3 of side 1 hold the directory, four entries of 256 bytes to a sector.
;
; Side 2 is addressed by setting bit 7 of the track number, so a track byte of &84 means track 4 of side 2.
; ---------------------------------------------------------------------------------------------------------------------

disk.sectors:  equ 10         ; sectors per track, numbered 1 to 10
disk.sctsize:  equ 512        ; bytes per sector
disk.sctdata:  equ 510        ; usable bytes; the last two link to the next sector
disk.dirtrks:  equ 4          ; tracks 0-3 hold the directory
disk.side2:    equ &80        ; set in a track number to select the second side
disk.sammax:   equ 195        ; bytes in a sector address map -- one bit per sector of the data area
disk.retries:  equ 10         ; attempts at a sector before giving up

page.size:     equ 16384      ; bytes in a 16K page, the unit of the page/offset address form


; ---------------------------------------------------------------------------------------------------------------------
; Directory entry
;
; Two 256-byte entries to a sector. The first byte is zero for a deleted or never-used entry, otherwise it holds the
; file type in its low five bits and the hidden and protected flags in its top two.
; ---------------------------------------------------------------------------------------------------------------------

de.size:       equ 256        ; bytes per entry
de.typemask:   equ &1f        ; file type field of the first byte
de.protect:    equ &40        ; protected: ERASE refuses without OVER
de.hide:       equ &c0        ; hidden: protected as well, and not listed by DIR
de.protectbit: equ 6          ; the same two flags as bit numbers, for BIT and SET
de.hidebit:    equ 7

de.type:       equ 0          ; file type and flags; zero if the entry is free
de.name:       equ 1          ; (10) file name
de.namelen:    equ 10
de.count:      equ 11         ; (2) sectors used by the file, high byte first
de.track:      equ 13         ; track of the file's first sector
de.sector:     equ 14         ; sector of the file's first sector
de.sam:        equ 15         ; (195) the file's own sector address map
de.hdr:        equ 211        ; the 9-byte file header, as written to disk
de.tail:       equ 220        ; the remaining 33 bytes of the 48-byte header

; Mode byte passed to fdhr in A and held at (ix+4), selecting what the directory scan is looking for.

fdh.number:    equ 0          ; bit 0: match the file number in fstr1
fdh.compact:   equ 1          ; bit 1: printing a DIR ! listing -- names only, in columns
fdh.list:      equ 2          ; bit 2: printing a full DIR listing
fdh.wild:      equ 3          ; bit 3: match the name in nstr1, honouring * and ?
fdh.name:      equ 4          ; bit 4: match the name in nstr1 exactly
fdh.free:      equ 6          ; bit 6: stop at the first free entry rather than looking for a match


; ---------------------------------------------------------------------------------------------------------------------
; File header
;
; Offsets within the 48-byte header exchanged with the ROM (uifa and difa in b.s). They match the ROM's own header
; layout -- see docs/file-formats.md in the samrom repository -- so uifa can be copied to the ROM's buffer unchanged.
;
; The three-byte numbers are in page form: a page number followed by an address within that page.
; ---------------------------------------------------------------------------------------------------------------------

hdr.type:      equ 0          ; file type, one of the ft.* values below
hdr.name:      equ 1          ; (10) file name
hdr.flags:     equ 15         ; the ROM calls this HFG
hdr.start:     equ 31         ; (3) start address, page form -- the ROM calls this HDN
hdr.length:    equ 34         ; (3) length, page form
hdr.exec:      equ 37         ; (3) execution address, page form, or &FF for none
hdr.size:      equ 48         ; bytes in the header

rom.hdr:       equ &4b00      ; the ROM's requested-file header buffer (HDR)
rom.hdl:       equ &4b50      ; the ROM's loaded-file header buffer (HDL)

; File names as the parser accepts them, which is wider than the directory stores: the extra room is for a "D1:"
; style prefix, which evfile strips before the ten characters that reach the disk are copied out.

fn.maxlen:     equ 14         ; longest name accepted, including any device and drive prefix
fn.field:      equ 15         ; bytes of nstr1 cleared to spaces before a name is copied in

maxstream:     equ 16         ; stream numbers run 0 to 15

nummark:       equ &0e        ; marks an invisible five-byte number the ROM has compiled into a line
nummarklen:    equ 6          ; the marker and its payload


; ---------------------------------------------------------------------------------------------------------------------
; File types
;
; Types 16 and up are SAM files and match the ROM's own numbering; 1 to 12 are the ZX Spectrum types SAMDOS can also
; hold, mostly so that Spectrum emulator snapshots and screens have somewhere to live.
; ---------------------------------------------------------------------------------------------------------------------

ft.zxbasic:    equ 1          ; ZX BASIC
ft.zxdarray:   equ 2          ; ZX numeric array
ft.zxsarray:   equ 3          ; ZX string array
ft.zxcode:     equ 4          ; ZX code
ft.zxsnap48:   equ 5          ; ZX 48K snapshot
ft.mdfile:     equ 6          ; microdrive file
ft.zxscreen:   equ 7          ; ZX SCREEN$
ft.special:    equ 8          ; special
ft.zxsnap128:  equ 9          ; ZX 128K snapshot
ft.opentype:   equ 10         ; open type
ft.execute:    equ 11         ; execute
ft.basic:      equ 16         ; BASIC program
ft.darray:     equ 17         ; numeric array
ft.sarray:     equ 18         ; string array
ft.code:       equ 19         ; code
ft.screen:     equ 20         ; SCREEN$


; ---------------------------------------------------------------------------------------------------------------------
; DOS error codes
;
; Raised by the rep0 to rep31 stubs in d.s, which pass the code to derr. The ROM treats any RST &08 code of &51 (81)
; or above as a DOS error and fetches its text from the DOS rather than from its own table -- see errtbl in d.s,
; whose entries are in exactly this order.
; ---------------------------------------------------------------------------------------------------------------------

err.base:      equ 81         ; the ROM's first DOS error code

err.nonsense:  equ 81         ; Nonsense in SAMDOS 1.1
err.snos:      equ 82         ; Nonsense in SNOS 1.1
err.stmtend:   equ 83         ; Statement end error
err.escape:    equ 84         ; Escape requested
err.trkerr:    equ 85         ; TRK-nn,SCT-n,Error
err.fmtlost:   equ 86         ; Format TRK-nn lost
err.checkdsk:  equ 87         ; Check disk in drive
err.noboot:    equ 88         ; No "BOOT" file
err.badname:   equ 89         ; Invalid file name
err.badstn:    equ 90         ; Invalid station
err.baddev:    equ 91         ; Invalid device
err.novar:     equ 92         ; Variable not found
err.verify:    equ 93         ; Verify failed
err.badtype:   equ 94         ; Wrong file type
err.merge:     equ 95         ; Merge error
err.code:      equ 96         ; Code error
err.pupil:     equ 97         ; Pupil set
err.badcode:   equ 98         ; Invalid code
err.readwrite: equ 99         ; Reading a write file
err.writeread: equ 100        ; Writing a read file
err.noauto:    equ 101        ; no AUTO* file
err.netoff:    equ 102        ; Network off
err.nodrive:   equ 103        ; No such drive
err.wprot:     equ 104        ; Disk is write protected
err.nospace:   equ 105        ; Not enough space on disk
err.dirfull:   equ 106        ; Directory full
err.notfound:  equ 107        ; File not found
err.eof:       equ 108        ; End of file
err.nameused:  equ 109        ; File name used
err.nodos:     equ 110        ; No SAMDOS loaded
err.strmused:  equ 111        ; Stream used
err.chanused:  equ 112        ; Channel used

romerr.loading: equ 19        ; the ROM's own "Loading error" -- the only ROM error code the DOS raises directly


; ---------------------------------------------------------------------------------------------------------------------
; DOS hook codes
;
; The ROM reaches the DOS by executing RST &08 with a code of 128 or more. hook in b.s subtracts the base and indexes
; the samhk table. Codes 128 to 142 are the ROM's published set; the rest are SAMDOS's own, used by the parts of the
; ROM's save and load machinery that call back into the DOS.
; ---------------------------------------------------------------------------------------------------------------------

hook.first:    equ 128        ; lowest hook code; anything below it is an error report


; ---------------------------------------------------------------------------------------------------------------------
; BASIC tokens
;
; The commands SAMDOS claims from the ROM, plus the keywords its own syntax accepts. dirtok, lodtok, savtok, newtok
; and ovrtok are defined further up, with the original equates.
; ---------------------------------------------------------------------------------------------------------------------

wrttok:        equ &86        ; WRITE
offtok:        equ &89        ; OFF
totok:         equ &8e        ; TO
fmttok:        equ &91        ; FORMAT
erztok:        equ &92        ; ERASE
modtok:        equ &aa        ; MODE
rdtok:         equ &b8        ; READ
cpytok:        equ &cf        ; COPY
rnmtok:        equ &e3        ; RENAME
caltok:        equ &e4        ; CALL
prttok:        equ &f1        ; PROTECT
hidtok:        equ &f2        ; HIDE


; ---------------------------------------------------------------------------------------------------------------------
; Further ROM entry points and system variables
; ---------------------------------------------------------------------------------------------------------------------

rst.print:     equ &0010      ; RST &10 -- print the character in A to the current channel
rst.getchr:    equ &0018      ; RST &18 -- get the character at (chadd)
rst.nextchr:   equ &0020      ; RST &20 -- advance chadd and get the next character

clsbl:         equ &014e      ; jump table: clear the whole screen if A is zero, otherwise the window
reclaim:       equ &0163      ; jump table: close up BC bytes at HL

dosact:        equ var2+&01c3 ; non-zero while a DOS operation is in progress
lowpos:        equ var2+&6e   ; lower screen print position, as column and row
ramtopp:       equ &5cb4      ; page containing RAMTOP -- the page the boot loader puts the DOS in

alloct:        equ &5100      ; the ROM's page allocation table, one byte per 16K page
page.dos:      equ &60        ; alloct entry meaning "in use by the resident DOS"

flags.running: equ &80        ; bit 7 of flags: running a program, as opposed to checking syntax
