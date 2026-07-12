# Threat model

*Design document. Status: proposed, 2026-07-12.*

What Pastella defends against, what it does not, and what it deliberately makes
impossible. **The "does not" list is the important half** — a threat model that
only lists wins is marketing.

---

## 1. Adversaries

| adversary | capability | our stance |
|---|---|---|
| **Curious peer** | is in your realm, reads what you send | in scope: they are a member, they see member traffic. Compartmentalise by realm |
| **Outsider on the wire** | sees traffic, can inject, can spoof source addresses | **defended** (§2) |
| **Sybil / botnet** | mints unlimited identities for free | **bounded, not excluded** (§3) — the honest framing |
| **Malicious realm admin** | admits and removes at will | **not defended** (§4). A social problem with a social answer |
| **Global passive observer** | sees all traffic everywhere | **not defended.** We are not Tor (§4) |
| **Endpoint compromise** | has the device and its keys | **not defended.** Nothing survives this (§4) |

---

## 2. What we defend

**Content confidentiality.** Payloads are sealed under the realm's epoch key
(ChaCha20-Poly1305). A non-member learns nothing from an object they somehow hold
except its envelope ([objects & wire §3](objects-and-wire.md)).

**Membership privacy / social-graph correlation.** The node key is **not** the
member identity, and `topicID = H(realm_value ‖ epoch)` rotates. So an observer of
the discovery layer cannot enumerate topics, cannot map who belongs to what, and
cannot dictionary-attack topic names
([identity §2, §3](identity-membership-discovery.md)).

**Forward secrecy across removals.** A removed member cannot read later traffic:
the epoch key rotates and is re-encrypted to the remaining members
([0003](../tickets/0003-membership-log-and-tiers.md)). *Per-epoch, not
per-message* — see §4.

**Impersonation.** Every object is signed by its author; identities are verified
out of band (in-person QR, PAKE-over-voice, long fingerprints), and a *short* code
over an *async* channel is refused because it is grindable
([0008](../tickets/0008-attestation-and-trust-graph.md)).

**Being a DDoS amplifier.** Never reply larger than the request to an unverified
address; prove return-routability before doing work
([0004 §6.2](../tickets/0004-discovery-dht.md)). This is a wire-format rule, not a
policy toggle — a rate limit protects *us*; these rules stop us being the
*weapon*.

**Storing strangers' content.** Nodes route metadata for everyone but **store
content only for realms they belong to**
([0002](../tickets/0002-layering-node-topic-membership.md)). The global layer is a
phonebook, never a filestore.

---

## 3. Sybil: bounded, not excluded

An identity costs a keygen (~7 ms). Anyone can mint a million, and **no mechanism
prevents that.** Claiming otherwise would be false.

What is *not* free is an **attack edge** — an edge from an honest human to a fake,
each costing a real act of deception against a real person. Deceiving humans does
not scale the way keygen does, so:

> **The attacker's cost is linear in humans deceived; its benefit is bounded by
> the cut — never by the number of fakes minted.**
>
> A million bots behind 3 attack edges are worth no more than 3 fooled friends.

Mechanism: capacity-constrained trust flow, subjective to the asking user
([0009](../tickets/0009-sybil-resistance-trust-flow.md)). **Never a global
reputation score** — a global score is Sybil-broken by construction, because the
attacker owns the inputs.

**The abuse vector that killed Gnutella is structurally absent**: there is no
public firehose. Realms are invite-gated, and the `open` tier is off until
[0009](../tickets/0009-sybil-resistance-trust-flow.md) exists. **You cannot
broadcast to people who never admitted you.** That is an architectural property,
not a moderation policy.

---

## 4. What we do NOT defend — stated plainly

Say these out loud. A user who assumes Signal semantics and gets something weaker
has been misled by our silence.

- **Traffic analysis / global passive adversary.** We are **not Tor**. An observer
  sees that you talk, roughly when, and to roughly how many peers. Padding and
  cover traffic are not in the design.
- **Per-message forward secrecy.** We have **per-epoch** (§2). Signal's double
  ratchet gives per-message. That is a deliberate complexity trade, and 1:1 is the
  place it may later be worth paying ([0007](../tickets/0007-pairwise-contacts.md)).
- **A malicious admin.** An admin can admit anyone and remove anyone. The trust
  graph mitigates; it does not fix. **A realm is only as good as its admins** —
  and that is true of every group of humans that has ever existed.
- **Endpoint compromise.** Keys on a compromised device are gone. No forward
  secrecy scheme survives an attacker who is already inside.
- **A user who never verifies.** Most people never compare safety numbers
  (empirically, on Signal). TOFU + **loud key-change alerts** is the mitigation,
  and it is a mitigation, not a solution.
- **Metadata inside a realm.** Members see who posts and when. Compartmentalise:
  that is what having 1:N realms is *for*.
- **Availability.** Anyone can flood their own realm; peers can go offline; a
  message with no online recipient may simply not arrive yet
  ([identity §7a](identity-membership-discovery.md)).

---

## 5. Documentation discipline: architecture, never posture

**Do not write legal arguments into this repository.** No "it's only a demo", no
"we host no service", no threat model framed as resistance to lawful process.

Two reasons, and both are practical rather than squeamish:

1. **It may stop being true.** Seed nodes are in scope
   ([0006](../tickets/0006-bootstrap-and-reachability.md)) — the moment one runs,
   a claim to host nothing is false.
2. **A stated intent about liability is the sentence that gets quoted back at
   you.** A threat model that reads as an evasion manual creates exposure rather
   than describing it.

None of that is needed, because **the architecture already says the true thing,
and it was chosen for security reasons that stand on their own**:

- nodes store content only for realms they belong to — an operator warehouses no
  stranger's content;
- there is no public firehose — anonymous mass distribution to strangers is not a
  feature that exists to be abused.

Both are engineering facts with engineering rationales. State those. Draw no
conclusions for the reader.

**And do not market it as "unblockable" or "uncensorable."** It invites the
attention and it is not true: traffic can be fingerprinted, and seed nodes can be
blocked. The accurate claim is stronger anyway:

> **Signal without its servers is a dead app. Pastella without its seed nodes is a
> slower Pastella.**

The property is **degradation, not death** — and unlike the other claim, that one
survives contact with an expert.
