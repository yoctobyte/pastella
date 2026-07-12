# 0006 — Bootstrap & reachability: bringing the network UP

- **Status:** open — **the highest-value ticket of the set.**
- **Depends:** [0002](0002-layering-node-topic-membership.md) (invite carries a
  realm credential; this adds peer hints to it).

## Why this is the one that matters

"Network ≫ peer" is true of a *mature* network. Ours has **zero nodes**.

Every P2P project dies here — not at the DoS stage, not at the crypto stage. The
protocol is beautiful and there is nobody to talk to. The engineering priority is
therefore not the DHT ([0004](0004-discovery-dht.md)); it is **bringing the
network up and keeping peers reachable**.

## The four pieces

### 1. The invite IS the bootstrap

Make an invite carry the realm credential **plus a few last-known peer
addresses**. Then a new node needs *no global infrastructure at all* — the thing
someone hands you is sufficient to join.

This is what lets the off-grid demo ([0005](0005-offgrid-group-chat.md)) work
with literally nothing but an invite: no DHT, no seeds, no internet.

### 2. Persistent peer cache

Remember peers across restarts. A node that has ever been online should almost
never need to bootstrap again. Cheap, boring, and it removes most cold starts.

### 3. Seed / rendezvous nodes — run a couple ourselves

This is **not** a betrayal of P2P. It is what every real network does:

- Bitcoin — DNS seeds
- BitTorrent — bootstrap nodes
- Tailscale — DERP relays

Pretending we do not need them is how a project fails its very first user. Keep
them dumb (they hand out addresses; they hold no content, no keys, no
membership), so losing them degrades the network rather than killing it, and
nobody has to trust them.

### 4. Reachability — the silent killer

Most home peers are behind NAT. We already have hole-punching and rendezvous
connect-back (0001 / `test_nat`). The gap is a **relay fallback for symmetric
NAT**, where hole-punching *cannot* work, ever.

Without it, some fraction of users can never connect — and they will not file a
bug, they will conclude the app is broken and leave. A relay is not elegant; it
is the difference between "works for everyone" and "works for people with the
right router."

## Acceptance

- A brand-new node with **only an invite** joins a realm and converges, with no
  internet and no seed reachable (LAN).
- A node that has been offline for a week rejoins from its peer cache without
  bootstrapping.
- Two peers both behind symmetric NAT can exchange messages (via relay).
- Losing every seed node degrades discovery but does not partition existing
  realms.
