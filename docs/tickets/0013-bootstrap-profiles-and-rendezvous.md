# 0013 — Bootstrap profiles & the rendezvous-strategy interface

- **Status:** open — settles *how* a node finds its first peer, and kills the
  one-size-fits-all assumption.
- **Depends:** [0006](0006-bootstrap-and-reachability.md) (the bootstrap ladder).
- **Settles:** [0004](0004-discovery-dht.md)'s "is our own DHT worth building?" —
  **almost certainly not** (see §5).

---

## 1. No one size fits all

Different applications want genuinely different discovery, and forcing one model on
all of them is how the design gets bloated *and* bad:

- a **private group** wants to touch nothing global, ever;
- a **festival chat** has no internet at all;
- an **IoT mesh** lives on one LAN behind a gateway;
- a **public community** wants world-wide coverage and strangers finding it.

These are not four protocols. They are **four configurations of one strategy
chain** — the same "policy over one mechanism" pattern the admission tiers already
use ([0003](0003-membership-log-and-tiers.md)).

## 2. The strategy interface

Every discovery mechanism implements exactly one function:

```
find_addresses(topicID) -> [address]
```

**Implementations** (all interchangeable, all optional):

LAN beacon · cached peers · invite hints · realm anchors · DNS TXT · HTTPS
well-known URL · pastebin / tweet / git repo / QR on a poster · BitTorrent mainline
DHT · our own DHT

**A deployment configures an ordered chain.** Adding a new rendezvous channel never
touches the core — it is a new implementation behind one function.

## 3. The principle that makes all of this safe

> ### The bootstrap channel must be REACHABLE, not TRUSTED.
>
> Any address a channel yields is a **hint**. A fake, poisoned or malicious hint
> simply **fails the realm handshake** and is discarded. Bootstrap poisoning costs a
> wasted connection attempt — **never a compromise**.

Two consequences, and both are large:

**(a) We can bootstrap off literally any garbage channel.** Anything that can carry
~100 bytes of text: a pastebin, a tweet, a DNS record, a git repo, a QR code on a
poster, a printed card, an SMS, a torrent infohash. The crypto decides who is real;
the channel only has to be *findable*.

**(b) We cannot be shut down by killing a channel.** Block one, add another. There
is no chokepoint to seize, because no channel is load-bearing and none is trusted.

**The only cost of a bad channel is a metadata leak, never a security failure.** That
is why channel choice is *privacy* policy, not *security* policy — and therefore
per-realm.

## 4. A bootstrap peer is NOT a tracker

The distinction matters, because it lets us accept the first while refusing the
second:

