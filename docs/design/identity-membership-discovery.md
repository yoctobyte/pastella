# Identity, membership & discovery

*Design document. Status: proposed, 2026-07-12. Supersedes the discovery model
sketched in [ticket 0001](../tickets/0001-realms-and-secure-transport.md).*

This document settles four questions that the ticket set kept tripping over, and
that are cheap to decide now and brutally expensive to retrofit:

1. Who is a node, and who is a member? (They are **not** the same key.)
2. What may the global layer see? (**Addresses, never content.**)
3. How does a group admit people? (**One mechanism, three policies.**)
4. How do two people talk directly, without publishing who they are?

---

## 0. The contradiction this resolves

Ticket 0001 states: *"Pastella has no global mode. The unit of a network is a
realm"* — and gates even **discovery** behind the realm key, so that "outsiders
cannot enumerate or join."

That was the right instinct (see §6) but it is too strong. It means every realm
must solve discovery alone, and it forbids the thing we actually want: a
**subject-independent discovery layer where all nodes collaborate**, so that
finding peers is a service the whole network provides, regardless of who belongs
to what.

Those two positions are irreconcilable as stated. **One rule reconciles them:**

> **Nodes route metadata for everyone.
> Nodes store content only for realms they belong to.**

The global layer is a **phonebook, never a filestore**. It holds *provider
records* — "peer P is reachable at address A for topic T" — with a short TTL. It
never stores, relays, or caches content.

This preserves exactly what 0001 was protecting. The liability that destroyed the
Gnutella model — becoming an unwitting relay and store for strangers' illegal
content, an abuse magnet, a DDoS amplifier, a legal exposure — attaches to
**content**, not to **addresses**. Handing out a phone number is not the same as
warehousing the goods.

---

## 1. The layers

Four layers. Each is ignorant of the one above it, and each is testable alone.

| | layer | knows about | does not know about |
|---|---|---|---|
| **L0** | node identity + transport | node keys, addresses, NAT | topics, members |
| **L1** | discovery | topicIDs, provider records | membership, content, *what a topic is* |
| **L2** | realm / topic | members, policy, keys, content | how peers were found |
| **L3** | app (chat, sync, telemetry) | conversations | everything below |

The critical property: **L1 cannot check membership, by construction** — it does
not hold the keys and never sees them. This is what makes it safe for everyone to
participate in, and what makes it swappable (LAN beacons / invite hints / DHT are
three implementations of one interface).

The test of whether this layering is honest, not aspirational: **the group-chat
demo must work with L1 switched off entirely** (LAN + invite only). See
[ticket 0005](../tickets/0005-offgrid-group-chat.md).

---

## 2. Two keys, deliberately

**The node key (L0/L1) MUST NOT be the membership key (L2).**

- **Node key** — long-lived, public, how you are dialed. Lives at the transport
  layer.
- **Member identity** — per-realm. Signs content, proves membership.

If these are the same key, the discovery layer becomes a **global correlation
index**: anyone watching which node announces which topics can reconstruct the
social graph — who is in the protest realm, who is in the family realm, who left
which group and when. The network would leak the very thing its users came to it
to protect.

A node announces a topic under a **rotating pseudonym**, never under its node
identity.

This is the single most important privacy decision in the design. It is nearly
free today and would require changing every stored record, log entry and wire
format later.

---

## 3. topicID is not the topic name

```
topicID = H(realm_public_value ‖ epoch)
```

Rotating on an epoch clock. Consequences, all of them load-bearing:

- **Knowing the ID does not grant membership.** The handshake still gates that.
  The ID is a meeting point, not a credential.
- **Topics cannot be enumerated** by dictionary-attacking names ("protest-berlin").
- **Provider lists do not accumulate** — they expire with the epoch.
- **Censorship must chase a moving target.**

This is how 0001's "outsiders cannot enumerate" survives *even with* a global
discovery layer. To L1, every topicID is an opaque rotating number, and one
topic is indistinguishable from another.

---

