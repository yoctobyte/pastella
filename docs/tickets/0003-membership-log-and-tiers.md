# 0003 — Membership log, auth tiers, key epochs (L2)

- **Status:** open
- **Depends:** [0002](0002-layering-node-topic-membership.md) (the layering);
  0001 Phase 2 realm CA (**done** — `src/realm_ca.inc`).

## Why

A topic needs to know who is in it, who may admit others, and who has been
removed — with no server, under partition, on a laptop that was offline for a
week. And it needs three different admission policies (open / invitation /
admin-approved) without forking into three protocols.

## Membership is a replicated signed log

Not a server, not a consensus protocol: an **append-only, admin-signed log** of
`add-member` / `remove-member` / `grant-admin` / `revoke` entries, replicated
inside the realm as **ordinary gossip objects**. The content-addressed
anti-entropy core already syncs exactly this shape — membership is just another
kind of object, so this costs us almost no new machinery.

## The three tiers are POLICY over one mechanism

One membership log, one handshake, a policy field. Do **not** fork the code three
ways — 0001 already states the principle ("tiers = per-realm policy, not code
forks"); this is that principle applied to admission.

- **open** — no membership check at join. Content must be self-signed by an
  identity key; abuse is handled by the trust graph. **Spam is the default
  outcome at this tier** — the trust graph has to exist *before* this tier is
  demoed, not after.
- **invitation** — a capability: an admin-signed member cert. **Already built**
  (0001 Phase 2 realm CA: founder key signs member certs, join proves cert
  validity AND key ownership, replay-proof).
- **admin-approved** — join request is gossiped; an admin signs a membership
  cert; revocations are entries in the same log.

## The hard part: removal

Adding people is easy. **Removal is the problem that eats group-messaging
designs.** A removed member still holds the old group key and can decrypt
anything gossiped under it.

**Key epochs.** On removal, an admin mints a new epoch key and encrypts it to
each remaining member individually. That is O(n) work per removal — completely
fine for 10–200 people, and it lets us skip the entire MLS/TreeKEM tree
machinery, which is the right trade at this scale. Every message carries its
epoch number.

Be honest in the docs: forward secrecy is **per-epoch, not per-message**. If we
ever need per-message, that is when MLS becomes worth its complexity — not
before.

## Message ordering: a DAG, not a chain

Concurrent posts in a partition-tolerant network mean there is no total order and
nobody to impose one. Each message references its causal predecessors by hash.
Display in causal order with a deterministic tiebreak (e.g. `(timestamp, hash)`).
Anti-entropy already syncs the DAG for free.

**Do not reach for consensus.** Chat does not need it, and reaching for it costs
months.

## Acceptance

- A realm's membership is reconstructible from the log alone, by any member,
  after an arbitrary offline period, with no server.
- All three tiers run on the same handshake, differing only in policy.
- Removing a member rotates the epoch; the removed member cannot read
  post-removal traffic; remaining members converge without an admin online.
- Concurrent posts from partitioned peers converge to the same causal order on
  every member.
