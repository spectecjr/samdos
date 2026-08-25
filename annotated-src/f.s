
; =====================================================================================================================
; F.S -- The commands
; =====================================================================================================================
;
; The implementations the syntax dispatcher in b.s jumps to, plus the argument parsing they share.
;
;   calll                 CALL MODE n -- restart a saved snapshot, or enter code in another page
;   copy / gtcop / trx    COPY, including wildcards and the single-drive case
;   dir / pcat            DIR, and the free space figure
;   eraz                  ERASE
;   renam / findc         RENAME
;   prot / hide / sfbt    PROTECT and HIDE, which differ only in the bit they set
;   write / read / evprm  WRITE AT and READ AT: raw sector access
;   load / autox / dlvm1  LOAD, including snapshots and the BASIC program length calculation
;   wfod                  FORMAT
;   fndfl / fndflx        walk the directory, resuming where the last call left off
;   evnam .. evfile       the argument parsers
;
; ---------------------------------------------------------------------------------------------------------------------
; How a command runs twice
; ---------------------------------------------------------------------------------------------------------------------
;
; BASIC checks the syntax of a line before running it, and calls the DOS both times. Each command therefore parses
; its arguments, calls ceos to insist on the end of the statement, and only then does any work: on the syntax pass
; ceos does not return to its caller at all but falls through to ends, so everything after it is run-time only.
;
; Commands that take two file specifiers -- COPY, RENAME, FORMAT TO -- parse the first into the block at dstr1, call
; exdat to swap that block with the one at dstr2, and parse the second into the same place. The work is then done by
; running the same code twice with exdat between, so nothing has to be written to handle "the other file".
; =====================================================================================================================


; ---------------------------------------------------------------------------------------------------------------------
; calll -- CALL MODE n
;
; Two forms, neither of which is a general call:
;
;   CALL MODE 0   page 3 in and jump to &B914 -- the entry point of a resumed snapshot
;   CALL MODE 1   resume the snapshot the NMI code saved, through snap7
;
; Errors: err.stmtend for anything else
; ---------------------------------------------------------------------------------------------------------------------

;ZX ENTRY INTO RAM SPACE

calll:         call gtnc
               cp modtok      ;mode
               jp nz,rep2
               call gtnc
               call evnum
               call ceos

               ld a,c
               cp 0
               jr nz,call1
               ld a,3
               out (port.hmpr),a
               ld a,4
               out (port.vmpr),a
               di
               jp &b914

call1:         cp 1
               jp nz,rep2
               ld a,4
               out (port.vmpr),a
               jp snap7


; =====================================================================================================================
; copy -- COPY [OVER] "source" TO "target"
; =====================================================================================================================
;
; Copies every file matching the source name, which may contain wildcards. The pattern is kept in nstr3 while nstr1
; holds each match in turn, and trx builds the target name by applying the target pattern to the source name -- so
; COPY "*" TO "*" keeps the names and COPY "*.bak" TO "*.old" renames as it goes.
;
; When both specifiers name the same drive, flag bit 5 is set and the user is asked to swap disks between each read
; and write.
;
; Errors: err.notfound if nothing matched
; ---------------------------------------------------------------------------------------------------------------------

;DISC COPY ROUTINE

copy:          call gtnc
               cp ovrtok      ;over
               jr nz,copy0a
               call setf1
               call gtnc
copy0a:        call evnam
               cp totok       ;to
               jp nz,rep2
               call gtnc
               call evnam2
               call ceos

; OVER suppresses the "overwrite?" prompt in ofsm, which reads the ROM's own SAVE OVER flag rather than flag3.

               ld a,0
               call bitf1
               jr nz,l572d
               ld a,&0f
l572d:         call nrwr
               defw overf     ;"SAVE OVER" flag used by DOS. Zero if SAVE OVER, else non-zero

               ld hl,nstr1+1
               call evfile
               call ckdisc

               call exdat
               ld hl,nstr1+1
               call evfile
               call ckdisc
               ld hl,nstr1+1
               ld de,nstr3+1
               ld bc,fn.maxlen
               ldir
               ld a,(dstr1)
               ld b,a
               ld a,(dstr2)
               cp b
               call z,setf5   ; same drive both ends: the user will have to swap disks

