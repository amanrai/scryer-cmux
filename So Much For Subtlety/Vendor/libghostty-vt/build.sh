#!/usr/bin/env bash
# Build the Ghostty VT core (libghostty-vt) and vendor its header + static lib.
#
# Requires `zig` on PATH (see https://ghostty.org/docs/install/build for the
# version matching the pinned commit). Produces:
#
#   Vendor/libghostty-vt/include/ghostty/vt.h
#   Vendor/libghostty-vt/lib/libghostty-vt.a
#
# The header is also copied next to the CGhosttyVT module so the package's
# include path resolves it.
set -euo pipefail

# Pinned to match the C API this app was written against. Bump deliberately.
GHOSTTY_COMMIT="ae52f97dcac558735cfa916ea3965f247e5c6e9e"

# Ghostty pins zig 0.15.2 exactly (0.16 is rejected). Override with e.g.
#   ZIG=/path/to/zig-0.15.2/zig ./build.sh
# to keep a different global zig untouched.
ZIG="${ZIG:-zig}"

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
work="${here}/.build-ghostty"
include_dir="${here}/include/ghostty"
lib_dir="${here}/lib"

command -v "${ZIG}" >/dev/null 2>&1 || { echo "error: zig not found (set ZIG=/path/to/zig)"; exit 1; }
echo "using zig: $(${ZIG} version) at $(command -v ${ZIG})"

mkdir -p "${include_dir}" "${lib_dir}"

# Shallow-fetch just the pinned commit (avoids a full-history clone).
if [ ! -d "${work}/.git" ]; then
  rm -rf "${work}"
  mkdir -p "${work}"
  git -C "${work}" init -q
  git -C "${work}" remote add origin https://github.com/ghostty-org/ghostty.git
fi
# Only fetch/checkout if not already at the pinned commit (saves a re-download).
if [ "$(git -C "${work}" rev-parse HEAD 2>/dev/null)" != "${GHOSTTY_COMMIT}" ]; then
  git -C "${work}" fetch --depth 1 origin "${GHOSTTY_COMMIT}"
  git -C "${work}" checkout -q --detach FETCH_HEAD
fi

# Build just the host static lib: emit-lib-vt skips the full Ghostty app/tests,
# emit-xcframework=false skips the slow universal xcodebuild step.
( cd "${work}" && "${ZIG}" build -Demit-lib-vt=true -Demit-xcframework=false -Doptimize=ReleaseFast )

# Locate the produced artifacts (paths may shift across Ghostty versions).
header_src="$(find "${work}" -path '*/include/ghostty/vt.h' -print -quit)"
lib_src="$(find "${work}/zig-out" -name 'libghostty-vt.a' -print -quit)"

[ -n "${header_src}" ] || { echo "error: vt.h not found under ${work}"; exit 1; }
[ -n "${lib_src}" ]    || { echo "error: libghostty-vt.a not found under ${work}/zig-out"; exit 1; }

# vt.h pulls in the whole ghostty/vt/ tree, so copy the entire directory.
src_ghostty_dir="$(dirname "${header_src}")"   # …/include/ghostty
rm -rf "${here}/include/ghostty"
mkdir -p "${here}/include"
cp -R "${src_ghostty_dir}" "${here}/include/ghostty"
cp "${lib_src}" "${lib_dir}/libghostty-vt.a"

echo "vendored:"
echo "  ${here}/include/ghostty/  ($(find "${here}/include/ghostty" -name '*.h' | wc -l | tr -d ' ') headers)"
echo "  ${lib_dir}/libghostty-vt.a"
