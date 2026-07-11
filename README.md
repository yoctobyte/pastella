# Pastella

A small, testable, cross-platform **peer-to-peer gossip layer** — greenfield
rewrite of a ~2005 idea, in the [pxx](https://github.com/) Pascal dialect on the
PAL (Platform Abstraction Layer).

Content-addressed anti-entropy at its core (offer hash lists → fetch what you
lack — the inv/getdata pattern), rebuilt on one rule: **the protocol is pure
functions, I/O lives at the edges.** That makes it deterministic, fuzzable, and
free of the lock-soup that killed the original.

**2026 simplification:** native PAL sockets, no wrapper. The only axes that
matter are POSIX-or-not and kernel-or-not — PAL is that seam (POSIX on desktop,
lwIP on ESP32, same calls). No Synapse. No Windows.

## Status

Spine working. The content-addressed anti-entropy core runs both ways:
- `src/gossip_mem.pas` — pure in-memory core, N peers gossip pairwise to
  convergence (deterministic, no I/O). This is the test harness.
- `src/gossip_tcp.pas` — the same offer/fetch (HAVE/WANT/DATA) over real PAL
  TCP loopback, every object content-hash verified.
- `src/spike_udp.pas` — the original PAL_NET + SHA-256 capability spike.
- `src/gossip_coro.pas` — coroutine reactor: 8 concurrent client coroutines +
  handlers on ONE epoll loop (pxx scheduler), converge.
- `src/pastella_node.pas` + `run_ring.sh` — a real async NODE; run N as separate
  processes and a gossip ring converges over real TCP (multi-CPU via the OS).

Run the whole suite: `FRANK2=/path/to/frank2 ./run_tests.sh` (9/9 green).

Proven end to end:
- **async** — coroutine reactor (pxx scheduler, epoll)
- **multithreading** — reactor-per-core (per-thread scheduler); `pastella_mt`
  runs 6 peers across 3 OS threads, converges
- **P2P protocol** — content-addressed offer/fetch gossip
- **zero-seed auto-discovery** — UDP broadcast beacons; nodes self-assemble with
  no peer list (`test_discovery`)
- **file transfer** — 256 KB object across a 5-node line, hash-verified per hop
- **routing** — TTL-flood directed delivery, only the destination delivers
- **NAT traversal** — rendezvous connect-back for an inbound-unreachable peer
- **multi-process** — independent node processes gossip over real TCP

Next: identity (ECDSA-P256 signing — the one frank2 RTL gap), then a trust graph
over the discovered mesh.