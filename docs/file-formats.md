# SAMDOS 2 — File Types and File Formats

What SAMDOS stores at the front of a file, what each file type's data contains, and how the ROM's header
relates to the DOS's. Derived from `svhd` / `ldhd` in [f.s](../annotated-src/f.s), `hconr` / `txinf` / `txhed`
in [h.s](../annotated-src/h.s), `gtflx` / `ofsm` / `cfsm` in [c.s](../annotated-src/c.s) and `pntyp` /
`drtab` in [e.s](../annotated-src/e.s).

The 48-byte header itself belongs to the ROM, not to the DOS. It is documented in full in the ROM
repository's `docs/file-formats.md`; what follows describes what SAMDOS does with it.

## Contents

| Section | |
|---|---|
| [File types](#file-types) | All the type numbers, and what `DIR` calls them |
| [Two headers](#two-headers) | Why there are two, and which is authoritative |
| [The nine-byte header](#the-nine-byte-header) | The one written into the file itself |
| [The 48-byte header](#the-48-byte-header) | The ROM's, and where SAMDOS keeps it |
| [Page form](#page-form) | The three-byte number format both headers use |
| [What the data contains](#what-the-data-contains) | Per type |
| [Every type in detail](#every-type-in-detail) | Per type: header meanings and data layout, with byte offsets |
| [Reading a file without the DOS](#reading-a-file-without-the-dos) | A complete recipe |

## File types

The type is in bits 0–4 of the first byte of the directory entry, and again in byte 0 of the nine-byte header.
Bits 6 and 7 of the directory byte are the protect and hidden flags and are **not** part of the type.

| Type | `ft.*` name | `DIR` shows | Meaning |
|---|---|---|---|
| 0 | — | — | Entry is free |
| 1 | `ft.zxbasic` | `ZX BASIC` | ZX Spectrum BASIC program |
| 2 | `ft.zxdarray` | `ZX D.ARRAY` | ZX Spectrum numeric array |
| 3 | `ft.zxsarray` | `ZX $.ARRAY` | ZX Spectrum string array |
| 4 | `ft.zxcode` | `ZX` | ZX Spectrum code |
| 5 | `ft.zxsnap48` | `ZX SNP 48k` | ZX Spectrum 48K snapshot |
| 6 | `ft.mdfile` | `MD.FILE` | Microdrive file |
| 7 | `ft.zxscreen` | `ZX SCREEN$` | ZX Spectrum screen |
| 8 | `ft.special` | `SPECIAL` | Special |
| 9 | `ft.zxsnap128` | `ZX SNP 128k` | ZX Spectrum 128K snapshot |
| 10 | `ft.opentype` | `OPENTYPE` | Open-ended file, no fixed length |
| 11 | `ft.execute` | `N/A EXECUTE` | Execute |
| 12 | — | *(blank)* | Present in `drtab` with no text |
| 16 | `ft.basic` | `BASIC` | SAM BASIC program |
| 17 | `ft.darray` | `D.ARRAY` | SAM numeric array |
| 18 | `ft.sarray` | `$.ARRAY` | SAM string array |
| 19 | `ft.code` | `C` | SAM code |
| 20 | `ft.screen` | `SCREEN$` | SAM screen |

Any type not in `drtab` prints `WHAT?`.

**[external]** The MGT filesystem documentation lists further types used by other DOSes on the same format —
12–13 UniDOS, 21 MasterDOS subdirectory, 22–23 SAM Driver, 24–26 EDOS, 28–31 HDOS. SAMDOS knows none of them
and will show `WHAT?`. Type 21 in particular matters: a MasterDOS subdirectory appears in a SAMDOS `DIR` as a
zero-length `WHAT?` file, and erasing it under SAMDOS orphans everything inside it.

### Type conversion on the way in

`gtflx` in [c.s](../annotated-src/c.s) moves any type below 16 into the SAM range as a file is opened, by
decrementing it and OR-ing in 16, and sets flag bit 7 to remember it was a Spectrum file. So a Spectrum file
is presented to the ROM as its nearest SAM equivalent, and the DOS converts its plain 16-bit length and start
into page form on the way (`conp`). Code and `SCREEN$` are treated as interchangeable for the purposes of the
type check, so `LOAD "x" CODE` will load a `SCREEN$` and vice versa.

## Two headers

A SAM file carries its identity **twice**, in two different formats:

| | Nine-byte header | 48-byte header |
|---|---|---|
| Whose | The DOS's, inherited from GDOS | The ROM's |
| Where on disk | The first 9 bytes of the file's data, **and** directory entry bytes 211–219 | Directory entry bytes 220–252, holding ROM header bytes 15–47; the name and type come from entry bytes 0–10 |
| Number format | Plain 16-bit, with separate page bytes | Page form throughout |
| Who reads it | The DOS, and Spectrum-side tools | The ROM |

They are written from the same values by `svhd` and `hconr`, so they agree — but a tool that edits one and
not the other will produce a file whose `DIR` line and `LOAD` behaviour disagree.

**Which is authoritative?** For a SAM file loaded through the ROM, the 48-byte header, because that is what
`txhed` hands back to the ROM in `HDL`. The nine-byte header is what a Spectrum-era tool would read, and what
SAMDOS itself uses for a Spectrum file.

## The nine-byte header

Written by `svhd` in [f.s](../annotated-src/f.s), which copies these nine bytes from the parameter block both
into the directory entry image at offset 211 and, through `sbyt`, into the first nine bytes of the file's
data. Read back by `ldhd`.

| Offset | Size | Field | Source | Contents |
|---|---|---|---|---|
| 0 | 1 | Type | `hd001` | One of the type numbers above |
| 1–2 | 2 | Length | `hd0b1` | Bytes within the last page: low byte first, and **masked to 14 bits** by `hconr` |
| 3–4 | 2 | Start | `hd0d1` | Start address, low byte first, in the &8000–&BFFF window |
| 5–6 | 2 | Execute | `hd0f1` | **Always &FFFF — see below.** Named for an execution address, but never written |
| 7 | 1 | Length pages | `pges1` | Whole 16K pages in the file |
| 8 | 1 | Start page | `page1` | Page the start address is in |

So the file's true length is

$`\text{length} = \text{pages} \times 16384 + \text{length}_{16}`$

and its true start is page × 16384 plus the offset of the address within its page.

### There is no execution address here

`hd0f1` and `hd0f2` appear **only in their own `defw` lines** — nothing in SAMDOS ever writes them and nothing
ever reads them. (Compare `hd0d1`, the start address, which is read and written in five places.) `hconr` takes
the type, start, start page, length and length pages out of the ROM's 48-byte header and simply skips the exec
field; `resreg` has already filled the parameter block with &FF, so `svhd` always copies &FFFF out.

The reason is in the format's ancestry. These nine bytes are the DISCiPLE/+D header, which is a **ZX Spectrum
tape header** — and a Spectrum is a 64K machine, so nothing in it needed a page byte:

| Byte | GDOS meaning | What SAMDOS does with it |
|---|---|---|
| 0 | Type | Type |
| 1–2 | Length | Length, low 14 bits |
| 3–4 | Start address | Start address |
| 5–6 | Type-specific — for BASIC, the length without variables | *Nothing* |
| 7–8 | Autostart line or address | **Length pages**, then **start page** |

SAM needs 20 bits to reach 512K. SAMDOS found them by spending the **last word** — the Spectrum's autostart
field — on two separate page bytes. That word is exactly where an execution page byte would have had to go,
and there was no tenth byte to extend into without breaking format compatibility. Start and length got the
extension; the execution address did not.

Nothing is lost by it, because that is not where a SAM file's execution address lives. **The authoritative one
is in the ROM's 48-byte header at directory offsets 242–244**, in full page form — that is what the ROM reads
back from `HDL` and what actually runs the code, and what `pntyp` reads to print a BASIC file's auto-run line.

> [!IMPORTANT]
> A tool reading the nine-byte header will find &FFFF in bytes 5–6 for every file SAMDOS has written,
> whatever its real execution address. Take the execution address from directory offsets 242–244 instead.

**[image]** Verified against the `MDOS23` file in `res/master_dos_v2-3.mgt`, whose first nine bytes are:

```text
13 86 3D 00 80 FF FF 00 01
```

— type 19 (`SAM CODE`), length &3D86 = 15750 bytes in 0 whole pages, start &8000 in page 1, no execution
address. The directory entry's own start/length fields at 236–241 give the same values in page form
(`01 00 80` and `00 86 3D`), which is an independent confirmation of both layouts at once.

> [!IMPORTANT]
> The nine bytes are part of the file's data. A file of length $`n`$ occupies $`n + 9`$ bytes on
> disk, and `LOAD` starts transferring from byte 9. A tool reading the sector chain must skip them. This is
> also why the DOS's own boot sector begins its code at offset 9 (see
> [disk-format.md](disk-format.md#the-boot-sector)).

## The 48-byte header

The ROM builds this at `HDR` (&4B00) before every save and expects it back at `HDL` (&4B50) after every load.
SAMDOS never interprets more of it than it must: `hconr` extracts the type, name, start and length into its
own parameter block, and the whole of bytes 15–47 is stored verbatim at directory offset 220 and handed back
untouched.

| Offset | Size | Field | Contents |
|---|---|---|---|
| 0 | 1 | Type | As above |
| 1–10 | 10 | Name | Space-padded |
| 11–14 | 4 | Name extension | Extra name characters allowed on a non-tape device |
| 15 | 1 | Flags (`HFG`) | Bit 0 invisible, bit 1 protected |
| 16–26 | 11 | Type-specific | BASIC: three page-form lengths. Arrays: the variable record header. `SCREEN$`: the mode |
| 27 | 1 | `DIRE` | Directory entry number, in a request header |
| 28–30 | 3 | — | Spare |
| 31–33 | 3 | Start | Page form |
| 34–36 | 3 | Length | Page form |
| 37–39 | 3 | Execute | Page form; for BASIC, `00 lo hi` is an auto-run line and &FF is none |
| 40–79 | 40 | Comment | Not touched by ROM or DOS |

Only bytes 0–52 of that reach the disk: the name comes from entry bytes 1–10 and bytes 15–47 from entry bytes
220–252. **Bytes 48–79, including the whole 40-byte comment area, are not stored** — there is no room for them
in a 256-byte entry, and SAMDOS does not write them anywhere. A comment set before `SAVE` is lost.

## Page form

Both the directory's copy of the ROM header and the ROM itself use a three-byte form for lengths and
addresses, written **pages, low, high**:

$`\text{value} = \text{pages} \times 16384 + \left( (\text{high} \times 256 + \text{low}) \bmod 16384 \right)`$

The high byte usually has bit 7 set, because it is an address in the &8000 window. A reader must mask bits 6
and 7 of the high byte before taking the remainder. A first byte of &FF means "not given".

`conp` in [c.s](../annotated-src/c.s) converts the other way, splitting a 16-bit value into a page count and
a remainder — which is how a Spectrum file's plain length becomes page form.

## What the data contains

After the nine-byte header:

| Type | Data |
|---|---|
| 16, BASIC | One contiguous block from `PROG` to `ELINE-1`: the tokenised program, then the numeric variables, the numbers-to-strings gap, and the strings and arrays. The three boundaries are **not** stored — ROM header bytes 16–24 hold the distances from `PROG` to each, and the ROM rebuilds the pointers from them on load. See [below](#basic-programs-what-travels-and-what-does-not) |
| 17 / 18, array | The array's contents as they sit in the variables area; the 11-byte record header is in ROM header bytes 16–26 |
| 19, code | The bytes, verbatim |
| 20, `SCREEN$` | The screen memory verbatim, followed by the 40-byte palette table and the line-interrupt colour list; the mode is in ROM header byte 16 |
| 10, open-type | Arbitrary bytes with no declared length. The chain runs until a `00 00` link |

Nothing is compressed, checksummed or escaped. A code file on disk is the same bytes as in memory.

[Every type in detail](#every-type-in-detail) below gives the byte offsets for each of these, and for the
types this table leaves out.

### BASIC programs: what travels, and what does not

None of this is SAMDOS's doing — the ROM builds the block and hands it over, and the DOS stores it like any
other. But it is what a tool reading a `.mgt` image has to understand, so it is summarised here. The full
account is in the ROM repository's `docs/memory-map.md` and `docs/file-formats.md`.

BASIC's variable area is a chain of contiguous regions, each boundary a system-variable pointer. `SAVE` writes
the first four and stops:

| Region | In the file? | Notes |
|---|---|---|
| Program (`PROG`) | Yes | Tokenised lines, ending with the &FF program terminator |
| Numeric variables (`NVARS`) | Yes | 26 letter-chain roots, 52 bytes, then the records — so **`SAVE` after `RUN` carries the variables with it** |
| The gap (`NUMEND`) | Yes, as it stood | Free slack between numbers and strings; it costs file space for nothing |
| Strings and arrays (`SAVARS`) | Yes, **except the final &FF** | The stopper is re-planted on load, which is why the length stops one byte short of `ELINE` |
| Edit line (`ELINE`) | No | |
| Workspace (`WORKSP`) | No | |

**The three boundaries are not stored.** ROM header bytes 16–18, 19–21 and 22–24 hold the distances from
`PROG` to `NVARS`, `NUMEND` and `SAVARS` in page form; the ROM adds each to `PROG` after loading. A program
image is therefore freely relocatable — only those three lengths and the total have to agree.

**Some state is deliberately discarded rather than restored.** The BASIC stack is emptied, since its
`DO`/`GOSUB`/`PROC` frames refer to a program that no longer exists; the `DATA` pointer is reset; and the
FN/PROC calling buffers inside the loaded program, which hold the addresses the program had *when it was
saved*, are all recomputed by the ROM's compile pass. A tool that writes a BASIC file may leave those buffers
unresolved for exactly that reason.

## Every type in detail

The nine-byte header's fields do not mean the same thing for every type, and the data block's layout varies.
This section gives both, per type, with byte offsets.

Two conventions throughout:

* **Entry offset** means a byte offset into the file's 256-byte directory entry.
* **Data offset** means an offset into the file's data as read by following the sector chain, *including* the
  nine-byte header where one is present.

### Types 1–4, 6, 8, 11 — Spectrum files

SAMDOS stores these mostly so a SAM can hold material for a Spectrum emulator. It does not interpret them; it
records the type, name and the nine-byte header and copies the bytes.

Their numbers live in the **nine-byte header**, not in the ROM's 48-byte one. `gtflx` reads entry bytes
211–219 for them, and `pntyp` prints a `ZX` code file's start and length from entry offsets 215 and 213 —
which are the nine-byte header's start and length fields. That is why a `ZX` file's `DIR` line looks right
even though entry bytes 236–244 are empty.

`gtflx` also converts on the way in: a type below 16 is decremented and OR-ed with 16 so the ROM sees its
nearest SAM equivalent, flag bit 7 records that it was really a Spectrum file, and `conp` converts the plain
16-bit length and start into page form.

| Type | Data block |
|---|---|
| 1 ZX BASIC | Nine-byte header, then the Spectrum BASIC program and its variables |
| 2 ZX numeric array | Nine-byte header, then the array as the Spectrum stored it |
| 3 ZX string array | As above |
| 4 ZX code | Nine-byte header, then the bytes |
| 6 Microdrive file | Nine-byte header, then the bytes. Never produced by SAMDOS |
| 8 Special | Nine-byte header, then the bytes. No defined meaning |
| 11 Execute | Nine-byte header, then the bytes |

### Type 5 — ZX Spectrum 48K snapshot

The only type whose directory entry carries **processor registers**, and the only one written **without a
nine-byte header**.

#### The data block

| Data offset | Size | Contents |
|---|---|---|
| 0 | 49152 | Spectrum RAM &4000–&FFFF, verbatim |

**There is no nine-byte header.** `snap6` in [d.s](../annotated-src/d.s) branches around the `svhd` call for
this type, and `svhd` is what writes those nine bytes both into the entry and into the file. So a 48K
snapshot's data begins immediately with the byte that was at Spectrum &4000, and entry bytes 211–219 are left
at the zero `ofsm` cleared them to.

The image is 49152 bytes, so a snapshot occupies

$`\lceil 49152 / 510 \rceil = 97`$ sectors.

#### The register dump

The 22 bytes at **entry offsets 220–241** are the machine's registers, in the order `nmi` pushed them.
Every pair is little-endian — low byte first — because each was written by a `PUSH`.

| Entry offset | Size | Register |
|---|---|---|
| 220–221 | 2 | `IY` |
| 222–223 | 2 | `IX` |
| 224–225 | 2 | `DE'` |
| 226–227 | 2 | `BC'` |
| 228–229 | 2 | `HL'` |
| 230–231 | 2 | `AF'` |
| 232–233 | 2 | `DE` |
| 234–235 | 2 | `BC` |
| 236–237 | 2 | `HL` |
| 238 | 1 | Flags — **not the program's `F`**; see below |
| 239 | 1 | `I` |
| 240–241 | 2 | `SP` |

`snap7`, which resumes a snapshot, pops them back in exactly that order, which is the definitive confirmation
of the layout.

> [!IMPORTANT]
> **`A` is not in the block, and byte 238 is not the program's flags.** `nmi` executes `LD A,I` before its
> first `PUSH AF`, which destroys `A`. So the byte in the `A` position holds **`I`**, and byte 238 holds
> whatever `LD A,I` left in `F`.
>
> That is deliberate rather than a bug: `LD A,I` copies **`IFF2` into the P/V flag (bit 2)**, so byte 238's
> bit 2 is the interrupt-enable state at the moment the button was pressed. The instruction also sets S and Z
> from `I`, clears H and N, and leaves C untouched.

**The interrupt mode is not stored either.** `snap7` infers it from `I`: a value of 0 or &3F means `IM 1`,
anything else means `IM 2`.

**[external]** The MGT filesystem documentation gives the same order for this block — *"IY, IX, DE', BC',
HL', AF', DE, BC, HL, junk, I, SP"* — which is an independent confirmation, and calls byte 238 "junk" for the
reason above. It adds that the real `AF`, `PC` and `R` live on the **interrupted program's own stack**, at the
address in the saved `SP`, in the order *"F indicating IFF, R, AF, PC"*.

That is consistent with how a SAM arrives here — the CPU pushes `PC` on NMI and the ROM's handler at &0066
pushes `AF` and then `HL` before any DOS code runs — but the ROM then switches to its own stack, and this
documentation has **not traced the SAM invocation path far enough to say exactly what the saved `SP` points
at**. Treat the stack layout as the DISCiPLE/+D convention, not as a verified SAM fact.

#### Loading one back

`load` in [f.s](../annotated-src/f.s) handles this type itself rather than returning to the ROM: the image is
read in, the machine paged as the snapshot expects, and execution **resumed**. The `LOAD` statement never
returns. `CALL MODE 1` resumes a snapshot directly.

#### A consequence for tools

Entry offsets 236–241 are `HL`, the flags byte, `I` and `SP` — which is exactly where a normal file keeps its
**start address and length**. A 48K snapshot therefore has no usable length field, and any tool reading the
entry must special-case the type and assume 49152. MasterDOS's `FSTAT(f$,2)` does precisely that.

### Type 7 — ZX Spectrum SCREEN$

6912 bytes: 6144 of pixel data followed by 768 of attributes, the Spectrum's &4000–&5AFF.

| Data offset | Size | Contents |
|---|---|---|
| 0 | 9 | Nine-byte header |
| 9 | 6144 | Pixel data |
| 6153 | 768 | Attributes |

**SAMDOS never writes this type.** Pressing NMI and `2` saves the screen as **type 19, SAM code**, not type 7
— `snap3` loads `ft.code` into A. The file is a Spectrum screen in content but a code file in type, so it
reloads with `LOAD "x" CODE`. Type 7 files on a SAM disk came from somewhere else.

### Type 9 — ZX Spectrum 128K snapshot

Recorded in the type table and shown by `DIR` as `ZX SNP 128k`, but **SAMDOS never writes one and has no code
that reads one**. The NMI handler offers only a 48K snapshot. Nothing in the source describes the layout, so
nothing is claimed here.

### Type 10 — OPENTYPE

An open-ended file with no declared length. The sector chain simply runs until a `00 00` link.

| Data offset | Size | Contents |
|---|---|---|
| 0 | 9 | Nine-byte header |
| 9 | … | Arbitrary bytes |

SAMDOS 2 has no way to create or append to one — its `OPEN #` hook is a bare `RET`. The type exists because
the format is shared with DOSes that do.

### Type 16 — SAM BASIC program

See [BASIC programs: what travels, and what does not](#basic-programs-what-travels-and-what-does-not) above
for the region layout and the three lengths. In byte terms:

| Data offset | Size | Contents |
|---|---|---|
| 0 | 9 | Nine-byte header |
| 9 | *(hdr16)* | Tokenised program, ending with the &FF program terminator |
| 9 + *(hdr16)* | … | Numeric variables: 26 chain roots (52 bytes) then the records |
| 9 + *(hdr19)* | … | The numbers-to-strings gap |
| 9 + *(hdr22)* | … | Strings and arrays — **without** the trailing &FF |

where *(hdr16)*, *(hdr19)* and *(hdr22)* are the three page-form lengths at entry offsets 221–223, 224–226
and 227–229 (ROM header offsets 16, 19 and 22).

The auto-run line is at entry offsets 242–244: a first byte of 0 means bytes 243–244 are the line number,
low byte first; a first byte of &FF means no auto-run.

### Types 17 and 18 — SAM numeric and string arrays

The data block is the complete **variables-area record**, copied from its type/length byte onward:

| Data offset | Size | Contents |
|---|---|---|
| 0 | 9 | Nine-byte header |
| 9 | 1 | Type/length byte: bit 7 hidden, bit 6 string array, bit 5 numeric array, bits 4–0 the true name length less one |
| 10 | 10 | Name, padded to ten characters |
| 20 | 1 | Data length in whole 16K pages |
| 21 | 2 | Data length modulo 16K, low byte first |
| 23 | … | Dimension count, then one word per dimension, then the elements — five bytes per numeric element; fixed-width rows for a string array |

The same eleven bytes — the type/length byte and the ten-character name — are also in the ROM header's
type-specific area, at **entry offsets 221–231**. `LOAD "x" DATA b()` uses that: the loaded record keeps its
element type but takes its name from the command.

### Type 19 — SAM code

The simplest type. Nothing is compressed, checksummed or escaped; a code file on disk is the same bytes as in
memory.

| Data offset | Size | Contents |
|---|---|---|
| 0 | 9 | Nine-byte header |
| 9 | *length* | The bytes |

| Field | Where |
|---|---|
| Start address | Entry offsets 236–238, page form |
| Length | Entry offsets 239–241, page form |
| Execution address | Entry offsets 242–244, page form; &FF in the first byte means none |

### Type 20 — SAM SCREEN$

The screen bitmap, then the palette, then the line-interrupt table. None of this is SAMDOS's doing — the ROM
assembles the whole thing as one contiguous block and the DOS stores it like any other file — but a tool
reading a `.mgt` image has to know where the picture stops, so the layout is given here. The full account,
including how the two tables are used at run time, is in the ROM repository's `docs/file-formats.md`.

The bitmap's size depends on the mode, which is in the ROM header's type-specific area at **entry offset
221**. It is the *internal* mode, one less than the number BASIC's `MODE` command takes:

| Mode byte | BASIC `MODE` | Bitmap size |
|---|---|---|
| 0 | `MODE 1` | &1B00 (6912) |
| 1 | `MODE 2` | &3800 (14336) |
| 2 | `MODE 3`, four colours | &6000 (24576) |
| 3 | `MODE 4` | &6000 (24576) |
| &20 | *(none)* | A code file being loaded as `SCREEN$`; the ROM substitutes the current mode |

| Data offset | Size | Contents |
|---|---|---|
| 0 | 9 | Nine-byte header |
| 9 | *(per mode)* | Screen memory |
| 9 + bitmap | 40 | `PALTAB` — the working palette |
| 9 + bitmap + 40 | 4*n* + 1 | The line-interrupt colour list: *n* four-byte entries, then an &FF terminator |

The trailer is never absent and never shorter than 41 bytes, so the smallest whole file of each mode is 6953,
14377 and 24617 bytes. A file whose length is exactly the bitmap size is a **code file being loaded as a
screen**, and the ROM stops after the picture.

#### The palette, 40 bytes

| Offset in the 40 | Bytes | Contents |
|---|---|---|
| 0–15 | 16 | Main palette, entries 0–15 — the colours in force in the file's mode |
| 16–19 | 4 | Parked main colours for entries 0–3 of the other mode group |
| 20–35 | 16 | Alternate palette, entries 0–15 — the flash partner of the first sixteen |
| 36–39 | 4 | Parked alternate colours for entries 0–3 of the other mode group |

Each byte is a SAM colour, 0–127, laid out `G1 R1 B1 BRIGHT G0 R0 B0` in bits 6–0. **To render the picture you
need offsets 0–15 only.** The second sixteen are the flash partners: the ROM's frame interrupt loads one set
or the other alternately, so an entry whose two colours differ flashes and one whose two agree is steady.

The eight parked bytes exist because `MODE 3` has only four inks and uses different colours for entries 0–3
than the sixteen-colour modes do; the ROM swaps them in and out of the live table as the mode changes.
Offsets 0–15 are therefore always correct for the mode in the header — carry the parked bytes through
unchanged when rewriting a file, but do not draw with them.

#### The line-interrupt list

Four bytes per entry, **sorted by scan line ascending**, ending in a single &FF in the scan-line position:

| Byte | Contents |
|---|---|
| 0 | Scan line, 0–190 — the last line drawn with the old colour, so the change appears on line + 1 |
| 1 | Palette entry to change, 0–15 |
| 2 | Colour |
| 3 | Alternate colour, the flash partner |

An empty list is the one &FF byte, which is what most files carry. At most 127 entries: the ROM refuses to
load a list of &200 bytes or more, and treats a first byte of 195 or above as "no list" — scan lines only run
to 190, so the terminator falls in that range. The two colour bytes are swapped in place by the ROM every few
frames to make the entry flash, so **in a saved file they may be in either order**.

Note that the screens written by the NMI handler are not this type at all: they are saved as type 19 code with
a fixed length of 6912 (see [the snapshot filler block](#the-snapshot-filler-block) below), so they carry no
palette and reload only with `LOAD "x" CODE`.

### The snapshot filler block

When the NMI handler saves anything **other** than a 48K snapshot — in practice, a screen — it writes the
ordinary nine-byte header with `svhd` and then a fixed 33-byte block, `snptab`, over entry offsets 220–252:

| Entry offset | Bytes | Meaning |
|---|---|---|
| 220–230 | `20` × 11 | ROM header bytes 15–25: the flags byte and the type-specific area, filled with spaces |
| 231–235 | `FF` × 5 | ROM header bytes 26–30 |
| 236–238 | `6E 00 80` | Start address, page form |
| 239–241 | `00 00 1B` | Length, page form — 0 pages plus &1B00, which is 6912, the screen size |
| 242–252 | `FF` × 11 | Execution address and the rest |

The length decodes correctly. **The start does not**: read as page form, a page byte of &6E is 110 pages,
which is past the top of even a 512K machine. MasterDOS's copy of the same table carries the author's comment
`;START (IF 256K MACHINE)`, so the value is a fixed assumption about the machine rather than a computed
address. Do not rely on it.

## Reading a file without the DOS

Everything needed to extract a file from a disk image, using only [disk-format.md](disk-format.md) and this
document:

1. Read the directory: tracks 0–3 of side 1, two 256-byte entries per sector, 80 entries.
2. Skip entries whose byte 0 is zero. The type is `byte0 & 0x1F`; bit 6 is protect, bit 7 hidden.
3. The name is bytes 1–10, space-padded.
4. The first sector is byte 13 (track) and byte 14 (sector). Bit 7 of the track selects side 2.
5. Follow the chain: each sector gives 510 bytes of data, then byte 510 is the next track and byte 511 the
   next sector. `00 00` ends the file.
6. The first nine bytes of the resulting stream are the header. The real content starts at byte 9.
7. The length is header bytes 7 × 16384 + bytes 1–2, or equivalently directory bytes 239–241 in page form.
   Trailing bytes in the last sector beyond that length are padding.
8. The start address is header byte 8 × 16384 plus bytes 3–4 masked to 14 bits, or directory bytes 236–238.
9. **The execution address is directory bytes 242–244 only.** Header bytes 5–6 are always &FFFF and must not
   be used — see [above](#there-is-no-execution-address-here).

Sector counts give an upper bound: `sectors × 510 - 9` bytes, which is what a length field should never
exceed.
