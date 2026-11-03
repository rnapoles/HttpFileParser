# Sourced by build.sh, test.sh and run-samples.sh (not meant to be run on its own).
# Sets: ROOT PLATFORM BIN OBJ PROGRAMS    Only Free Pascal is supported here.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# the only optional argument is the compiler, and only "fpc" exists
case "${1:-fpc}" in
  fpc) ;;
  *) echo "Usage: ${0##*/} [fpc]   (only Free Pascal is supported)" >&2; exit 2 ;;
esac

command -v fpc >/dev/null 2>&1 || { echo "fpc was not found on the PATH" >&2; exit 1; }

# native platform: linux64, linux32, linuxarm64, darwin64, darwinarm64 ...
case "$(fpc -iTO)-$(fpc -iTP)" in
  linux-x86_64)  PLATFORM=linux64 ;;
  linux-i386)    PLATFORM=linux32 ;;
  linux-aarch64) PLATFORM=linuxarm64 ;;
  darwin-x86_64) PLATFORM=darwin64 ;;
  darwin-aarch64) PLATFORM=darwinarm64 ;;
  *) PLATFORM="$(fpc -iTO)-$(fpc -iTP)" ;;
esac

BIN="$ROOT/build/fpc-$PLATFORM/bin"
OBJ="$ROOT/build/fpc-$PLATFORM/obj"

# the test project and the example programs, without extension
PROGRAMS=(tests/HttpFileTests examples/DumpHttpFile examples/ConvertHttpFile
          examples/LintHttpFile examples/FormatHttpFile examples/RunHttpFile)
