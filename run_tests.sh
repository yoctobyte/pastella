#!/usr/bin/env bash
# Build and run the whole pastella test suite. Each test is self-checking and
# prints a "... OK" line on success. Exits non-zero if any test fails.
#
#   FRANK2=/path/to/frank2 ./run_tests.sh
set -uo pipefail
cd "$(dirname "$0")"

# in-process / single-binary self-checking tests (name -> success marker)
TESTS=(
  "gossip_mem:CONVERGED"
  "gossip_tcp:TCP GOSSIP OK"
  "gossip_coro:COROUTINE REACTOR OK"
  "pastella_mt:MULTI-CORE PASTELLA OK"
  "test_discovery:ZERO-SEED AUTO-DISCOVERY OK"
  "test_filetransfer:FILE TRANSFER OK"
  "test_routing:ROUTING OK"
  "test_nat:NAT TRAVERSAL OK"
  "test_realm:REALM + SECURE TRANSPORT OK"
  "test_realm_ca:CA-REALM MEMBERSHIP OK"
)

pass=0; fail=0
echo "=== building + running pastella test suite ==="
for entry in "${TESTS[@]}"; do
  name="${entry%%:*}"; marker="${entry#*:}"
  if ! FRANK2="${FRANK2:-$HOME/frank2}" ./build.sh "src/$name.pas" >/tmp/pt_$name.build 2>&1; then
    printf '  BUILD-FAIL  %-18s\n' "$name"; fail=$((fail+1)); continue
  fi
  out="$(timeout 120 "build/$name" 2>&1)"
  if echo "$out" | grep -qF "$marker"; then
    printf '  PASS        %-18s %s\n' "$name" "$(echo "$out" | grep -F "$marker")"
    pass=$((pass+1))
  else
    printf '  FAIL        %-18s\n' "$name"; echo "$out" | sed 's/^/                '; fail=$((fail+1))
  fi
done

# multi-process ring (separate node processes over real TCP)
echo "=== multi-process ring (3 node processes) ==="
if FRANK2="${FRANK2:-$HOME/frank2}" ./build.sh src/pastella_node.pas >/tmp/pt_node.build 2>&1; then
  build/pastella_node 5000 5001 alpha 6 >/tmp/pt_n0 2>&1 &
  build/pastella_node 5001 5002 beta  6 >/tmp/pt_n1 2>&1 &
  build/pastella_node 5002 5000 gamma 6 >/tmp/pt_n2 2>&1 &
  wait
  if [ "$(grep -hc 'final store: 3 objects' /tmp/pt_n0 /tmp/pt_n1 /tmp/pt_n2 | paste -sd+ | bc)" = "3" ]; then
    printf '  PASS        %-18s 3/3 nodes converged\n' "ring(multiprocess)"; pass=$((pass+1))
  else printf '  FAIL        %-18s\n' "ring(multiprocess)"; cat /tmp/pt_ring; fail=$((fail+1)); fi
else printf '  BUILD-FAIL  ring\n'; fail=$((fail+1)); fi

echo "=== $pass passed, $fail failed ==="
[ "$fail" -eq 0 ]
