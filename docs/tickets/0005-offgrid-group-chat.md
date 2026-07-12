# 0005 — Off-grid group chat (the demo)

- **Status:** open
- **Depends:** [0003](0003-membership-log-and-tiers.md) (membership + epochs);
  [0006](0006-bootstrap-and-reachability.md) (invite-as-bootstrap). Explicitly
  does **NOT** depend on [0004](0004-discovery-dht.md).

## The demo

A group chat that works with **no internet at all** — festival, conference wifi,
disaster, protest. Realm = the group. Messages are small gossip objects. Signing
already exists (0001 Phase 2).

**Run it with the DHT switched off entirely.** That is the point, not a
limitation:

- LAN broadcast discovery — already built (zero-seed beacons, `test_discovery`).
- Realm = the group — already built (PSK realms + CA realms).
- Messages = gossip objects — the anti-entropy core already syncs them.
- Signing = ECDSA-P256 — done, and now ~25x faster (see 0001's follow-up), so a
  realm join is not dominated by signature work.

If chat works with L1 absent, then discovery really *is* subject-independent and
swappable — the demo doubles as the proof that
[0002](0002-layering-node-topic-membership.md)'s layering is honest, not
aspirational.

Second act, later: switch the DHT on and the same chat works across the internet,
unchanged.

## Why this demo and not another

Cheapest to build of the candidates (messages are just gossip objects), strongest
story on video, and it exercises every layer end to end. Weaker as a *lasting*
artifact than the ESP32 mesh — that one is the flagship, because no Go/Rust P2P
stack can run the same protocol on a $3 chip — but ESP32 is blocked on frank2's
`bug-riscv32-p256field-coredump` (realm crypto does not run on device yet), and
this one is not blocked on anything.

## Watch out for

- **Ordering.** Concurrent posts across a partition — the DAG + deterministic
  tiebreak from [0003](0003-membership-log-and-tiers.md). Not consensus.
- **Removal.** Kicking someone must actually stop them reading — key epochs
  ([0003](0003-membership-log-and-tiers.md)).
- **The open tier is a spam magnet.** Demo the invitation tier. Do not demo
  `open` until the trust graph exists.

## Acceptance

- Two laptops on a wifi network with no internet, no router config, no server:
  scan an invite, chat converges.
- A third joins late and back-fills history.
- A member removed by an admin can no longer read new messages.
- Kill the wifi mid-conversation, reconnect: both sides converge with no lost or
  duplicated messages.
