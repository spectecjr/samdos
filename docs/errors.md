# SAMDOS 2 — Error Codes and Messages

From `errtbl` and `derr` in [d.s](../annotated-src/d.s), with the code names in
[a.s](../annotated-src/a.s).

## How a DOS error is reported

The ROM's error reporting handles codes 0 to 80 from its own message table. Code **81 and above** are the
DOS's. When the ROM meets one it:

1. checks `DOSACT`, the flag the DOS sets on entry to every command and hook (`setbit` in
   [b.s](../annotated-src/b.s));
2. reads the word at the DOS page + &0210, which is the address of `errtbl`;
3. indexes it by $`\text{code} - 81`$, stepping over that many messages;
4. prints the message, which runs until a character with bit 7 set.

So a DOS is free to define its own error text, and MasterDOS's list differs from SAMDOS's. If no DOS is
loaded, the ROM reports *No DOS loaded* instead.

A DOS error is raised with `RST &08` followed by the code byte, exactly as the ROM raises its own.

## The codes

| Code | Name in the source | Message |
|---|---|---|
| 81 | `err.nonsense` | `Nonsense in SAMDOS 1.1` |
| 82 | `err.snos` | `Nonsense in SNOS 1.1` |
| 83 | `err.stmtend` | `Statement end error` |
| 84 | `err.escape` | `Escape requested` |
| 85 | `err.trkerr` | `TRK-nn,SCT-n,Error` |
| 86 | `err.fmtlost` | `Format TRK-nn lost` |
| 87 | `err.checkdsk` | `Check disk in drive` |
| 88 | `err.noboot` | `No "BOOT" file` |
| 89 | `err.badname` | `Invalid file name` |
| 90 | `err.badstn` | `Invalid station` |
| 91 | `err.baddev` | `Invalid device` |
| 92 | `err.novar` | `Variable not found` |
| 93 | `err.verify` | `Verify failed` |
| 94 | `err.badtype` | `Wrong file type` |
| 95 | `err.merge` | `Merge error` |
| 96 | `err.code` | `Code error` |
| 97 | `err.pupil` | `Pupil set` |
| 98 | `err.badcode` | `Invalid code` |
| 99 | `err.readwrite` | `Reading a write file` |
| 100 | `err.writeread` | `Writing a read file` |
| 101 | `err.noauto` | `no AUTO* file` |
| 102 | `err.netoff` | `Network off` |
| 103 | `err.nodrive` | `No such drive` |
| 104 | `err.wprot` | `Disk is write protected` |
| 105 | `err.nospace` | `Not enough space on disk` |
| 106 | `err.dirfull` | `Directory full` |
| 107 | `err.notfound` | `File not found` |
| 108 | `err.eof` | `End of file` |
| 109 | `err.nameused` | `File name used` |
| 110 | `err.nodos` | `No SAMDOS loaded` |
| 111 | `err.strmused` | `Stream used` |
| 112 | `err.chanused` | `Channel used` |

## What actually raises each one

Only some of these are reachable in SAMDOS 2; the table was inherited and includes codes for facilities this
DOS does not have.

| Message | Raised when |
|---|---|
| `Nonsense in SAMDOS 1.1` | A command's arguments do not parse — a missing `TO`, a bad separator. The version in the text is the message's own and does not track the DOS version |
| `Statement end error` | Something followed a command that should have ended. Also what `CALL` gives for anything but `MODE 0` or `MODE 1` |
| `Escape requested` | `ESC` pressed during a long operation |
| `TRK-nn,SCT-n,Error` | A sector could not be read or written after `disk.retries` (10) attempts. The track and sector digits are patched into the message text itself by `derr` before it is printed |
| `Format TRK-nn lost` | The controller reported a failure while writing a track |
| `Check disk in drive` | No disk, or the drive is not ready |
| `No "BOOT" file` | The ROM's `BOOT` found no such entry |
| `Invalid file name` | An empty name, or one longer than 14 characters including any `d1:` prefix |
| `Invalid device` | A device letter other than `D` |
| `Verify failed` | `VERIFY` found a difference, or `FORMAT`'s read-back pass failed |
| `Wrong file type` | The type found does not match the type asked for — `LOAD "x" CODE` on a BASIC file |
| `Invalid code` | A hook code below 128 reached `hook`. There is no upper check, so a code above 168 does not raise this; it indexes past the end of the table |
| `No such drive` | A drive other than 1 or 2, or drive 2 when `DVAR 2` says none is fitted |
| `Disk is write protected` | The write-protect tab is closed |
| `Not enough space on disk` | Allocation ran off the end of side 2 |
| `Directory full` | All 80 entries are in use |
| `File not found` | Nothing matched the pattern |
| `File name used` | `RENAME`'s target already exists |
| `No SAMDOS loaded` | Reported by the ROM, not the DOS, when there is no DOS to call |

Codes 82, 90, 92, 95, 96, 97, 99, 100, 101, 102, 108, 111 and 112 belong to facilities SAMDOS 2 does not
implement — the network, open files, `MERGE`'s own errors and the schools' `SNOS` variant. Their text is
present so that the numbering stays aligned with other DOSes on the format.

## Trapping a DOS error from BASIC

`ON ERROR` works normally, and the code is available as usual. A program that wants to test for a disk being
absent without provoking an error has no clean way to do it under SAMDOS 2 — MasterDOS adds `DSTAT` for
exactly that purpose.

## Errors and the stack

`hksp` (`DVAR 28–29`) holds the stack pointer saved on entry to a hook, so that an error inside a hook
unwinds to the ROM routine that called it rather than to the command loop. `syntax` sets it to zero, meaning
"no hook to unwind to — go back to BASIC".
