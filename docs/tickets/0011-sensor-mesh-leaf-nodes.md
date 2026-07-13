# 0011 — Sensor mesh & the leaf-node role (optional tenant)

- **Status:** open — **optional as a product; load-bearing as a constraint.**
- **Depends:** [0003](0003-membership-log-and-tiers.md) (realm membership);
  frank2 `bug-riscv32-p256field-coredump` — **blocking**: realm crypto does not
  run on ESP32 yet.
- **Design:** [substrate & tenants §3, §4](../design/substrate-and-tenants.md)

## Two applications, not one

The demo is a **pair**, and the split is the whole point — same realm, same protocol,
different roles ([objects & wire](../design/objects-and-wire.md) capability flags):

| | **1. sensor reader** (ESP32) | **2. logger / viewer** (PC) |
|---|---|---|
| does | reads a sensor, publishes | collects, stores, graphs, relays |
| HELLO | `offers=yes, wants=no, serves=no` | all `yes` |
| store | **outbox** — RAM ring buffer, freed on `ACK`, decimated under pressure | **archive** — disk, forever |
| crypto | realm HMAC (no ECDSA — a chip cannot afford it) | same |

**The reading format is sensor-agnostic**: a *name tag* and a *value*. A thermometer, a
humidity sensor and a light meter differ only by a name and a unit string — so the app does
not care what is plugged in. (Format: `sensor` + `value:i64` + `scale:i8` + `unit` — integer
and decimal exponent, **no floats**, because the ESP32-C3 has no FPU and an I2C sensor hands
you an integer anyway.)

## The demo — CROSS-SITE, not LAN-only

An ESP32 (or a spare laptop) left at **each of several physical locations** — home,
work, a friend's place — each with a temperature sensor. They gossip readings into
one realm **across the internet**. Your laptop is **just another peer** that happens
to draw graphs. No broker, no MQTT server, no cloud, no pairing app, no account.

This is not the LAN demo. It is the real thing, and it is the shape the whole
substrate was designed for.

### Why it needs almost nothing

**Outbound connections traverse NAT for free.** No hole-punching, no STUN, no relay.
NAT is only a problem when *two unreachable peers* must talk directly.

So if **one** member of the realm is reachable — a home box, a laptop that stays put,
a EUR 3/month VPS — every sensor at every site simply **connects outward** to it.
Gossip flows.

- **No DHT** ([0004](0004-discovery-dht.md)).
- **No NAT traversal** ([0012](0012-nat-traversal-and-transport.md)).
- **No relays, no seeds, no global anything.**
- One reachable member is the entire answer.

That is a star topology at first, and that is fine: the anchor is a **member**,
storing its own realm's content — not a relay for strangers, not a tracker
([0013 §4](0013-bootstrap-profiles-and-rendezvous.md)). Direct peer links and
hole-punching are a later *optimisation*, never a prerequisite.

### Zero-config, honestly defined

A device must learn *something*, or it cannot tell your realm from a stranger's. What
we actually mean:

> **Configured once at pairing; never configured again.** No IP addresses, no
> per-site setup — and it survives the ISP changing your address.

The trick: **give the device a NAME, never an address.** At pairing (QR / factory
key) it receives the realm credential plus a rendezvous *name*. Then:

- home IP changes → dynamic DNS updates, the device re-resolves. Nothing to do.
- move a sensor between sites → plug it in. It phones home.
- add a sensor → pair it once.

frank2 already ships a DNS client, so this is nearly free.

**And with no domain at all:** the anchor publishes its address as an **encrypted
blob at a URL derived from the realm key**
([0013 §3](0013-bootstrap-profiles-and-rendezvous.md)) — a pastebin, GitHub Pages, an
S3 bucket. The host sees an opaque path and opaque bytes; outsiders cannot even find
the path. Zero leak, zero infrastructure of our own.

