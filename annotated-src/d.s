
; =====================================================================================================================
; D.S -- ROM interface, the flag byte, error reporting, and the NMI snapshot
; =====================================================================================================================
;
; Four unrelated groups share this file:
;
;   smchk .. sum          a checksum over the DOS image. Never called
;   ciel .. brktst        parsing helpers: end of statement, syntax pass, BREAK
;   gtnc .. nrwr, gthl    the ROM interface -- reading and writing system variables across the paging
;   hlfg, setf0 .. bitf7  the DOS's own flag byte
;   bcc, bcr              the border colour flashed during disk access
;   rep0 .. derr, errtbl  error reporting and the message table
;   conr, nmi .. snap8    the NMI snapshot: dump the machine's state to disk at the touch of a button
;
; ---------------------------------------------------------------------------------------------------------------------
; Reaching the ROM's system variables
; ---------------------------------------------------------------------------------------------------------------------
;
; The DOS occupies &4000-&7FFF, which is where the ROM's system variables also live. To read one, the DOS asks the
; ROM to map the system page and run a one-instruction helper there: cmr (jump table entry &0103) does the paging and
; the stack switch, and nrread and nrrite are LD A,(HL) / RET and LD (HL),A / RET in ROM 0.
;
; The wrappers below hide the whole arrangement behind an inline argument, so a read looks like:
;
;       call nrrd
;       defw chadd
;
; They work by popping their own return address, which points at the word, reading through it, and pushing the
; address back one word further on.
; =====================================================================================================================


; ---------------------------------------------------------------------------------------------------------------------
; smchk / chksm / sum -- checksum the DOS image
;
; None of the three is referenced. That is fortunate, because the length is wrong: size is defined as
; zzend-gnd+&0220 where it should subtract that offset rather than add it, so the sum would run &440 bytes past the
; end of the image.
; ---------------------------------------------------------------------------------------------------------------------

;CHECKSUM CALCULATE ON DOS

smchk:         call sum
               ld (hl),a
               ret


;CHECKSUM CHECK ON DOS

chksm:         call sum
               cp (hl)
               ret


sum:           xor a
               push af
               ld hl,gnd+&0220
               ld bc,size

sum1:          pop af
               add (hl)
               push af
               inc hl
               dec bc
               ld a,b
               or c
               jr nz,sum1
               pop af
               ret



; ---------------------------------------------------------------------------------------------------------------------
; ciel / cfso / ceos -- statement parsing helpers
;
; ciel   is the character at chadd the end of a statement?
; cfso   is this the run pass or the syntax-checking pass? A is preserved across the call through sva
; ceos   insist on the end of the statement, then return NZ on the run pass and fall through to ends on the syntax
;        pass -- which is how every command returns to BASIC without executing anything while syntax is being checked
;
; Exit:   ciel -- Z at a carriage return or a colon
;         cfso -- NZ when running, Z when syntax checking, A unchanged
; Errors: ceos -- err.stmtend
; ---------------------------------------------------------------------------------------------------------------------

;CHECK IS IT END OF LINE

ciel:          call gchr
               cp &0d         ;cr
               ret z
               cp &3a         ;:
               ret


;CHECK FOR SYNTAX ONLY

cfso:          ld (sva),a
               call nrrd
               defw flags
               and flags.running
               ld a,(sva)
               ret


;CHECK FOR END OF SYNTAX

ceos:          call ciel
               jp nz,rep2
               call cfso
               ret nz


; ---------------------------------------------------------------------------------------------------------------------
; ends / endsx -- finish a command and return to BASIC
;
; Clears the error marker and the "DOS busy" flag, unwinds the stack to where the command started, and restores the
; border. E is the value the ROM reads back: zero means the command is complete, one means it wants the ROM's own
; load/save machinery to continue.
; ---------------------------------------------------------------------------------------------------------------------

;END OF STATEMENT

ends:          ld e,0
end1:          xor a
               call nrwr
               defw xptr+1

               call nrwr
               defw dosact

               ld sp,(entsp)
               jp bcr

endsx:         ld e,1
               jr end1


; ---------------------------------------------------------------------------------------------------------------------
; brktst -- has the ESC key been pressed?
;
; Reads the keyboard row selected by putting &F7 on the high address lines and tests the bit ESC occupies. Called
; from inside the drive polling loops, so that a disk that never becomes ready can still be escaped from.
;
; Errors: err.escape
; ---------------------------------------------------------------------------------------------------------------------

;TEST FOR BREAK ROUTINE

