# 0009 — Sybil resistance: attack edges & capacity-constrained trust flow

- **Status:** open — design settled, ready to implement.
- **Depends:** [0008](0008-attestation-and-trust-graph.md) (produces the edges
  this ticket evaluates); [0003](0003-membership-log-and-tiers.md) (replicates
  them as signed objects).
- **Blocks:** the `open` admission tier ([0003](0003-membership-log-and-tiers.md))
  and **any** ranking, sorting or "trending" feature, forever.

---

## 1. The problem, stated correctly

An identity costs ~7 ms of keygen. An attacker can mint a million. Signal binds
identity to a phone number — a scarce resource; **we bind it to nothing**.

The naive defences all fail, and it is worth being explicit about *why*, because
each one is somebody's first instinct:

| defence | why it fails |
|---|---|
| Proof-of-work on identity | Botnets **are** CPU. It taxes legitimate phone users and favours the attacker. Fine as a rate limiter; useless against Sybil. |
| Global reputation score | Sybil-broken **by construction**: a million fakes upvoting each other produce a big number. The attacker owns the inputs; no weighting scheme survives that. |
| **k disjoint paths** | **Fails at exactly the case we care about.** If the botnet has edges from several of your friends, it *has* k disjoint paths. Path counting waves it straight through. *(This was in an earlier draft of 0008. It is wrong.)* |

## 2. The invariant: count ATTACK EDGES, not identities

Identities are free. **Attack edges are not.**

An *attack edge* is an edge from an honest human to a fake — and each one costs a
real act of deception against a real person. The honest region and the fake region
are connected **only** through those edges, so the cut between them is **sparse**.
Not because of any cleverness on our part, but because **deceiving humans does not
scale the way keygen does.** That asymmetry is the entire lever. (Basis:
SybilGuard / SybilLimit / Advogato.)

> ### The win condition
>
> **Not** "keep the botnet out" — that is impossible, and any design claiming it
> is lying.
>
> **Instead:** the attacker's cost is **linear in humans deceived**, and its
> benefit is **bounded by the cut** — never by the number of fakes it mints.
>
> *A million bots behind 3 attack edges must be worth no more than 3 fooled
> friends.*

## 3. The mechanism: capacity-constrained max-flow

Every trust edge carries a finite **capacity**. Trust from user U to a stranger X
is the **max-flow** from U to X through the attestation graph. The load-bearing
property is that **flow is conserved**.

Consequences, which are the whole point:

- 3 fooled friends ⇒ at most **3 edges' worth of capacity** crosses into the fake
  region.
- A thousand bots behind those 3 edges **share** those 3 units — ~3/1000 each.
  Individually: noise.
- **Minting more identities gains the attacker nothing.** The bottleneck is the
  cut, and the cut is human.

**Sybil growth is therefore self-defeating**: the more fakes they create, the more
diluted each one becomes. This is the Advogato insight, and it is the core of this
ticket.

### Two edge types — never collapsed into one number

From [0008](0008-attestation-and-trust-graph.md), and load-bearing here:

- **identity-binding** (*"I verified this key really is Bob"*) — **chains**.
  Alice did the work; if Alice is honest the binding holds. This is what flows.
- **behavioural** (*"I think Bob is not a spammer"*) — **does NOT chain**.
  Trusting Alice's judgment says nothing about Bob's conduct toward me, and
  chaining it is precisely how vouching rings form.

Two graphs, or one graph with typed edges. Never one "trust" scalar.

## 4. Data model

An attestation is a signed object, replicated like any other
([0003](0003-membership-log-and-tiers.md)):

```
attestation {
  from        : identity        // the voucher
  to          : identity        // the subject
  type        : identity-binding | behavioural
  method      : in-person-qr | pake-voice | fingerprint-async | invite | external-claim
  realm       : realm-id        // SCOPED. never global
  capacity    : integer         // the voucher's allocation, from a conserved budget
  visibility  : private | realm | public
  issued      : timestamp
  expires     : timestamp
  signature
}
```

Plus a `revocation { attestation-hash, reason, signature }`.

**Capacity is drawn from a conserved budget.** A user has a finite total to
allocate across their vouches; vouching for everyone is the same as vouching for
nobody. This is what stops trust inflation, and it makes an attacker's
already-compromised friend a *bounded* conduit rather than an unlimited one.

## 5. Two multipliers

