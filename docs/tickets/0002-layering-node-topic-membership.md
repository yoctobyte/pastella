# 0002 — The layering: node vs topic vs membership

- **Status:** open — the design decision the other tickets depend on.
- **Depends:** nothing. This is the one to settle first, on paper.

## Why

Ticket [0001](0001-realms-and-secure-transport.md) says *"Pastella has no global
mode. The unit of a network is a realm"*, and gates even DISCOVERY behind the
realm key (beacons carry realmID + an HMAC so outsiders cannot enumerate).

We now want something 0001 forbids: a **subject-independent discovery layer where
all nodes collaborate**, regardless of which topics they belong to. That is a
global mode. This ticket resolves the contradiction instead of leaving it to be
discovered mid-implementation.

## The rule that reconciles them

> Nodes **route metadata** for everyone.
> Nodes **store content** only for realms they belong to.

The global layer is a **phonebook, never a filestore**. It holds *provider
records* — "peer P can be reached at this address for topic T" — with a short
TTL. It never stores, relays or caches content.

That is what keeps the 2005 Gnutella failure mode out (you become a relay for
strangers' illegal content, an abuse magnet and a legal liability — the whole
reason 0001 abandoned the global model) while still letting every node help
everyone discover each other. The liability that 0001 was avoiding attaches to
*content*, not to *addresses*.

## The layers

Each layer is ignorant of the one above it.

- **L0 — node identity + transport.** Long-lived node keypair, connections, NAT
  traversal. No notion of topics at all.
- **L1 — discovery.** Answers exactly one question: *who claims to serve topic
  T?* Cannot check membership — it does not have the keys, by construction.
  Subject-independent and swappable (LAN beacons / invite hints / DHT).
  See [0004](0004-discovery-dht.md).
- **L2 — realm / topic.** Membership, auth policy, content encryption, signing.
  This is where 0001's realm work lives; it just stops owning discovery.
  See [0003](0003-membership-log-and-tiers.md).
- **L3 — app.** Group chat, file sync, sensor telemetry. See
  [0005](0005-offgrid-group-chat.md).

## Two keys, deliberately

**The node key (L0/L1) must NOT be the membership key (L2).**

If they are the same, the discovery layer becomes a global correlation index:
anyone can watch which node announces which topics and reconstruct the social
graph — who is in the protest group, who is in the family realm. Each member gets
a per-realm identity, and a node announces a topic under a rotating pseudonym.

This is the single most important privacy decision in the design. It is nearly
free to make now and expensive to retrofit — every stored record, every log
entry and every wire format would have to change later.

## topicID is not the topic name

`topicID = H(realm_public_value ‖ epoch)`, rotating on an epoch clock.

- Knowing the ID does not grant membership — the handshake still gates that.
- Topics cannot be enumerated by dictionary-attacking names.
- Provider lists do not accumulate forever.
- Censoring a topic means chasing a moving target.

This is how 0001's "outsiders cannot enumerate" survives *even with* a global
discovery layer.

## Acceptance

- The layering, the phonebook rule, the two-key rule and the topicID derivation
  are written into `DESIGN.md`, and 0001's "no global mode" wording is amended to
  the phonebook rule rather than silently contradicted.
- Node identity and realm-member identity are distinct key types in the code.
