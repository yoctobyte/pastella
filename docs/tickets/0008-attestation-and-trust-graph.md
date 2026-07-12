# 0008 — Attestation & the trust graph

- **Status:** open — design early, implement when the `open` tier or any ranking
  is contemplated. **Nothing may ship a global score before this exists.**
- **Depends:** [0002](0002-layering-node-topic-membership.md) (identities);
  [0003](0003-membership-log-and-tiers.md) (the log carries attestations).
- **Design:** [identity, membership & discovery §0a](../design/identity-membership-discovery.md#0a-identity-is-cheap-it-must-therefore-mean-nothing)

## The problem

An identity costs ~7 ms of keygen. Anyone can craft a million. Signal binds
identity to a phone number — a scarce resource; we bind it to nothing.

So **a valid identity must confer exactly zero trust.** Trust can only come from
**attestation**: a signed statement by a human who did something out of band.

Today this is a small issue (invite-only realms, tiny networks). At scale it is
*the* issue — botnets vouching for one another into legitimacy — and it cannot be
retrofitted once trust semantics are load-bearing.

## What an attestation is

A signed statement: *"I, key A, met key B, on this date, by this channel."*

The channel determines the strength, and the UI must never flatten that
distinction:

| channel | strength | notes |
|---|---|---|
| **QR scan, in person** | strongest | proves physical co-presence AND binds the key. The "scan my QR" case |
| **Invite from an existing member** | the workhorse | already built (0001 Phase 2 realm CA certs) |
| **External evidence** — fingerprint on your own site / Mastodon / DNS | weak, user-checked | **the user verifies it themselves. We never verify it for them, and we never become a CA.** We only carry the claim |

Attestations expire, can be revoked, and **decay with distance**: I trust you
fully, what you vouch for somewhat, what *that* vouches for barely — with a hard
depth cap. A scoped, subjective web of trust, which is what makes it tractable
where PGP's global WoT failed.

Attestations are ordinary signed objects — the membership log
([0003](0003-membership-log-and-tiers.md)) already replicates exactly this shape.

## Non-goals — these are the traps

- **NEVER a global reputation score.** Not for sorting, not for "trending", not
  as a convenience. A global score is Sybil-broken by construction: a million
  fake accounts vouching for each other produce a big number, and no weighting
  scheme fixes it because the attacker controls the inputs. **Trust is only ever
  computed over paths FROM the asking user.** A botnet with no edge from anyone
  you trust has exactly zero weight in your view.
- **Proof-of-work is NOT a Sybil defence.** Botnets *are* CPU — PoW taxes
  legitimate phone users and favours the attacker. PoW is fine as a *rate
  limiter* on unsolicited requests ([0007](0007-pairwise-contacts.md)); it buys
  nothing against Sybil. **Sybil resistance comes from the social layer, not the
  compute layer.**
- **No global namespace.** Petnames only — you name your contacts locally, bound
  to a fingerprint. Global unique names mean squatting and impersonation.

## Also in scope

**Key succession.** Identity is a keypair, so a lost device is a lost person. A
signed "key A declares key B its successor" statement, plus re-attestation by
contacts. Must be verifiable by everyone who ever trusted the old key — which is
why it has to be designed early, not bolted on after people have real histories.

## Acceptance

- Trust is *only* ever evaluated relative to an asking identity. There is no
  code path that produces a reputation number independent of who is asking.
- A clique of N mutually-attesting identities, with no edge from the user, has
  zero effect on that user's view — demonstrated with a test that builds exactly
  that clique.
- Attestation strength (in-person / invite / external claim) survives into the UI
  rather than collapsing to one "verified" checkmark.
- A key succession is accepted by peers who trusted the predecessor, and rejected
  when the succession statement is forged or missing.
