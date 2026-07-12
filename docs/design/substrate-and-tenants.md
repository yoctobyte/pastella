# The substrate and its tenants

*Design document. Status: proposed, 2026-07-12.*

> **Pastella is not a messenger. It is a substrate, and the messenger is its first
> tenant.**

Same north star as the compiler it is written in: *push generality down into the
core, keep the tenants thin.* An app is **payload types + a policy** — nothing
more.

---

## 1. The stack

```
  APPS        messenger · 1:1 · file sync · sensor mesh · <yours>
              ───── policies over the core, NOT subsystems ─────
  REALM       membership · admission policy · epoch keys · trust
  SPINE       signed objects + content-addressed anti-entropy
  DISCOVERY   who serves topic T?   (LAN | invite hints | DHT)
  TRANSPORT   PAL: POSIX | lwIP
```

### The test that keeps this honest

> **A new app must be definable as (a) new payload types plus (b) a policy, with
> ZERO changes to the core.**
>
> If an app forces a core change, **the core was wrong** — that is a bug report
> against the substrate, not a feature request for the app.

This is the whole reason to build a substrate rather than a messenger. It is also
falsifiable, which is why it is written as a rule rather than an aspiration.

---

## 2. The four tenants, in one frame

| | messenger (group) | 1:1 | file sharing | sensor mesh |
|---|---|---|---|---|
| **object type** | `MESSAGE` | `MESSAGE` | `CHUNK` + `MANIFEST` | `READING` |
| **admission** | invite / admin-approve | pairwise invite | realm invite | factory / QR pairing |
| **object size** | tiny | tiny | **large → chunked** | tiny |
| **ordering** | causal DAG | causal DAG | none (a set) | timestamps; lossy is fine |
| **retention** | keep | keep | **evict — GC matters** | ring buffer; drop old |
| **what it stresses** | membership, moderation | **offline delivery** | **size + GC** | **RAM, power, leaf role** |
| **ticket** | [0005](../tickets/0005-offgrid-group-chat.md) | [0007](../tickets/0007-pairwise-contacts.md) | [0010](../tickets/0010-file-sharing-in-realm.md) | [0011](../tickets/0011-sensor-mesh-leaf-nodes.md) |

They differ in **payload type, policy and retention**. They do **not** differ in
transport, discovery, membership, signing or anti-entropy.

**That is the substrate paying for itself.**

---

## 3. What each tenant forces on the core — the honest list

### File sharing — free, with one asterisk and one refusal

**Free:** content-addressed anti-entropy *is* BitTorrent's shape. Offer hashes,
fetch what you lack. A file is just objects.

**The asterisk:** large objects force **chunking + a manifest object**, and they
force **garbage collection** — a problem chat lets you dodge, because chat objects
are tiny and you keep them forever. Even though file sharing is not a near-term
goal, **the envelope must not design it out**: hence `refs` and a `MANIFEST` type
in [objects & wire](objects-and-wire.md). Designing them out would be the
cheapest-looking and most expensive mistake available.

**The refusal:** **public** file sharing is exactly what we do not do. Sharing
*within a realm* is free and fine. A public firehose is the Gnutella vector — an
abuse magnet, a legal liability, and the thing the whole realm model exists to
avoid. Its absence is **the design**, not an oversight to be fixed later.

### The sensor mesh — forces a genuinely new concept

An ESP32 has ~300 KB of RAM. It **cannot** hold a DAG, **cannot** serve a DHT,
**cannot** store history.

It is therefore **not a smaller full node**. It is a **leaf** — and recognising
leaf-vs-full as a *capability profile* (§4) is the piece the architecture was
missing until now. Without it, every core data structure silently assumes a
desktop, and the ESP32 port becomes a fork.

### 1:1 — forces the mailbox

A two-member realm has **no third party** to hold a message for an offline peer.
Groups get store-and-forward for free (the other members *are* the mailbox); 1:1
gets nothing. See [identity §7a](identity-membership-discovery.md) and
[0007](../tickets/0007-pairwise-contacts.md).

### The messenger — forces membership and moderation

Which is why it is first: it stresses the parts everything else depends on.

---

