# Pastella — design

A small, **testable**, cross-platform peer-to-peer gossip layer. Greenfield
rewrite of a ~2005 idea (the original `TPastella`, a Gnutella-lineage P2P layer),
keeping the one good idea and discarding everything that made it fail.

Written in the **pxx** Pascal dialect (frankonpiler), on the **PAL**. No backward
compatibility with the old wire format or code — nothing is inherited but the
concept.

## The one good idea we keep

**Content-addressed anti-entropy.** Every object has a hash (its name). Peers
exchange *hash lists* (offers), then fetch only what they lack. This is the
inv/getdata pattern that BitTorrent, Bitcoin, and IPFS later formalized — the
original pastella had it in 2005. We keep the shape; we modernize the hash
(SHA-256, not MD5-folded-to-64-bit).

## Non-negotiables (what killed the old one, fixed)

1. **Protocol = pure functions; I/O = edges.** The state machine takes messages
   and state in, returns new state + actions out. It has *no sockets, no threads,
   no locks*. This makes it single-threaded-testable, deterministic, and
   fuzzable. The lock-soup that deadlocked the 2005 version cannot exist here —
   the core has no locks to order.
2. **Native PAL, no wrapper.** Transport is PAL directly. In 2026 the only axes
   are **POSIX-or-not** and **kernel-or-not** — and PAL *is* that seam (POSIX
   sockets on desktop, lwIP on ESP32, identical `PalSocket`/`PalSend`/`PalRecv`).
   Synapse was a win32-era uniformity wrapper; it has no place here. **Windows is
   not a target.**
3. **Testing built first.** N in-process peers over an in-memory transport,
   deterministic, plus a fuzzed decoder. The tool the 2005 solo author never had
   — and the reason the old one couldn't be debugged.
4. **Trust is a layer, not a bolt-on.** Subjective, trust-weighted reputation
   (not a global ban list). `ignore(pubkey)` drops a peer at the edge.

## Layers (each testable alone)

```
identity     ECDSA-P256 keypair; every message signed. ignore(pubkey)=edge drop.
L3 trust     subjective, trust-weighted reputation → "reality is your trust graph"
L3 messaging broadcast / direct / TTL-walk — POLICIES over L2, not subsystems
L2 content   content-addressed store + offer/fetch reconciliation  ★the spine
L1 overlay   membership / discovery / connection lifecycle — pure state machine
L0 transport PAL directly: PalSocket/PalConnect/PalSend/PalRecv (POSIX | lwIP)
```

**Superseded in part** — see
**[docs/design/identity-membership-discovery.md](docs/design/identity-membership-discovery.md)**.
That document splits L1's "membership / discovery" in two, because they are not
one layer: **discovery is subject-independent and every node serves it for
everybody**, while **membership is per-realm and private**. It also fixes the two
key decisions this sketch left open — the node key is not the membership key, and
the global layer is a *phonebook, never a filestore* (nodes route metadata for
everyone; they store content only for realms they belong to).

Read it before touching the protocol.

## Mapping to pxx/PAL primitives (all present unless noted)

| Need | Provided by | Status |
|------|-------------|--------|
| Sockets (desktop + ESP32) | `platform` — `PalSocket`, `PalBindIpv4`, `PalConnectIpv4`, `PalListen`, `PalAccept`, `PalSend`/`PalRecv`, `PalSendToIpv4`/`PalRecvFromIpv4`, `PalPoll` | ✅ verified (spike) |
| Content hash | `sha256` — `Sha256` (raw digest), `Sha256Hex` (hex-encoder), `HmacSha256` | ✅ verified vs `sha256sum` |
| Threads / sync (edge only) | `palthread`, `palsync`, `syncobjs`, `channel` | ✅ |
| Signature **verify** | `ecdsa_p256` — `EcdsaP256Verify` | ✅ |
| Signature **sign + keygen** | `ecdsa_p256` — `EcdsaP256Sign`, `EcdsaP256GenKey` | ✅ landed 2026-07-12 (see below) |
| ESP32 target | `platform/esp` backend + `examples/esp32/net-c3` (working lwIP net) | ✅ demonstrated (but see gap below) |

### Known gaps (drive frank2 work)
- **ECDSA-P256 sign + keygen — DONE** (2026-07-12), and ~25x faster while we were
  there: keygen 244→~7 ms, sign 257→~12 ms, verify 482→~19 ms. Three steps in
  frank2: Knuth-D division in `bignum`, a dedicated `p256field` (Montgomery/CIOS
  on saturated 64-bit limbs, behind a new `__pxxmulhi_u64` widening-multiply
  intrinsic), and Euclid instead of Fermat for the inverse mod n. A realm join is
  no longer dominated by signature work.
- **Realm crypto does not run on ESP32 yet.** `p256field` core-dumps on riscv32
  (frank2 `bug-riscv32-p256field-coredump`), and ESP32 is riscv32/xtensa. The net
  stack works; the *crypto* is unproven on device. This gates any "same protocol
  on a $3 chip" demo.
  *(Writing that library also flushed out three real compiler bugs, one of which —
  64-bit named constants silently truncated on 32-bit targets — would have made
  every crypto constant wrong on ESP32 while passing on the dev box.)*
- No Ed25519 / BLAKE2 — using ECDSA-P256 + SHA-256 instead; fine, optional
  frank2 tickets if wanted later.
- `channel` carries `Int64` only — pass buffer-pool indices, not payloads.

## Wire (sketch, not frozen)

Length-prefixed framed messages; versioned handshake. Minimal verbs:
`HELLO` (identity + version) · `HAVE` (offer hash list) · `WANT` (fetch) ·
`DATA` (payload) · `PING`/`PONG`. Every frame signed by the sender's key.

## Build

`./build.sh [src.pas]` — pinned pxx compiler + PAL RTL (posix backend for
desktop). See the spike: `src/spike_udp.pas` proves PAL_NET + SHA-256 end to end.

## Roadmap (full vision, built incrementally)

1. **Spine** — framed PAL transport + content store + offer/fetch reconciliation
   + the N-peer in-memory harness. *(Buildable now — no gaps.)*
2. **Identity** — ECDSA-P256 keypair + signed frames. *(Blocked on the sign gap →
   frank2 ticket.)*
3. **Trust** — subjective trust-weighted reputation + `ignore`.
4. **Messaging** — broadcast / direct / TTL-walk policies.
5. **Overlay** — discovery + membership.
6. **ESP32** — same core, `platform/esp` backend; the swarm demo.
