# Design documents

Decisions that outlive any single ticket. **Read these before touching the
protocol** — several of them exist because an earlier draft got it wrong, and the
reasoning is more valuable than the conclusion.

| doc | the question it answers |
|---|---|
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
- **Document architecture, never legal posture.**
  → [threat model §5](threat-model.md)
