# 0007 — Pairwise contacts (1:1)

- **Status:** open
- **Depends:** [0003](0003-membership-log-and-tiers.md) (membership log + key
  epochs — a contact is a two-member realm);
  [0006](0006-bootstrap-and-reachability.md) (the invite object).
- **Design:** [identity, membership & discovery §5](../design/identity-membership-discovery.md#5-11--pairwise-contacts)

## Why it is not a fourth tier

The three admission tiers answer *"who may join this group?"*. 1:1 asks a
different question — *"how do I reach one specific person?"* — so it gets its own
shape. But it reuses the whole stack.

## The model

**A contact is a two-member realm.** Both parties are admins; membership is the
pair. That inherits the membership log, key epochs, gossip sync and anti-entropy
for free, and gives a natural upgrade path: **add a third member and the DM
becomes a group**, no new protocol.

**Reachability is a private rendezvous, never a `pubkey -> address` lookup:**

```
rendezvous = H(pairwise_shared_secret || epoch)
```

Only the two parties can compute it; to the discovery layer it is an opaque
rotating ID, indistinguishable from any other topicID. So 1:1 needs **no new
discovery concept at all**.

## What we explicitly will NOT build

**A global `pubkey -> address` index.** It leaks *presence*: anyone holding your
public key can probe whether you are online and from where. This is Tox's
structural flaw — your ID is your locator, so being reachable means being
trackable — and it cannot be fixed later without changing what an identity is.

Cold-calling a stranger is therefore out of scope. If it is ever wanted it is the
`open` tier of 1:1: opt-in flag (default **off**), proof-of-work stamp, explicit
user approval before a conversation exists.

## Acceptance

- Two people exchange an invite (QR / string) and can talk, with no global index
  touched and neither identity published.
- An observer with a party's public key cannot tell whether they are online, nor
  enumerate their contacts.
- Key-change alerts fire on a changed fingerprint (trust-on-first-use is only
  acceptable with this).
- Promoting a 1:1 to a group by adding a third member works without a new
  protocol path.
- Docs state plainly: forward secrecy is per-EPOCH, not per-message (this is not
  Signal's double ratchet).
