# 0012 — NAT traversal & transport strategy

- **Status:** open — **big feature.** Decides whether the network works for real
  users on the real internet, and therefore ranks with
  [0006](0006-bootstrap-and-reachability.md), not below it.
- **Depends:** [0006](0006-bootstrap-and-reachability.md) (rendezvous, relays).
- **Design:** [architecture — transport](../design/architecture.md)

## Why this is not a detail

Most home peers are behind NAT. If two of them cannot connect, the app is broken
for them — and they will not file a bug, they will conclude it does not work and
leave. **NAT traversal is the difference between a protocol and a product.**

## The fork, and the mistake we nearly made

An earlier draft declared **"Pastella is TCP by design"**, on the grounds that
TCP's three-way handshake *is* a return-routability check, so
reflection/amplification is structurally impossible. That part is true and worth
keeping.

**But TCP-only carries a cost that was understated: TCP hole-punching is poor.**
Simultaneous-open behaves inconsistently across NAT implementations, so two peers
*both* behind NAT frequently cannot connect at all. The consequence is that
**relays would carry a large fraction of all internet traffic** — infrastructure we
must run and pay for. That does not make the design dishonest (relays are blind —
[substrate §4](../design/substrate-and-tenants.md)), but *needing* them for most
connections is a materially different network from one where they are a last
resort.

### And the amplification objection to UDP is a SOLVED problem

The earlier draft treated UDP amplification as inherent. **It is not.**

- **WireGuard** — UDP, hole-punches, and under load replies with a **cookie**
  instead of doing work. A reply never exceeds the request. No amplification.
- **QUIC** — UDP, with an explicit **anti-amplification limit**: a server may not
  send more than **3x the bytes received** from an unvalidated address, plus an
  address-validation token.

So reliable hole-punching **and** zero amplification are available together. The
right formulation is transport-independent:

> ### Invariant: no unvalidated amplification
>
> - On **TCP** it is satisfied for free — the handshake *is* the validation.
> - On **UDP** it is satisfied by a **cookie + a 3x limit** before validation.
>
> The invariant never changes. Only the mechanism does.

*(The earlier "never reply larger than the request" / "cookie round-trip" rules
were not wrong — they were UDP-specific, and were discarded prematurely when the
design went TCP-only.)*

## The strategy — hybrid, and staged

What WireGuard and Tailscale do, for exactly these reasons:

| path | when | notes |
|---|---|---|
| **UDP, hole-punched** | the default on the internet | cookie + 3x limit. This is what makes direct connections work for the majority |
| **TCP** | UDP blocked (corporate / hostile networks) | also the LAN and demo path |
| **Relay** | genuinely unpunchable (symmetric NAT both ends) | blind byte-forwarding ([0006](0006-bootstrap-and-reachability.md)) |
| **UDP beacons** | LAN discovery | **announce-only, never request-response** — a protocol that never answers a UDP packet cannot amplify one |

Tailscale reports roughly **5–10%** of pairs needing a relay *with* UDP punching.
TCP-only would be a large multiple of that — which is the whole argument.

### The honest cost

**Reliable gossip over UDP means implementing retransmit/ordering ourselves** — a
small reliability layer, or a QUIC-ish stream. That is real work.

It is, however, the *right kind* of work: it lives in the **pure core**, so it is
deterministic, in-memory testable and fuzzable
([architecture](../design/architecture.md)). It is not lock-soup work.

### The seam that lets us defer it

**The core does not care.** A connection is *"a byte stream, however obtained"* —
TCP socket, punched UDP session, or relayed stream. That is PAL's job, and the core
never learns which. So this is **staged, not front-loaded**:

- **v1 (the demo)** — TCP + LAN beacons. No NAT involved at all. Ships now,
  blocked by nothing ([0005](0005-offgrid-group-chat.md)).
- **v2 (the internet)** — UDP punch with cookie validation; TCP fallback; relay
  last.

## Acceptance

- Two peers behind ordinary consumer NATs connect **directly** (no relay).
- Two peers behind **symmetric** NATs connect via relay, and the relay can read
  nothing.
- On a network where UDP is blocked entirely, peers still connect (TCP fallback).
- **Amplification, tested adversarially:** an unvalidated UDP source cannot make a
  node emit more than 3x what it sent, and cannot make it do real work before
  address validation. Test with *forged source addresses*, not merely with load.
- Switching transport changes **no core code** — if it does, the seam is in the
  wrong place.
- Relay usage is *measured*: if a large fraction of pairs need a relay, the punch
  is broken and we want to know, not to quietly pay for it.
