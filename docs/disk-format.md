# SAMDOS 2 — On-Disk Format

The physical layout of a SAM Coupé disk and everything SAMDOS stores on it. Derived from
[c.s](../annotated-src/c.s) (`fnfs`, `fdhr`, `ofsm`, `gtfle`, `cfsm`), [e.s](../annotated-src/e.s) (`dfmt`) and
the structural equates in [a.s](../annotated-src/a.s).

This is the **MGT format**, shared with the DISCiPLE and +D interfaces for the ZX Spectrum. **[external]**
Everything in this document except the SAM-specific fields applies to a GDOS or G+DOS disk as well.

## Contents

| Section | |
|---|---|
| [Geometry](#geometry) | Tracks, sides, sectors, and how a track number encodes the side |
| [Layout of the disk](#layout-of-the-disk) | What lives where |
| [Sector chaining](#sector-chaining) | How a file's sectors are linked |
| [The directory](#the-directory) | Where it is and how it is addressed |
| [The directory entry](#the-directory-entry) | All 256 bytes |
| [The sector address map](#the-sector-address-map) | Bit ordering, and how it is used twice |
| [Free space](#free-space) | Why it is not stored anywhere |
| [Allocation](#allocation) | How a new sector is chosen |
| [The boot sector](#the-boot-sector) | How a DOS gets loaded |
| [Disk images](#disk-images) | MGT and DSK file ordering |

## Geometry

| Property | Value |
|---|---|
| Tracks per side | 80 (`DVAR 1` sets what the formatter writes) |
| Sides | 2 |
| Sectors per track | 10, numbered **1 to 10** |
| Bytes per sector | 512 |
| Usable bytes per sector | 510 — the last two link to the next sector |
| Encoding | MFM, double density |
| Total capacity | $`80 \times 2 \times 10 \times 512 = 819200`$ bytes |
| Capacity for files | 1560 sectors, $`1560 \times 510 = 795600`$ bytes |

**The side is carried in bit 7 of the track number.** Side 1 is tracks 0–79; side 2 is tracks 128–207
(`disk.side2` = &80). There is no separate side argument anywhere in the DOS: `READ AT 1,128,1,32768` reads
track 0 of side 2. Physically the controller is told the side through the drive-select port, but every
interface above that level uses the encoded form.

Tracks run 0–79 on side 1 and *then* 128–207 on side 2, in that order — the DOS fills one whole side before
starting the other (`fns5` in [c.s](../annotated-src/c.s)). This is not the interleaved order a PC would use.

## Layout of the disk

| Tracks | Sectors | Contents |
|---|---|---|
| 0–3, side 1 | 40 | The directory: 80 entries of 256 bytes |
| 4–79, side 1 | 760 | File data |
| 128–207, side 2 | 800 | File data, continuing from track 79 side 1 |

`disk.dirtrks` is 4 and is a constant in SAMDOS — the directory is always four tracks and always exactly 80
entries. (MasterDOS makes this variable; see its `disk-format.md`.)

## Sector chaining

Every sector holds **510 bytes of data followed by a two-byte link**:

| Offset in sector | Contents |
|---|---|
| 0–509 | Data |
| 510 | Track of the next sector |
| 511 | Sector of the next sector |

A link of `00 00` marks the last sector of the file. The order is **track first**, which is the opposite of the
directory entry's first-sector field — a real inconsistency in the format, and worth knowing when writing a
tool.

A file is therefore a singly linked list. There is no length in the chain; the length comes from the
directory entry, or from the file's own nine-byte header. Following the chain is exactly what the boot code
does, at `dos8` in [b.s](../annotated-src/b.s):

```asm
dos8:          dec hl
               ld e,(hl)       ; sector
               dec hl
               ld d,(hl)       ; track
               ld a,d
               or e
               jr nz,dos       ; 00 00 ends the file
```

**[image]** Verified against `res/master_dos_v2-3.mgt`: the first sector of the `MDOS23` file is track 4
sector 1, and its bytes 510–511 are `04 02` — track 4, sector 2.

## The directory

Tracks 0 to 3 of side 1, forty sectors, **two 256-byte entries per sector**. Entry $`n`$, counting from
zero, is at:

$`\text{track} = \left\lfloor \frac{n}{20} \right\rfloor, \quad \text{sector} = \left\lfloor \frac{n \bmod 20}{2} \right\rfloor + 1, \quad \text{half} = n \bmod 2`$

The half is the `RPTH` field of the channel record — 0 for the entry at offset 0 of the sector, 1 for the one
at offset 256.

The number `DIR` prints, and the number `LOAD n` takes, is $`n + 1`$: entries are numbered from **1** to the
user.

**An entry whose first byte is zero is free.** That is all that marks it: erasing a file writes one zero byte.

## The directory entry

All 256 bytes. Offsets in decimal, with hex in brackets where it helps. Fields marked **[SAM]** are SAMDOS's
own; the rest are the DISCiPLE/+D layout.

| Offset | Size | Field | Contents |
|---|---|---|---|
| 0 | 1 | Type and flags | Bits 0–4 file type (`de.typemask`), bit 6 protected, bit 7 hidden. **Zero means the entry is free** |
| 1–10 | 10 | Name | Ten characters, space-padded, no terminator |
| 11–12 | 2 | Sector count | **High byte first** — the only big-endian field in the format |
| 13 | 1 | First track | Of the file's first sector |
| 14 | 1 | First sector | 1–10 |
| 15–209 | 195 | Sector address map | See [below](#the-sector-address-map) |
| 210 | 1 | — | Unused by SAMDOS. Other DOSes on this format use 210–219 of entry 0 as the disk label |
| 211–219 | 9 | Nine-byte header | The file's own header, byte for byte identical to the copy at the start of its data — `svhd` writes both from the same buffer. See [file-formats.md](file-formats.md#the-nine-byte-header) |
| 220–252 | 33 | **[SAM]** ROM header tail | Bytes 15–47 of the ROM's 48-byte file header, copied verbatim |
| 253–255 | 3 | — | Unused by SAMDOS. MasterDOS uses 254 for the parent directory tag and 255 for extra directory tracks |

### Where the ROM's header fields land

Because bytes 220 onwards are the ROM's header from its offset 15, the useful fields have fixed positions.
These are the offsets the DOS's own code uses, so they are the ones a tool should use:

| Directory offset | ROM header offset | Field |
|---|---|---|
| 220 (&DC) | 15 | Flags (`HFG`): bit 0 invisible, bit 1 protected |
| 236–238 (&EC–&EE) | 31–33 | Start address, page form |
| 239–241 (&EF–&F1) | 34–36 | Length, page form |
| 242–244 (&F2–&F4) | 37–39 | Execution address, page form; for BASIC, the auto-run line |

`pntyp` in [e.s](../annotated-src/e.s) reads exactly 236 and 239 to print a code file's start and length, and
242 to print a BASIC file's auto-run line. **[external]** The MGT filesystem wiki gives the same range
(236–244) as "SAM file start/length information", which agrees.

> [!NOTE]
> **[image]** The one entry in `res/master_dos_v2-3.mgt` does *not* match this in every particular. Its
> fields at 236–244 are exactly right (`01 00 80` start, `00 86 3D` length, `FF FF FF` exec, agreeing with the
> nine-byte header at the front of the file data), and so are the type, name, sector count, first sector and
> sector map. But bytes 211–219 are zero where `svhd` would have written the nine-byte header, byte 220 is
> &20 rather than a plausible flags value, and there is a *second* start/length/exec triple at 221–229, in a
> region the ROM's header leaves unused for a code file.
>
> The most likely reading is that this image's directory entry was synthesised by a PC-side build tool from
> the binary rather than written by the DOS. It is good evidence for the fields it agrees on, and should not
> be taken as evidence about the ones it does not.

**Page form** means three bytes — pages, low, high — meaning
$`\text{pages} \times 16384 + ((\text{high}{:}\text{low}) \bmod 16384)`$, with a first byte of &FF meaning
"none". It is described fully in the ROM's `docs/file-formats.md`.

### Entry 0 is *not* special in SAMDOS 2

Other DOSes on this format treat the first directory entry as the disk's own record, keeping a disk label at
bytes 210–219 and, in MasterDOS, a disk identity word at 252–253 and an extra-directory-track count at 255.

**SAMDOS 2 does none of that.** It never writes a disk label, never reads one, and has no disk-name concept at
all: `FORMAT "d1:mydisk"` uses the string only to find the drive prefix, and the `DIR` heading is a fixed
`* SAM DRIVE n - DIRECTORY *` with no name in it. Entry 0 is an ordinary entry and the first file saved to a
fresh disk occupies it.

The practical consequences:

* A disk formatted by SAMDOS has zeros in all of those fields. MasterDOS reads that as a blank disk name, no
  extra directory tracks (its count is *extra* tracks, so zero means the standard four) and a disk identity of
  zero — all of which are correct, so a SAMDOS disk is fully usable under MasterDOS.
* A disk formatted by MasterDOS with **more than four directory tracks** is *not* safe under SAMDOS. SAMDOS's
  `disk.dirtrks` is a constant 4, so it will treat tracks 4 upwards as data and allocate over the extra
  directory.

## The sector address map

195 bytes at offset 15, **one bit per data sector**, set if the sector belongs to this file.

$`195 \times 8 = 1560`$, which is exactly the number of data sectors on an 80-track double-sided disk. The
map is sized for a full disk and has no room for more.

**Bit ordering is little-endian within each byte, and the sequence starts at track 4 sector 1:**

| Byte | Bit | Track | Sector |
|---|---|---|---|
| 0 | 0 | 4 | 1 |
| 0 | 1 | 4 | 2 |
| 0 | 7 | 4 | 8 |
| 1 | 0 | 4 | 9 |
| 1 | 1 | 4 | 10 |
| 1 | 2 | 5 | 1 |
| … | | | |
| 94 | 7 | 79 | 10 |
| 95 | 0 | 128 | 1 |
| … | | | |
| 194 | 7 | 207 | 10 |

The jump from track 79 to track 128 is the side change, and it is contiguous in the map: bit 760 is track 79
sector 10 and bit 761 is track 128 sector 1. **[external]** The MGT filesystem wiki states the same starting
point and ordering.

**The map is used for two different things.** In a file's own entry it says which sectors that file owns. But
the DOS also keeps a **global** map in memory at `sam` (&770F), built by OR-ing every entry's map together as
the directory is scanned (`fdhr` calls `nrsad`, which accumulates as it reads). That combined map is what
tells the DOS which sectors are free.

A file's map is redundant with its sector chain, and SAMDOS never uses it to *find* a sector — it always
follows the chain. It exists for the free-space calculation, and it is what makes MasterDOS's random access
possible without any disk reads at all.

## Free space

**Free space is not stored anywhere on the disk.** There is no allocation table, no free count, no bitmap of
the whole disk. It is recomputed from scratch every time it is needed, by reading all forty directory sectors
and OR-ing together the 195-byte maps of every entry that is in use.

That has several consequences worth knowing:

* **Deleting a file frees its sectors instantly and implicitly.** Zeroing the type byte removes that entry's
  map from the union. Nothing else needs updating, which is why `ERASE` writes exactly one byte.
* **An interrupted save cannot corrupt the free space.** If the directory entry was never written, the
  sectors were never claimed.
* **The file's data survives deletion**, and so does its complete sector map, sitting in the entry that was
  zeroed. Everything an undelete tool needs is still there.
* **Every operation that allocates has to read the whole directory first.** That is why saving a file begins
  with a noticeable pause.
* **The capacity figure `DIR` prints is assumed, not measured** — see [commands.md](commands.md#dir).

## Allocation

`fnfs` in [c.s](../annotated-src/c.s) finds the next free sector. It is a straight first-fit scan from the
start of the data area:

1. Start at track 4 sector 1, byte 0 of the global map.
2. If a map byte is &FF, all eight sectors are taken — skip forward eight sectors and move on. This is the
   fast path, and it is why the scan over a nearly-full disk is quick.
3. Otherwise test bits from bit 0 upward until a clear one is found.
4. Set that bit in **both** the global map and the file's own map in the entry image, and increment the file's
   sector count.
5. Stepping past sector 10 moves to the next track; stepping past the last track of side 1 moves to track 128.
   Running off the end of side 2 raises *Not enough space on disk*.

There is no attempt at contiguity, no interleave and no cylinder grouping. A file written to a fragmented disk
gets whatever holes exist, in order, and its chain will step back and forth across the disk. SAMDOS's
performance on a heavily rewritten disk reflects that; the only remedy is to copy everything to a fresh disk,
which lays each file out contiguously.

## The boot sector

The ROM's `BOOT` command does not know what a DOS is. It does this (see the ROM's `docs/dos-and-extensions.md`):

1. Look from the end of the `ALLOCT` table for a free 16KiB page to load the DOS into, and marks it with `&60`.
   (If it finds an existing DOS page (marked with `&60`, it'll use that instead).
3. Read track 4 sector 1 and look for the text `BOOT` (bits 7 and 5 are ignored) 256-bytes
   from the start of the sector.
4. If this matches, the rest of the DOS is loaded, and then executed with the DOS paged in, at address `&8009`,
   which complete initialization.

Everything after that is the DOS's own doing. SAMDOS's boot sector is at the start of the image
([b.s](../annotated-src/b.s), `org gnd+&4000`) and:

1. Reads the rest of the image in by following the sector chain, into &8000 upwards;
2. Works out which page it and the screen occupy, from `RAMTOP`;
3. Writes the DOS's page number to the ROM's `DOSFLG`, which is how everything else in the ROM knows a DOS is
   present;
4. Claims the page in the ROM's allocation table at &5100, so that BASIC will not use it;
5. Sets the default device to `D`, drive 1, by writing `&0144` to &5A06.

The boot sector is loaded at &8000 but assembled to run at &4000 — the source assembles it with
`org gnd+&4000` and dumps it at offset 0, so the same bytes are correct at either address. The DOS is
*used* at &8000 (the ROM pages it there for each call) but *written* as though it were at &4000.

The first nine bytes of the file are the nine-byte header, so the boot code proper begins at file offset 9.
The source can build the image either way — `include-header` controls it, and `org.adjust` compensates so the
addresses come out the same.

## Disk images

A `.mgt` image is 819200 bytes: **every sector in physical order, both sides interleaved by track**.

$`\text{offset} = ((\text{track} \times 2 + \text{side}) \times 10 + \text{sector} - 1) \times 512`$

where side is bit 7 of the DOS's track number and track is the low seven bits. So track 0 side 1 sectors 1–10
occupy the first 5120 bytes, then track 0 side 2 sectors 1–10, then track 1 side 1, and so on.

A `.dsk` (SAD) image carries a header and may use different geometry; `.sdf` stores raw track data including
IDs and is the format for copy-protected disks. Neither is produced or read by SAMDOS itself.

The Python fragment used to verify this document against `master_dos_v2-3.mgt`:

```python
def offset(track, sector):
    side = 1 if track & 0x80 else 0
    return ((( track & 0x7f) * 2 + side) * 10 + sector - 1) * 512
```
