# 0010 — File sharing within a realm (optional tenant)

- **Status:** open — **optional.** Not a product goal. Its value is as a **test of
  the substrate**, and as the thing that forces chunking + GC to exist before they
  are needed in anger.
- **Depends:** [objects & wire](../design/objects-and-wire.md);
  [0003](0003-membership-log-and-tiers.md) (realm membership).
- **Design:** [substrate & tenants §3](../design/substrate-and-tenants.md)

## Why it is nearly free

Content-addressed anti-entropy **is** BitTorrent's shape: offer hashes, fetch what
you lack. A file is just objects. `test_filetransfer` already moves 256 KB across a
5-node line, hash-verified per hop.

## What it forces on the core — the point of the ticket

**Chunking + a manifest.** Chat objects are tiny; files are not. A file becomes
content-addressed `CHUNK` objects plus a `MANIFEST` object listing them. Both
types are already reserved in [objects & wire](../design/objects-and-wire.md) —
**reserving them was the whole reason to think about this ticket early.**

**Garbage collection.** Chat lets you dodge GC (small objects, keep forever). Files
do not. This ticket is where the substrate's retention story gets built:

- when may a member evict an object?
- how does a late peer distinguish *"I am missing history"* from *"this was
  pruned"*?
- who is obliged to keep what, and for how long?

**Those questions have no good answer today.** Better to face them driven by a
toy file-share than to meet them for the first time when the messenger's DAG has
grown for a year.

## The refusal — explicit, and not negotiable

**Sharing WITHIN a realm: free and fine.**
**PUBLIC file sharing: we do not do it.**

A public firehose is the Gnutella vector — an abuse magnet, a legal liability, and
precisely the failure the realm model exists to prevent
([threat model §3](../design/threat-model.md)). You cannot distribute to people who
never admitted you. That is architecture, not moderation, and it must not be
"fixed" later.

## Acceptance

- A 100 MB file syncs across a realm without any node holding it entirely in RAM.
- A late joiner fetches only the chunks it lacks.
- Eviction works, and a peer that has pruned old chunks does not appear to a late
  joiner as if it were withholding them.
- **No core change was required** — only new payload types and a policy. *(If a
  core change WAS required, that is a bug against the substrate: file it there.)*
