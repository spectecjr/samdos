#!/bin/bash
#
# check.sh -- prove that the annotated source assembles to the same binary as the original.
#
# Builds samdos.s from src/ and from annotated-src/, compares the two binaries byte for byte, and checks both
# against res/samdos2.reference.bin -- the released SAMDOS 2 image the original source is known to reproduce
# exactly. Finally the static equivalence checker is run, which reports *which line* differs when something does.
#
# Usage:  annotated-src/check.sh [options]
#
#   --no-verify    skip verify_annotated.py (the binary comparison alone is the authoritative check)
#   --keep         leave the build directory in place and print its path
#
# Exit status is 0 only if every comparison matched.

set -u

verify=1
keep=0

for arg in "$@"; do
    case "$arg" in
        --no-verify) verify=0 ;;
        --keep)      keep=1 ;;
        -h|--help)   sed -n '3,15p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *)           echo "check.sh: unknown option '$arg'" >&2; exit 2 ;;
    esac
done

here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/.." && pwd)

# ---------------------------------------------------------------------------------------------------------------------
# Locate pyz80. The pip package installs a console script called "pyz80" (not "pyz80.py", which is what build.xml
# still invokes). On Windows it lands in the per-user scripts directory, which is often not on PATH.
# ---------------------------------------------------------------------------------------------------------------------

if ! command -v pyz80 >/dev/null 2>&1; then
    for finder in "sysconfig.get_path('scripts','nt_user')" "sysconfig.get_path('scripts')"; do
        dir=$(python -c "import sysconfig;print($finder)" 2>/dev/null) || continue
        # python may report a Windows path; make it usable from this shell.
        case "$dir" in
            [A-Za-z]:\\*) dir="/$(echo "${dir:0:1}" | tr 'A-Z' 'a-z')/$(echo "${dir:3}" | tr '\\' '/')" ;;
        esac
        if [ -x "$dir/pyz80" ] || [ -f "$dir/pyz80" ]; then
            PATH="$PATH:$dir"
            export PATH
            break
        fi
    done
fi

if ! command -v pyz80 >/dev/null 2>&1; then
    echo "check.sh: pyz80 not found. Install it with:  python -m pip install pyz80" >&2
    exit 2
fi

# ---------------------------------------------------------------------------------------------------------------------

work=$(mktemp -d) || exit 2
if [ "$keep" -eq 0 ]; then
    trap 'rm -rf "$work"' EXIT
fi

status=0

# build <source-dir> <top-level-source> <output-binary> <label>
build() {
    local dir=$1 src=$2 out=$3 label=$4
    local log="$work/$(basename "$out").log"
    if ( cd "$dir" && pyz80 --obj="$out" -o "$work/$(basename "$out").dsk" "$src" ) >"$log" 2>&1; then
        return 0
    fi
    echo "*** $label BUILD FAILED ***"
    tail -30 "$log"
    return 1
}

# compare <binary-a> <binary-b> <label>
compare() {
    local a=$1 b=$2 label=$3
    if cmp -s "$a" "$b"; then
        echo "$label: BYTE-IDENTICAL"
        return 0
    fi
    echo "*** $label DIFFERS ***"
    cmp -l "$a" "$b" | head -20
    echo "differing bytes: $(cmp -l "$a" "$b" | wc -l)"
    return 1
}

# --- The DOS image ------------------------------------------------------------------------------------------------

build "$root/src" samdos.s "$work/orig.bin" "ORIGINAL" || exit 1
build "$here"     samdos.s "$work/anno.bin" "ANNOTATED" || exit 1

count=$(ls "$here"/*.s | wc -l)
compare "$work/orig.bin" "$work/anno.bin" "samdos.s  ($count annotated files)" || status=1

# --- Against the released image -------------------------------------------------------------------------------------
#
# The original source is a reconstruction of the shipped SAMDOS 2 and reproduces it byte for byte, so the annotated
# build must match it too. This catches the case where both trees are wrong in the same way.

reference="$root/res/samdos2.reference.bin"
if [ -f "$reference" ]; then
    compare "$reference" "$work/anno.bin" "vs samdos2.reference.bin" || status=1
fi

# --- Static equivalence check ---------------------------------------------------------------------------------------

if [ "$verify" -eq 1 ] && [ -f "$here/verify_annotated.py" ]; then
    echo
    if out=$(cd "$root" && python "$here/verify_annotated.py" --ext=.s "$root/src" "$here" 2>&1); then
        echo "verify_annotated.py: $(echo "$out" | tail -1)"
    else
        # Print each mismatch block: the "** MISMATCH" line and the differing lines under it, but not the
        # per-file OK lines that follow.
        echo "$out" | awk '/\*\* MISMATCH/ {show=1} /^  (OK|--) / {show=0} show'
        echo "verify_annotated.py: $(echo "$out" | tail -1)"
        status=1
    fi
fi

if [ "$keep" -eq 1 ]; then
    echo
    echo "build directory kept at $work"
fi

exit $status