| | tracker (BitTorrent's original) | anchor (ours) |
|---|---|---|
| who runs it | a **third party**, outside the swarm | a **member** of the realm |
| who chose it | the torrent author, for everyone | the realm's own members |
| mandatory? | historically yes — no tracker, no swarm | no — one rung of several |
| what it sees | **every peer of every torrent** | one realm's peers, and it is *in* that realm |
| if it dies | the swarm dies | fall back a rung |

What is objectionable is not *"a peer that helps you bootstrap"*. It is **a
mandatory, all-seeing, third-party authority that is a single point of failure and a
surveillance point.** An anchor is none of those.

Bitcoin's DNS seeds, IPFS's bootstrap list and Tox's node list are all **anchors**,
not trackers. **You can have bootstrap peers and still refuse tracker
architecture.**

## 5. Channels, ranked by what they actually cost

| channel | cost to implement | scale | privacy | verdict |
|---|---|---|---|---|
| **LAN beacon** | **done** | one room | perfect | ship |
| **Cached peers** | trivial | n/a | perfect | ship |
| **Invite hints** | trivial | n/a | perfect | ship ([0006](0006-bootstrap-and-reachability.md)) |
| **Realm anchors** | trivial | the realm | perfect | ship |
| **HTTPS well-known URL** | **~zero — frank2 already ships HTTP + TLS 1.3** | anyone who can host a file | good (host sees fetchers) | **do this first** |
| **DNS TXT** | **~zero — frank2 already ships a DNS client** | global | good | **do this too** (Bitcoin's seeds are exactly this) |
| **Pastebin / tweet / git / QR** | trivial (it is text) | ad-hoc | good | free consequence of §3 |
| **BitTorrent mainline DHT** | **small** — bencode over UDP, four RPCs (`ping`, `find_node`, `get_peers`, `announce_peer`); a client is a few hundred lines | **~10–30M nodes** — someone else already solved the chicken-and-egg and left it running for 20 years | **public and enumerable** — announcing says "some IP wants hash X" | **the one serious piggyback**, for the public profile only |
| **Our own DHT** ([0004](0004-discovery-dht.md)) | large — the widest attack surface in the system | starts at zero (chicken-and-egg) | ours to control | **almost certainly never** |
| **IPFS / libp2p** | **large** — multiaddr, PeerID, multistream-select, Noise/TLS, yamux/mplex, protobuf, Kademlia-over-libp2p, CIDs; no mature C impl, so FFI to Rust/Go | huge | public | **trap — see below** |
| **GNUnet** | large | **tiny network (hundreds of nodes)** | strong | no scale to lift on |

### Why IPFS / libp2p is a trap (recorded so it is not re-proposed)

The irony is fatal: **you would implement a DHT (theirs, the complicated one) in
order to avoid implementing a DHT (ours, the simple one).** Our own Kademlia is
*less* work than a libp2p client.

And linking the real thing (FFI to rust-libp2p / go-libp2p as a cdylib) drags a
Rust/Go toolchain plus a multi-megabyte dependency into the build — which **kills
the ESP32 story instantly.** A 300 KB chip cannot host libp2p. That story is the
project's single most distinctive claim.

A legitimate cheat for a desktop-only public build. Never a legitimate core.

### Why Tox is worth knowing (it is our cautionary tale)

A 2013 P2P encrypted messenger, no servers, its own DHT, **identity = public key**.
It independently proves two of our decisions the hard way:

- **Your ID is your locator** — to be reachable you must be findable by your public
  key, so **anyone holding your Tox ID can see whether you are online, and your
  IP.** Unfixable without redefining what an identity is. This is exactly the
  presence leak that made us choose a **private rendezvous** for 1:1
  ([0007](0007-pairwise-contacts.md)).
- **No offline delivery** — both parties must be online at once. Precisely the hole
  we found in two-member realms
  ([identity §7a](../design/identity-membership-discovery.md)).

## 6. The profiles

| profile | chain | needs |
|---|---|---|
| **private group** *(the default)* | LAN → cache → invite → anchors | **nothing global** |
| **off-grid / festival** | LAN only | nothing |
| **IoT / sensor mesh** | factory pairing → gateway anchor → LAN | nothing |
| **public community** | anchors → HTTPS/DNS → mainline DHT | a public channel |
| **"WWW coverage"** | + open admission | **DHT + open tier + trust graph ([0009](0009-sybil-resistance-trust-flow.md))** |

### The payoff

**The expensive machinery — a global DHT, the `open` tier, Sybil trust-flow — is
needed by exactly ONE profile.**

Every other use case ships without any of it. So the "world-wide-web coverage"
profile is a *later, optional product*, not a tax the design has to pay up front.

## 7. Acceptance

- Bootstrap channels are pluggable behind `find_addresses(topicID)`; adding one
  touches no core code.
- A realm declares its chain; a `lan-only` realm provably emits nothing to any
  global channel.
- **Poisoning is harmless:** feed the node a bootstrap list of entirely hostile
  addresses; it wastes connection attempts and joins correctly anyway (the handshake
  rejects them). *This is the test that proves §3.*
- HTTPS well-known + DNS TXT work against a real deployment, reusing frank2's
  existing HTTP/TLS/DNS.
- (Optional) A mainline-DHT client finds peers for a rotating topicID.
