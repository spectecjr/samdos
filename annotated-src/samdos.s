; =====================================================================================================================
; SAMDOS.S -- build glue
; =====================================================================================================================
;
; Assembles the whole DOS. The include order is load-bearing: a.s must come first because it defines the symbols
; every other file uses, and b.s must come second because it establishes the assembly address and the output file
; layout with its org and dump directives.
;
; The files are named a through h with no g -- one was dropped somewhere in the source's history.
;
;   a.s   equates only; emits nothing
;   b.s   the boot sector, the DOS variables, the file name and header buffers, and the three entry points
;   c.s   the disk driver: sector read and write, the sector address map, the directory, open and close
;   d.s   ROM interface helpers, the flag byte, error reporting and messages, and the NMI snapshot code
;   e.s   formatting, disk copy, and the number and text printing used by DIR
;   f.s   the command implementations: DIR, ERASE, COPY, RENAME, PROTECT, HIDE, LOAD, FORMAT, CALL
;   h.s   the hook code routines the ROM calls, and file name parsing
;
; The image is padded to exactly 10000 bytes, which is what the ROM's boot loader expects to read.
; =====================================================================================================================

        include "a.s"
        include "b.s"
        include "c.s"
        include "d.s"
        include "e.s"
        include "f.s"
        include "h.s"

        defs &782
        defb &00
