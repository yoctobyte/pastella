# Pastella docs & tickets

Minimal, file-based. No tracker, no tooling — just markdown under version control.

## Right now

**[0014 — v0.1: the smallest real network](tickets/0014-v0.1-two-laptops.md)** is the
only active work: two or three laptops, different locations, gossiping readings,
manual peer-add + LAN, running for a week.

→ **[The v0.1 implementation plan](plans/v0.1-implementation-plan.md)** is
self-contained: start a fresh session, read only that, and build. It says explicitly
*not* to read the rest of this page first — the design docs are **thinking ahead of
the code**, a menu rather than a meal, and they will pull you into decisions v0.1
deliberately does not make.

## Design documents

Decisions that outlive any one ticket. **Read before touching the protocol** —
[`design/`](design/) has its own index.

- [The substrate and its tenants](design/substrate-and-tenants.md) — Pastella is
  **not a messenger; it is a substrate**, and the messenger is its first tenant. An
  app is payload types + a policy, with **zero** core changes — if it needs a core
  change, the core was wrong. Node roles (leaf / full / seed / mailbox / relay),
  the blind-infrastructure rule, and **the constitution** every tenant must obey.
- [Architecture](design/architecture.md) — where the pure core ends and the I/O
  edge begins; what each layer may and may not know.
- [Objects & wire](design/objects-and-wire.md) — one signed envelope, many payload
  types. The spine every other document assumes and none of them defined.
- [Identity, membership & discovery](design/identity-membership-discovery.md) —
  **identity is cheap, so it must confer zero trust**; the node key is not the
  membership key; the global layer is a phonebook, never a filestore; the three
  admission tiers as policy over one mechanism; 1:1 as a two-member realm reached
  by private rendezvous; and offline delivery — what Signal's servers actually buy.
- [Threat model](design/threat-model.md) — what we defend, what we deliberately do
  **not**, and why we document architecture rather than legal posture.

## Tickets

Live in [`tickets/`](tickets/), one file per ticket: `NNNN-slug.md`.

Frontmatter-ish header each ticket carries:

- **Status:** `open` · `in-progress` · `blocked` · `done` · `rejected`
- **Depends:** other tickets or external gaps (e.g. a frank2 RTL feature)

Flow: write the ticket → implement → flip Status to `done` with the commit(s) →
if a phase is blocked, mark `blocked` and say on what.

## Index

- [0001 — Realms & secure transport](tickets/0001-realms-and-secure-transport.md)
- [0002 — The layering: node vs topic vs membership](tickets/0002-layering-node-topic-membership.md)
- [0003 — Membership log, auth tiers, key epochs](tickets/0003-membership-log-and-tiers.md)
- [0004 — Discovery: subject-independent, three knobs](tickets/0004-discovery-dht.md)
- [0005 — Off-grid group chat (the demo)](tickets/0005-offgrid-group-chat.md)
- [0006 — Bootstrap & reachability: bringing the network UP](tickets/0006-bootstrap-and-reachability.md)
- [0007 — Pairwise contacts (1:1)](tickets/0007-pairwise-contacts.md)
- [0008 — Attestation & the trust graph](tickets/0008-attestation-and-trust-graph.md) — *how do I prove this person is who they say?*
- [0009 — Sybil resistance: attack edges & trust flow](tickets/0009-sybil-resistance-trust-flow.md) — *what is a chain of vouches actually worth, and what can a botnet extract from it?*
- [0010 — File sharing within a realm](tickets/0010-file-sharing-in-realm.md) — *optional tenant; forces chunking + GC*
- [0011 — Sensor mesh & the leaf-node role](tickets/0011-sensor-mesh-leaf-nodes.md) — *optional tenant; forces the leaf contract*
- [0012 — NAT traversal & transport strategy](tickets/0012-nat-traversal-and-transport.md) — **big feature.** Hole-punching decides whether the network works for real users at all
- [0013 — Bootstrap profiles & rendezvous strategies](tickets/0013-bootstrap-profiles-and-rendezvous.md) — *no one-size-fits-all; the bootstrap channel must be reachable, not trusted*
- **[0014 — v0.1: the smallest real network](tickets/0014-v0.1-two-laptops.md) — the only thing being built**
- [0015 — UDP datagram transport](tickets/0015-udp-datagram-transport.md) — *the v0.2 path: don't rebuild TCP; gossip already IS the reliability layer*

## Build order (and why it is not the obvious one)

Ticket numbers are not priorities. **The order is:**

**0002 (decide on paper) → 0006 (bootstrap) + 0012 (NAT) → 0003 (membership) →
0005 (demo) → 0004 (DHT).**

Trust (0008 → 0009) rides alongside: stages 0–1 of 0008 (trust-on-first-use with
loud key-change alerts, plus in-person QR) are near-free and ship with the demo.
The optional tenants (0007 1:1, 0010 files, 0011 sensors) come after, and each is
really a **test of the substrate** — if one of them forces a core change, the core
was wrong.

**Why the DHT is last.** It is an optimisation on discovery, and it only starts to
matter once there are more nodes than invites and seeds can handle. It is also the
most fun and the most code — which is exactly the trap: a beautiful global index
with nobody in it.

**Why bootstrap and NAT are first.** *Bringing the network UP* is how P2P projects
actually die — a first node with nobody to talk to, and peers behind NAT who can
never connect. "Network ≫ peer" is true of a mature network; ours has zero nodes.
NAT traversal is the difference between a protocol and a product.

Two rules from 0002 that everything else inherits:

- **Nodes route metadata for everyone; nodes store content only for realms they
  belong to.** The global layer is a phonebook, never a filestore. This is what
  reconciles "all nodes collaborate on discovery" with 0001's refusal to become a
  relay for strangers' content.
- **The node key is not the membership key.** Otherwise discovery becomes a
  global correlation index of who is in which group.
