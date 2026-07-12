# 0004 — Discovery: subject-independent, three knobs (L1)

- **Status:** open — **build this LAST of the four.** See "Ordering" below.
- **Depends:** [0002](0002-layering-node-topic-membership.md) (layering, the
  phonebook rule, topicID derivation).

## What it is

One question, answered for everybody: *who claims to serve topic T?* The layer
cannot check membership — by construction it does not hold the keys. It stores
**provider records** (peer + address + TTL), never content
([0002](0002-layering-node-topic-membership.md)'s phonebook rule).

Three **independent** knobs. They are often conflated; they are not the same
thing:

### 1. DHT participation — opt-in

Serving the global phonebook costs bandwidth, exposes your IP to strangers, and
makes you a small piece of infrastructure for people you do not know. That is a
consent decision and it belongs to the user.

- A high-bandwidth always-on server **opts in**.
- An ESP32, or a phone on a metered link, **opts out** — it still *uses*
  discovery, it just does not *serve* it.

**Known cost, written down rather than wished away:** an opt-in DHT is a
*smaller* DHT, and Sybil/eclipse attacks get *easier* as the honest node count
drops. If only a few percent participate, an attacker needs far fewer fake nodes
to surround a target and lie about who serves a topic. Opt-in trades user safety
against network security — a real tension, not a free win. Mitigate with
pubkey-bound node IDs and disjoint lookup paths (S/Kademlia).

### 2. DoS resistance — NOT a knob. Unconditional, in the wire format.

Rate-limiting ("drop everything above the limit") protects us as the **victim**.
It does **not** stop us being used as the **weapon**, and that is the dangerous
case: an amplification attack sends a *small* number of *spoofed* queries — well
under any rate limit — and we dutifully mail a big reply to the forged victim
address. We never notice. The victim gets hit by a thousand of our peers at once,
and Pastella's traffic signature gets blocked network-wide.

Three rules, all cheap, all mandatory:

- **Never reply with more bytes than were received** from an unverified address.
- **Prove return-routability first** — a cookie round-trip before doing any real
  work for a stranger.
- **Rate-limit per source** (the self-defence we already wanted).

The first two are a few lines each and are the difference between a P2P network
and a DDoS weapon.

### 3. Discovery mode — per realm

`dht` / `lan-only` / `invite-hints-only`. A privacy-sensitive realm (the protest
group) can refuse to touch any global index at all. A realm that never enables
`dht` is invisible to it.

## Ordering: why this is LAST

The DHT is an **optimisation on discovery**. It only starts to matter once there
are enough nodes that invites and seeds are not enough — and it is the most fun,
the most code, and the least demo value. Building it first is the classic P2P
trap: a beautiful global index with nobody in it.

Bootstrap ([0006](0006-bootstrap-and-reachability.md)) and membership
([0003](0003-membership-log-and-tiers.md)) come first; the off-grid demo
([0005](0005-offgrid-group-chat.md)) runs with this layer switched **off
entirely**, which is exactly what proves the layering is honest.

## Acceptance

- Chat works with the DHT disabled (proves L1 is genuinely swappable).
- A node that opted out still resolves topics; it just serves nobody.
- Amplification: no unverified request can provoke a larger reply; a spoofed
  source cannot make us send anything substantial. Test with forged source
  addresses, not just load.
- A `lan-only` realm emits nothing to the global index.
- topicIDs rotate by epoch; an outsider holding an old topicID cannot enumerate
  current members.
