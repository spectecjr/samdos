# SAMDOS 2 — Command Reference

Every command SAMDOS adds to SAM BASIC, derived from `SYNTAX` in [b.s](../annotated-src/b.s) and the command
routines in [f.s](../annotated-src/f.s).

## How a DOS command reaches SAMDOS

The ROM has no disk code. When it meets a statement it cannot parse it raises error 29, *Not understood*, and
before reporting it calls the DOS at `JP SYNTAX` with that code in A. `SYNTAX` rewinds `CHADD` to the start of
the statement, reads the token again, and compares it against its own eleven:

```text
DIR  FORMAT  ERASE  WRITE  LOAD  READ  COPY  RENAME  CALL  PROTECT  HIDE
```

If none match, `CHADD` is restored and the user's external vector at `ONERR` ([DVAR](dos-variables.md)) is
called, if one is installed; otherwise the ROM's error stands. This means:

* every DOS command is an ordinary BASIC keyword the ROM already tokenises — SAMDOS adds **no new keywords**
  and cannot, because it never sees the tokeniser;
* a DOS command works in a program and in direct commands alike, and can be the target of `ON ... GOTO`;
* a DOS command is **not syntax-checked when the line is entered**. It is parsed when it runs.

The token values are in [a.s](../annotated-src/a.s):

| Token | Value | Token | Value | Token | Value |
|---|---|---|---|---|---|
| `WRITE` | &86 | `DIR` | &90 | `FORMAT` | &91 |
| `ERASE` | &92 | `LOAD` | &95 | `READ` | &B8 |
| `COPY` | &CF | `RENAME` | &E3 | `CALL` | &E4 |
| `PROTECT` | &F1 | `HIDE` | &F2 | | |

`OVER` (&A6), `OFF` (&89), `TO` (&8E), `AT` (&87) and `MODE` (&AA) are used as sub-keywords.

## Summary

