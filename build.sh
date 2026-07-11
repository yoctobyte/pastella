#!/usr/bin/env bash
# Build a pastella program with the pinned pxx compiler + PAL RTL.
#
# pastella is written in the pxx Pascal dialect and targets the PAL (Platform
# Abstraction Layer) directly — native POSIX sockets on desktop, lwIP on ESP32,
# the same calls. No Synapse, no wrapper, no Windows.
#
# Requires a frankonpiler (frank2) checkout for the compiler + RTL.
#   FRANK2=/path/to/frank2 ./build.sh [src.pas] [out]
set -euo pipefail
FRANK2="${FRANK2:-$HOME/frank2}"
PXX="$FRANK2/stable_linux_amd64/default/pinned"
RTL="$FRANK2/lib/rtl"

if [ ! -x "$PXX" ]; then
  echo "pxx compiler not found at: $PXX"
  echo "set FRANK2=/path/to/frank2 (the frankonpiler checkout)"; exit 1
fi

src="${1:-src/spike_udp.pas}"
out="${2:-build/$(basename "$src" .pas)}"
mkdir -p "$(dirname "$out")"

# posix backend for desktop builds; swap to platform/esp for the ESP32 target.
"$PXX" -Fu"$RTL" -Fu"$RTL/platform/posix" "$src" "$out"
echo "built $out"
