
; =====================================================================================================================
; E.S -- Formatting, disk copying, and the printing DIR needs
; =====================================================================================================================
;
;   dfmt / dmt1 / wfm     format a disk, and build the track image the controller writes
;   sctrk / itrck / isect track and sector housekeeping
;   pntyp / drtab / gtval print a file's type and, for some types, its address and length
;   pnum6 .. pnm5         decimal printing with leading-zero suppression
;   ptm / spc / pnt       print an inline message, a space, a character
;   pmo1 .. pmod          the DOS's screen messages
;   tspce1 / tspce2       prompt for a disk swap during a single-drive copy
; =====================================================================================================================


; =====================================================================================================================
; dfmt -- FORMAT
; =====================================================================================================================
;
; Writes every track of the disk, then either copies another disk onto it, verifies it, or does neither, depending on
; whether a second file specifier was given.
;
; Formatting is done with the controller's write-track command, which writes a whole track from an image in memory
; including the gaps, sync fields and address marks. dmt1 builds that image at ftadd in the screen page; the
; controller stops writing when the index hole comes round, so the trailing gap is deliberately longer than a track
; and is simply truncated.
;
; The sector numbering is skewed by two between adjacent tracks, so that after the head has stepped the next sector
; wanted is about to pass under it rather than just gone by.
;
; Interrupts are off for the whole operation: a write-track cannot be interrupted without losing the track.
; ---------------------------------------------------------------------------------------------------------------------

;DISC FORMAT ROUTINE

dfmt:          di
               call gtixd
               call ckdrv
               call seld

               ld b,10        ; step in a little first, so the restore below has somewhere to come back from
dfmta:         push bc
               call instp
               pop bc
               djnz dfmta

               call restx

               call getscr

               push de
               call cmr
               defw clslow
               call pmoa
               pop de

fmt1:          ld hl,ftadd
               call dmt1

               call sctrk
               call svint
               call commp
               push bc

fmt3:          ld c,wtrk
               call precmp
               pop bc
               ld hl,ftadd
               call wsa3      ; the write loop from c.s, shared with wsad
               call stpdel
               inc d

               call tstd
               cp d
               jr z,fmt7      ; past the last track of the last side: done
               and &7f
               cp d
               jr z,fmt6      ; past the last track of side 1: restart on side 2
               call instp
               dec e
               jr nz,fmt4
               ld e,disk.sectors
fmt4:          dec e
               jr nz,fmt5
               ld e,disk.sectors
fmt5:          jp fmt1

fmt6:          call restx
               ld d,disk.side2
               call seld
               jp fmt1

fmt7:          call rest

               ld a,(dstr2)
               cp &ff
               jr z,fmt11a    ; no second disk given: verify instead of copying

               ld hl,(buf)
               ld (svbuf),hl

; FORMAT "x" TO "y": read each track of the source into the screen page and write it to the target, a track at a
; time, switching drives between the two.

fmt8:          push de
               call cmr
               defw clslow
               call pmob
               pop de
               call sctrk
               ld a,(dstr2)
               call ckdrx
               ld hl,ftadd

fmt9:          ld (buf),hl
               call rsad
               ld bc,disk.sctsize
fmt9a:         add hl,bc
               call isect
               jr nz,fmt9

               ld a,(dstr1)
               call ckdrx
               ld hl,ftadd

fmt10:         ld (buf),hl
               call wsad
               ld bc,disk.sctsize
fmt10a:        add hl,bc
               call isect
               jr nz,fmt10

               call itrck
               jr nz,fmt8

               ld hl,(svbuf)
               ld (buf),hl
               jr fmt12

; Plain FORMAT: read every sector back, which proves the format took.

fmt11a:        push de
               call cmr
               defw clslow
               call pmoc
               di
               pop de
               jr fmt11c

fmt11b:        call rsad
               call isect
               jr nz,fmt11b
fmt11c:        call sctrk
               call itrck
               jr nz,fmt11b

fmt12:         call cmr
               defw clslow
               ld hl,ftadd
               call putscr
               ei
               jp rest


; ---------------------------------------------------------------------------------------------------------------------
; sctrk -- show the track number being formatted
;
; Rewinds the lower screen to the column the message left off at, so the number overwrites the previous one.
; ---------------------------------------------------------------------------------------------------------------------

