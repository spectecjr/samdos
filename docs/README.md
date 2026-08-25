# SAMDOS 2 — Documentation

Reference and user documentation for **SAMDOS 2**, the standard disk operating system for the SAM Coupé,
derived from the annotated source in [annotated-src/](../annotated-src/).

> [!WARNING]
> This documentation was produced with AI assistance by reading the source. Almost everything here is derived
> directly from the code and is marked as such; the few claims taken from outside sources are labelled
> **[external]** and listed in [Sources](#sources). Nothing here has been checked on real hardware.

## The documents

**Start here if you are using SAMDOS:** [user-guide.md](user-guide.md).

| Document | Contents |
|---|---|
| [user-guide.md](user-guide.md) | A practical guide: getting started, everyday tasks, the traps, and recovery |
| [commands.md](commands.md) | Every command SAMDOS adds to BASIC: syntax, arguments, behaviour and errors |
| [disk-format.md](disk-format.md) | Disk geometry, the directory, sector chaining, the sector address map, free space |
| [file-formats.md](file-formats.md) | File types, the nine-byte header, the 48-byte header, and what each type's data contains |
| [hook-interface.md](hook-interface.md) | The `RST &08` hook codes, with the register contract for each |
| [errors.md](errors.md) | Error codes 81–112 and their messages |
| [dos-variables.md](dos-variables.md) | The `DVAR` block: every variable, its default and its effect |

Related documentation in the [SAM Coupé ROM repository](https://github.com/stefandrissen/samrom):

| Document | Why it matters here |
|---|---|
| `docs/file-formats.md` | The 48-byte header is the ROM's, not the DOS's; SAMDOS stores it and hands it back |
| `docs/dos-and-extensions.md` | How the ROM finds a DOS, pages it in, and calls it |
| `docs/machine-code-interface.md` | Calling the DOS from machine code, and the calculator-stack conventions the hooks use |
| `docs/tokenized-program-format.md` | What is inside a saved BASIC file |

## What SAMDOS is

SAMDOS is not part of the SAM Coupé ROM. It is an ordinary CODE file, `SAMDOS2`, loaded into one 16K page of
RAM at the top of memory. The ROM knows only three things about it:

| Address in the DOS page | What the ROM does with it |
|---|---|
| `+&0200` | `JP HOOK` — entered by `RST &08` with a code of 128 or more |
| `+&0203` | `JP SYNTAX` — entered when the ROM cannot parse a statement |
| `+&0206` | `JP NMI` — entered when the NMI button is pressed |
| `+&0210` | A word holding the address of the DOS's error message table |

Everything SAMDOS does reaches BASIC through those four things. There is no other published interface, and no
part of the ROM contains disk code — `LOAD`, `SAVE`, `DIR` and the rest are all handled by whichever DOS happens
to be loaded.

The DOS is booted by the ROM's `BOOT` command, which reads track 0 sector 1 of the disk, finds a directory
entry named `BOOT`, and loads and runs the first sector of that file. That sector is the DOS's own
bootstrap: it reads the rest of the image in by following the sector chain, then registers itself with the
ROM (see `START` in [b.s](../annotated-src/b.s)).

## Version

`DVAR 7` reads 20, which the DOS's own convention renders as version **2.0**. The released binary is
`res/samdos2.reference.bin`.

## Relationship to GDOS, G+DOS and MasterDOS

SAMDOS's disk format is the **MGT format**, inherited from the DISCiPLE and +D interfaces for the ZX Spectrum,
where it was managed by GDOS and G+DOS. **[external]** The geometry, the 256-byte directory entry, the
195-byte sector address map and the nine-byte file header are all the same; SAMDOS adds the SAM file types
(16–20) alongside the Spectrum ones (1–11) and stores the ROM's 48-byte header in bytes that GDOS left spare.
That is why a SAMDOS disk can hold Spectrum files, and why SAMDOS's `LOAD` understands a 48K snapshot.

[MasterDOS](https://github.com/stefandrissen/masterdos) replaces SAMDOS, keeps the format unchanged, and adds
subdirectories, RAM discs, a clock and record files — all in bytes of the directory entry SAMDOS leaves at
zero. A SAMDOS disk is readable by MasterDOS and, so long as no subdirectories are used, the reverse is true
as well.

## Sources

Everything not marked below is derived from the annotated source in [annotated-src/](../annotated-src/), and
cites the file and routine it came from.

* **[external]** [MGT filesystem — Sinclair Wiki](https://sinclair.wiki.zxnet.co.uk/wiki/MGT_filesystem) —
  used to cross-check the directory entry layout, the sector address map's bit ordering, and the file type
  numbers against the DISCiPLE/+D originals. Where the wiki and the source disagree, the source is followed
  and the difference noted.
* **[external]** [SAMDOS — World of SAM](https://www.worldofsam.org/products/samdos) — product background.
* The released disk image `res/master_dos_v2-3.mgt` in the MasterDOS repository was parsed byte by byte
  against the layout given in [disk-format.md](disk-format.md), and agrees with it. Findings from that are
  marked **[image]**.
