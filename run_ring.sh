#!/usr/bin/env bash
# Launch an N-node pastella gossip ring as separate processes over loopback TCP.
# Each node seeds one distinct object; after a few rounds all converge.
set -euo pipefail
N=build/pastella_node
[ -x "$N" ] || { echo "build first: FRANK2=/path/to/frank2 ./build.sh src/pastella_node.pas"; exit 1; }
rounds="${1:-6}"
$N 5000 5001 alpha "$rounds" & $N 5001 5002 beta "$rounds" & $N 5002 5000 gamma "$rounds" &
wait
