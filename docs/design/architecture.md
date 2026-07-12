# Architecture — layers, contracts, and where the I/O lives

*Design document. Status: proposed, 2026-07-12.*

`DESIGN.md` states the rule that the whole project hangs on:

> **Protocol = pure functions; I/O = edges.** The state machine takes messages and
> state in, returns new state + actions out. It has *no sockets, no threads, no
> locks*.

That rule is worth restating precisely, because it is what killed the 2005
version (lock soup) and it is what makes everything above testable. This document
says **where exactly the line is**, and what each layer may and may not know.

---

## 1. The shape

```
                    ┌─────────────────────────────────┐
   messages in ───► │  PURE CORE                      │ ───► new state
   state in    ───► │  no sockets, no threads,        │ ───► actions out
                    │  no locks, no clock, no random  │      (send X to P,
                    └─────────────────────────────────┘       store Y, ...)
                                    ▲
                                    │  the ONLY seam
                                    ▼
                    ┌─────────────────────────────────┐
                    │  EDGE: PAL sockets, scheduler,  │
                    │  clock, entropy, disk           │
                    └─────────────────────────────────┘
```

**Everything nondeterministic is an input, never a call.** The core does not
*ask* the clock, it is *given* a time. It does not *draw* randomness, it is
*given* a nonce. It does not *open* a socket, it *returns* "connect to P".

This is what makes the core:

- **deterministic** — same inputs, same outputs, always;
- **testable without a network** — `gossip_mem.pas` already gossips N peers to
  convergence with no sockets, and that is not a mock, it is *the real core*;
- **fuzzable** — feed it garbage frames, assert it never panics and never
  violates an invariant;
- **free of the lock-soup failure mode** — there are no locks to order, because
  there is no concurrency inside.

If you ever find yourself wanting a mutex in the core, the design has gone wrong.

---

## 2. The layers

Each layer is ignorant of the one above it. This is not tidiness; it is what makes
each independently replaceable and independently attackable-in-testing.

### L0 — transport (edge)

PAL directly: `PalSocket` / `PalConnect` / `PalSend` / `PalRecv` / `PalPoll`.
POSIX on desktop, lwIP on ESP32 — **the same calls**.

Knows: node keys, addresses, NAT traversal, framing.
Does **not** know: topics, members, content.

*(Browser is not a target today, and would not be a "wasm backend" — browsers
cannot open raw sockets at all, so it needs a WebRTC transport behind this seam
plus signalling infrastructure. Scope it honestly if it ever comes up.)*

#### Transport: the invariant is fixed, the mechanism is not

**The invariant, which never changes:**

> ### No unvalidated amplification
>
> A node must never be induceable into mailing bytes at a victim it never spoke
> to. This is what separates a P2P network from a distributed DDoS weapon.

**The mechanism differs per transport, and both are fine:**

| transport | how the invariant is met |
|---|---|
| **TCP** | **free** — the three-way handshake *is* the return-routability check. A spoofed source cannot complete it. |
| **UDP** | a **cookie** under load (WireGuard) plus an **anti-amplification limit**: send no more than **3x the bytes received** from an unvalidated address (QUIC). |
| **UDP beacons (LAN)** | **announce-only.** You shout; nobody replies. *A protocol that never answers a UDP packet cannot amplify one.* |

**UDP amplification is a SOLVED problem** — WireGuard and QUIC both solved it, and
the fixes are small. Treating UDP as inherently unsafe was an error in an earlier
draft of this document, and it led to a "TCP by design" absolutism that quietly
cost far more than it saved (below).

#### Why not TCP-only

TCP-only is tempting: the invariant comes free. But **TCP hole-punching is poor** —
simultaneous-open is inconsistent across NAT implementations, so two peers *both*
behind NAT often cannot connect at all.

That would make **relays carry a large fraction of all internet traffic** —
infrastructure we must run and pay for. Relays are blind and honest
([substrate §4](substrate-and-tenants.md)), but *needing* them for most connections
is a materially different network from one where they are a last resort. **NAT
traversal is a big feature, not a detail** ([0012](../tickets/0012-nat-traversal-and-transport.md)).

#### The strategy: hybrid, staged

- **UDP, hole-punched** — the default on the internet (cookie + 3x limit). Direct
  connections for the large majority.
- **TCP** — fallback where UDP is blocked; also the LAN and demo path.
- **Relay** — last resort, for the genuinely unpunchable (symmetric NAT both ends).
- **UDP beacons** — LAN discovery, announce-only.

