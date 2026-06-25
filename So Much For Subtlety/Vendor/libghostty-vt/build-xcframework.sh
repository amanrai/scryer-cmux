#!/usr/bin/env bash
# Build the Ghostty **VT core** (the vt.h API our code uses) as a multi-platform
# xcframework, so the iOS + macOS app targets link one binary with the right slice
# per platform.
#
# NOTE: Ghostty's own `-Demit-xcframework=true` packages the *app* embedding API
# (ghostty.h) — it does NOT carry the vt.h terminal API. So we cross-compile the vt
# static lib per Apple target with zig's -Dtarget and assemble the xcframework with
# `xcodebuild -create-xcframework`, bundling vt.h + a CGhosttyVT modulemap.
#
# Requires zig 0.15.2 (set ZIG=/path/to/zig) and Xcode (xcodebuild). Slow; run once.
#
# Produces: Vendor/libghostty-vt/GhosttyVT.xcframework  (module: CGhosttyVT)
set -euo pipefail

GHOSTTY_COMMIT="ae52f97dcac558735cfa916ea3965f247e5c6e9e"
ZIG="${ZIG:-zig}"

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
work="${here}/.build-ghostty"
stage="${here}/.xcframework-build"

command -v "${ZIG}" >/dev/null 2>&1 || { echo "error: zig not found (set ZIG=/path/to/zig)"; exit 1; }
command -v xcodebuild >/dev/null 2>&1 || { echo "error: xcodebuild not found"; exit 1; }
echo "using zig: $(${ZIG} version) at $(command -v ${ZIG})"

# Shallow-fetch the pinned commit (reuses an existing checkout).
if [ ! -d "${work}/.git" ]; then
  rm -rf "${work}"; mkdir -p "${work}"
  git -C "${work}" init -q
  git -C "${work}" remote add origin https://github.com/ghostty-org/ghostty.git
fi
if [ "$(git -C "${work}" rev-parse HEAD 2>/dev/null)" != "${GHOSTTY_COMMIT}" ]; then
  git -C "${work}" fetch --depth 1 origin "${GHOSTTY_COMMIT}"
  git -C "${work}" checkout -q --detach FETCH_HEAD
fi

rm -rf "${stage}"; mkdir -p "${stage}"

# Names of slices that built successfully (drives the xcframework assembly below).
SLICES=()

# Cross-compile the vt static lib for one zig target → stage/<name>/libghostty-vt.a.
# Args: <triple> <name> <required:0|1> [extra zig flags…]. A non-required slice that
# fails is warned about and skipped rather than aborting the whole build.
build_slice () {
  local triple="$1" name="$2" required="$3"; shift 3
  echo "── building vt core for ${name} (${triple})${*:+ [$*]} ──"
  if ( cd "${work}" && "${ZIG}" build -Demit-lib-vt=true -Demit-xcframework=false \
        -Doptimize=ReleaseFast -Dtarget="${triple}" "$@" ); then
    local lib_src
    lib_src="$(find "${work}/zig-out" -name 'libghostty-vt.a' -print -quit)"
    if [ -n "${lib_src}" ]; then
      mkdir -p "${stage}/${name}"
      cp "${lib_src}" "${stage}/${name}/libghostty-vt.a"
      SLICES+=("${name}")
    elif [ "${required}" = "1" ]; then
      echo "error: libghostty-vt.a not found for ${name}"; exit 1
    else
      echo "warning: ${name} produced no lib — skipping"
    fi
  elif [ "${required}" = "1" ]; then
    echo "error: required slice ${name} failed to build"; exit 1
  else
    echo "warning: optional slice ${name} failed to build — skipping (xcframework will omit it)"
  fi
  # zig-out is reused across targets — clear it so the next slice can't pick up a stale lib.
  rm -rf "${work}/zig-out"
}

# macOS + iOS device are required (physical-iPad target). The simulator is best-effort:
# zig defaults it to -mcpu baseline (no NEON), which breaks simdutf, so force a real CPU.
build_slice "aarch64-macos"          "macos-arm64"          1
build_slice "aarch64-ios"            "ios-arm64"            1
build_slice "aarch64-ios-simulator"  "ios-arm64-simulator"  0  -Dcpu=apple_m1

# Headers: the full ghostty/ vt.h tree + a modulemap exposing it as `CGhosttyVT`
# (so `import CGhosttyVT` keeps working unchanged in Swift).
hdr="${stage}/Headers"
mkdir -p "${hdr}"
header_src="$(find "${work}" -path '*/include/ghostty/vt.h' -print -quit)"
[ -n "${header_src}" ] || { echo "error: vt.h not found under ${work}"; exit 1; }
cp -R "$(dirname "${header_src}")" "${hdr}/ghostty"      # …/include/ghostty → Headers/ghostty
cat > "${hdr}/module.modulemap" <<'EOF'
module CGhosttyVT {
    header "ghostty/vt.h"
    export *
}
EOF

# Assemble the xcframework (static-library form: -library + shared -headers) from
# whatever slices built.
args=()
for name in "${SLICES[@]}"; do
  args+=( -library "${stage}/${name}/libghostty-vt.a" -headers "${hdr}" )
done
rm -rf "${here}/GhosttyVT.xcframework"
xcodebuild -create-xcframework "${args[@]}" -output "${here}/GhosttyVT.xcframework"

# The app-API xcframework (if a previous run made it) is not what we use.
rm -rf "${here}/GhosttyKit.xcframework"

echo
echo "vendored: ${here}/GhosttyVT.xcframework  (module: CGhosttyVT)"
find "${here}/GhosttyVT.xcframework" -maxdepth 1 -mindepth 1 -type d -exec basename {} \;