;PRINT TRACK ON SCREEN

sctrk:         push de
               ld a,&15
               call nrwr
               defw lowpos ; Lower window position as column/row.
               ld l,d
               ld h,0
               ld a," "
               call pnum3
               di
               pop de
               ret


; ---------------------------------------------------------------------------------------------------------------------
; itrck -- step to the next track, changing sides at the end of side 1
;
; Exit:   Z when the last track of the last side has been passed
; ---------------------------------------------------------------------------------------------------------------------

;INCREMENT TRACK

itrck:         inc d
               call tstd
               cp d
               ret z
               and &7f
               cp d
               ret nz
               call rest
               ld d,disk.side2
               cp d
               ret


; ---------------------------------------------------------------------------------------------------------------------
; dmt1 -- build a double density track image
;
; The IBM System 34 layout the WD1772 expects, written out as a run-length list: a count in B and a byte in C for
; each field. Three byte values are not written literally by the controller but stand for something else:
;
;   &F5   write &A1 with a missing clock pulse -- the address mark prefix
;   &F7   write the two CRC bytes just accumulated
;   (&F6 would be the index mark prefix; this format has no index address mark)
;
; Per sector: 12 sync bytes, the three-byte mark prefix, the ID mark, the track, side, sector and size, a CRC, a
; 22-byte gap, another sync and mark, the data mark, disk.sctsize bytes of zero, a CRC, and a 24-byte gap. The
; trailing gap is 768 bytes -- longer than the rest of the track has room for -- because the controller stops at the
; index hole and the surplus is never written.
;
; Entry:  HL = where to build the image, D = track (bit 7 = side), E = first sector number
; ---------------------------------------------------------------------------------------------------------------------

;DOUBLE DENSITY FORMAT

dmt1:          ld bc,&3c4e    ; 60 bytes of &4E -- the gap before the first sector
               call wfm
               ld b,disk.sectors
dmt2:          push bc
               ld bc,&0c00    ; 12 sync bytes
               call wfm
               ld bc,&03f5    ; three address mark prefixes
               call wfm
               ld bc,&01fe    ; ID address mark
               call wfm
               ld a,d
               and &7f
               ld c,a         ; track
               ld b,&01
               call wfm
               ld a,d
               and disk.side2
               rlca
               ld c,a         ; side, as 0 or 1
               ld b,1
               call wfm
               ld c,e         ; sector
               call isect
               ld b,&01
               call wfm
               ld bc,&0102    ; size code 2 = 512 bytes
dmt3:          call wfm
               ld bc,&01f7    ; write the ID CRC
               call wfm
               ld bc,&164e    ; 22-byte gap
               call wfm
               ld bc,&0c00    ; 12 sync bytes
               call wfm
               ld bc,&03f5
               call wfm
               ld bc,&01fb    ; data address mark
               call wfm
               ld bc,0        ; b = 0 means 256, so two calls fill the 512-byte data field
               call wfm
               call wfm
dmt4:          ld bc,&01f7    ; write the data CRC
               call wfm
               ld bc,&184e    ; 24-byte gap
               call wfm
               pop bc
               dec b
               jp nz,dmt2
               ld bc,&004e    ; 768 bytes of gap; the controller truncates it at the index hole
               call wfm
               call wfm
               jp wfm



;WRITE FORMAT IN MEMORY

wfm:           ld (hl),c
               inc hl
               djnz wfm
               ret


; ---------------------------------------------------------------------------------------------------------------------
; isect -- step to the next sector, wrapping from the last back to the first
;
; Exit:   Z when the sector number wrapped
; ---------------------------------------------------------------------------------------------------------------------

;INCREMENT SECTOR ROUTINE

isect:         inc e
isect1:        ld a,e
               cp disk.sectors+1
               ret nz
               ld e,1
               ret


; ---------------------------------------------------------------------------------------------------------------------
; pntyp -- print a file's type, and for some types its address and length
;
; drtab pairs each type byte with its name. cpir searches for the byte and leaves HL pointing at the text, which runs
; until the next byte below 32 -- the following type number. A type that is not in the table exhausts the count and
; stops at drtbx, so it prints "WHAT?".
;
; Entry:  A = the type byte from the directory entry
; ---------------------------------------------------------------------------------------------------------------------