brktst:        ld a,&f7
               in a,(port.status)
               and &20
               ret nz

               jp rep3



; ---------------------------------------------------------------------------------------------------------------------
; gtnc / gchr -- the next character, and the current one
;
; Both go through the ROM's RST &18 and RST &20 handlers, which understand the invisible five-byte number forms
; embedded in a tokenised line and skip over them.
; ---------------------------------------------------------------------------------------------------------------------

;GET THE NEXT CHAR.

gtnc:          call cmr
               defw rst.nextchr
               ret


;GET THE CHAR UNDER POINTER

gchr:          call cmr
               defw rst.getchr
               ret


; ---------------------------------------------------------------------------------------------------------------------
; nrrdd / nrrd / nrwrd / nrwr -- read and write ROM system variables
;
; Each takes the address of the variable in the word following the call.
;
;   nrrd   A  = the byte at that address
;   nrrdd  BC = the word
;   nrwr   writes A
;   nrwrd  writes BC
;
; Exit:   the return address has been advanced past the inline word; HL and DE are preserved
; ---------------------------------------------------------------------------------------------------------------------

;READ A DOUBLE ROM WORD IN BC

nrrdd:         ex (sp),hl
               push de
               call gthl
               push de
               call cmr
               defw nrread
               ld c,a
               inc hl
               call cmr
               defw nrread
               ld b,a
               pop hl
               pop de
               ex (sp),hl
               ret


;READ A ROM SYSTEM VARIABLE

nrrd:          ex (sp),hl
               push de
               call gthl
               push de
               call cmr
               defw nrread
               pop hl
               pop de
               ex (sp),hl
               ret


;WRITE A DOUBLE WORD IN BC

nrwrd:         ex (sp),hl
               push de
               call gthl
               push de
               ld a,c
               call cmr
               defw nrrite
               inc hl
               ld a,b
               call cmr
               defw nrrite
               pop hl
               pop de
               ex (sp),hl
               ret


;WRITE ROM SYSTEM VARIABLE

nrwr:          ex (sp),hl
               push de
               call gthl
               push de
               call cmr
               defw nrrite
               pop hl
               pop de
               ex (sp),hl
               ret


; gthl -- fetch the inline word at (HL) into HL, leaving DE pointing past it. The caller then pushes DE back as the
; return address, so control resumes after the word.

gthl:          ld e,(hl)
               inc hl
               ld d,(hl)
               inc hl
               ex de,hl
               ret


; =====================================================================================================================
; flag3 -- the DOS's flag byte
; =====================================================================================================================
;
; There is one routine per bit for setting and one for testing, rather than a parameterised pair, because that is
; cheaper at every call site. hlfg is the shared prologue: it pushes the caller's return address a second time so
; that the "pop hl / ret" at the end of each routine returns to the right place with HL restored.
;
; The bits, as far as the code reveals them:
;
;   0  something was found or done -- set by ERASE, COPY and PROTECT for each file they act on, and tested at the
;      end to decide whether to report "File not found"
;   1  a qualifier was present: OVER on ERASE and COPY, OFF on PROTECT and HIDE
;   2  a directory search is already in progress, so fndfl and fndflx should resume rather than restart
;   3  a hook save is running
;   5  COPY's source and target are the same drive, so the user must swap disks between reads and writes
;   6  a block transfer is running, which tells ctas to fix up the transfer address when it crosses &C000
;   7  the file is a Spectrum type, renumbered into the SAM range by gtfle
;
;   4  never set or tested
; ---------------------------------------------------------------------------------------------------------------------

;GET THE HALF FLAG3

hlfg:          ex (sp),hl
               push hl
               ld hl,flag3
               ret



;SET FLAG3 SUBROUTINE

setf0:         call hlfg
               set 0,(hl)
               pop hl
               ret

setf1:         call hlfg
               set 1,(hl)
               pop hl
               ret

setf2:         call hlfg
               set 2,(hl)
               pop hl
               ret

setf3:         call hlfg
               set 3,(hl)
               pop hl
               ret

setf4:         call hlfg
               set 4,(hl)
               pop hl
               ret

setf5:         call hlfg
               set 5,(hl)
               pop hl
               ret

setf6:         call hlfg
               set 6,(hl)
               pop hl
               ret

setf7:         call hlfg
               set 7,(hl)
               pop hl
               ret



;BIT TEST OF FLAG3 ROUTS.

bitf0:         call hlfg
               bit 0,(hl)
               pop hl
               ret

