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

Next: identity (needs ECDSA-P256 signing in the pxx RTL — a frank2 gap), then
trust, messaging policies, discovery, and the ESP32 swarm.

See **[DESIGN.md](DESIGN.md)** for the architecture, the layer plan, the mapping
to pxx/PAL primitives, and the known gaps (notably: ECDSA-P256 signing must be
added to the pxx RTL for the identity layer).

## Build

```sh
FRANK2=/path/to/frank2 ./build.sh src/spike_udp.pas
build/spike_udp
```

Requires a [frankonpiler](https://github.com/) (frank2) checkout for the pxx
compiler and PAL RTL.

## License

CC0 / public domain (see LICENSE) — for the future, no strings.