The pitch, and it is not a small one: **the same binary protocol on a $3 chip and
on a laptop.** No Go or Rust P2P stack can do this — they do not fit. It is the
one demo nobody else can copy, which is why it is the *flagship* even though the
chat demo ([0005](0005-offgrid-group-chat.md)) ships first.

## Why it earns its place even if never shipped

**It forces the `leaf` role to exist** — the piece the architecture was missing.

An ESP32 has ~300 KB of RAM. It **cannot** hold a DAG, **cannot** serve a DHT,
**cannot** keep history. It is therefore **not a smaller full node**; it is a
different *capability profile* ([substrate §4](../design/substrate-and-tenants.md)):

- bounded store — keeps what it published plus what it currently needs
- no DHT service (opts out — [0004 §1](0004-discovery-dht.md))
- no history / no back-fill — it may have missed everything before it booted
- no trusted wall clock (`created` is advisory anyway)

> **If a core algorithm requires full history or a full DAG, it is wrong for a
> leaf — and therefore wrong for the substrate.**

That constraint is a **gift**: it keeps the core small, and it is far cheaper to
honour from the start than to retrofit once every structure quietly assumes a
desktop. Designing the leaf contract early is the real deliverable here; the
weather station is the excuse.

## Shape

- **Pairing**: factory key + QR, or a button-press window. Same invite object as
  [0006](0006-bootstrap-and-reachability.md), scoped to a device — and it carries a
  rendezvous NAME, never an address.
- **Objects**: `READING` — tiny, signed, realm-scoped.
- **Retention**: ring buffer. Old readings are dropped, and that is *correct*, not
  a degradation. A late peer must not mistake a pruned tail for withheld data
  (same problem as [0010](0010-file-sharing-in-realm.md); solve once).
- **Ordering**: timestamps, lossy tolerated. No DAG. Sensor data is a stream, not
  a conversation.
- **Power**: a leaf may sleep for hours. It is an *offline peer* by design — which
  is [§7a](../design/identity-membership-discovery.md)'s problem again, arriving
  from a third direction, and further evidence it must be solved once in the core.

## The crypto budget on a chip (do not skip this)

- **Sealed datagrams are LIGHTER than HTTPS on an ESP32**, not heavier: TLS costs
  ~16–40 KB of RAM per session versus <1 KB for ours, and its per-record AEAD is the
  same work we would do anyway. See [0015 §4a](0015-udp-datagram-transport.md).
- **The real cost is ECDSA.** ~12 ms per signature on a desktop implies **~1–2 s on an
  ESP32-C3** (160 MHz, 32-bit). **Do not sign every reading.** Use a realm-key HMAC for
  readings (the chip has a SHA accelerator) and keep ECDSA for membership/certs, which
  are rare. Or batch-sign. Or use the C3/S3 **ECC accelerator**.
- **Measure before choosing.** These are estimates.

## Blocked on

`p256field` core-dumps on riscv32 (frank2 `bug-riscv32-p256field-coredump`), and
ESP32 is riscv32/xtensa. The **net** stack works on device today
(`examples/esp32/net-c3`, lwIP); the **crypto** does not.

*(Writing that library also flushed out three frank2 compiler bugs — one of which,
64-bit named constants truncated on 32-bit targets, would have made every crypto
constant silently wrong on ESP32 while passing every test on the dev box. Fixed.)*

## Acceptance

- Sensors at **two or more physical sites** (different NATs, different ISPs) gossip
  into one realm, with **no DHT, no hole-punching and no relay** — only one reachable
  member.
- The realm survives the anchor's IP changing, with no device reconfigured.
- A leaf joins a realm, publishes readings, and **never** holds a full DAG.
- The desktop node is *just a peer* — no privileged role, no server.
- Power-cycle a sensor: it rejoins and resumes without back-filling history.
- **No core change was required** — new payload type plus a policy. *(If one was,
  that is a bug against the substrate.)*
- Realm crypto (sign/verify) runs on device.
