# SAMDOS

Source code of [samdos2](https://www.worldofsam.org/products/samdos), the standard disk operating system for the SAM Coupé.

### Contents

| Folder | |
|---|---|
| [src/](src/) | The original source, for the Comet assembler |
| [annotated-src/](annotated-src/) | The same source documented as a modern codebase, assembling to a byte-identical binary — see [its README](annotated-src/README.md) |
| [docs/](docs/) | Reference and user documentation, derived from the source — see below |
| [res/](res/) | The released binary, for comparison |

### Documentation

| Document | Contents |
|---|---|
| [docs/user-guide.md](docs/user-guide.md) | **Start here.** Getting started, everyday tasks, the traps, and recovery |
| [docs/commands.md](docs/commands.md) | Every command SAMDOS adds to BASIC: syntax, arguments, behaviour and errors |
| [docs/disk-format.md](docs/disk-format.md) | Disk geometry, the directory, sector chaining, the sector map, free space |
| [docs/file-formats.md](docs/file-formats.md) | File types, the nine-byte header, the 48-byte header, per-type data |
| [docs/hook-interface.md](docs/hook-interface.md) | The `RST &08` hook codes, with the register contract for each |
| [docs/errors.md](docs/errors.md) | Error codes 81–112 and their messages |
| [docs/dos-variables.md](docs/dos-variables.md) | The `DVAR` block |

> [!WARNING]
> The `annotated-src/` and `docs/` trees were produced with AI assistance and have not been run on real
> hardware. The annotated source is proven byte-identical by `annotated-src/check.sh`; the commentary and
> documentation are a well-evidenced reading of the code, not the author's own words.

### Procedure
The starting point was the source code [SamDos2InCometFormatMasterv1.2.zip](http://ftp.nvg.ntnu.no/pub/sam-coupe/sources/) which contains five versions (comp1.s through comp5.s).  These five versions have been uploaded over each other with the version numbers in the files being renamed to provide source history.

comp5.s is not the final "samdos2" as was publicly distributed.

I disassembled the samdos2 binary using [dZ80](http://www.inkland.org.uk/dz80/) and merged it into the last source release. Prior to merging I standardised (lowercased) the sources making the changes and additions from samdos2 visible.

### Triva
- The final build of samdos2 contains various pieces of noise from assembling and / or using the DOS before saving it. This noise, some of which looks like assembly source, is surrounded by <noise> comments.
- The unused copyright message at label pmo4 changed from 'Miles Gordon Technology Plc  1' (e1.s) to 'Sam Computers Ltd. Version  1' (e2.s & e3.s) to 'MILES GORDON TECHNOLOGY plc  1' (final)