**The core does not care.** A connection is *"a byte stream, however obtained"* —
TCP socket, punched UDP session, or relayed. That is the edge's job, and the core
never learns which. So the decision is **staged, not front-loaded**: the demo
([0005](../tickets/0005-offgrid-group-chat.md)) is TCP + LAN beacons and needs no
NAT traversal at all; UDP punching lands when the network goes to the internet.

**The honest cost:** reliable gossip over UDP means implementing retransmit and
ordering ourselves. That is real work — but it is the *right kind*: it lives in the
pure core, so it is deterministic, in-memory testable and fuzzable. It is not
lock-soup work.

#### No node owes anyone service

> **Any node may refuse a connection, rate-limit, or drop traffic — at any time,
> for any reason.** Liveness comes from **redundancy** (k replicas, alpha-parallel
> queries), never from an obligation to answer.

This is not a concession; it is what makes the network robust, and it is what makes
opt-in DHT participation ([0004](../tickets/0004-discovery-dht.md)) coherent.
Kademlia already behaves this way — an unresponsive node is simply skipped. **A
protocol whose correctness depends on strangers answering is a protocol that dies
the first time somebody rate-limits.**

### L1 — discovery (pure core + edge beacons)

Answers exactly one question: **who claims to serve topic T?**

Knows: topicIDs, provider records, peer addresses.
Does **not** know: membership, content, or *what a topic means*. **It cannot check
membership — it does not hold the keys, by construction.** That is precisely why
it is safe for every node to serve it for everybody
([0002](../tickets/0002-layering-node-topic-membership.md)).

Three interchangeable implementations behind one interface — LAN beacons, invite
hints, DHT ([0004](../tickets/0004-discovery-dht.md)). **The demo runs with the
DHT absent**, which is the proof that this layer really is swappable rather than
merely drawn as a box.

### L2 — realm / topic (pure core)

Knows: members, admission policy, epoch keys, the object DAG, attestations.
Does **not** know: how any peer was found.

This is the spine — content-addressed anti-entropy over signed objects
([objects & wire](objects-and-wire.md)).

### L3 — app (pure core + UI edge)

Group chat, 1:1, file sync, sensor telemetry. Policies over L2, not subsystems.

---

## 3. The contracts

What crosses each boundary — and just as importantly, what must not.

| boundary | crosses | must NOT cross |
|---|---|---|
| edge → core | received frames, timer ticks, entropy, peer up/down | sockets, threads, locks |
| core → edge | "send frame F to peer P", "connect to A", "store object O", "wake me in T" | anything requiring the core to block |
| L1 → L2 | "peer P claims topic T at address A" | any claim about *membership* — L1 cannot know |
| L2 → L1 | "find peers for topicID X" | the realm key, the member list, any content |
| L2 → L3 | ordered objects, membership changes, trust facts | raw peers, raw frames |

**The L1 ↔ L2 boundary is the security-critical one.** If membership ever leaks
downward, discovery becomes the global correlation index the design exists to
prevent. If L1 ever gets to *assert* membership, an attacker who controls
discovery controls admission.

---

## 4. What is pure and what is not (current code)

| component | status |
|---|---|
| `src/gossip_mem.pas` — content store + offer/fetch reconciliation | **pure**, no I/O. The N-peer harness. This is the model to follow |
| `src/realm.inc` / `src/realm_ca.inc` — handshake, sealing, membership | pure crypto over inputs |
| `src/gossip_tcp.pas`, `src/pastella_node.pas`, `src/gossip_coro.pas` | **edge** — sockets, scheduler, epoll |
| `src/spike_udp.pas`, `src/disco_probe.pas` | edge — beacons |

The test suite (11/11) runs the pure core with no network at all. **Keep it that
way**: any new protocol logic goes in the pure core and gets an in-memory test
*first*, and only then a socket path.

---

## 5. Concurrency

Concurrency lives **only** at the edge, and it is already proven:

- **coroutine reactor** — N clients + handlers on one epoll loop
  (`gossip_coro.pas`);
- **reactor per core** — `pastella_mt` runs 6 peers across 3 OS threads;
- **multi-process** — independent node processes over real TCP (`run_ring.sh`).

The core is single-threaded and knows nothing about any of it. **Three different
concurrency models over one unchanged core** is the strongest evidence the seam is
in the right place — and it is *why* there is no lock soup to fall into.

---

## 6. The rule for new work

1. Write the logic as a pure function over state + input → state + actions.
2. Test it in memory, deterministically, with no sockets.
3. *Then* wire it to an edge.
4. If it needs a lock, a clock, or a socket **inside** the core — stop, the design
   is wrong.
