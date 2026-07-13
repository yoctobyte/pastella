# Design documents

> ## ⚠️ STATUS: these are THOUGHTS, not commitments
>
> Written 2026-07-12/13, in one long design conversation, **before a single line of
> new protocol code existed.** Treat almost all of it as **explored options**, not
> settled architecture.
>
> **The only thing being built right now is [0014 — v0.1: the smallest real
> network](../tickets/0014-v0.1-two-laptops.md)**: two or three laptops in different
> places, gossiping readings, manual peer-add plus LAN discovery, running for a week.
> Nothing else.
>
> **What is actually DECIDED** — a short list, and only because breaking these later
> would be expensive or dishonest:
>
> 1. **The core is pure.** Clock, entropy, sockets are *inputs*, never calls.
> 2. **Every object is signed and belongs to exactly one realm.**
> 3. **Nodes store content only for realms they belong to.** (Never a filestore for
>    strangers.)
> 4. **The node key is not the membership key.**
> 5. **No global reputation score.**
> 6. **No unvalidated amplification.**
> 7. **Document architecture, never legal posture.**
>
> **Everything else below is a menu, not a meal** — the DHT, trust flow, mailboxes,
> NAT traversal, bootstrap channels, admission tiers, profiles. Each is a
> *hypothesis*. v0.1 is the experiment that tells us which ones are real, and it will
> be fewer than we think.
>
> Do not treat a document here as a decision just because it is well argued.

Decisions that outlive any single ticket. **Read these before touching the
protocol** — several of them exist because an earlier draft got it wrong, and the
reasoning is more valuable than the conclusion.

| doc | the question it answers |
|---|---|
| [Realm profiles](realm-profiles.md) | **Mechanism is universal; policy is per realm; invariants are not negotiable.** The pattern the design kept rediscovering — admission, discovery, transport, object authentication, retention and DHT participation are all per-realm CHOICES with real drawbacks, not one-size-fits-all answers. |
| [Architecture](architecture.md) | Where is the line between the pure core and the I/O edge, and what may each layer know? |
| [Objects & wire](objects-and-wire.md) | What *is* an object? One signed envelope, many payload types — the spine every other doc assumes. |
| [Identity, membership & discovery](identity-membership-discovery.md) | Identity is free, so it must confer zero trust. The node key is not the membership key. The global layer is a phonebook, never a filestore. |
| [Threat model](threat-model.md) | What we defend, what we do **not** defend, and why we document architecture rather than legal posture. |

## The load-bearing decisions, in one place

If you read nothing else:

- **Protocol = pure functions; I/O = edges.** The core has no sockets, no threads,
  no locks, no clock, no randomness — all of it arrives as *input*. This is what
  killed the 2005 version and what makes this one testable.
  → [architecture](architecture.md)
- **Nodes route metadata for everyone; nodes store content only for realms they
  belong to.** The global layer is a phonebook, never a filestore. This is what
  lets every node help with discovery without inheriting Gnutella's liability.
  → [identity §0](identity-membership-discovery.md)
- **The node key is NOT the membership key**, and `topicID = H(realm ‖ epoch)`.
  Otherwise discovery becomes a global index of who is in which group.
  → [identity §2, §3](identity-membership-discovery.md)
- **Identity is free, so it confers zero trust.** Trust comes only from
  attestation — a human act, out of band. **Never a global reputation score.**
  → [identity §0a](identity-membership-discovery.md),
  [0009](../tickets/0009-sybil-resistance-trust-flow.md)
- **Count attack edges, not identities.** A million bots behind 3 attack edges are
  worth no more than 3 fooled friends. Capacity-constrained flow, never path
  counting. → [0009](../tickets/0009-sybil-resistance-trust-flow.md)
- **Chat must work with discovery switched off.** If it does not, the layering is
  a lie. → [0005](../tickets/0005-offgrid-group-chat.md)
- **Bringing the network UP is the real problem**, not taking it down. Zero nodes
  is how P2P projects die. → [0006](../tickets/0006-bootstrap-and-reachability.md)
- **The bootstrap channel must be REACHABLE, not TRUSTED.** A poisoned hint just
  fails the realm handshake, so bootstrap costs a wasted connection, never a
  compromise. Therefore *anything carrying ~100 bytes of text can bootstrap the
  network* — a pastebin, a tweet, a DNS record, a QR on a poster, a torrent
  infohash — and no channel can be seized, because none is load-bearing.
  → [0013](../tickets/0013-bootstrap-profiles-and-rendezvous.md)
- **Every realm is its own infrastructure.** A realm's peer list is realm CONTENT,
  gossiped like everything else. The only global thing is bootstrap — and even that
  is a last resort. → [0006](../tickets/0006-bootstrap-and-reachability.md)
- **Document architecture, never legal posture.**
  → [threat model §5](threat-model.md)
