# Pastella docs & tickets

Minimal, file-based. No tracker, no tooling — just markdown under version control.

## Design documents

Decisions that outlive any one ticket. Read before touching the protocol.

- [Identity, membership & discovery](design/identity-membership-discovery.md) —
  the node key is not the membership key; the global layer is a phonebook, never
  a filestore; three admission tiers as policy over one mechanism; 1:1 as a
  two-member realm reached by private rendezvous; what we deliberately do **not**
  defend against.

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

## Build order (and why it is not the obvious one)

Ticket numbers are not priorities. The order is:

**0002 (decide on paper) → 0006 (bootstrap) → 0003 (membership) → 0005 (demo) →
0004 (DHT).**

The DHT comes **last**, deliberately. It is the most fun, the most code, and the
least demo value — an optimisation on discovery that only starts to matter once
there are more nodes than invites and seeds can handle. Building it first is the
classic P2P trap: a beautiful global index with nobody in it.

The thing that actually kills P2P projects is the opposite problem — **bringing
the network UP** (0006): a first node with nobody to talk to, and peers behind
NAT who can never connect. That is where the effort goes.

Two rules from 0002 that everything else inherits:

- **Nodes route metadata for everyone; nodes store content only for realms they
  belong to.** The global layer is a phonebook, never a filestore. This is what
  reconciles "all nodes collaborate on discovery" with 0001's refusal to become a
  relay for strangers' content.
- **The node key is not the membership key.** Otherwise discovery becomes a
  global correlation index of who is in which group.