;PRINT TYPE OF FILE

pntyp:         and de.typemask
               push af
               ld hl,drtab
               ld bc,drtbx-drtab
               cpir

pnty1:         ld a,(hl)
               cp 32
               jr c,pnty2
               call pnt
               inc hl
               jr pnty1

; BASIC: print the autostart line number, if the file has one.

pnty2:         pop af
               cp ft.basic
               jr nz,pnty3
               ld (ix+rptl),242
               call grpnt
               ld a,(hl)
               and &c0
               jr nz,pnty5
               inc hl
               ld e,(hl)
               inc hl
               ld d,(hl)
               ex de,hl
               call pnum5
               jr pnty5

; Code: print the start address and the length. Control then falls into pnty4, but A no longer holds the type, so
; the test there cannot match and the ZX code path is not taken twice.

pnty3:         cp ft.code
               jr nz,pnty4
               ld (ix+rptl),236
               call grpnt
               call gtval
               inc c
               res 5,c
               ex de,hl
               push de
               ld a," "
               call pnum6
               ld a,","
               call pnt
               pop hl
               call gtval
               ex de,hl
               xor a
               call pnum6

; ZX code: the same, from a different offset and without the page byte.

pnty4:         cp ft.zxcode
               jr nz,pnty5
               ld (ix+rptl),215
               call grpnt
               ld d,(hl)
               dec hl
               ld e,(hl)
               ex de,hl
               push de
               call pnum5
               ld a,","
               call pnt
               pop hl
               dec hl
               ld d,(hl)
               dec hl
               ld e,(hl)
               ex de,hl
               xor a
               call pnum5x

pnty5:         ld a,&0d
               jp pnt


; ---------------------------------------------------------------------------------------------------------------------
; gtval -- read a three-byte page-form number from a header
;
; Exit:   C = page, DE = address, HL advanced past the number
; ---------------------------------------------------------------------------------------------------------------------

;GET NUMBER FROM HEADER

gtval:         ld a,(hl)
               and de.typemask
               ld c,a
               inc hl
               ld e,(hl)
               inc hl
               ld a,(hl)
               and &7f
               ld d,a
               inc hl
               ret


; Type byte followed by its name, in pairs. drtbx marks both the end of the search and the fallback text.

drtab:         defb ft.zxbasic
               defm "ZX BASIC"
               defb ft.basic
               defm "BASIC "
               defb ft.zxdarray
               defm "ZX D.ARRAY"
               defb ft.darray
               defm "D.ARRAY"
               defb ft.zxsarray
               defm "ZX $.ARRAY"
               defb ft.sarray
               defm "$.ARRAY"
               defb ft.zxcode
               defm "ZX "
               defb ft.code
               defm "C "
               defb ft.zxsnap48
               defm "ZX SNP 48k"
               defb ft.mdfile
               defm "MD.FILE"
               defb ft.zxscreen
               defm "ZX SCREEN$"
               defb ft.screen
               defm "SCREEN$"
               defb ft.special
               defm "SPECIAL"
               defb ft.zxsnap128
               defm "ZX SNP 128k"
               defb ft.opentype
               defm "OPENTYPE"
               defb ft.execute
               defm "N/A EXECUTE"
               defb 12
drtbx:         defm "WHAT?"
               defb 0


; =====================================================================================================================
; Decimal printing
; =====================================================================================================================
;
; A chain of entry points, each printing one more digit than the one below it: pnum6 handles six digits and a page
; number, pnum5 five, and so on down to pnum1, which prints the remainder as a single digit.
;
; A carries the character to print in place of a leading zero -- a space to pad the field, or zero to print nothing
; at all. As soon as a significant digit appears it is replaced by "0", so that zeros inside the number are printed
; normally.
;
; Entry:  HL = the value, A = the leading-zero character; pnum6 also takes a page count in C
; ---------------------------------------------------------------------------------------------------------------------

;PRINT NUMBER IN HL

; Combine the page number in C with the address in HL to give a 24-bit byte count in B:HL, then print the
; hundred-thousands digit before joining the ordinary chain.

pnum6:         ld (sva),a
               xor a
               ld de,0

               rr c
               rr d
               rr c
               rr d           ; d = the low two bits of the page, aligned to bit 14 of the total
               ld a,d
               add h
               ld h,a
               ld a,c
               adc e
               ld b,a
               ld de,34464
               ld c,1         ;65536
               ld a,(sva)
               call pnm2
               jr pnum5y