bitf1:         call hlfg
               bit 1,(hl)
               pop hl
               ret

bitf2:         call hlfg
               bit 2,(hl)
               pop hl
               ret

bitf3:         call hlfg
               bit 3,(hl)
               pop hl
               ret

bitf4:         call hlfg
               bit 4,(hl)
               pop hl
               ret

bitf5:         call hlfg
               bit 5,(hl)
               pop hl
               ret

bitf6:         call hlfg
               bit 6,(hl)
               pop hl
               ret

bitf7:         call hlfg
               bit 7,(hl)
               pop hl
               ret


; ---------------------------------------------------------------------------------------------------------------------
; bcc / bcr -- flash the border during disk access
;
; The colour is taken from the low bits of rbcc, and ANDed with E -- the sector number -- so the border changes as
; the head moves across the disk. Setting rbcc to zero turns the effect off. bcr puts the BASIC border back.
; ---------------------------------------------------------------------------------------------------------------------

;BORDER COLOUR CHANGE

bcc:           ld a,(rbcc)
               and &0f
               ret z
               and 7
               and e
               out (ula),a
               ret

;BORDER COLOUR RESTORE

bcr:           push af
               call nrrd
               defw bordcr
               out (ula),a
               pop af
               ret


; =====================================================================================================================
; Error reporting
; =====================================================================================================================
;
; Each rep stub calls derr with its code in the byte that follows, which derr picks up from its own return address.
; The ROM treats codes of err.base and above as belonging to the DOS and fetches the text from errtbl, whose address
; it finds at gnd+&0210.
;
; A hook that failed unwinds to the stack pointer saved in hksp, so the ROM's own code can report the failure. A
; command that failed unwinds to entsp and leaves the error marker at the current position in the line.
; ---------------------------------------------------------------------------------------------------------------------

;ERROR REPORT MESSAGES

rep0:          call derr
               defb err.nonsense

rep1:          call derr
               defb err.snos

rep2:          call derr
               defb err.stmtend

rep3:          call derr
               defb err.escape

rep4:          call derr
               defb err.trkerr

rep5:          call derr
               defb err.fmtlost

rep6:          call derr
               defb err.checkdsk

rep7:          call derr
               defb err.noboot

rep8:          call derr
               defb err.badname

rep9:          call derr
               defb err.badstn

rep10:         call derr
               defb err.baddev

rep11:         call derr
               defb err.novar

rep12:         call derr
               defb err.verify

rep13:         call derr
               defb err.badtype

rep14:         call derr
               defb err.merge

rep15:         call derr
               defb err.code

rep16:         call derr
               defb err.pupil

rep17:         call derr
               defb err.badcode

rep18:         call derr
               defb err.readwrite

rep19:         call derr
               defb err.writeread

rep20:         call derr
               defb err.noauto

rep21:         call derr
               defb err.netoff

rep22:         call derr
               defb err.nodrive

rep23:         call derr
               defb err.wprot

rep24:         call derr
               defb err.nospace

rep25:         call derr
               defb err.dirfull

rep26:         call derr
               defb err.notfound

rep27:         call derr
               defb err.eof

rep28:         call derr
               defb err.nameused

rep29:         call derr
               defb err.nodos

rep30:         call derr
               defb err.strmused

rep31:         call derr
               defb err.chanused


; ---------------------------------------------------------------------------------------------------------------------
; conr -- three decimal digits for the number in A
;
; Leading zeros come back as spaces.
;
; Exit:   A = hundreds, B = units, C = tens
; ---------------------------------------------------------------------------------------------------------------------

;CONVERT NUMBER IN A

conr:          push de
               ld h,0
               ld l,a
               ld de,100
               call conr1
               push af
               ld de,10
               call conr1
               push af
               ld a,l
               add "0"
               ld b,a
               pop af
               ld c,a
               pop af
               pop de
               ret


conr1:         xor a
conr2:         sbc hl,de
               jr c,conr3
               inc a
               jr conr2
conr3:         add hl,de
               and a
               jr nz,conr4
               ld a," "
               ret
conr4:         add "0"
               ret



; ---------------------------------------------------------------------------------------------------------------------
; derr -- report a DOS error
;
; The track and sector in DE are converted to decimal and patched into the two messages that quote them, so the
; report names the sector that failed. The code itself is read from the byte after the caller's call.
;
; Entry:  DE = track and sector, the return address pointing at the error code
; Exit:   does not return: the stack is unwound to entsp, or to hksp if a hook is in progress
; ---------------------------------------------------------------------------------------------------------------------

