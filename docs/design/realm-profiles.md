# Realm profiles — one mechanism, per-realm policy

*Design document. Status: proposed, 2026-07-13.*

> **Every hard question in this project has turned out to have no single right answer —
> only trade-offs. So stop choosing. Implement the mechanism once, and let each realm
> (each application) pick its policy.**

This is not a new idea bolted on. It is the pattern the design **kept rediscovering
independently**, in six separate places, before anyone named it. Naming it is the point
of this document: once you see it, you stop having the same argument over and over.

---

## 1. The six places it already appeared

| axis | the options | the trade-off | decided by |
|---|---|---|---|
| **Admission** | invite · admin-approve · open | gatekeeping vs reach | the realm |
| **Discovery / bootstrap** | LAN · invite hints · anchors · DNS/HTTPS · encrypted blob · BitTorrent · DHT | privacy & effort vs reach | the realm |
| **Transport** | TCP · UDP · relay | simplicity vs NAT traversal & load | the deployment |
| **Object authentication** | realm HMAC · per-author signature | **cost vs attribution** (see §2) | the realm |
| **Retention** | keep forever · evict · ring buffer | history vs footprint | the tenant |
| **DHT participation** | opt in · opt out | helping others vs exposure & load | the **node** |

**None of these has a right answer.** Each has a real drawback. A private group and a
public community want opposite things; an ESP32 and a desktop want opposite things.

**So: one mechanism, many policies. Not one-size-fits-all — and not a fork either.**

---

## 2. The newest one: how is an object authenticated?

This is the axis the sensor MVP forced into the open, and it is the clearest example of
the pattern.

| | **realm HMAC** | **per-author signature** |
|---|---|---|
| how | `HmacSha256(realmKey, obj)` | `EcdsaP256Sign(authorPriv, obj)` |
| cost on an ESP32 | **fast** (SHA accelerator) | **~1–2 s per object** — the chip does nothing else |
| attribution | **none** — any member can forge any member's objects | **yes** — this member said this |
| revocation | rotate the realm key (everyone) | revoke one member |
| good for | **sensors**, own devices, tiny hardware | **chat**, moderation, anything with strangers |

**Both are correct. For different realms.**

- A sensor mesh of *your own* devices: HMAC. Forgery by a member is not in its threat
  model, and the chip cannot afford signatures.
- A group chat: signatures. "Who said this" is the entire point, and a laptop does not
  care about 12 ms.

### The one thing you must do NOW

**Put an `auth` discriminator in the object envelope** ([objects &
wire](objects-and-wire.md)):

```
auth : u8    ; 1 = REALM_HMAC   2 = AUTHOR_SIG
```

One byte. **Free today; a flag-day migration if omitted.** It is what makes the two
policies coexist instead of forking the format.

**Implement one, leave room for the other.** v0.1 implements `auth = 1` and *rejects*
`auth = 2` as unsupported.

---

## 3. What a profile is

A **realm profile** is just a bundle of policy choices, chosen once when a realm is
created:

```
profile "sensor-mesh"          profile "private-group"        profile "public-community"
  admission : invite             admission : invite             admission : admin-approve
  auth      : realm-hmac         auth      : author-sig         auth      : author-sig
  discovery : lan, anchor        discovery : lan, invite,       discovery : anchors, DNS,
  transport : udp (esp) / tcp                anchors                        BitTorrent
  retention : ring buffer        transport : tcp, relay         transport : udp, relay
                                 retention : keep               retention : keep + evict
```

**A profile is configuration, not code.** If a profile needs a new *mechanism*, that is
a substrate change and it must be justified as such
([substrate & tenants](substrate-and-tenants.md)). If it only needs a new *combination*,
it is free.

---

## 4. Why this is not just "make everything configurable"

Configurability is usually a smell — a way to avoid deciding. It is legitimate **here**,
and only here, because of one property:

> **The trade-offs are genuinely opposed, and the populations are genuinely different.**
> A 300 KB chip and a moderated public chat cannot be served by one choice. Not because
> we lack conviction, but because the physics and the threat models differ.

The discipline that keeps this from becoming mush:

1. **The mechanism is implemented ONCE.** Two policies must not mean two code paths that
   drift — they mean one code path with a discriminator.
2. **Every policy is written down with its DRAWBACK.** A choice whose cost is not stated
   is a choice nobody can make responsibly. (See the tables above — every row has a
   loss.)
3. **The invariants are NOT configurable.** The constitution
   ([substrate & tenants §5](substrate-and-tenants.md)) holds for every profile: objects
   are always authenticated *somehow*; content is never stored for realms you do not
   belong to; there is never a global reputation score; the core is always pure.
   **Policy chooses HOW, never WHETHER.**
4. **Default to the strictest sane profile.** Private, invite-only, no global anything.
   Opening up is a deliberate act.

---

## 5. The rule, in one line

> **Mechanism is universal. Policy is per realm. Invariants are not negotiable.**
