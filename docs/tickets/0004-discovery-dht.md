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

### 2. DoS resistance — NOT a knob. The invariant is fixed; the mechanism follows the transport.

> **Invariant: no unvalidated amplification.** A node must never be induceable into
> mailing bytes at a victim it never spoke to.

How it is met depends on the transport
([architecture](../design/architecture.md), [0012](0012-nat-traversal-and-transport.md)):

| transport | mechanism |
|---|---|
| **TCP** | **free** — the handshake *is* the return-routability check |
| **UDP** | **cookie** under load (WireGuard) + **3x anti-amplification limit** before address validation (QUIC) |
| **UDP beacons** | **announce-only** — you shout, nobody replies. A protocol that never answers a UDP packet cannot amplify one |

Plus, always: **rate-limit per source** — the self-defence, which is a separate
concern from being the *weapon*.

**Do not conclude "therefore TCP-only".** That was an earlier draft's mistake: TCP
hole-punching is poor, so TCP-only would push most internet traffic through relays.
UDP amplification is a solved problem (WireGuard/QUIC), and NAT traversal is a big
feature — see [0012](0012-nat-traversal-and-transport.md).

#### Kademlia over either transport

Kademlia is conventionally UDP, and that works here **provided the cookie + 3x rules
hold**. Over TCP it also works, paying a handshake per hop (~2 RTT instead of 1,
across ~log N hops, alpha=3 parallel). **Finding a peer is a background operation,
not an interactive one**, so either is affordable. Cache provider records so lookups
are rare regardless.

#### No node owes anyone service

> **Any node may refuse a connection, rate-limit, or drop traffic — at any time,
> for any reason.** Liveness comes from **redundancy** (k replicas, alpha-parallel
> queries), never from an obligation to answer.

Not a concession — this is what makes the DHT *robust*, and what makes opt-in
participation (§1) coherent. Kademlia already behaves this way: an unresponsive node
is simply skipped. **A protocol whose correctness depends on strangers answering is
a protocol that dies the first time somebody rate-limits.**

### 2a. The DHT carries NO metadata — no extension point, ever

A `PROVIDER` record is strictly typed, fixed-shape, size-capped and TTL'd:
*"peer P is reachable at A for topicID T, until X"* — **and nothing else**. No
free-form field, no "notes", no counts, no names, no reserved bytes.

One rule, two holes:

- **Covert channel / storage abuse.** Any free-form field is somewhere to stuff
  payload — the phonebook quietly becoming a **filestore**, breaking the rule the
  entire global layer rests on
  ([0002](0002-layering-node-topic-membership.md)). It never arrives as a proposal
  to store content; it arrives as a *flexible field* in a harmless-looking patch.
- **Metadata leak.** Anything past reachability tells an outsider something about a
  realm — size, activity, naming, rhythm. Discovery is the one place we *invite*
  outsiders to look, so it must be the place that says the least.

**Parsers must REJECT an over-long or unknown-shaped record — not skip the extra
bytes.** A lenient parser recreates the extension point the format refuses to have.

**If a feature needs the DHT to carry more, the feature is wrong.**

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
- **Amplification, tested adversarially:** on UDP, an unvalidated source cannot
  make a node emit more than 3x what it sent, nor do real work before address
  validation. On TCP it is free. Test with *forged source addresses*, not just load.
- **Refusal is legal:** a lookup still succeeds when an arbitrary fraction of nodes
  refuse, rate-limit or drop. Liveness comes from redundancy, never from obligation.
- A `lan-only` realm emits nothing to the global index.
- topicIDs rotate by epoch; an outsider holding an old topicID cannot enumerate
  current members.
- **No metadata, provably:** a provider record with any extra byte is REJECTED,
  not tolerated. Fuzz the parser with over-long, padded and unknown-shaped records
  and assert none is stored or relayed — i.e. the DHT cannot be used as a covert
  store, and an observer of it learns nothing about a realm beyond "some peer is
  reachable for some opaque topicID".
