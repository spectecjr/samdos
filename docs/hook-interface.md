# SAMDOS 2 — The Hook Interface

The `RST &08` codes a machine-code program can call the DOS with. From `hook` and `samhk` in
[b.s](../annotated-src/b.s) and the routines in [h.s](../annotated-src/h.s) and
[c.s](../annotated-src/c.s).

## Calling a hook

A hook is called exactly as a ROM error is raised — `RST &08` followed by a byte:

```asm
           LD IX,&4B00      ; the ROM's header buffer, HDR
           RST &08
           DB 129           ; open the file described there
```

The ROM's `RST &08` handler notices that the code is 128 or more and that a DOS is loaded, pages the DOS in at
&8000 and calls it at page offset &0203. Codes below 128 are ordinary errors.

### What the DOS does on entry

`hook` in [b.s](../annotated-src/b.s):

1. Saves `SP` in `entsp` and `IX` in `svhdr`.
2. Saves **both register sets** — `A`, `HL`, `DE`, `BC` from the alternate set, into `hka`, `hkhl`, `hkde`,
   `hkbc`. The ROM's save and load code passes arguments in the alternate set, which is why the `EXX`/`EX AF,AF'`
   happens first.
3. Sets `DOSACT`, so an error is looked up in the DOS's message table.
4. Zeroes `hksp`, then subtracts 128 and indexes `samhk`.
5. Pushes `rfhk` as the return address, so the routine can simply `RET` when done.

> [!IMPORTANT]
> **Arguments are read from the alternate register set, not the main one.** `hka` is `A'`, `hkhl` is `HL'`,
> and so on. Set them with `EXX` / `EX AF,AF'` before the `RST`, or use the ROM's own save/load path which
> already does.

### Errors

A code **below 128** gives *Invalid code* (98). **There is no upper bound check**: a code above 168 indexes
past the end of `samhk` and jumps to whatever the following bytes happen to be. This is a real hazard when
porting code written for MasterDOS, which defines codes up to 174.

On success the DOS clears `DOSACT`, sets E to 0 and returns.

## The table

Hooks 128–142 are the set the ROM publishes and are common to every SAM DOS. 143 upwards are the DOS's own.
`s` in the table below is a bare `RET` — the code is accepted and does nothing.