## 4. Node roles — capability profiles, not codebases

**One codebase. Capability flags.** A "role" is a set of things a node does and
does not do — never a fork.

| role | holds | serves | typical |
|---|---|---|---|
| **leaf** | few realms, small store, no DAG history | nothing (publish-mostly) | ESP32, phone |
| **full** | full DAG for its realms | peers in its realms; store-and-forward for members | desktop |
| **seed** | nothing | addresses only | a box we run ([0006](../tickets/0006-bootstrap-and-reachability.md)) |
| **mailbox** | encrypted blobs, TTL'd | offline peers | volunteer / paid ([0007](../tickets/0007-pairwise-contacts.md)) |
| **relay** | nothing (streams bytes) | symmetric-NAT peers | volunteer ([0006](../tickets/0006-bootstrap-and-reachability.md)) |

### The blind-infrastructure rule

**`seed`, `mailbox` and `relay` are all BLIND.** They carry addresses or
ciphertext — **never plaintext, never membership, never keys.**

- a **seed** hands out addresses and knows nothing else;
- a **mailbox** holds a sealed blob addressed to a rendezvous: it cannot read it,
  and does not know who sent it;
- a **relay** forwards bytes it cannot interpret.

This is the phonebook rule ([identity §0](identity-membership-discovery.md))
generalised to every piece of infrastructure — and it is what keeps *"an operator
stores no stranger's content"* true **even when we run the infrastructure
ourselves**. It is the property that makes running seed nodes clean, and it is
worth defending against every future convenience that would erode it.

### The leaf contract

A leaf must be able to participate **without** any of the following, because on an
ESP32 none of them exist:

- a full object DAG (bounded store; keeps only what it published + what it needs)
- DHT service (opts out — §1 of [0004](../tickets/0004-discovery-dht.md))
- history / back-fill (it may have missed everything before it booted)
- a wall clock it trusts (`created` is advisory anyway —
  [objects & wire §5](objects-and-wire.md))

If any core algorithm *requires* full history or a full DAG, **it is wrong for a
leaf, therefore wrong for the substrate.** This constraint is a gift: it forces the
core to stay small.

---

## 5. The constitution — invariants no tenant may break

1. **Every object is signed.** Unsigned objects do not exist.
2. **Every object belongs to exactly one realm.** `PROVIDER` records are the sole
   exception — the phonebook.
3. **Nodes route metadata for everyone; nodes store content only for realms they
   belong to.**
4. **The node key is never the membership key.**
5. **No global reputation score. Ever.**
6. **No public firehose** — you cannot broadcast to people who never admitted you.
7. **The core is pure.** Clock, entropy and sockets are *inputs*, never calls.
8. **The DHT carries NO metadata.** A `PROVIDER` record is strictly typed,
   fixed-shape, size-capped and TTL'd: *"peer P is reachable at A for topicID T,
   until X"* — and **nothing else**. No free-form fields, no extension point, no
   "notes", no counts, no names, no padding. Two holes, closed by one rule:
   - **Covert channel / storage abuse.** Any free-form field is somewhere to stuff
     payload — and that is the phonebook quietly becoming a **filestore**,
     violating (3) through a side door. It never arrives as a proposal to store
     content; it arrives as a *flexible field*.
   - **Metadata leak.** Anything beyond reachability tells an observer something
     about a realm — its size, its activity, its naming, its rhythm — and the
     discovery layer is the one place outsiders are *invited* to look.

   **If a feature needs the DHT to carry more, the feature is wrong.**

> **An app that needs to break one of these is not an app for this substrate.**

That is a feature, not a limitation: it is what makes the ethical properties
**structural** rather than aspirational. Nobody has to be trusted to enforce them,
and no future maintainer can quietly drop them in a UI ticket.

### Checklist for any new tenant

- [ ] Definable as payload types + policy, with no core change?
- [ ] Works for a **leaf** (no full history, bounded store)?
- [ ] Objects signed, realm-scoped?
- [ ] Retention/GC story stated (or "keep forever" justified)?
- [ ] Needs no global score, no public broadcast?
- [ ] Offline behaviour stated (who holds it while the recipient is away)?