## 4. Membership: a replicated signed log

Not a server. Not a consensus protocol.

An **append-only, admin-signed log** of `add-member` / `remove-member` /
`grant-admin` / `revoke` entries, replicated inside the realm as **ordinary
gossip objects**. The content-addressed anti-entropy core already syncs exactly
this shape, so membership costs us almost no new machinery — it is just another
kind of object.

Any member can reconstruct current membership from the log alone, after an
arbitrary offline period, with nobody online to ask.

### The three tiers are POLICY over one mechanism

One membership log, one handshake, a policy field. **Do not fork the protocol
three ways** — 0001 already fixed this principle ("tiers = per-realm policy, not
code forks"); this applies it to admission.

| tier | admission | status |
|---|---|---|
| **invitation** | admin-signed member cert (a capability) | **the default; already built** (0001 Phase 2 realm CA) |
| **admin-approved** | join request gossiped → an admin signs a cert | the second mode |
| **open** | no check; content must be self-signed; abuse handled by the trust graph | **not recommended — do not ship or demo before the trust graph exists** |

`open` is a spam magnet by construction. It is listed for completeness, and it
stays off.

### Removal is the hard part

Adding people is easy. **Removal is what eats group-messaging designs.** A
removed member still holds the old group key and can decrypt anything gossiped
under it.

**Key epochs.** On removal, an admin mints a new epoch key and encrypts it to
each remaining member individually. O(n) per removal — entirely fine for 10–200
people, and it lets us skip the whole MLS/TreeKEM tree, which is the right trade
at this scale. Every message carries its epoch.

**Honest limitation:** forward secrecy is **per-epoch, not per-message**. If
per-message is ever required, that is when MLS earns its complexity — not before.

### Ordering: a DAG, not a chain

Concurrent posts across a partition mean there is no total order and nobody to
impose one. Each message names its causal predecessors by hash; display in causal
order with a deterministic tiebreak (`(timestamp, hash)`). Anti-entropy syncs the
DAG for free.

**Do not reach for consensus.** Chat does not need it; reaching for it costs
months.

---

## 5. 1:1 — pairwise contacts

*"I have your key, and you may recognize it — I am calling you."*

This is **not a fourth tier.** The tiers answer *"who may join this group?"*;
1:1 asks *"how do I reach one specific person?"* Different question, different
shape — but it reuses everything.

### A contact is a two-member realm

Both parties are admins; membership is the pair. This inherits the membership
log, key epochs, gossip sync and anti-entropy at zero cost, and gives a natural
upgrade path: **add a third member and the DM becomes a group**, with no new
protocol.

### The trap: never publish `pubkey → address`

The obvious implementation of "call this key" is a global lookup keyed by node
identity. **We will not do this.** Besides being the correlation index §2
forbids, it leaks **presence**: anyone holding your public key — an ex, an
employer, a state — can probe whether you are online, and from where, at will.

This is the known, structural flaw in **Tox**: your ID is your locator, so being
reachable means being trackable. It cannot be fixed afterwards without changing
what an identity *is*.

### Instead: a private rendezvous

Two people who have exchanged contact details share a secret:

```
rendezvous = H(pairwise_shared_secret ‖ epoch)
```

Only the two of them can compute it. To L1 it is an opaque, rotating, meaningless
ID — **indistinguishable from any other topicID**. Nobody can enumerate your
contacts; nobody can probe your presence; neither identity is ever published.

Note what this buys us: **1:1 requires no new discovery concept at all.** It is
§3's mechanism with a different input.

### Adding a contact

An exchange of a pairwise realm credential plus peer hints — the same invite
object as [ticket 0006](../tickets/0006-bootstrap-and-reachability.md), scoped to
two people. In practice: scan a QR code in person, or paste an invite string.

### Cold-calling a stranger

Contacting someone who has *not* exchanged an invite with you is the one case
that genuinely requires the dangerous global `pubkey → address` lookup — and it
buys spam, presence leaks and harassment.

**We do not ship it.** If it is ever wanted, it is the `open` tier of 1:1: an
explicit opt-in flag (*"discoverable by my public key"*, default **off**), a
proof-of-work stamp on the request, and explicit user approval before any
conversation exists. Same status as `open`, same warning.

### Key verification

Fingerprints / safety numbers, verified out of band (QR, in person).
Trust-on-first-use is acceptable **only with an alert on key change** — without
that, the whole scheme is defeated by swapping the key at introduction time.

**Honest limitation:** a 1:1 messenger invites comparison with Signal, which
gives per-message forward secrecy via the double ratchet. Key epochs give
per-*epoch* forward secrecy. That is a reasonable v1 trade and a large complexity
saving, but it must be stated plainly rather than letting users assume Signal
semantics. 1:1 is also the one place where the ratchet may later be worth its
cost — groups are where it is not.

---

## 6. Discovery: three independent knobs

Frequently conflated. They are not the same thing.

### 6.1 DHT participation — opt-in

Serving the global phonebook costs bandwidth, exposes your address to strangers,
and makes you a small piece of infrastructure for people you do not know. That is
a consent decision and it belongs to the user.

- a high-bandwidth always-on server **opts in**
- an ESP32, or a phone on a metered link, **opts out** — it still *uses*
  discovery, it just does not *serve* it

**Cost, written down rather than wished away:** an opt-in DHT is a *smaller* DHT,
and Sybil/eclipse attacks get **easier** as the honest node count drops. If only a
few percent participate, an attacker needs far fewer fake nodes to surround a
target and lie about who serves a topic. Opt-in trades user safety against network
security — a real tension, not a free win. Mitigate with pubkey-bound node IDs and
disjoint lookup paths (S/Kademlia).

### 6.2 DoS resistance — NOT a knob

Unconditional, in the wire format.

Rate-limiting ("drop everything above the limit") protects us as the **victim**.
It does nothing about being used as the **weapon**, which is the dangerous case:
an amplification attack sends a *small* number of *spoofed* queries — well under
any rate limit — and we dutifully mail a large reply to the forged victim address.
We never notice. The victim is hit by a thousand of our peers at once, and
Pastella's traffic signature gets blocked network-wide.

Three rules, all cheap, all mandatory:

1. **Never reply with more bytes than were received** from an unverified address.
2. **Prove return-routability first** — a cookie round-trip before doing real work
   for a stranger.
3. **Rate-limit per source** (the self-defence, kept).

Rules 1 and 2 are a few lines each, and they are the difference between a P2P
network and a DDoS weapon.

### 6.3 Discovery mode — per realm

`dht` · `lan-only` · `invite-hints-only`.

A privacy-sensitive realm (the protest group) can refuse to touch any global
index at all, and is then invisible to it.

---

## 7. Bringing the network UP

*"Network ≫ peer"* is true of a **mature** network. Ours has **zero nodes**.

This is where P2P projects actually die — not at the DoS stage, not at the crypto
stage. The protocol is beautiful and there is nobody to talk to. So the
engineering priority is **not** the DHT; it is bootstrap and reachability
([ticket 0006](../tickets/0006-bootstrap-and-reachability.md)):

- **The invite IS the bootstrap** — it carries the realm credential *plus*
  last-known peer addresses. A new node then needs *no global infrastructure at
  all*: the thing someone hands you is enough to join. This is what makes the
  off-grid demo work with nothing but an invite.
- **Persistent peer cache** — a node that has ever been online should almost never
  bootstrap again.
- **A couple of dumb seed nodes, run by us.** Not a betrayal of P2P: Bitcoin has
  DNS seeds, BitTorrent has bootstrap nodes, Tailscale has DERP relays. Pretending
  otherwise is how a project fails its first user. Keep them dumb — addresses
  only, no content, no keys, no membership — so losing them degrades the network
  rather than killing it, and nobody has to trust them.
- **A relay fallback for symmetric NAT**, where hole-punching *cannot* work, ever.
  Without it some users can never connect; they will not file a bug, they will
  conclude the app is broken and leave.

**Therefore the DHT is built LAST.** It is an optimisation on discovery that only
starts to matter once there are more nodes than invites and seeds can handle. It
is also the most fun and the most code — which is exactly why it is the trap.

**Build order: 0002 (decide) → 0006 (bootstrap) → 0003 (membership) → 0005 (demo)
→ 0004 (DHT).**

---

## 7a. Offline delivery — the problem Signal's servers actually solve

The usual framing is that Signal depends on central infrastructure for
*bootstrap*. That is true, and it is a real difference:

> **Signal without its servers is a dead app. Pastella without its seed nodes is
> a slower Pastella.**

Signal *cannot function* without its servers — registration needs a phone number
and a server round-trip, every message routes through central infrastructure, and
there is a finite set of endpoints for a state to block. Our seed nodes (§7) are
**convenience, not dependency**: remove every one of them and the network
degrades rather than dies. Two people in a room with an invite and no internet
still talk.

Claim it in exactly that shape. Do **not** claim "no servers" while running seed
nodes — the honest claim is stronger anyway, and [ticket
0005](../tickets/0005-offgrid-group-chat.md) *proves* it (the demo runs with
discovery off and nothing but an invite) instead of asserting it.

**But their servers buy something else, and it is not bootstrap: offline
delivery.** If you message me while my phone is off, Signal's server holds the
ciphertext until I return. In a pure P2P system, if two peers are never online at
the same time, **the message never arrives.** This — not discovery — is what has
killed every serious P2P messenger. Mobile push is the same problem wearing a
different hat: a backgrounded phone is an offline peer.

**Groups already solve this, for free.** The phonebook rule (§0) says members
store content for their own realm — so the other members *are* the mailbox. Post
to a realm of eight and seven nodes hold it until the last member syncs.
Store-and-forward with no infrastructure.

**1:1 does not.** A two-member realm has exactly two nodes; if they are never
online together, nothing moves. Options, in order of preference:

1. **Volunteer mailbox nodes** — dumb, blind stores (like the seed nodes): hold
   an encrypted blob addressed to a rendezvous, with a TTL. Cannot read it, do
   not know who it is from. This is Briar's "mailbox" concept and it is the
   pragmatic answer. **Design for this.**
2. **Mutual contacts as mailboxes** — leave the blob with peers both parties
   trust. Zero infrastructure, but it leaks: someone learns that two of their
   contacts are corresponding.
3. **Synchronous-only 1:1** — messages flow only when both are online. Honest,
   fine for the demo, not fine for a real messenger. **Ship this first.**

This is the single biggest gap between "works at a festival" and "replaces your
messenger", and it should not be discovered late.

---

## 8. Threat model — what we do and do not defend

**Defended:**

- outsiders enumerating topics, members, or the social graph (§2, §3)
- outsiders reading content (realm-keyed AEAD, 0001)
- a removed member reading future traffic (§4, key epochs)
- being used as a DDoS amplifier (§6.2)
- being an unwitting store/relay for strangers' content (§0, phonebook rule)

**Not defended (state plainly, do not pretend):**

- **traffic analysis / global passive adversary** — we are not Tor. A network
  observer sees that you talk, and roughly when.
- **per-message forward secrecy** — we have per-epoch (§4).
- **a malicious admin** — an admin can admit and remove at will. The trust graph
  is a mitigation, not a fix.
- **endpoint compromise** — keys on a compromised device are gone.
- **Sybil in the open tier** — which is why `open` is not recommended and the
  trust graph gates it.

---

## 9. Open questions

- Epoch clock: wall time (needs loose sync) or event-driven (needs a trigger)?
  Wall time is simpler and probably sufficient; log the choice when made.
- Trust graph: intra-realm reputation is sketched in 0001 but not designed. It is
  the gate on the `open` tier, and therefore not on the critical path.
- Do seed nodes also serve as relays (§7), or are those separate roles? Separate
  is cleaner; combined is cheaper to run.
