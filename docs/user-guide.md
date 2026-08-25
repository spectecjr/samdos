# SAMDOS 2 — User Guide

A practical guide to using SAMDOS from BASIC. The [command reference](commands.md) gives the full syntax of
everything; this shows how the pieces fit together and where the traps are.

> [!NOTE]
> Everything here is derived from the source. Where SAMDOS behaves surprisingly, the reason is given and the
> routine named, so you can check it.

## Contents

| Section | |
|---|---|
| [Getting started](#getting-started) | Booting, and the first thing to do |
| [Everyday tasks](#everyday-tasks) | Saving, loading, listing, deleting |
| [Two drives](#two-drives) | Why the second drive does not work until you say so |
| [Formatting](#formatting) | And why `FORMAT TO` is not what it sounds like |
| [Copying](#copying) | Wildcards and templates |
| [Making a disk bootable](#making-a-disk-bootable) | `BOOT` and `AUTO*` |
| [Protecting and hiding](#protecting-and-hiding) | And the trap in `PROTECT OFF` |
| [Working with raw sectors](#working-with-raw-sectors) | `READ AT` and `WRITE AT` |
| [Tuning the DOS](#tuning-the-dos) | The pokes worth knowing |
| [What SAMDOS cannot do](#what-samdos-cannot-do) | And what to use instead |
| [Recovering from trouble](#recovering-from-trouble) | |

## Getting started

SAMDOS is not in the ROM. It is a file called `SAMDOS2` on a disk, and it has to be loaded before any disk
command works:

```basic
BOOT
```

`BOOT` reads track 4 sector 1, looks for the text `BOOT` at offset `&100` (ignoring bits 5 and 7 of each character),
loads its first sector to &8000 and calls it. That sector is SAMDOS's own bootstrap, which reads the rest of itself
in, claims a 16K page at the top of memory, tells the ROM a DOS is present, and sets the default device to drive 1.

Until then, every disk command gives *No DOS loaded* — the ROM has no disk code of its own at all.

Once loaded, check it took:

```basic
PRINT PEEK DVAR 7
```

20 means SAMDOS 2. (42 or 43 would mean MasterDOS.) If `DVAR` itself gives an error, no DOS is loaded.

### The first thing to do

If you have two disk drives, tell SAMDOS about the second one. It does not detect drives:

```basic
POKE DVAR 2, 128+80
```

See [Two drives](#two-drives).

## Everyday tasks

```basic
DIR                          : REM list the disk
DIR 2                        : REM list drive 2
DIR "*.bas"                  : REM only matching files
DIR !                        : REM names only, in columns

SAVE "myprog"                : REM save the BASIC program
SAVE "myprog" LINE 10        : REM ...so that loading it runs it from line 10
LOAD "myprog"                : REM load it back

SAVE "d2:backup"             : REM to drive 2
SAVE "screen" SCREEN$        : REM the screen
SAVE "block" CODE 32768,1000 : REM a block of memory
LOAD "block" CODE 40000      : REM ...loaded somewhere else

ERASE "old"                  : REM delete a file
ERASE "*.bak"                : REM delete several
RENAME "old" TO "new"
```

`SAVE`, `LOAD`, `MERGE` and `VERIFY` are the ROM's commands, not SAMDOS's — the ROM parses them and hands the
work to whatever DOS is loaded. `DIR`, `ERASE`, `RENAME` and the rest are SAMDOS's own.

### File names

A name is a **string expression**, so it must be quoted or come from a variable:

```basic
LET f$ = "data"
LOAD f$ CODE 32768
```

Names are up to ten characters as stored on disk. A `d1:` or `d2:` prefix chooses the drive:

```basic
LOAD "d2:myprog"
```

Only the letter `D` is accepted; anything else gives *Invalid device*.

### Wildcards

| Pattern | Matches |
|---|---|
| `*` | Everything |
| `*.bas` | Everything up to the first `.` in the name, then `.bas` |
| `prog?` | `prog1`, `progA`, and so on |

Case does not matter — the comparison masks bit 5, so `MYPROG` and `myprog` are the same file.

Wildcards work in `DIR`, `ERASE`, `COPY`, `PROTECT` and `HIDE`. They do **not** work in `LOAD` or `RENAME`,
which match exactly.

### Loading by number

`DIR` numbers the files. That number can be used directly, which is handy when a name has awkward characters
in it:

```basic
DIR
LOAD 7
```

## Two drives

**SAMDOS assumes a single drive.** `DVAR 2` is zero by default, and until it is set, `DIR 2` gives
*No such drive*:

```basic
POKE DVAR 2, 128+80          : REM 80 tracks, double sided
```

The encoding is: low bits the track count, bit 7 set for double sided. So `128+80` is the standard 80-track
double-sided drive, `80` would be single sided, and `128+40` a 40-track double-sided one.

`DVAR 1` is the same thing for drive 1, and defaults to `128+80` already.

This is worth putting in a boot program, because it does not survive switching off.

## Formatting

```basic
FORMAT "d1:"
```

SAMDOS always asks *Are you SURE ? (y/n)*, then writes every track and reads it all back to verify.

> [!NOTE]
> **The name is not stored.** SAMDOS 2 has no disk-name concept at all. `FORMAT "d1:mydisk"` and
> `FORMAT "d1:"` do exactly the same thing — the string is parsed only for the drive prefix. `DIR`'s heading
> is a fixed `* SAM DRIVE n - DIRECTORY *`. Disk names are a MasterDOS addition.

The disk is formatted according to `DVAR 1` (or `DVAR 2`), so to make a single-sided disk:

```basic
POKE DVAR 1, 80
FORMAT "d1:"
POKE DVAR 1, 128+80          : REM put it back afterwards
```

Leaving `DVAR 1` wrong afterwards is a real hazard: it is also what the allocator uses to decide where the
disk ends, and what `DIR` subtracts from to report free space.

### `FORMAT TO` is a disk copy, not a file copy

```basic
FORMAT "d1:" TO "d2:"
```

> [!WARNING]
> This reads **each track** of drive 2 and writes it to drive 1, directory tracks included. The result is a
> byte-for-byte duplicate — same files, same layout, same free space. It does not merge with what is already
> on the target; everything there is lost.

Use [`COPY`](#copying) to move files between disks. Use `FORMAT TO` to duplicate a disk.

With one drive, SAMDOS prompts for the source and target disks a track at a time, which is a great many swaps
for a whole disk.

## Copying

```basic
COPY "*" TO "d2:*"           : REM everything to drive 2
COPY "*.bak" TO "*.old"      : REM rename in bulk, in place
COPY "prog" TO "d2:prog2"    : REM one file, renamed
```

The target is a **template**, not a literal name. Every file matching the source is copied, and the target
pattern is applied to each name in turn — which is what makes the second example work.

`COPY OVER` suppresses the *overwrite?* prompt for each existing target.

**With one drive**, source and target resolve to the same drive and SAMDOS asks you to swap disks between each
read and each write. A file larger than the buffer needs several swaps.

## Making a disk bootable

Two mechanisms, and they are different:

| | What it is | When it runs |
|---|---|---|
| The DOS file, which must be the first file written to the disk. | The DOS itself | When you type `BOOT` |
| A file named `AUTO*` | Your program | Automatically, after the DOS has loaded |

So a fully self-starting disk needs both: a copy of `SAMDOS2`, and your program saved with a
name starting `AUTO`.

The DOS file must be written first to the disk, as its first sector must be the first data sector of the
disk (Track 4, Sector 1, Side 1).

```basic
COPY "d2:SAMDOS2" TO "d1:"
SAVE "d1:AUTOSTART" LINE 10
```

The `AUTO*` file is loaded and run by hook 136 as the last thing the boot sequence does. If there is none, the
DOS simply finishes and returns to BASIC.

### Loading a new program from within a program

A common need, and it works because `LOAD` of a BASIC program replaces the running one and restarts it:

```basic
10 LOAD "nextpart"
```

There is no need for `NEW` first — loading a BASIC program clears the old one.

## Protecting and hiding

```basic
PROTECT "important"          : REM ERASE now refuses
HIDE "secret"                : REM ...and DIR no longer lists it
PROTECT OFF "important"
```

> [!IMPORTANT]
> **`HIDE` also protects**, because it sets bits 6 and 7 together. And **`PROTECT OFF` also un-hides**,
> because the routine clears both bits before deciding whether to set one again (`sfbt`). There is no
> hidden-but-erasable state, and no way to un-protect without un-hiding.

Hidden files still occupy their sectors, so hiding a file does not appear to free space. And `ERASE OVER`
deletes protected files regardless — protection is a guard against accidents, not a lock.

## Working with raw sectors

```basic
READ  AT 1,0,1,32768         : REM drive 1, track 0, sector 1, to &8000
WRITE AT 1,0,1,32768
```

512 bytes each way. Neither command looks at the directory, the free space or anything else.

Arguments after the drive are optional and keep their previous values, so stepping through a disk is short:

```basic
10 FOR s = 1 TO 10
20   READ AT 1,0,s,32768
30   REM ...examine it
40 NEXT s
```

Tracks are 0–79 for side 1 and **128–207 for side 2** — the side is bit 7 of the track number, there is no
separate side argument.

This is the tool for reading foreign disks, examining the directory by hand, and undeleting files. It is also
the fastest way to destroy a disk: `WRITE AT` will overwrite a directory track without complaint.

### Reading the directory by hand

The directory is tracks 0–3, two 256-byte entries per sector:

```basic
10 READ AT 1,0,1,32768
20 FOR e = 0 TO 1
30   LET b = 32768 + e*256
40   IF PEEK b = 0 THEN GO TO 80: REM free entry
50   PRINT PEEK b BAND 31;" ";
60   FOR i = 1 TO 10: PRINT CHR$ PEEK (b+i);: NEXT i
70   PRINT " ";PEEK (b+11)*256 + PEEK (b+12);" sectors"
80 NEXT e
```

See [disk-format.md](disk-format.md#the-directory-entry) for every field.

## Tuning the DOS

`DVAR n` gives the **address** of DOS variable $`n`$, so it is always used with `PEEK` or `POKE`:

```basic
POKE DVAR 2, 128+80          : REM enable the second drive
POKE DVAR 0, 0               : REM stop the border flashing during disk access
POKE DVAR 5, CODE "."        : REM show the spaces inside file names in DIR
POKE DVAR 1, 80              : REM format single sided from now on
```

`DVAR 5` is more useful than it looks. File names are space-padded, so `"MY FILE"` and `"MYFILE"` look
identical in a listing; setting the substitute character to something visible is the only way to tell them
apart.

The full list is in [dos-variables.md](dos-variables.md).

## What SAMDOS cannot do

Several ROM keywords exist, parse, run — and do nothing, because their DOS hooks are bare `RET`s
([hook-interface.md](hook-interface.md)):

| Keyword | What happens under SAMDOS 2 |
|---|---|
| `OPEN #` | Nothing. No stream is opened, and no error is raised |
| `CLOSE #` | Nothing |
| `EOF` | Nothing is returned |
| `PTR` | Nothing is returned |
| `PATH$` | Nothing is returned |

So SAMDOS has **no open files, no random access, no subdirectories, no RAM discs and no clock**. A file is
read or written whole, and that is all.

If you need any of those, you need [MasterDOS](https://github.com/stefandrissen/masterdos), which implements
all of them on the same disk format. A SAMDOS disk is readable by MasterDOS without conversion.

The silent failure is the dangerous part: a program that calls `OPEN #4` gets no error and no stream, and only
fails later. Test the DOS version first:

```basic
10 IF PEEK DVAR 7 < 42 THEN PRINT "This program needs MasterDOS": STOP
```

## Recovering from trouble

**"TRK-nn,SCT-n,Error"** — a sector could not be read after ten attempts. The track and sector are in the
message. Try again; if it persists, the data on that sector is gone, but the rest of the disk is fine. Copy
what you can off it with `COPY "*" TO "d2:*"`, which will fail only on the affected file.

**"Directory full"** — all 80 entries are used. SAMDOS's directory is a fixed four tracks and cannot be
enlarged; the disk may have plenty of free space and still be full of files. Copy to a fresh disk, or delete
something.

**"Not enough space on disk"** — the allocator ran off the end. If this happens on a disk that ought to have
room, check `DVAR 1` matches how the disk was actually formatted.

**A file deleted by mistake** — the data is still there, and so is the file's complete sector map, sitting in
the directory entry that was zeroed. `ERASE` writes exactly one byte. Provided nothing has been written since,
writing the type byte back restores the file:

```basic
10 READ AT 1,t,s,32768       : REM the sector holding the entry
20 POKE 32768, 19            : REM restore the type: 19 = CODE, 16 = BASIC
30 WRITE AT 1,t,s,32768
```

Finding *which* entry is the work; the name is still at offset 1 of the entry, so scanning the directory tracks
for it will locate it. Do this before saving anything else to the disk, since the sectors are now free and will
be reused.

**The drive keeps stepping after an error** — hook 164 returns the head to track 0. From BASIC there is no
direct equivalent, but any successful `DIR` does the same thing.