| Code | Routine | Purpose | SAMDOS 2 |
|---|---|---|---|
| 128 | `init` | Boot the DOS | ✓ |
| 129 | `hgthd` | [Open a file and return its header](#129-open-a-file) | ✓ |
| 130 | `hload` | [Load the file body](#load-verify-and-save) | ✓ |
| 131 | `hvery` | Verify the file body against memory | ✓ |
| 132 | `hsave` | Save header and body | ✓ |
| 133 | `s` | Park the head | **`RET`** |
| 134 | `hopen` | Open a stream onto a file | **`RET`** |
| 135 | `hclos` | Close a stream | **`RET`** |
| 136 | `initx` | Load and run the auto-load file | ✓ |
| 137 | `hdir` | Directory listing | ✓ |
| 138 | `s` | Format a track | **`RET`** |
| 139 | `hvar` | [The `DVAR` function](#139-dvar) | ✓ |
| 140 | `heof` | The `EOF` function | **`RET`** |
| 141 | `hptr` | The `PTR` function | **`RET`** |
| 142 | `hpath` | The `PATH$` function | **`RET`** |
| 143–146 | `s` | *(MasterDOS: paged load/verify, set directory)* | **`RET`** |
| 147 | `hofle` | [Open a file for writing](#writing-a-file) | ✓ |
| 148 | `sbyt` | Save one byte | ✓ |
| 149 | `hwsad` | [Write a sector](#raw-sector-access) | ✓ |
| 150 | `hsvbk` | Save a block | ✓ |
| 151 | `s` | *(MasterDOS: output to an open-type file)* | **`RET`** |
| 152 | `cfsm` | Close the file being written | ✓ |
| 153 | `s` | *(MasterDOS: sort)* | **`RET`** |
| 154 | `pntp` | — | **`RET`** |
| 155 | `cops1` | — | **`RET`** |
| 156 | `cops2` | — | **`RET`** |
| 157 | `s` | — | **`RET`** |
| 158 | `hgfle` | [Open a file for reading](#reading-a-file) | ✓ |
| 159 | `lbyt` | Load one byte | ✓ |
| 160 | `hrsad` | Read a sector | ✓ |
| 161 | `hldbk` | Load a block | ✓ |
| 162–163 | `s` | *(MasterDOS: multi-sector far transfers)* | **`RET`** |
| 164 | `rest` | Move the head to track 0 | ✓ |
| 165 | `pcat` | Print the catalogue | ✓ |
| 166 | `heraz` | Erase a file | ✓ |
| 167–168 | `s` | *(MasterDOS: channel read and write)* | **`RET`** |

> [!WARNING]
> Fourteen of these are `RET`s that report success. A program that calls hook 134 to open a stream gets no
> error and no stream. Test `DVAR 7` — 20 for SAMDOS 2, 42 or 43 for MasterDOS — before relying on anything
> above 142.

---

## 129: open a file

Reads the ROM's 48-byte header at `IX`, finds the file, and writes the file's own header back.

| Entry | |
|---|---|
| `IX` | The 48-byte header buffer, normally `HDR` at &4B00 |
| `(IX+0)` | The type wanted, or a wildcard |
| `(IX+1)`…`(IX+10)` | The name wanted; &FF in the first byte means "match anything" |

| Exit | |
|---|---|
| `HDL` (&4B50) | The header found, copied there by `txhed` |
| The file | Left open, positioned at its first sector, ready for hook 130 |

The length handed back has **bit 15 of its address word set** (`set 7,d`), because the ROM expects an address
in the &8000 window.

## Load, verify and save

All three start by calling `dschd`, which reads the file's first sector, reads and **discards** the nine-byte
header, and then takes the transfer parameters from the hook registers — overriding whatever the file says:

| Register | Meaning |
|---|---|
| `HL'` (`hkhl`) | Destination address, in the &8000–&BFFF window |
| `C'` (`hkbc`) | Number of whole 16K pages |
| `DE'` (`hkde`) | Length modulo 16K; bit 7 of D is cleared |

That override is the mechanism behind `LOAD "x" CODE address` — the file is loaded where the caller says, not
where it was saved.

**Hook 131, verify**, compares byte by byte and raises *Verify failed* (93) at the first difference. It skips
the nine-byte header explicitly by setting the buffer pointer to 9.

**Hook 132, save**, takes a complete 48-byte header at `IX`: type, name, start, length and execution address.
The page the data lives in comes from the header, so the caller's paging is saved and restored around the
transfer. It calls `ofsm`, `svhd`, `svblk` and `cfsm` in turn — so it allocates, writes the nine-byte header,
writes the body and closes the entry. If the user declines an overwrite, it returns having done nothing.

## 136: auto-load

Looks for a file named `AUTO*` — the name is a ready-made parameter block at `autnam` — loads it and runs it.
Raises *no AUTO\* file* (101) if there is none.

## 137: directory listing

| Entry | |
|---|---|
| `A'` (`hka`) | The `fdhr` mode byte: `1<<fdh.list` (4) for a full listing, `1<<fdh.compact` (2) for the short form |
| `IX` | A header buffer, read by `rxhed` for the drive and pattern |

Prints to the current stream. Hook 165 is the same thing without the header read.

## 139: `DVAR`

| Entry | |
|---|---|
| Calculator stack | The variable number, read by `GETINT` |

| Exit | |
|---|---|
| Calculator stack | The **address** of that variable, as a floating-point number |

The address is the DOS's page × 16384 plus the offset, which needs more than sixteen bits — `hvar` normalises
`A:HL` by shifting left until the top bit is set, starting the exponent at &96 so the arithmetic lands exactly
on the address. See [dos-variables.md](dos-variables.md).

## Writing a file

The sequence a program uses to write a file byte by byte:

| Step | Hook | Effect |
|---|---|---|
| 1 | 147 `hofle` | Read the header at `IX`, scan the directory, allocate the first sector, write the nine-byte header. Returns with carry set if the user declined an overwrite |
| 2 | 148 `sbyt` | Write one byte, in A. Allocates and flushes a sector when the buffer fills |
| 2′ | 150 `hsvbk` | Write a whole block instead: `HL'` = start, `A'` = pages, `DE'` = length mod 16K |
| 3 | 152 `cfsm` | Flush the last buffer and write the directory entry |

**Step 3 is not optional.** Until `cfsm` runs, the directory entry exists only in memory and the file does not
exist on disk. A program that abandons a write halfway leaves the allocated sectors untouched and therefore
still free — which is safe, but means nothing was written.

## Reading a file

The mirror image:

| Step | Hook | Effect |
|---|---|---|
| 1 | 158 `hgfle` | Find the file named in the header at `IX`, read its first sector, read and discard the nine-byte header |
| 2 | 159 `lbyt` | Read one byte into A, fetching the next sector when the buffer runs out |
| 2′ | 161 `hldbk` | Read a whole block: `HL'` = destination, `A'` = pages, `DE'` = length mod 16K |

There is no close for reading — nothing has to be written back.

## Raw sector access

The hook form of the `READ AT` and `WRITE AT` commands.

| Entry | |
|---|---|
| `A'` (`hka`) | Drive, 1 or 2 |
| `D'` (`hkde` high) | Track; bit 7 selects side 2 |
| `E'` (`hkde` low) | Sector, 1–10 |
| `HL'` (`hkhl`) | The caller's address |

512 bytes are transferred. **The transfer goes through the DOS's own buffer and is then copied**, because the
caller's page may not be mappable at the same time as the DOS's. `cals` splits the caller's address into a
page and an offset in the &8000 window and maps it:

| Caller's address | Page selected |
|---|---|
| &4000–&7FFF | The page mapped at &4000 |
| &8000–&BFFF | The page mapped at &8000 |
| &C000–&FFFF | The page mapped at &C000 |
| below &4000 | *Nonsense in SAMDOS* (81) — section A has no page of its own |

Neither hook consults the directory, the sector map or the free space. See the warning under
[`READ` and `WRITE`](commands.md#read-and-write).

## 164, 165, 166

| Code | Effect |
|---|---|
| 164 `rest` | Step the head to track 0. Useful after an error, and before ejecting |
| 165 `pcat` | Print the catalogue to the current stream; `A'` is the `fdhr` mode byte |
| 166 `heraz` | Erase the file named at `(IX+1)`…`(IX+10)`. Raises *File not found* (107) if there is none. **Does not check the protect flag** — unlike the `ERASE` command, this deletes a protected file without complaint |

## A worked example

Writing a 100-byte code file called `TEST` to drive 1:

```asm
           LD IX,HEADER
           EXX
           RST &08
           DB 147            ; open for writing
           JR C,ABANDONED    ; the user said no to overwriting

           LD HL,DATA
           EXX
           LD A,0            ; no whole pages
           LD DE,100         ; 100 bytes
           EXX
           RST &08
           DB 150            ; save the block

           RST &08
           DB 152            ; close -- the file appears now, not before
           RET

HEADER:    DB 19             ; type: code
           DM "TEST      "   ; ten characters, space padded
           DS 4              ; name extension
           DB 0              ; flags
           DS 15             ; type-specific, DIRE, spare
           DB 0,<DATA,>DATA  ; start, page form
           DB 0,100,0        ; length, page form
           DB &FF,&FF,&FF    ; no execution address
```

The header is the ROM's 48-byte form; only bytes 0–47 are read.