pnum5:         ld a," "

pnum5x:        ld b,0
pnum5y:        ld c,0
               ld de,10000
               call pnm2
pnum4:         ld de,1000
               call pnm1
pnum3:         ld de,100
               call pnm1
pnum2:         ld de,10
               call pnm1
pnum1:         ld a,l
               add "0"
               jr pnt

; One digit by repeated subtraction. C:DE is the place value, B:HL the remaining number.

pnm1:          ld bc,0
pnm2:          push af
               ld a,b
               ld b,0
               and a

pnm3:          sbc hl,de
               sbc a,c
               jr c,pnm4
               inc b
               jr pnm3
pnm4:          add hl,de
               adc a,c
               ld c,a
               ld a,b
               ld b,c
               and a
               jr nz,pnm5

               pop de         ; the digit is zero and nothing significant has been printed yet
               add d
               ret z          ; the pad character is zero: print nothing at all
               jr pnt

pnm5:          add "0"
               call pnt
               pop de
               ld a,"0"       ; from here on, zeros are printed rather than padded
               ret



; ---------------------------------------------------------------------------------------------------------------------
; ptm -- print the message that follows the call
;
; The text ends at the character with bit 7 set. The routine never returns to its caller: it takes the return address
; as the start of the message and returns past the end of it.
; ---------------------------------------------------------------------------------------------------------------------

;PRINT TEXT MESSAGE

ptm:           pop hl
ptm2:          ld a,(hl)
               and &7f
               call pnt
               bit 7,(hl)
               ret nz
               inc hl
               jr ptm2

;SEND A SPACE CHARACTER

spc:           ld a," "

;OUTPUT A CHAR TO CURRENT CHAN

pnt:           push af
               push bc
               push de
               push hl
               push ix

               call cmr
               defw rst.print

               pop ix
               pop hl
               pop de
               pop bc
               pop af
               ret


; ---------------------------------------------------------------------------------------------------------------------
; The DOS's messages
;
; Each is a call to ptm followed by the text. pmo4 is the copyright banner and is never called -- the README records
; that its wording changed with every version of the source.
; ---------------------------------------------------------------------------------------------------------------------

;SCREEN ROUTINES

pmo1:          call ptm
               defm "Tape ready ? "
               defm "press SPACE ."
               defb "."+128

pmo2:          call ptm
               defm " - DIRECTORY *"
               defw &8d0d

pmo3:          call ptm
               defw &0d0d
               defm "Number of Free "
               defm "K-Bytes ="
               defb &a0

pmo4:          call ptm
               defb &7f
               defm " MILES GORDON TECHNOLOGY plc  1"
               defw &8d0d

pmo5:          call ptm
               defm "OVERWRITE "
               defb """"+128

pmo6:          call ptm
               defm "Are you SURE ?"
               defm " (y/n"
               defb ")"+128

pmo7:          call ptm
               defm """ (y/n"
               defb ")"+128

pmo8:          call ptm
               defm "  * SAM DRIVE "
               defb &a0

pmo9:          call ptm
               defb &0d
               defm "Enter source disk "
               defm "press any ke"
               defb "y"+&80

pmoa:          call ptm
               defm "Format disk at "
               defm "track "
               defb " "+&80

pmob:          call ptm
               defm "Copy   disk at "
               defm "track "
               defb " "+&80

pmoc:          call ptm
               defm "Verify disk at "
               defm "track "
               defb " "+&80

pmod:          call ptm
               defm "Enter target disk "
               defm "press any ke"
               defb "y"+&80


; ---------------------------------------------------------------------------------------------------------------------
; tspce1 / tspce2 -- ask for the other disk during a single-drive copy
;
; Waits for a key to be pressed and then released, so that holding it down does not answer the next prompt too.
; ---------------------------------------------------------------------------------------------------------------------

tspce1:        call cmr
               defw clslow
               call pmod
tspc1:         call cmr
               defw rdkey
               jr nc,tspc1
tspc2:         call cmr
               defw rdkey
               jr c,tspc2
               call cmr
               defw clslow
               ret

tspce2:        call cmr
               defw clslow
               call pmo9
               jr tspc1