| Command | Purpose |
|---|---|
| [`DIR`](#dir) | List the catalogue |
| [`FORMAT`](#format) | Format a disk, optionally copying another onto it |
| [`ERASE`](#erase) | Delete files |
| [`RENAME`](#rename) | Rename a file |
| [`COPY`](#copy) | Copy files, including between disks in one drive |
| [`PROTECT`](#protect-and-hide) | Set or clear the protect flag |
| [`HIDE`](#protect-and-hide) | Set or clear the hidden flag |
| [`LOAD`](#load) | Load a file by directory number, or load a snapshot |
| [`READ` / `WRITE`](#read-and-write) | Raw sector access, bypassing the directory entirely |
| [`CALL`](#call) | Resume a snapshot |

Commands the ROM provides that SAMDOS services through [hooks](hook-interface.md) rather than through
`SYNTAX` — `LOAD`, `SAVE`, `MERGE`, `VERIFY`, `BOOT` — are documented in the ROM's own manual. Their disk
behaviour is described in [file-formats.md](file-formats.md).

## File names and drives

Every command that takes a file name accepts the same form. It is a **string expression**, not a bare word, so
it must be quoted or come from a variable.

```text
[ device [ drive ] ":" ] name
```

| Part | Rules |
|---|---|
| device | A single letter. Only `D` is a disk; anything else raises *Invalid device* (`ckdisc` in [f.s](../annotated-src/f.s)). Defaults to the `DEVICE` letter, which the boot code sets to `D` |
| drive | `1` or `2`. Defaults to the `DEVICE` number, or to 1 |
| name | Up to **10 characters** as stored on disk. The parser accepts up to 14 characters in total, the surplus being room for the prefix (`fn.maxlen` in [a.s](../annotated-src/a.s)). An empty name, or one longer than 14, gives *Invalid file name* |

The default drive comes from the ROM's `DEVICE` command, whose letter and number live at &5A06 and &5A07.
Wherever a name is parsed, `gtdef` reads those two bytes first, so `DEVICE D2` makes drive 2 the default for
every DOS command as well as for `LOAD` and `SAVE`.

### Wildcards

`cknam` in [c.s](../annotated-src/c.s) compares the type byte and all ten name characters, ignoring case
(it masks bit 5, so letters match regardless of case; digits and punctuation are unaffected because the
comparison is an `XOR` followed by `AND &DF`).

| Pattern | Meaning |
|---|---|
| `?` | Matches exactly one character, whatever it is |
| `*` | If nothing follows it, matches the whole of the rest of the name |
| `*.xyz` | Matches up to the first `.` in the stored name, then continues comparing |
| `*` alone | Matches every file |

Wildcards are only honoured by commands that ask for them — `DIR`, `ERASE`, `COPY`, `PROTECT`, `HIDE`. `LOAD`
and `RENAME` match exactly.

---

## DIR

```text
DIR [#stream] [drive] ["pattern"] [!]
```

Prints the catalogue. Implemented at `dir` / `dirx` in [f.s](../annotated-src/f.s), with the listing itself in
`pcat` and `fdhr`.

| Form | Effect |
|---|---|
| `DIR` | Full listing of every file on the default drive |
| `DIR 2` | The same, on drive 2 |
| `DIR "*.bas"` | Only files matching the pattern |
| `DIR !` | Short form: names only, in columns, no heading |
| `DIR #4` | Send the listing to stream 4 instead of stream 2 |

The default pattern is `*` and the default stream is 2, the upper screen. The full form clears the screen
first (`CLSBL`); the short form does not.

**Full listing.** One line per file:

```text
  n  NAME       ss  TYPE  [extra]
```

| Column | From |
|---|---|
| `n` | The file's directory number, counted from 1 in directory order |
| `NAME` | The ten name characters, with spaces replaced by the character in `DVAR 5` (`chdir`, normally a space) |
| `ss` | Sectors used, from directory entry offsets 11–12 |
| `TYPE` | The name from `drtab` in [e.s](../annotated-src/e.s) — see [file-formats.md](file-formats.md#file-types) |
| extra | `BASIC` prints its auto-run line number; `C` (code) prints `start,length`; `ZX` code prints the same from the Spectrum header |

**Hidden files are not listed**, and do not contribute to the file count, but their sectors are still counted
as used. Protected files are listed normally.

**Heading and footer.** `pcat` prints `* SAM DRIVE n - DIRECTORY *` — there is no disk name in SAMDOS 2 — and
afterwards `Number of Free K-Bytes = nnnn`. The
sectors *used* are accumulated in `cnt` by `fdhr` as it scans; the disk's *capacity* is not read from the disk
at all but looked up from the track byte for the drive (`DVAR 1` or `DVAR 2`):

| Track byte | Disk | Data sectors |
|---|---|---|
| 40 | 40 tracks, one side | 360 |
| 80 | 80 tracks, one side | 760 |
| 128+40 | 40 tracks, two sides | 760 |
| anything else | 80 tracks, two sides | 1560 |

Each is the whole disk less the 40 sectors of the four directory tracks. The figure printed is

$`\text{free K} = \frac{\text{capacity} - \text{used}}{2}`$

— halved because a sector is half a kilobyte. Two consequences follow from the capacity being assumed rather
than measured. A disk formatted with a non-standard track count reports the wrong free space until `DVAR 1` is
set to match, and a disk holding **more** than its nominal capacity prints a **negative** figure rather than
failing.

---

## FORMAT

```text
FORMAT "name"
FORMAT "name" TO "name"
FORMAT TO "name"
```

Implemented at `wfod` in [f.s](../annotated-src/f.s); the formatter itself is `dfmt` in
[e.s](../annotated-src/e.s).

| Form | Effect |
|---|---|
| `FORMAT "d1:x"` | Format the disk in drive 1, then verify it by reading every sector back |
| `FORMAT "d1:x" TO "d2:y"` | Format drive 1, then copy drive 2 onto it **track by track** |
| `FORMAT TO "d2:y"` | The track-by-track copy alone, onto a disk already formatted |

> [!NOTE]
> **The name is not stored.** SAMDOS 2 has no disk-name concept; the string is parsed only for its `d1:`
> prefix, to say which drive to work on. `FORMAT "d1:anything"` and `FORMAT "d1:"` do the same thing. A disk
> name is a MasterDOS addition.

**SAMDOS always asks for confirmation**, whatever the form, because the operation destroys the target
(`pmo6`, *"Are you SURE ? (y/n)"*). Answer `Y` to proceed; anything else abandons the command.

The number of tracks and sides comes from `DVAR 1` for drive 1 and `DVAR 2` for drive 2 — bit 7 set means
double-sided, the low bits the track count. The default is `128+80`: 80 tracks, both sides. Changing `DVAR 1`
before formatting is the only way to produce a non-standard disk.

`dfmt` builds each track image in memory (`dmt1`) and issues the controller's write-track command a track at a
time, flashing the border colour in `DVAR 0` as it goes and printing the track number. Interrupts are off for
the whole operation, since a write-track cannot be interrupted without losing the track. A track the
controller could not write raises *Format TRK-nn lost*.

**Sector numbering is skewed by two between adjacent tracks**, so that after the head has stepped, the sector
wanted next is about to pass under it rather than having just gone by.

> [!WARNING]
> `FORMAT TO` is a **whole-disk sector copy, not a file copy.** It reads each track of the source and writes
> it to the target, including the directory tracks. The target becomes a byte-for-byte duplicate: same files,
> same layout, same free space. It does not merge, it does not skip unused sectors, and anything already on
> the target is lost. Use [`COPY`](#copy) to move files between disks. With one drive, SAMDOS prompts for the
> source and target disks a track at a time.

---

## ERASE

```text
ERASE [OVER] "pattern"
```

Deletes **every** file matching the pattern. Implemented at `eraz` in [f.s](../annotated-src/f.s).

A file is deleted by writing zero to the first byte of its directory entry. Nothing else is changed: the
sectors are freed implicitly, because free space is derived by scanning the entries that remain (see
[disk-format.md](disk-format.md#free-space)). **The data is still on the disk** and the entry still holds the
file's whole sector map, so an undelete utility has everything it needs.

| Case | Behaviour |
|---|---|
| Ordinary file | Deleted |
| Protected file (bit 6 set) | Skipped, with a beep |
| `ERASE OVER` | Protected files are deleted too |
| Nothing matched | *File not found* |

`ERASE` gives no per-file confirmation. `ERASE "*"` empties the disk in one step.

---

## RENAME

```text
RENAME "old" TO "new"
```

Implemented at `renam` in [f.s](../annotated-src/f.s). Both names are exact — **wildcards are not applied** —
and both are looked up before anything is written:

| Condition | Error |
|---|---|
| The new name already exists | *File name used* |
| The old name does not exist | *File not found* |

Only the ten name characters are rewritten. The type byte, the flags, the sector count, the map and both
headers are left exactly as they were, so renaming cannot change a file's type and does not clear its
protect or hidden flags.

Note that the **nine-byte header inside the file itself** still carries the old name in some file types; see
[file-formats.md](file-formats.md).

---

## COPY

```text
COPY [OVER] "source" TO "target"
```

Implemented at `copy` in [f.s](../annotated-src/f.s), with `trx` building the target name.

Every file matching the source pattern is copied. The source pattern is kept in `nstr3` while `nstr1` holds
each match in turn, and the **target acts as a template**:

| Command | Effect |
|---|---|
| `COPY "*" TO "d2:*"` | Copy everything to drive 2, keeping the names |
| `COPY "*.bak" TO "*.old"` | Copy in place, changing the extension as it goes |
| `COPY "prog" TO "d2:prog2"` | One file, renamed |

`OVER` suppresses the *overwrite?* prompt for each existing target. It works by writing the ROM's own
`SAVE OVER` flag at &5BB9, which is what `ofsm` consults — so `COPY OVER` and `SAVE OVER` share one mechanism.

**Single-drive copying.** If source and target resolve to the same drive, flag bit 5 is set and the user is
asked to swap disks between each read and each write. A file larger than the buffer therefore needs several
swaps.

*File not found* if nothing matched.

---

## PROTECT and HIDE

```text
PROTECT [OFF] "pattern"
HIDE [OFF] "pattern"
```

Both set flag bits in the type byte of every matching directory entry. Implemented at `prot` / `hide` / `sfbt`
in [f.s](../annotated-src/f.s).

| Command | Bits affected | Effect |
|---|---|---|
| `PROTECT "x"` | bit 6 | `ERASE` refuses without `OVER` |
| `HIDE "x"` | bits 6 **and** 7 | Not listed by `DIR`, and protected as well |
| `PROTECT OFF "x"` | clears bit 6 | Also clears bit 7, because the mask is cleared before being reapplied |
| `HIDE OFF "x"` | clears bits 6 and 7 | |

Because `HIDE` sets both bits, **a hidden file is always protected**; there is no hidden-but-erasable state.
And because `sfbt` clears the whole mask before deciding whether to set it again, `PROTECT OFF` on a hidden
file un-hides it too.

The file's sectors are still counted as used while it is hidden, so hiding a file does not appear to free
space.

*File not found* if nothing matched.

---

## LOAD

```text
LOAD n
```

The ROM handles every ordinary `LOAD`. This command is reached **only when the ROM's own `LOAD` syntax has
failed**, which in practice means `LOAD` followed by a number — loading a file by its directory number rather
than by name. Implemented at `load` in [f.s](../annotated-src/f.s).

```basic
DIR              : REM find the number
LOAD 7           : REM load the seventh entry
```

Two file types need more than the ROM can do, and `load` handles both:

| Type | What happens |
|---|---|
| 5, ZX 48K snapshot | The Spectrum image is loaded, the machine paged as the snapshot expects, and the snapshot **resumed** — `LOAD` does not return |
| 16, BASIC | The program's start and length are worked out from the ROM's own pointers before the ROM is left to do the loading |

**A note on the syntax pass.** Before evaluating anything, `load` walks the statement and reclaims every
five-byte number form the ROM compiled into it (`nummark`, &0E). Without that, `LOAD n` inside a loop would
reload whatever number it saw the first time.

---

## READ and WRITE

```text
READ  AT drive, track, sector, address
WRITE AT drive, track, sector, address
```

Raw sector access. `READ` transfers 512 bytes from the disk into memory; `WRITE` transfers 512 bytes the other
way. Implemented at `read` / `write` / `evprm` in [f.s](../annotated-src/f.s).

| Argument | Range |
|---|---|
| drive | 1 or 2 |
| track | 0–79 for side 1, 128–207 for side 2 (bit 7 selects the side) |
| sector | 1–10 |
| address | Any address; it is taken as a page-form address in the caller's context |

**Neither command goes near the directory.** No file is opened, no map is consulted, no free space is checked.
`WRITE` will happily overwrite a directory track or the middle of a file. This is the tool for disk repair,
copy protection and reading foreign disks — and the fastest way to destroy a disk.

Every argument after the drive is optional, and anything omitted keeps whatever the previous `READ` or `WRITE`
left behind, because the values are collected in the hook register block rather than in fresh variables:

```basic
READ AT 1,0,1,32768   : REM read track 0 sector 1
READ AT 1,0,2         : REM same drive and address, next sector
```

---

## CALL

```text
CALL MODE 0
CALL MODE 1
```

Not a general subroutine call — that is the ROM's `CALL`, which this shadows only when the ROM's syntax fails.
Implemented at `calll` in [f.s](../annotated-src/f.s).

| Form | Effect |
|---|---|
| `CALL MODE 0` | Page RAM page 3 in at &8000, select video page 4, and jump to &B914 — the entry point of a resumed Spectrum image |
| `CALL MODE 1` | Resume the snapshot the NMI code saved, through `snap7` |

Anything else gives *Statement end error*.

---

## The NMI button

Not a command, but the third entry point the ROM knows about. Pressing NMI freezes whatever is running and
reads the keyboard (`nmi` in [d.s](../annotated-src/d.s)):

| Key | Action |
|---|---|
| *(none)* | Resume, having done nothing |
| `2` | Save the screen as a 6912-byte Spectrum `SCREEN$` (type 19, code) |
| `3` | Save a 48K snapshot (type 5) |
| `4` | Step the page mapped at &8000, so a page other than the default can be captured |

The file is named `SNAPnnnn`, formed from the drive number and the directory position it lands in, so
successive snapshots do not collide.

---

## Commands SAMDOS does *not* provide

The ROM tokenises several keywords whose DOS hooks SAMDOS leaves as bare `RET`s (`h.s`, `hopen` onward). They
parse, they run, and they do nothing:

| Keyword | Hook | SAMDOS 2 |
|---|---|---|
| `OPEN #` | 134 | `RET` — no stream is opened |
| `CLOSE #` | 135 | `RET` |
| `EOF` | 140 | `RET` — nothing is stacked, so the value is whatever was there |
| `PTR` | 141 | `RET` |
| `PATH$` | 142 | `RET` |

All five are implemented by [MasterDOS](https://github.com/stefandrissen/masterdos). If a program needs open
files, record access or directories, it needs MasterDOS.

`DVAR` (hook 139) **is** implemented — see [dos-variables.md](dos-variables.md).

## Extending the command set

`SYNTAX` calls `extadd` for any token it does not recognise, which is a `CALL` through the word at `onerr`
(`DVAR 24–25`). Poking an address there gives a program the chance to implement its own commands:

| On entry | |
|---|---|
| A | The ROM error code, normally 29 |
| `CHADD` | Restored to the ROM's original position |

Returning without acting lets the error stand. The default is a `RET`, so nothing is intercepted.
