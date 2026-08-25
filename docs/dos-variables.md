# SAMDOS 2 — DOS Variables (`DVAR`)

The block at `dvar` in [b.s](../annotated-src/b.s), reached from BASIC through the `DVAR` function, which is
hook code 139 (`hvar` in [h.s](../annotated-src/h.s)).

## How `DVAR` works

> [!IMPORTANT]
> **`DVAR n` returns the *address* of variable $`n`$, not its value.** Use `PEEK DVAR n` to read and
> `POKE DVAR n, x` to write.

The address is a full linear address — the DOS's page number times 16384, plus the offset — which does not
fit in sixteen bits, so `hvar` stacks it as a floating-point number rather than an integer. `PEEK` and `POKE`
accept that form directly, so nothing special is needed in BASIC:

```basic
PRINT PEEK DVAR 7          : REM the DOS version, times 10
POKE DVAR 0, 2             : REM flash the border blue during disk access
POKE DVAR 1, 80            : REM format single-sided from now on
```

`hvar` reads its argument with `GETINT`, so $`n`$ may be any integer the DOS's page can address. **There is
no range check.** `DVAR 5000` returns an address 5000 bytes into the DOS's own code, and poking it will
corrupt the DOS.

## The variables

| `DVAR` | Name | Default | Purpose |
|---|---|---|---|
| 0 | `rbcc` | 7 | Border colour flashed during disk access. **Zero disables the effect** |
| 1 | `traks1` | 128+80 | Drive 1: track count in the low bits, bit 7 set for double sided |
| 2 | `traks2` | 0 | Drive 2, same encoding. **Zero means no second drive** |
| 3 | `stprat` | 0 | Drive 1 head step rate, in units of the `stpdel` delay loop |
| 4 | `stprt2` | 0 | Drive 2 step rate |
| 5 | `chdir` | &20 | The character `DIR` prints in place of a space inside a file name |
| 6 | `nstat` | 1 | Network station number |
| 7 | `vers` | 20 | DOS version × 10 — 20 is version 2.0 |
| 8 | `size1` | 80 | Printer page length |
| 9 | `size2` | 0 | |
| 10 | `szea` | 12 | |
| 11 | `lfeed` | 1 | Printer line feed |
| 12 | `lmarg` | 0 | Printer left margin |
| 13 | `graph` | 1 | Printer graphics mode |
| 14–21 | — | 0 | Spare |
| 22–24 | `extadd` | `CALL cmr` | The three bytes of a `CALL` instruction — do not poke these |
| 25–26 | `onerr` | 0 | **The external command vector.** See below |
| 27 | — | `RET` | The `RET` that ends the external call |
| 28–29 | `hksp` | 0 | Stack pointer saved on entry to a hook, for error unwinding |
| 30–31 | — | 0 | Spare |
| 32 onwards | `pcc1` … | | Printer control sequences, all unreferenced — see [below](#the-printer-variables) |

### The three that matter in practice

**`DVAR 0`, the border flash.** SAMDOS flashes the border while the drive is busy. On a monitor this is
distracting and on some displays it beats against the frame rate; poking zero turns it off with no other
effect.

**`DVAR 1` and `DVAR 2`, the drive geometry.** These are consulted for three different things, and getting
them wrong shows up in three different ways:

| Used by | Effect of a wrong value |
|---|---|
| `FORMAT` | Formats that many tracks and sides — this is the only way to make a non-standard disk |
| `fns5`, the allocator | Decides where side 1 ends and side 2 begins, and when the disk is full |
| `pcat` | Chooses the capacity figure `DIR` subtracts from, so free space is misreported |

`DVAR 2` is zero by default: **SAMDOS assumes a single drive**. A machine with two drives needs
`POKE DVAR 2, 128+80` before the second one can be used at all, or `DIR 2` gives *No such drive*. This is the
single most commonly needed poke on the whole list.

**`DVAR 5`, the `DIR` space character.** File names are space-padded, so a name with a space in the middle is
indistinguishable from one without. Setting this to something visible — say `POKE DVAR 5, CODE "."` — makes
the padding show, which is the only way to tell `"MY FILE"` from `"MYFILE"` in a listing.

## The external command vector

`DVAR 25–26` is the one genuinely programmable hook in SAMDOS. `syntax` in [b.s](../annotated-src/b.s) calls
through it for any command token it does not recognise:

```asm
extadd:        call cmr        ; DVAR 22-24
onerr:         defw 0          ; DVAR 25-26  -- the address to call
               ret             ; DVAR 27
```

The address is called through `cmr`, the DOS's ROM-calling helper, with:

| On entry | |
|---|---|
| A | The ROM error code that would have been reported, normally 29 |
| `CHADD` | Already restored to where the ROM left it, pointing at the unrecognised statement |
| `cstr1` | The command token that was read |

Returning without acting lets the ROM's error stand, so a handler that does not recognise the command should
simply `RET`. The default value of zero means the vector is skipped entirely — `syntax` tests for it before
calling.

This is how a utility adds commands to SAMDOS. It is also how a utility *breaks* SAMDOS: there is no chaining
convention, so two programs installing themselves here will fight, and nothing restores the vector when a
program exits.

## The printer variables

`DVAR 8` to `DVAR 13`, and the control sequences from `DVAR 32` onward (`pcc1` to `pcc5`, plus bitmaps for
`£`, `#` and a copyright sign), are **the remains of a printer driver that SAMDOS 2 does not have**. None of
them is referenced by any code in the image. They are documented here only so that a program poking around
the block knows they are inert.

## Reading `DVAR` from machine code

Hook code 139 does the work directly. See [hook-interface.md](hook-interface.md#139-dvar).

The block's own address can be had once and reused: it is at offset &0100 in the DOS page, and the DOS page
number is in the ROM's `DOSFLG`. Reading `DVAR 0` and subtracting nothing gives the base.