copy1:         call exdat
               call ckdrv
               call fndfl
               jr c,copy2

               call bitf0
               jp z,rep26
               jp ends

copy2:         call gdifa
               call rsad
               call gtcop
               call ldblk

               call exdat
               call ckdrv
               call bitf5
               call nz,tspce1

               call trx
               call ofsm
               jr c,copy3     ; the user declined to overwrite: skip this file
               call gtcop
               call svblk
               call cfsm
copy3:         call setf0
               call bitf5
               call nz,tspce2
               jr copy1


; ---------------------------------------------------------------------------------------------------------------------
; gtcop -- point at the buffer a copy passes through
;
; A copy is read into page 3 at &8000 and written back out from there, so its size is limited by the page rather
; than by free memory. The length comes from the header just read.
; ---------------------------------------------------------------------------------------------------------------------

gtcop:         ld a,3
               out (port.hmpr),a
               ld a,(difa+34)
               ld (pges1),a
               ld hl,9
               ld de,(difa+35)
               add hl,de
               ex de,hl
               ld hl,&8000
               ret


; ---------------------------------------------------------------------------------------------------------------------
; dir -- DIR [#stream] [drive] ["pattern"] [!]
;
; With "!" the listing is names only, in columns; otherwise each entry gets its number, name, sector count and type.
; The default pattern is "*", set up by dirx, and the default stream is 2 -- the upper screen.
; ---------------------------------------------------------------------------------------------------------------------

;CALL UP DIRECTORY

dirx:          call gtdef
               ld a,"*"
               ld (nstr1+1),a
               ld a,2
               ld (sstr1),a
               ret


dir:           call gtixd
               call dirx

               call gtnc
               call ciel
               jr z,cat1a

               cp "#"
               jr nz,cat1
               call evsrm
               call separx

cat1:          call evdnm

               call separ
               call z,evnam
               cp "!"
               jr nz,cat2
               call gtnc

cat1a:         call ceos

               call ckdrv
               ld a,1<<fdh.compact
               jr cat3

cat2:          call ceos

               xor a
               call cmr
               defw clsbl     ;cls in sam
               call ckdrv
               ld a,1<<fdh.list

cat3:          call pcat
               jp ends


; ---------------------------------------------------------------------------------------------------------------------
; pcat -- print the catalogue  (hook code 165)
;
; fdhr does the listing itself and accumulates the total sectors used in cnt; this adds the heading and the free
; space figure. The disk's capacity is deduced from the track count, and halved to give kilobytes because a sector
; is half a K.
;
; A disk holding more than its nominal capacity -- which is possible, since the formatter will write as many tracks
; as traks1 asks for -- prints the excess as a negative figure.
;
; Entry:  A = the fdhr mode byte
; ---------------------------------------------------------------------------------------------------------------------

;SETUP FOR DIRECTORY
;NSTR1+1,*
;SSTR1  ,2
;A WITH ,2 OR 4

pcat:          push af
               ld a,(sstr1)
               call cmr
               defw stream
               ld a,&0d
               call pnt

               call pmo8
               ld a,(drive)
               and 3
               or "0"
               call pnt
               call pmo2
               ld hl,0
               ld (cnt),hl
               pop af
               call fdhr
               call pmo3
               call tstd
               ld hl,360      ; 40 tracks, one side: 400 sectors less the 40 the directory uses
               ld de,400
               cp 40
               jr z,trk2
               cp 80
               jr z,trk1      ; 80 tracks, one side: 760
               cp disk.side2+40
               jr z,trk1      ; 40 tracks, two sides: 760
               ld hl,1160     ; 80 tracks, two sides: 1560
trk1:          add hl,de
trk2:          ld de,(cnt)
               xor a
               sbc hl,de
               jr nc,pct1

               add hl,de      ; more used than the disk nominally holds: print the excess as negative
               ex de,hl
               sbc hl,de
               ld a,"-"
               call pnt

pct1:          srl h
               rr l           ; sectors to kilobytes
               xor a
               call pnum4
               ld a,&0d
               call pnt
               ret


; ---------------------------------------------------------------------------------------------------------------------
; eraz -- ERASE [OVER] "pattern"
;
; Deletes every matching file by zeroing the first byte of its directory entry; the sectors are freed implicitly,
; since free space is worked out from the entries that remain. A protected file is skipped with a beep unless OVER
; was given.
;
; Errors: err.notfound if nothing matched
; ---------------------------------------------------------------------------------------------------------------------

;ERASE A FILE

eraz:          call gtnc
               cp ovrtok      ;over
               jr nz,eraz1
               call setf1
               call gtnc

eraz1:         call evnam
               call ceos

               ld hl,nstr1+1
               call evfile
               call ckdisc

eraz3:         call fndflx
               jr nc,eraz5
               call bitf1
               jr nz,eraz4

               call point
               ld a,(hl)
               bit de.protectbit,a
               jr z,eraz4
               call beep
               jr eraz3

eraz4:         call point
               ld (hl),0
               call wsad
               call setf0
               jr eraz3

eraz5:         call bitf0
               jp z,rep26
               jp ends


; ---------------------------------------------------------------------------------------------------------------------
; fndfl -- find the next file matching nstr1
;
; Unlike fdhr this is resumable: flag bit 2 records that a search is already under way, and fndfr and fndts remember
; where it had got to, so calling again continues from the entry after the last match. That is what lets COPY work
; through a wildcard one file at a time.
;
; Exit:   CY and IX addressing the entry if a match was found, NC at the end of the directory
; ---------------------------------------------------------------------------------------------------------------------

;FIND A FILE IN THE DIRECTORY

fndfl:         call bitf2
               jr nz,fndf4
               call setf2
               ld ix,dchan
               call rest

fndf1:         xor a
               ld (ix+4),a
               ld (fndfr),a

fndf2:         call rsad
               ld (fndts),de

               ld a,(fndfr)
               ld (ix+rpth),a
               call point
               ld a,(hl)
               and a
               jr nz,fndf3

               inc hl
               ld a,(hl)
               and a
               jr nz,fndf4    ; a deleted entry: keep looking
               ret            ; never used: the end of the directory

fndf3:         call cknam
               jr nz,fndf4
               scf
               ret

fndf4:         ld de,(fndts)
               ld a,(fndfr)
               cp 1
               jr z,fndf5

               inc a
               ld (fndfr),a
               jr fndf2

fndf5:         call isect
               jr nz,fndf1
               inc d
               ld a,d
               cp disk.dirtrks
               ret nc
               jr fndf1


; ---------------------------------------------------------------------------------------------------------------------
; renam -- RENAME "old" TO "new"
;
; The new name must not already exist and the old one must. Only the ten name characters are written back; the type
; and everything else in the entry are left alone.
;
; Errors: err.nameused, err.notfound
; ---------------------------------------------------------------------------------------------------------------------

;RENAME A FILE

renam:         call gtnc
               call evnam
               cp totok       ;to
               jp nz,rep2
               call gtnc
               call evnam2
               call ceos

               ld hl,nstr1+1
               call evfile
               call ckdisc

               call exdat
               ld hl,nstr1+1
               call evfile
               call ckdisc

               call findc
               jp z,rep28     ; the new name is already in use
               call exdat

               call findc
               jp nz,rep26
               inc hl
               push de
               ld de,nstr2+1
               ex de,hl
               ld bc,de.namelen
               ldir
               pop de
               call wsad
               jp ends


;FIND A FILE ROUTINE

findc:         ld a,1<<fdh.name
               call fdhr
               jp point


; ---------------------------------------------------------------------------------------------------------------------
; prot / hide -- PROTECT and HIDE, with OFF to reverse them
;
; Both set bits in the type byte of every matching entry: protect sets bit 6, hide sets bits 6 and 7 together, so a
; hidden file is always protected as well.
;
; Errors: err.notfound if nothing matched
; ---------------------------------------------------------------------------------------------------------------------

;PROTECT ROUTINE

prot:          ld a,de.protect
               jr sfbt

;HIDE FILE ROUTINE

hide:          ld a,de.hide

sfbt:          ld (hstr1),a
               call gtnc
               cp offtok      ;off
               jr nz,sfb1
               call setf1
               call gtnc

sfb1:          call evnam
               call ceos

               ld hl,nstr1+1
               call evfile
               call ckdisc

sfb2:          call fndflx
               jr c,sfb3
               call bitf0
               jp z,rep26
               jp ends

sfb3:          ld (ix+rptl),de.type
               call grpnt
               ld a,(hstr1)
               ld c,a
               cpl
               ld b,a
               ld a,(hl)
               and b          ; clear the bits either way
               call bitf1
               jr nz,sfb4     ; OFF: leave them clear
               or c           ; otherwise set them
sfb4:          ld (hl),a
               call wsad
               call setf0
               jr sfb2



; ---------------------------------------------------------------------------------------------------------------------
; separ / separx -- accept an argument separator
;
; A comma or a semicolon separates arguments and is stepped over; a quote is the start of the next argument and is
; left alone.
;
; Exit:   separ -- Z if a separator was found and skipped
; Errors: separx -- err.stmtend if there was no separator
; ---------------------------------------------------------------------------------------------------------------------

;SEPARATOR REPORT ROUTINE

separx:        call separ
               ret z
               jp rep2


;THE SEPARATOR SUBROUTINE

separ:         cp ","
               jr z,sepa1
               cp ";"
               jr z,sepa1
               cp """"
               ret

sepa1:         call gtnc
               ld (sva),a
               xor a          ; set Z, which the caller tests
               ld a,(sva)
               ret



; ---------------------------------------------------------------------------------------------------------------------
; evprm -- parse "AT drive,track,sector,address" for READ and WRITE
;
; Every argument is optional after the drive: anything omitted keeps whatever the previous command left in the hook
; register block, which is where the values are collected.
; ---------------------------------------------------------------------------------------------------------------------

;EVALUATE PARAMETERS IN SYNTAX

evprm:         call gtnc

               cp &87         ;at
               jp nz,rep2

;GET DRIVE NUMBER

               call gtnc
               call evdnm

;GET TRACK NUMBER

               call separx
               call evnum
               jr z,evpr1

               ld d,c
               ld (hkde),de

;GET SECTOR NUMBER

evpr1:         call separx
               call evnum
               jr z,evpr2

               ld de,(hkde)
               ld e,c
               ld (hkde),de

;GET ADDRESS

evpr2:         call separx
               call evnum
               jr z,evpr3

               ld (hkhl),bc

evpr3:         call ceos

               ld a,(dstr1)
               ld (hka),a
               ret


; ---------------------------------------------------------------------------------------------------------------------
; svhd -- write the nine-byte file header
;
; The header goes into the directory entry image and into the file itself, so that a file carries its own type,
; length and address independently of the directory.
; ---------------------------------------------------------------------------------------------------------------------

;SAVE HEADER INFORMATION

svhd:          ld hl,hd001
               ld de,fsa+de.hdr
               ld b,9
svhd1:         ld a,(hl)
               ld (de),a
               call sbyt
               inc hl
               inc de
               djnz svhd1
               ret


; ---------------------------------------------------------------------------------------------------------------------
; write / read -- WRITE AT and READ AT: raw sector access
;
; Neither goes near the directory. The sector is transferred between the disk and the address given, through the
; same hook routines the ROM would use.
; ---------------------------------------------------------------------------------------------------------------------

;WRITE AT A TRACK AND SECTOR

write:         call gtixd
               call evprm

               call hwsad
               jp ends


;READ AT A TRACK AND SECTOR

read:          call gtixd
               call evprm

               call hrsad
               jp ends


;LOAD HEADER INFORMATION

ldhd:          ld b,9
ldhd1:         call lbyt
               djnz ldhd1
               ret


; =====================================================================================================================
; load -- LOAD
; =====================================================================================================================
;
; Handles the cases the ROM cannot: a 48K snapshot, which has to be loaded and then resumed rather than returned
; from, and a BASIC program, whose length the DOS works out from the ROM's own pointers.
;
; During the syntax pass the statement is walked and every five-byte number form the ROM compiled into it is
; reclaimed, so that the arguments are evaluated fresh at run time rather than from stale compiled values. BC still
; holds the address of the start of the statement, put there by the syntax dispatcher in b.s.
; ---------------------------------------------------------------------------------------------------------------------

;LOAD SYNTAX COMMAND

load:          call gtixd
               call gtnc
               call cfso
               jr nz,load3

               push bc
               pop hl
load1:         ld a,(hl)
               cp nummark
               jr nz,load2
               ld bc,nummarklen
               call cmr
               defw reclaim   ; JRECLAIM

load2:         ld a,(hl)
               inc hl
               cp &0d
               jr nz,load1

load3:         call evnum

               push af
               ld a,c
               ld (fstr1),a
               call gtdef
               pop af
               call ceos

               call gtfle

; A 48K snapshot: page the machine as the snapshot expects, load it under the DOS's own stack, and resume it.

autox:         ld a,(difa)
               cp ft.screen
               jr nz,dlvm1
               call bitf7
               jr z,dlvm1

;48k SNAPSHOT IS FOUND

               ld de,(svde)
               call rsad

               in a,(port.lmpr)
               ld (snprt0),a
               in a,(port.hmpr)
               ld (snprt1),a
               in a,(port.vmpr)
               ld (snprt2),a

               ld a,%00000100
               out (port.hmpr),a
               out (port.vmpr),a

               ld sp,str-20
               ld hl,&8000
               ld de,page.size
               ld a,2
               ld (pges1),a
               call ldblk
               jp snap7

; A BASIC program: fill in the start and length the ROM will need, computed from prog and eline. The two page/address
; pairs are normalised by ahln and subtracted, and the result converted into the page form the header uses.

dlvm1:         cp ft.basic
               jr nz,dlvm2
               call bitf7
               jp nz,rep13

               call nrrdd
               defw prog
               push bc
               pop hl

               call nrrd
               defw progp
               ld (uifa+hdr.start),a
               ld (uifa+hdr.start+1),hl
               ex de,hl
               ld c,a

               push bc
               call nrrdd
               defw eline
               push bc
               pop hl

               call nrrd
               defw elinp

               pop bc
               dec hl
               bit 7,h
               jr nz,lab2
               dec a
lab2:          push bc
               push de
               call ahln
               push af
               ex de,hl
               ld a,c
               call ahln
               ex de,hl
               ld c,a
               pop af
               and a
               sbc hl,de
               sbc a,c
               pop de
               pop bc
               rl h
               rla
               rl h
               rla
               rr h
               scf
               rr h
               ld (uifa+hdr.length),a
               ld (uifa+hdr.length+1),hl
               xor a
               ld (uifa+hdr.flags),a

dlvm2:         call txinf
               call txhed
               jp endsx       ; E = 1: the ROM's own loader takes it from here


; ahln -- normalise a page and address pair so that the address lies within one 16K page and the surplus has been
; moved into the page number.

ahln:          rlc h
               rlc h
               rra
               rr h
               rra
               rr h
               and 7
               ret


; ---------------------------------------------------------------------------------------------------------------------
; wfod -- FORMAT "disk" [TO "disk"]
;
; With TO, the second disk is copied onto the first once it has been formatted. Either way the user is asked to
; confirm, since the operation destroys everything on the target.
; ---------------------------------------------------------------------------------------------------------------------

;WRITE FORMAT ON DISC

wfod:          call gtnc
               cp totok       ;to
               jr z,wfod1
               call ciel
               jr z,wfod2

               call evnam

               cp totok       ;to
               jr nz,wfod2
wfod1:         ld (hstr1),a   ; remember that TO was given

               call gtnc
               call evnam2

wfod2:         call ceos

               ld hl,nstr1+1
               call evfile
               call ckdisc

               ld a,(hstr1)
               cp totok
               jr nz,wfod3

               call exdat
               ld hl,nstr1+1
               call evfile
               call ckdisc
               call exdat


wfod3:         call pmo6
               call cyes
               jp nz,ends

               call dfmt
               jp ends


; ---------------------------------------------------------------------------------------------------------------------
; The argument parsers
;
; Each evaluates one thing through the ROM's expression evaluator and stores it in the parameter block, and each
; returns without storing anything on the syntax pass -- cfso reports which pass this is.
; ---------------------------------------------------------------------------------------------------------------------

;CHECK VALID SPECIFIER DISC

ckdisc:        ld a,(lstr1)
               cp "D"
               jp nz,rep10
               jp ckdrv

;EVALUATE DRIVE NUMBER

evdnm:         call evnum
               ret z

               push af
               ld a,c
               ld (dstr1),a
               pop af
               ret

;EVALUATE STREAM INFORMATION

evsrm:         call gtnc
evsrmx:        call evnum
               ret z

               push af
               ld a,c
               cp maxstream
               jp nc,rep9
               ld (sstr1),a
               pop af
               ret


;EVALUATE NUMBER ROUTINE

evnum:         call cmr
               defw expnum
               call cfso
               ret z

               push af
               call cmr
               defw getint
               pop af
               ret


; ---------------------------------------------------------------------------------------------------------------------
; fndflx -- the resumable directory walk used by ERASE, HIDE and PROTECT
;
; Differs from fndfl in that it keeps its place with svdpt and svtrs and re-reads the sector each time round, which
; it must because the caller writes the entry back between calls.
;
; Exit:   CY and IX addressing the entry if a match was found, NC at the end of the directory
; ---------------------------------------------------------------------------------------------------------------------

;FIND A FILE IN THE DIRECTORY - for ERASE / HIDE / PROTECT

fndflx:        call bitf2
               jr nz,fndflx3
               call setf2
               ld ix,dchan
               xor a
               ld (ix+4),a
               call rest

fndflx1:       call rsad
               ld (svtrs),de

fndflx2:       call point
               ld a,(ix+rpth)
               ld (svdpt),a
               ld a,(hl)
               and a
               jr z,fndflx3
               call cknam
               jr nz,fndflx3
               scf
               ret

fndflx3:       ld a,(svdpt)
               ld (ix+rpth),a
               cp 1
               jr z,fndflx4
               call clrrpt
               inc (ix+rpth)
               jr fndflx2

fndflx4:       ld de,(svtrs)
               call isect
               jr nz,fndflx1
               inc d
               ld a,d
               cp disk.dirtrks
               ret nc
               jr fndflx1




; ---------------------------------------------------------------------------------------------------------------------
; evsp -- evaluate a channel specifier
;
; Unreferenced. It would have accepted a one-character string naming a channel, for a version of the DOS with the
; record-structured channels the unused equates in a.s describe.
; ---------------------------------------------------------------------------------------------------------------------

;EVALUATE CHANNEL SPECIFIER

evsp:          call gtnc
evspx:         call evstr
               jr z,evsp1

               push af
               ld a,c
               dec a
               or b
               jp nz,rep10

               ex de,hl
               call cmr
               defw nrread
               call alpha
               jp nc,rep10

               ld (lstr1),a
               pop af

evsp1:         cp ";"
               ret z
               cp ","
               ret z
               jp rep0




; ---------------------------------------------------------------------------------------------------------------------
; evnam2 / exdat -- parse the second file name
;
; exdat swaps the two parameter blocks, so that whichever file is being worked on is always the one at dstr1.
; ---------------------------------------------------------------------------------------------------------------------

;EVALUATE SECOND FILE NAME

evnam2:        call exdat
               call evnam

exdat:         push af
               push bc
               push de
               push hl

               ld b,28        ; the size of one parameter block: dstr1 through page1
               ld de,dstr1
               ld hl,dstr2
exdt1:         ld a,(de)
               ld c,(hl)
               ex de,hl
               ld (de),a
               ld (hl),c
               inc de
               inc hl
               djnz exdt1

               pop hl
               pop de
               pop bc
               pop af
               ret


; ---------------------------------------------------------------------------------------------------------------------
; evnam -- evaluate a file name
;
; The name field is cleared to spaces first, so a short name is padded. The string may live in any page, so the page
; getstr reported is mapped in for the copy and the caller's paging restored afterwards.
;
; Errors: err.badname if the name is empty or longer than fn.maxlen
; ---------------------------------------------------------------------------------------------------------------------

;EVALUATE FILE NAME

evnam:         call evstr
               ret z

               push af
               ld a,c
               or b
               jp z,rep8

               ld hl,fn.maxlen
               sbc hl,bc
               jp c,rep8

               ld hl,nstr1
               ld a,fn.field
evnm1:         ld (hl),&20
               inc hl
               dec a
               jr nz,evnm1

               ld hl,nstr1+1
               ex de,hl

               in a,(port.hmpr)
               push af
               ld a,(svc)
               and page.mask
               out (port.hmpr),a
               ldir
               pop af
               out (port.hmpr),a

               pop af
               ret


;EVALUATE STRING EXPRESSION

evstr:         call cmr
               defw expstr
               call cfso
               ret z

               push af
               call cmr
               defw getstr
               ld (svc),a     ; the page the string lives in
               pop af
               ret


; ---------------------------------------------------------------------------------------------------------------------
; alpha / number -- character class tests
;
; number is unreferenced.
;
; Exit:   alpha -- CY if A is a letter of either case
; ---------------------------------------------------------------------------------------------------------------------

;CHECK FOR ALPHA CHAR

alpha:         cp "A"
               ccf
               ret nc
               cp "Z"+1
               ret c
               cp "a"
               ccf
               ret nc
               cp "z"+1
               ret


;CHECK FOR NUMBER

number:        sub "0"
               cp 10
               ret nc
               jp rep11


; ---------------------------------------------------------------------------------------------------------------------
; trx -- build the target name for a copy
;
; Starts from the source file's own name and applies the target pattern to it: "?" keeps the character underneath,
; "*" keeps everything up to the ".", and anything else replaces.
; ---------------------------------------------------------------------------------------------------------------------

;TRANSFER FILE NAMES IN COPY

trx:           ld hl,difa
               ld de,nstr1
               ld bc,fn.field
               ldir

               ld hl,nstr3+1
               ld de,nstr1+1
               ld b,de.namelen

trx1:          ld a,(hl)
               cp "*"
               jr z,trx3
               cp "?"
               jr z,trx2
               ld (de),a
trx2:          inc hl
               inc de
               djnz trx1
               ret

trx3:          inc hl
               ld a,(hl)
               cp "."
               ret nz
trx4:          ld a,(de)
               cp "."
               jr z,trx2
               inc de
               djnz trx4
               ret


; ---------------------------------------------------------------------------------------------------------------------
; gdifa -- copy a directory entry into difa, ready for a copy or a load
;
; Exit:   DE = the track and sector of the file's first sector
; ---------------------------------------------------------------------------------------------------------------------

gdifa:         call point
               ld de,difa
               ld bc,de.namelen+1
               ldir
               ld b,4
               call lcnta
               ld (ix+rptl),de.tail
               call grpnt
               ld bc,33
               ldir

               ld hl,difa
               ld de,uifa
               ld bc,hdr.size
               ldir

               ld (ix+rptl),de.track
               call grpnt
               ld d,(hl)
               inc hl
               ld e,(hl)
               ret
