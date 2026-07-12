# Objects & wire

*Design document. Status: proposed, 2026-07-12. This is the spine every other
document assumes and none of them define.*

Today the content store holds **untyped blobs** — `TItem = record hash, data end`
(`src/gossip_mem.pas`). That was right for the spike: it proved anti-entropy
converges. But every ticket from 0003 onward — membership entries, attestations,
chat messages, provider records — needs to know *what an object is*, *who signed
it*, *which realm it belongs to*, and *what came before it*.

So: one envelope, many payload types. Get this right and the rest of the system
is mostly bookkeeping; get it wrong and every later feature fights it.

---

## 1. The object

```
object {
  # --- envelope (signed) ---
  ver        : u8            # wire version
  type       : u16           # payload discriminator (§2)
  realm      : realm-id      # 32 bytes. WHICH realm this belongs to
  epoch      : u32           # key epoch (0003) — which group key encrypts it
  author     : identity      # per-realm member identity (NOT the node key)
  created    : u64           # author's clock, milliseconds. ADVISORY ONLY (§5)
  refs       : [hash]        # causal predecessors — this is what makes it a DAG
  payload    : bytes         # type-specific; encrypted for closed realms
  # --- outside the signature ---
  sig        : signature     # ECDSA-P256 over H(envelope)
}
```

**The object's name is `H(everything including sig)`** — content-addressed, so
the existing offer/fetch (`HAVE`/`WANT`/`DATA`) machinery keeps working
unchanged. An object is immutable by construction: change any field and it is a
different object.

### Why each field is there

- **`realm`** — an object without a realm cannot be routed, stored or authorised.
  Everything belongs somewhere. This is also what makes "store content only for
  realms you belong to" ([0002](../tickets/0002-layering-node-topic-membership.md))
  *checkable* rather than aspirational.
- **`epoch`** — a receiver must know which key decrypts a payload, and a *removed*
  member must be unable to read later epochs
  ([0003](../tickets/0003-membership-log-and-tiers.md)). Without this in the
  envelope, key rotation is unimplementable.
- **`author`** — the **per-realm member identity**, never the node key. Putting
  the node key here would leak the cross-realm correlation the design
  specifically forbids ([design §2](identity-membership-discovery.md)).
- **`refs`** — causal predecessors. This is what makes the store a **DAG** rather
  than a bag, and it is how concurrent posts order themselves without consensus.
- **`sig`** — every object is signed by its author. Unsigned objects do not exist.

### What is deliberately NOT in the envelope

- **No global sequence number.** There is no authority to issue one.
- **No "trust" or "score" field.** Trust is subjective and computed by the
  reader ([0009](../tickets/0009-sybil-resistance-trust-flow.md)); an object that
  carried its own trustworthiness would be a Sybil vector.
- **No sender/recipient routing header.** Delivery is by anti-entropy, not by
  routing. A DM is a two-member realm
  ([0007](../tickets/0007-pairwise-contacts.md)), not an addressed packet.

---

## 2. Payload types

One envelope; the `type` field discriminates. Every type below is *already
required* by an existing ticket — none is speculative.

| type | payload | ticket |
|---|---|---|
| `MESSAGE` | user content (chat text, file chunk ref) | [0005](../tickets/0005-offgrid-group-chat.md) |
| `MEMBER_ADD` / `MEMBER_REMOVE` / `GRANT_ADMIN` | the membership log | [0003](../tickets/0003-membership-log-and-tiers.md) |
| `EPOCH_KEY` | new group key, encrypted to ONE member (n copies per rotation) | [0003](../tickets/0003-membership-log-and-tiers.md) |
| `ATTESTATION` | "A verified B, by method M" | [0008](../tickets/0008-attestation-and-trust-graph.md) |
| `REVOCATION` | revokes an attestation or a member cert | [0008](../tickets/0008-attestation-and-trust-graph.md) / [0009](../tickets/0009-sybil-resistance-trust-flow.md) |
| `KEY_SUCCESSION` | "key A declares key B its successor" | [0008](../tickets/0008-attestation-and-trust-graph.md) |
| `PROVIDER` | "peer P serves topic T until time X" — **the only object type that lives OUTSIDE a realm** | [0004](../tickets/0004-discovery-dht.md) |