;SAMDOS ERROR PRINT
;DE HOLDS TRACK AND SECTOR

derr:          call bcr

               ld hl,(hksp)
               ld a,h
               or l
               jr z,derr1
               ld sp,hl
               ret            ; a hook is in progress: unwind to it and let the ROM report

derr1:         ld a,d
               call conr
               ld (prtrk),a
               ld (fmtrk),a
               ld (prtrk+1),bc
               ld (fmtrk+1),bc
               ld a,e
               call conr
               ld (prsec),bc

               call nrrdd
               defw chadd
               call nrwrd
               defw xptr      ; mark the error position in the line

               xor a
               ld (flag3),a
               ld e,a
               pop hl
               ld a,(hl)      ; the error code, from the byte after the call
               ld sp,(entsp)
               ret



; ---------------------------------------------------------------------------------------------------------------------
; errtbl -- the DOS error messages, in code order from err.base
;
; Each message ends by setting bit 7 of its last character. The ROM finds the table through the pointer at gnd+&0210
; and prints from it whenever it reports a code of err.base or above.
;
; The digits inside the fifth and sixth messages are overwritten by derr with the track and sector that failed.
; ---------------------------------------------------------------------------------------------------------------------

errtbl:        defm "Nonsense in "
               defm "SAMDOS 1."
               defb "1"+&80

               defm "Nonsense in "
               defm "SNOS 1."
               defb "1"+&80

               defm "Statement "
               defm "end erro"
               defb "r"+&80

               defm "Escape requeste"
               defb "d"+&80

               defm "TRK-"
prtrk:         defb &20
               defb &20
               defb "0"
               defm ",SCT-"
prsec:         defb &20
               defb "5"
               defm ",Erro"
               defb "r"+&80

               defm "Format TRK-"
fmtrk:         defb &20
               defb &20
               defb "0"
               defm " los"
               defb "t"+&80

               defm "Check disk in "
               defm "driv"
               defb "e"+&80

               defm "No ""BOOT"" fil"
               defb "e"+&80

               defm "Invalid file nam"
               defb "e"+&80

               defm "Invalid statio"
               defb "n"+&80

               defm "Invalid devic"
               defb "e"+&80

               defm "Variable not foun"
               defb "d"+&80

               defm "Verify faile"
               defb "d"+&80

               defm "Wrong file typ"
               defb "e"+&80

               defm "Merge erro"
               defb "r"+&80

               defm "Code erro"
               defb "r"+&80

               defm "Pupil se"
               defb "t"+&80

               defm "Invalid cod"
               defb "e"+&80

               defm "Reading "
               defm "a write fil"
               defb "e"+&80

               defm "Writing "
               defm "a read fil"
               defb "e"+&80

               defm "no AUTO* fil"
               defb "e"+&80

               defm "Network of"
               defb "f"+&80

               defm "No such driv"
               defb "e"+&80

               defm "Disk is write "
               defm "protecte"
               defb "d"+&80

               defm "Not enough space "
               defm "on dis"
               defb "k"+&80

               defm "Directory ful"
               defb "l"+&80

               defm "File not foun"
               defb "d"+&80

               defm "End of fil"
               defb "e"+&80

               defm "File name use"
               defb "d"+&80

               defm "No SAMDOS loade"
               defb "d"+&80

               defm "Stream use"
               defb "d"+&80

               defm "Channel use"
               defb "d"+&80

ertabx:        defb 0



; =====================================================================================================================
; nmi -- the snapshot button
; =====================================================================================================================
;
; Pressing the NMI button freezes whatever is running and offers to write it to disk, so that a game can be resumed
; later. The whole machine state is pushed onto a stack in the DOS's own page, and the keys held down when the button
; was pressed choose what to save:
;
;   nothing   resume, having done nothing
;   2         the screen only, as a 6912-byte Spectrum SCREEN$
;   3         a 48K snapshot
;   4         cycle through the memory pages, so a page other than the default can be captured
;
; The file name is formed from the drive and the directory position it lands in, so successive snapshots do not
; collide. Control returns through snap7, which restores everything and jumps back to the interrupted code.
; ---------------------------------------------------------------------------------------------------------------------

;NON MASK INT ROUT.

nmi:           ld (str),sp
               ld sp,str
               ld a,i
               push af
               push hl
               push bc
               push de
               ex af,af'
               exx
               push af
               push hl
               push bc
               push de
               push ix
               push iy