**Voucher accountability.** When a vouched identity is revealed as a bot, the
**voucher** loses standing *in the discovering user's graph*. Vouching becomes a
bet with a downside: it raises the human cost of every attack edge, and it makes a
fooled friend degrade gracefully instead of becoming an open conduit. (Advogato /
Freenet WoT do this.)

**Per-realm scoping.** A user has **1:N networks**. Trust does **not** cross them:
an edge earned in the chess club grants **nothing** in the activist realm. The
attacker must pay the human cost *per realm*, so a bot network that penetrates one
of your worlds cannot walk into the others. One breach stays one *contained*
breach.

This is also the honest model of how people actually trust — I would lend my
neighbour a drill, not my passport — which is why users will find it intuitive
rather than arbitrary.

## 6. Parameters (defaults, all user-overridable)

| parameter | default | note |
|---|---|---|
| depth cap | **0** (direct only) | opt in to 1 ("trust friends of"); 2 is the practical maximum. **Never unbounded.** |
| per-hop decay | 0.5 | trust attenuates with distance |
| total capacity budget | fixed per user | conserved — vouching for everyone dilutes every vouch |
| attestation lifetime | 12 months | expiry forces the graph to stay live rather than fossilising |
| method weight | qr > pake > fingerprint > invite > external | from [0008](0008-attestation-and-trust-graph.md); never flattened |

## 7. Non-goals — the traps, restated so they cannot creep back

- **NEVER a global reputation number.** Not for sorting, not for "trending", not
  as a convenience. This is the rule that a future UI ticket will violate
  innocently unless it is written here in capitals.
- **Trust is only ever evaluated relative to an asking identity.** There must be
  no code path that produces a score independent of who is asking.
- **PoW is not a Sybil defence** (it is a rate limiter — see
  [0007](0007-pairwise-contacts.md)).
- **No path counting.** Capacity, not paths.

## 8. What we accept, and say out loud

**If several friends genuinely vouch for a scammer, the user will trust the
scammer somewhat.** No mechanism fixes this, and pretending otherwise is how
security theatre gets built.

But observe the failure mode it degrades to: **the user is exactly as exposed as
their friends' judgment.** That is the real-world situation, it is the one users
already intuitively grasp, and it is acceptable.

What is **not** acceptable is unbounded propagation from a *single* fooled friend
— and capacity-constrained flow eliminates exactly that.

## 9. Test plan (this is how we know it works)

- **The dilution test.** Mint **1,000 Sybils behind 3 attack edges**. Each must
  end up with ≈ 3/1000 of an edge's weight. Then mint 100,000 and show the total
  crossing the cut is *unchanged*. **Minting more must gain nothing** — if it
  gains anything, the mechanism is broken.
- **Single-fooled-friend bound.** One compromised friend must not admit an
  unbounded set: total admitted weight ≤ that one edge's capacity.
- **Revocation collapse.** Revoke the attack edge; all weight behind it drops to
  zero immediately.
- **Realm isolation.** Trust earned in realm A grants exactly zero in realm B.
- **Asker-relativity.** No two users see the same trust value for the same
  stranger, unless their graphs coincide. (If they do, something global has crept
  in.)
- **Clique-with-no-edge.** N mutually-attesting identities with **no** edge from
  the user have **zero** effect on that user's view.

## 10. Phasing

The evaluator is **pure and offline** — it reads signed objects that
[0003](0003-membership-log-and-tiers.md) already replicates, and it changes no
wire format. So it can be built and tested in isolation, against synthetic graphs,
long before any UI exists. Fits the project's "protocol = pure functions" rule
exactly, and it is fuzzable.

1. Attestation object + revocation, replicated as gossip objects.
2. The evaluator (max-flow, per-realm, typed edges) — pure, deterministic,
   property-tested against §9.
3. Provenance UI (*"vouched by Alice, whom you verified in person"* — never a bare
   checkmark; **provenance IS the security property**).
4. Only then: `open`-tier realms, which are gated on this ticket existing.

## 11. Open questions

- **Capacity assignment policy** — equal split of the budget, or user-set per
  edge? Equal is simpler and harder to get wrong; user-set is more expressive and
  invites mistakes.
- **Computation cost.** Max-flow on a *local* graph is cheap (hundreds of nodes),
  but what is the bound as a user's realm count grows? Cache per-realm; recompute
  on revocation.
- **Edge privacy vs evaluability.** Computing a path requires *someone* to reveal
  edges — the `visibility` flag is the blunt answer; private set intersection is
  the sharp one. Unresolved, and it is the reason depth defaults to 0.