`PROVIDER` is the exception that proves the rule: it is the *phonebook* entry, it
carries no content, it has a short TTL, and it is the **only** thing a node stores
for realms it does not belong to
([0002](../tickets/0002-layering-node-topic-membership.md)'s phonebook rule).

### PROVIDER carries NO metadata — strictly typed, no extension point

```
provider {
  topic   : topic-id      # 32 bytes, = H(realm_value || epoch). Opaque
  peer    : pseudonym     # rotating. NOT the node key, NOT a member identity
  addr    : ip:port       # fixed shape
  expires : u32           # short TTL
  sig     : signature     # over the above, by the pseudonym key
}
```

**Fixed shape. Size-capped. No free-form field. No extension point. Ever.**
No notes, no counts, no realm names, no padding, no "reserved" bytes.

This single rule closes two holes that arrive by different doors:

- **Covert channel / storage abuse.** Any free-form field is a place to stuff
  payload — and that is the phonebook quietly becoming a **filestore**, breaking
  the one rule the whole global layer rests on. It never arrives as *"let's store
  content"*; it arrives as a *flexible field* in a pull request that looks
  harmless.
- **Metadata leak.** Anything beyond reachability tells an outsider something about
  a realm — its size, activity, naming, rhythm. The discovery layer is the one
  place we *invite* outsiders to look, so it must be the one place that says the
  least.

**If a feature needs the DHT to carry more, the feature is wrong.** Parsers must
reject an over-long or unknown-shaped provider record outright — not skip the
extra bytes, *reject the record* — because a lenient parser is what turns "no
extension point" back into one.

**Unknown types must be relayed, not dropped.** A node that does not understand a
type still gossips it to realm peers who might. This is what makes the format
extensible without a flag day — and it is a decision that must be made now,
because a v1 that drops unknown types can never be extended.

---

## 3. Encryption

For a closed realm the **payload** is sealed under the epoch key
(ChaCha20-Poly1305, as 0001 already does for transport). The **envelope stays in
the clear** — `realm`, `epoch`, `refs` and `sig` must be readable to route,
verify and order an object without decrypting it.

**This leaks structure to a realm outsider who somehow holds an object**: they
learn that *someone* posted *something* in realm R at epoch E, and its shape in
the DAG. They do not learn the author's real-world identity (the author is a
per-realm identity), nor the content.

That is an accepted trade, and it must be stated rather than discovered: hiding
the envelope too would mean an object could not be verified or ordered without
the group key, which breaks store-and-forward by non-members — and store-and-forward
by *members* is exactly how offline delivery works
([design §7a](identity-membership-discovery.md)).

---

## 4. Wire

Unchanged in shape from the working spike (`src/gossip_tcp.pas`), now typed:

```
frame  = u32 length | body        # length-prefixed, as today
verbs  = HELLO | HAVE | WANT | DATA | PING | PONG
```

- `HELLO` — version, node identity, realm(s) claimed. Realm membership is proven
  by the handshake (0001), not asserted here.
- `HAVE` — offer: a list of object hashes.
- `WANT` — fetch: the subset the peer lacks.
- `DATA` — one object, verbatim.

Anti-entropy is unchanged: **offer hashes, fetch what you lack.** The 2005 idea,
and it still carries everything above.

### Rules that are not optional

- **Verify before store.** `H(bytes)` must equal the announced hash, and `sig`
  must verify under `author`. An object failing either is dropped and the peer is
  penalised — never stored, never relayed.
- **No unvalidated amplification.** A node must never be induceable into mailing
  bytes at a victim it never spoke to. Free on TCP (the handshake validates); on
  UDP, a cookie plus a 3x limit before address validation; LAN beacons are
  announce-only ([0012](../tickets/0012-nat-traversal-and-transport.md)). This
  belongs in the wire format, not a policy layer — it is what stops the network
  being a DDoS weapon.
- **Cap everything**: frame size, `refs` count, objects per `HAVE`. An unbounded
  field is a memory-exhaustion bug waiting to be found by someone else.

---

## 5. Time and ordering

**`created` is advisory and MUST NOT be trusted.** A malicious author will lie —
timestamps are free. It is a display hint and a tiebreak input, nothing more.

Ordering comes from `refs`: an object is causally after everything it references.
Concurrent objects (neither reachable from the other) are genuinely concurrent,
and there is no authority to break the tie. Display order is
`(causal order, then deterministic tiebreak on (created, hash))` — deterministic
so that **every member renders the same conversation**, which matters more than
being *right* about which of two simultaneous messages came first.

**No consensus.** Chat does not need it; reaching for it costs months
([0003](../tickets/0003-membership-log-and-tiers.md)).

---

## 6. What this obsoletes

`src/gossip_mem.pas`'s `TItem = record hash, data end` — the untyped blob. It
stays as the spike/test harness; the real store holds envelopes.

## 7. Open questions

- **Object size cap** — chat messages are tiny, file transfer is not
  (`test_filetransfer` moves 256 KB). Chunk large payloads into content-addressed
  pieces referenced by a manifest object, or allow big `DATA` frames? Chunking is
  the right answer and costs a type.
- **`refs` width** — how many predecessors does a message name? 1 is a chain
  (loses concurrency), all-heads is correct but grows. Cap it and accept that the
  DAG is approximate.
- **Garbage collection** — the DAG grows forever. When may a member drop old
  objects, and how does a late-joining peer know it is not missing history rather
  than looking at a pruned tail?