;PUSH RETURN ADDRESS ON STACK

               ld hl,snap7
               push hl
               ld (hksp),sp   ; an error during the save unwinds to here, which resumes the program

;TEST FOR SNAPSHOT TYPE

               ld a,4
               out (port.hmpr),a
               ld hl,&8000
               im 1

snap3:         ld bc,&f7fe
               in e,(c)

               bit 1,e        ;save scr
               ret z          ; no key held: return through snap7 and resume

               bit 2,e        ;save scr
               jr nz,snap3a
               ld a,ft.code
               ld de,6912     ; a Spectrum screen -- pixels plus attributes -- saved as a code file
               jr snap4

snap3a:        bit 3,e        ;snp 48k
               jr nz,snap3b
               ld a,ft.zxsnap48
               ld de,49152
               jr snap4

; Step to the next page and wait for the key to be released, so the user can pick which page is captured.

snap3b:        inc a
               and 7
               out (c),a
               ld b,&fe
               in e,(c)
               bit 2,e
               jr nz,snap3

snap3c:        in e,(c)
               bit 2,e
               jr z,snap3c

               ld bc,0
snap3d:        dec bc
               ld a,b
               or c
               jr nz,snap3d

               ld a,(snprt0)
               out (port.hmpr),a
               ld a,(snprt2)
               out (port.vmpr),a
               ei
               jp ends

;SAVE VARIABLES OF FILE

snap4:         ld (snme),a
               ld (snlen),de
               ld (snadd),hl

;TEST FOR DIRECTORY SPACE

               ld ix,dchan
               ld b,&fe
               in a,(c)
               bit 0,a        ; CAPS held selects drive 2
               ld a,1
               jr nz,snap4a
               ld a,2
snap4a:        call ckdrx
               ld a,1<<fdh.free
               call fdhr
               ret nz         ; directory full: resume without saving

;FORM SNAPSHOT FILE NAME
; The name ends with the drive number and a letter derived from the directory position, so each snapshot is unique.

               ld a,d
               and 7
               jr z,snap5
               add "0"
               ld (snme+5),a
snap5:         ld l,e
               sla l
               dec l
               ld a,(ix+rpth)
               add l
               add &40
               ld (snme+6),a

;TRANSFER NAME TO FILE AREA

               ld hl,snme
               ld de,nstr1
               ld bc,24
               ldir

;OPEN A FILE

               xor a
               ld (flag3),a
               ld (pges1),a
               call ofsm

;SAVE REGISTERS IN DIRECTORY
; A 48K snapshot carries the 22 bytes of saved registers in its directory entry, so that whatever reloads it can put
; the machine back as it was. Anything else gets the ordinary nine-byte file header written by svhd, followed by the
; fixed filler in snptab.

               ld hl,str-20
               ld bc,22
               ld a,(nstr1)
               cp ft.zxsnap48
               jr z,snap6

               call svhd
               ld hl,snptab
               ld bc,33

snap6:         ld de,fsa+de.tail
               ldir
               ld hl,(snadd)
               ld de,(snlen)
               call svblk

               jp cfsm


snptab:        defb &20,&20,&20,&20,&20
               defb &20,&20,&20,&20,&20
               defb &20
               defb 255,255,255,255,255
               defb &6e,&00,&80,&00,&00
               defb &1b,255,255,255,255
               defb 255,255,255,255,255
               defb 255,255


; ---------------------------------------------------------------------------------------------------------------------
; snap7 -- resume the interrupted program
;
; Unwinds the register stack built by nmi, leaves a copy of the NMI entry point and the paging registers in the
; screen page where a resumed snapshot can find them, restores the interrupt mode, and jumps back into the code that
; was interrupted.
; ---------------------------------------------------------------------------------------------------------------------

;RETURN ADDRESS OF SNAPSHOT

snap7:         di
               ld a,3
               out (port.hmpr),a

               ld hl,0
               ld (hksp),hl
               ld sp,str-20
               pop iy
               pop ix
               pop de
               pop bc
               pop hl
               pop af
               ex af,af'
               exx

               ld hl,nmi
               ld (&b8f6),hl
               ld a,(snprt0)
               ld (&b8f8),a
               ld a,(snprt1)
               ld (&b8f9),a
               ld a,(snprt2)
               ld (&b8fa),a

               pop de
               pop bc
               pop hl
               pop af
               ld i,a
               cp 0
               jr z,snap8
               cp &3f
               jr z,snap8
               im 2
snap8:         ld sp,(str)

               jp &8000+&3900
