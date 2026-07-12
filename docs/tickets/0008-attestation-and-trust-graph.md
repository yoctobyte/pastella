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

## Part 1 — proving each other over an alternate channel

Users must be able to **truly prove each other**, out of band. Two mechanisms,
and the difference is a security difference, not a UX one:

### Fingerprint comparison (asynchronous)

A hash of **both** identity keys — sorted, concatenated, hashed — so both sides
see the same string. Read it to each other over a phone call, an existing
messenger, in person.

**It must be LONG** (~128 bits: 32 hex chars, or Signal's 60 digits). A *short*
code compared this way is **insecure**: an active man-in-the-middle grinds keys
offline until the fingerprint collides. This is the mistake to not make.

### PAKE over voice (interactive) — the one to build

Agree on a **weak** shared secret out of band — a spoken word, a 5-digit number
over the phone — and run **SPAKE2** over it.

The property that makes this work: **a weak secret yields strong
authentication**, because an active attacker gets exactly *one online guess*, not
offline grinding. This is what ZRTP does, and it is why a four-word verbal
comparison suffices there where plain fingerprinting needs 60 digits.

Better security *and* better UX than reading hex at each other. This is the
answer to "scan my QR" for the case where the two people are not in the same
room.

### The output of either is one object

A signed **attestation**: *"I, key A, verified key B, on this date, by this
method."*

| channel | strength | notes |
|---|---|---|
| **QR scan, in person** | strongest | proves physical co-presence AND binds the key |
| **PAKE over voice** | strong | remote, weak secret, active attacker gets one guess |
| **Long fingerprint compare** | strong *if long* | insecure if shortened |
| **Invite from an existing member** | the workhorse | already built (0001 Phase 2 realm CA certs) |
| **External evidence** — fingerprint on your own site / Mastodon / DNS | weak, user-checked | **the user verifies it themselves. We never verify it for them, and we never become a CA.** We only carry the claim |

Attestations are ordinary signed objects — the membership log
([0003](0003-membership-log-and-tiers.md)) already replicates exactly this shape.
They expire and can be revoked.

## Part 2 — "trust friends of" (optional, and this is the sharp edge)

### The distinction most designs get wrong

> **Transitivity is defensible for IDENTITY BINDING.
> It is NOT defensible for BEHAVIOUR.**

- *"Alice verified that this key really is Bob"* — I can lean on this. Alice did
  the work; if Alice is honest, the binding holds. This is PGP's web of trust,
  and for **key binding** it genuinely works.
- *"Alice thinks Bob is not a spammer"* — this does **not** compose. Trusting
  Alice's judgment says nothing about Bob's behaviour toward *me*, and chaining
  it is exactly how vouching rings form.

**Transitive attestation for keys; never transitive reputation.** One graph, two
edge types, and they must never collapse into a single "trust" number.

### With that split, friend-of-friend is safe and useful

- **Depth cap** — default **0** (direct only). The user may opt in to 1 ("trust
  friends of"), perhaps 2. **Never unbounded.**
- **k disjoint paths** — beyond depth 1, require **>= 2 paths through different
  friends**. This is the Sybil hardening: deceiving one friend buys the attacker
  one path, not admission.
- **Decay per hop.**
- **Show the path in the UI** — *"vouched by Alice, whom you verified in
  person."* **Never a bare checkmark.** Provenance *is* the security property;
  hiding it behind a green tick destroys it.

## The staging — each rung ships alone, each is safe alone

The full graph is hard. It does not have to arrive at once. What we build is a
**personal trust chain** — *personal* being the load-bearing word: computed from
YOUR edges, never a global score.

| stage | what | cost | when |
|---|---|---|---|
| **0** | **TOFU + loud key-change alerts** | trivial | with the demo — this is what protects the majority who never verify anything |
| **1** | **In-person QR** — the strongest attestation there is | trivial | with the demo |
| **2** | **Async long-fingerprint confirm** — voice note, email, any channel | no new crypto | cheap, next |
| **3** | **Live short-code confirm** (PAKE / commit-then-reveal) — the nice UX | real crypto work | after 2 |
| **4** | **Transitive, depth 1** — "trust friends of", provenance shown | graph work | after 3 |
| **5** | **Depth N** — k>=2 disjoint paths, decay, visibility flags | the hard part | last, and only if wanted |

Stages 0–1 ship with the off-grid demo and cost almost nothing. That is the point
of staging: a real trust story on day one, with the hard graph work kept optional.

### Trust levels are PROVENANCE, not a score

"2nd order / 3rd order" is a **fact about how you know someone**, not a number to
sort by. Present it as provenance — *"vouched by Alice, whom you verified in
person"* — and never collapse it to `trust = 0.6`. The moment it is a number,
someone sorts by it; the moment someone sorts by it, someone games it.

### The trap: a SHORT code over an ASYNC channel is INSECURE

This one matters because the insecure version looks identical to the secure one
in the UI.

Comparing a **short** code (5 digits, a few words) over an **asynchronous**
channel — a recorded voice note, an email — is **broken**. The MITM sits between
the parties and picks its own key `M`. It needs `SAS(A,M)` (what A sees) to equal
`SAS(M,B)` (what B sees) — and since it controls `M`, it simply **grinds `M`
offline** until those two short strings collide. For a 5–6 digit code that is
~10^6 tries: seconds. Both parties then read out matching codes and are owned.

What defeats this is not the channel but **commitment ordering**: the attacker
must be forced to commit to its key *before* learning the other side's. That
requires **interactivity** (ZRTP's commit-then-reveal, or a PAKE). Then it cannot
search — its only option is to guess the code in advance: one shot, ~10^-6,
detectable.

**The rule:**

- **async channel** (voice note, email, paste into another messenger) → the code
  must be **LONG** (~128 bits — a fingerprint);
- **short human-friendly code** (5 digits, four words) → the exchange must be
  **LIVE / interactive**.

Both are worth offering. **Never a short code over an async channel.**

*(A voice note does carry a second, non-cryptographic authentication channel —
you recognise the person's voice. That is real and worth keeping. It is not a
substitute for length.)*

## The two hard parts — stated, not wished away

**1. Nobody verifies.** Empirically only a tiny fraction of Signal users ever
compare safety numbers. The system must therefore be safe-ish for people who
*never* do it: trust-on-first-use plus **loud alerts on key change**. Design for
the lazy majority, not the diligent minority — a verification scheme that only
protects the 2% who use it is theatre.

**2. "Friends of" leaks the social graph.** To compute a path, *someone* must
reveal edges. Enabling friend-of-friend trust makes part of your contact list
visible to whoever evaluates it. This is a real tension, not a detail.
Mitigations:

- attestations carry a **visibility flag** — the voucher decides whether a vouch
  is publishable at all;
- scope attestations to a realm rather than globally;
- for *"do we have a contact in common?"*, **private set intersection** computes
  the overlap without either side revealing their whole list. Expensive, but it
  exists — and knowing it exists is what lets us offer the feature without
  promising the leak.

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

- Two people who have never met can verify each other over a **voice call** using
  a short spoken secret (PAKE), and an active MITM on the network cannot succeed
  — it gets one online guess, not offline grinding.
- A *shortened* fingerprint comparison is not offered anywhere in the UI (it is
  the insecure variant, and it looks identical to the secure one).
- Trust is *only* ever evaluated relative to an asking identity. There is **no
  code path** that produces a reputation number independent of who is asking.
- A clique of N mutually-attesting identities, with no edge from the user, has
  **zero** effect on that user's view — demonstrated by a test that builds exactly
  that clique.
- Identity-binding attestations chain (depth-capped, k-disjoint-path); behavioural
  judgments **do not chain at all**. Two edge types, never one number.
- "Trust friends of" is off by default, and turning it on does not publish the
  user's contact edges without a per-attestation visibility choice.
- Attestation strength (in-person / PAKE / invite / external claim) survives into
  the UI, with the path shown ("vouched by Alice, whom you verified"), rather than
  collapsing to one "verified" checkmark.
- A user who never verifies anyone is still protected against silent key
  substitution (TOFU + key-change alert).
- A key succession is accepted by peers who trusted the predecessor, and rejected
  when the succession statement is forged or missing.
