# Annotated SAMDOS 2 source

A parallel copy of `../src`, documented as a modern codebase would be: file-level overviews, per-routine contracts
(entry, exit, errors, notes), inline explanation of non-obvious code, and named constants in place of magic numbers.

**The annotated source assembles to a byte-identical binary.** Nothing here changes behaviour.

> [!WARNING]
> This annotation was produced with AI assistance and has not been run on real hardware (see
> [Verification](#verification) for what *has* been checked). Treat the commentary as a well-evidenced reading of the
> code, not as the author's own documentation.

## Status

Complete. All eight source files are converted, and both the annotated build and the original reproduce
`../res/samdos2.reference.bin` exactly.

| File | Lines (orig → annotated) | Contents |
|---|---|---|
| `samdos.s` | 12 → 31 | Build glue: the include list and the padding to 10000 bytes |
| `a.s` | 152 → 497 | Equates: hardware, ROM interface, disk format, directory and header layouts, error and hook codes |
| `b.s` | 545 → 706 | Boot sector, DOS variables, the parameter and header buffers, the three entry points, hook dispatch |
| `c.s` | 1574 → 2010 | The disk driver: sector I/O, error recovery, the sector map, the directory, file open and close |
| `d.s` | 778 → 970 | ROM interface helpers, the flag byte, error reporting and messages, the NMI snapshot |
| `e.s` | 546 → 682 | Formatting and disk copying, file type printing, decimal printing, the screen messages |
| `f.s` | 956 → 1198 | The commands: DIR, ERASE, COPY, RENAME, PROTECT, HIDE, LOAD, FORMAT, CALL, READ/WRITE AT |
| `h.s` | 447 → 589 | The hook routines the ROM calls, and file name parsing |

## Documentation derived from this source

The [`docs/`](../docs/) folder documents what the code *does*, for someone using or reimplementing the DOS
rather than reading it: the [commands](../docs/commands.md), the
[on-disk format](../docs/disk-format.md), the [file formats](../docs/file-formats.md), the
[hook interface](../docs/hook-interface.md), the [errors](../docs/errors.md), the
[DOS variables](../docs/dos-variables.md), and a [user guide](../docs/user-guide.md). Each claim cites the
routine here that it came from.

## What SAMDOS is

SAMDOS is not part of the SAM Coupé ROM. It is a 10000-byte image loaded from the first tracks of a disk into a 16K
RAM page, where it runs at `&4000`. The ROM contains no disk code at all: it forwards everything to whatever DOS is
resident, through three fixed entry points at the base of that page and a set of `RST &08` hook codes.

That arrangement shapes the whole program. Because the DOS occupies the same addresses as the ROM's own system
variables, it cannot simply read one — it has to ask the ROM to map the system page and run a one-instruction helper
there. The `cmr` / `nrrd` / `nrwr` family in `d.s` is that mechanism, and it accounts for a great deal of otherwise
puzzling indirection.

The counterpart documentation for the ROM's side of the interface is in the
[samrom](https://github.com/stefandrissen/samrom) repository — `docs/machine-code-interface.md` for the hook codes
and `docs/file-formats.md` for the header layout, which `a.s` reproduces as the `hdr.*` equates.

## Things worth knowing about the code

A few findings that took some working out, recorded here because they explain otherwise baffling code:

* **`rsadx` builds the free-space map for free.** There is no allocation table on the disk; the sectors a file uses
  are a bitmap in its own directory entry. To find free space the DOS ORs those bitmaps together — and it does so
  *while reading the directory*, by pointing the accumulating pointer at `&7700` and letting each entry's bitmap land
  on top of the global map at `&770F`, which is exactly `de.sam` bytes in. The padding either side of `sam` exists so
  the rest of each entry has somewhere harmless to go.
* **Both register sets carry two destinations.** `ldblk` and `svblk` read or write a sector in one loop that serves
  two counts: the main set holds the caller's memory and a count of 510, the alternate set the sector buffer and a
  count of 2, and `exx` switches between them when the first count runs out. That is how the two link bytes at the
  end of a sector are separated from the data without a second pass.
* **The screen is used as scratch.** A save has to know a sector's successor before it can write the sector, so it
  cannot allocate as it streams. Instead it allocates every sector the block will need up front and keeps the list in
  the screen page.
* **`cdec` returns to its caller's caller.** On a successful transfer it discards the return address of the retry
  loop above it, so the `jr` that follows the call is only ever reached on a retry.
* **Six unrolled status polls per byte.** At 250 kbit/s a byte arrives every 32 µs; a rolled-up polling loop would
  spend too much of that budget on the jump back.

Some things are simply dead, and are marked as such rather than removed:

* Over half the equates in `a.s` are never referenced — leftovers from the network (SNOS) and Master DOS variants
  that share this source lineage, including a whole set of channel record offsets for record-structured files that
  SAMDOS 2 does not have (`hopen`, `hclos`, `heof` and `hptr` are bare `RET`s).
* `smchk`, `chksm` and `sum` checksum the image and are never called — which is as well, because `size` is defined as
  `zzend-gnd+&0220` where it should subtract that offset, so the sum would run `&440` bytes past the end.
* The printer control sequences in `b.s`, `evsp`, `number` and `pmo4` (the copyright banner) are all unreferenced.
* `hook` has no upper bound check: a hook code above 168 indexes past the end of `samhk`.

## Conventions

### Naming

The original source already uses dotted lowercase names (`gnd.bank`, `org.adjust`, `comm.port.1`), so the constants
added by this annotation follow the same convention. None of the original symbols contain a dot except those three,
so there is no risk of collision.

| Prefix | Meaning | Example |
|---|---|---|
| `port.` | I/O port number | `port.hmpr` (251) |
| `page.` | Paging field or value | `page.mask` (%00011111) |
| `wd.st1.` / `wd.st2.` | WD1772 status bit, type I or type II/III command | `wd.st2.drq` (1) |
| `disk.` | Disk geometry | `disk.sctdata` (510) |
| `de.` | Directory entry field, flag or size | `de.sam` (15) |
| `fdh.` | Bit of the `fdhr` directory-scan mode byte | `fdh.wild` (3) |
| `hdr.` | Field within the 48-byte file header | `hdr.start` (31) |
| `ft.` | File type | `ft.basic` (16) |
| `err.` | DOS error code, as passed to `derr` | `err.notfound` (107) |
| `fn.` | File name lengths | `fn.maxlen` (14) |
| `rom.` / `rst.` | ROM address | `rom.hdr` (&4B00) |
| `...tok` | BASIC token, following the original's own convention | `totok` (&8E) |

The type I and type II status bits are given separately because bits 1 and 2 mean different things depending on
which command was issued, and this code relies on both readings.

### Layout

* Labels in column 0, mnemonics in column 16, matching the original.
* Maximum line length 120 characters.
* Section banners use `=` rules, routine headers `-` rules.
* The original's own comments are kept, in their original wording and position, alongside the added ones.

## Verification

`check.sh` performs the whole comparison:

```sh
python -m pip install pyz80
annotated-src/check.sh
```

```text
samdos.s  (8 annotated files): BYTE-IDENTICAL
vs samdos2.reference.bin: BYTE-IDENTICAL

verify_annotated.py: FAILURES: 0
```

It builds `samdos.s` from `src/` and from `annotated-src/`, compares the two binaries, checks the annotated build
against `res/samdos2.reference.bin` — the released image the original source is known to reproduce exactly, which
catches the case where both trees are wrong in the same way — and then runs the static checker, which reports *which
line* differs when something does. Exit status is 0 only if every comparison matched, so it drops straight into a
hook or a CI step. Run it after every edit.

Options: `--no-verify` skips the static checker; `--keep` leaves the build directory behind. The script finds pyz80
itself, including in the per-user scripts directory Windows installs it into. Note that the pip package provides a
console script called `pyz80`, **not** `pyz80.py`, which is what `build.xml` still invokes.

### Static equivalence check

`verify_annotated.py` checks equivalence directly from the text:

1. Strip comments and blank lines.
2. Build a symbol table from every `EQU` in both trees and resolve each to an integer.
3. Normalise each code line: canonicalise numeric literals (`&FF`, `%11111111`, `255`, `"A"`) to decimal, substitute
   resolved symbols for their values, constant-fold arithmetic operands, and standardise whitespace and case.
4. Compare the resulting instruction streams line for line.

If the streams match, the two files must assemble identically — no annotation or renaming can have altered the
emitted bytes. Memory indirection is distinguished from arithmetic so `ld hl,(chadd)` is never confused with a folded
constant, though the address *inside* an indirection is still folded; and where an expression starts with a label,
whose value is unknowable without assembling, the numeric terms are still added up, so `uifa+hdr.start+1` and
`uifa+32` compare equal.

It is the same script the samrom tree uses, with `--ext=.s` to select the source extension. Annotating SAMDOS
required four fixes to it, all of them genuine parsing bugs that produced false mismatches on files the assembler had
already confirmed byte-identical:

* dotted identifiers were not recognised as symbols, so `port.hmpr` never resolved
* the numeric-literal pattern matched inside identifiers, reading `fdh.number` as the suffix-hex literal `fdh`
* `<<`, `>>` and `|` were not folded, so a bit mask written as `1<<fdh.name | 1<<5` did not reduce
* expressions inside an indirection, and expressions led by a label, were not folded at all

### What it does not prove

* That the DOS behaves correctly on hardware. A byte-identical image cannot behave differently, but nothing here has
  been run on a real machine or an emulator as part of this work.
* That the commentary is correct. The build proves the *code* is unchanged, not that the explanations of it are
  right — see the warning at the top.
