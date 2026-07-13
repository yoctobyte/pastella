# 0015 — UDP datagram transport (the v0.2 path)

- **Status:** open — **not v0.1.** This is what unlocks hole-punching *and* ESP32.
- **Depends:** [0012](0012-nat-traversal-and-transport.md) (why UDP at all).
- **Not needed for** [0014](0014-v0.1-two-laptops.md): v0.1 is TCP + one reachable
  laptop, and stays that way.

---

## 1. Why UDP, restated in one line

Not because hole-punching succeeds more often. Because of **what the third party has
to be** ([0012](0012-nat-traversal-and-transport.md)):

| transport | the third party is | it costs |
|---|---|---|
| **TCP** | a **RELAY** — carries every byte, forever | bandwidth; and it sees volume + timing |
| **UDP** | a **RENDEZVOUS** — helps both sides learn their mapped addresses, then **the data goes direct** | ~nothing |

UDP is also what lets an **ESP32** participate (lwIP UDP is trivial) and it reuses the
socket the LAN beacons already use.

## 2. Do NOT rebuild TCP

The instinct is to tunnel a reliable, ordered byte-stream over UDP. **Resist it.** Look
at what gossip actually needs:

- **Objects are content-addressed** → a duplicate delivery is *harmless* (same hash,
  same object, stored once).
- **Anti-entropy is already a reliability layer** → a lost `DATA` is re-offered by the
  next `HAVE` round. **The protocol self-heals by construction.** That is what
  anti-entropy *is*.
- **Order is irrelevant** → objects are independent and self-verifying. There is no
  head-of-line anything.

> **We need "get this across, probably, eventually." The gossip loop does the rest.**

Rebuilding TCP means paying for guarantees the application then throws away. If you
find yourself writing congestion control and sequence numbers to carry 200 bytes a
minute, **you have rebuilt TCP for a sensor mesh.**

## 3. The good news: the crypto is already datagram-shaped

`src/realm.inc` today:

```pascal
procedure SealSend(fd: Integer; const sessionKey, plain: AnsiString); async;
begin
  nonce := RandNonce(12);
  ct := Chacha20Poly1305Seal(sessionKey, nonce, '', plain);
  await RSendFrame(fd, nonce + ct);         { <-- only THIS is TCP }
end;
```

That is **per-message AEAD with its own nonce** — not a stream cipher, not TLS. Each
message is already independently encrypted and authenticated. **Only the framing is
TCP.** Swap `RSendFrame` for a `sendto` and the crypto works unchanged.

### And TCP never gave us authentication

Worth stating plainly, because it is the thing that makes this cheap:
**authentication was always ours.** `RealmHandshake` is an HMAC challenge-response
that derives a session key. TLS certificates are not in the peer-to-peer path at all —
they belong to *bootstrap fetches over HTTPS*
([0013](0013-bootstrap-profiles-and-rendezvous.md)), which stay TCP and are unaffected.

**TCP gave us a SESSION, not authentication.** So moving to UDP is not a crypto
redesign; it is re-adding the three things a session was quietly providing (§4).

## 4. What UDP actually costs — the whole list

**1. Replay protection.** TCP's sequencing made replay impossible for free. Over UDP,
a captured sealed datagram can simply be re-sent, and it will decrypt perfectly.

- Make the nonce a **counter**, not random.
- Keep a **sliding replay window** — a 64-bit bitmap of recently-seen counters. Reject
  anything too old or already seen.
- ~30 lines. Textbook.

**2. Session identity.** TCP's 4-tuple *was* the session. Add a **connection ID** to
the cleartext header.

Cheap, and it buys something TCP cannot do: **the session survives an IP change**,
because only the real peer can produce a valid AEAD tag. (QUIC's connection migration.)
That is exactly what a laptop moving between wifi networks needs.

**3. Handshake retransmission.** The 2–3 handshake messages *are* a strict sequence and
do need ordering + retry. But that is a tiny state machine — send, wait, resend on
timeout, dedupe — **not a general reliability layer**.

**4. Keepalives — every ~20 s.** UDP NAT mappings expire in **30–120 s** (TCP's last far
longer). Without keepalives the hole closes silently. **This is the detail that bites
everyone doing UDP for the first time.**

**5. Anti-amplification.** Cookie under load + never send more than **3× the bytes
received** from an unvalidated address, before address validation. Mandatory, cheap,
already the design's invariant.

### The packet

```
cleartext : connID (8B) | counter (8B)
sealed    : Chacha20Poly1305(sessionKey, nonce=counter, aad=header, payload)
```

Keep datagrams **≤ 1200 bytes** — no fragmentation, no PMTU discovery, no games.

**That is the entire list.** Datagram framing · counter nonce · replay window ·
connection ID · handshake retransmit · keepalive · cookie. **This is WireGuard's
design**, and it is a few hundred lines. Not TLS, not QUIC.

## 4a. ESP32: sealed datagrams are LIGHTER than HTTPS, not heavier

The IDF supports HTTPS, so it is tempting to think per-packet AEAD is the expensive
option. **It is the other way round.**

TLS is **handshake (asymmetric + certificate parsing) + per-record AEAD**. That
per-record AEAD is *exactly the work we would be doing anyway*. Using HTTPS does not
save the symmetric crypto — it **adds** a handshake and a large buffer on top of it.

On a ~300 KB chip, the buffer is decisive:

| | RAM per session | handshake |
|---|---|---|
| **mbedTLS / HTTPS** | **~16–40 KB** (record buffers, cert chain) | RSA/ECDSA + cert parsing |
| **sealed datagrams (ours)** | **< 1 KB** (session key + replay window) | HMAC challenge-response |

An ESP32 can afford *one or two* TLS sessions. It can afford **dozens** of ours. For a
gossip node with several peers that is not a tuning detail — it is work-or-not-work.

**And the symmetric crypto is noise.** ChaCha20-Poly1305 in software on a C3 runs at a
few MB/s; a reading is a few hundred bytes, every 30 s. Sealing 1 KB costs on the order
of a **millisecond**. It only becomes interesting if file transfer lands (§5, Phase 2).

## 4b. The REAL ESP32 cost is ASYMMETRIC crypto — signing every object

This is the one that will actually hurt, and it is easy to miss.

**ECDSA-P256 signing is ~12 ms on a desktop** (after frank2's 25x work). An ESP32-C3 is
~160 MHz, 32-bit, no 64-bit registers — expect **~1–2 seconds per signature**. If every
reading is individually signed, **the chip spends its life signing.**

Options, in order of preference:

1. **Symmetric MAC for readings.** Authenticate objects with the *realm key*
   (HMAC-SHA256 — fast, and the ESP32 has a **SHA accelerator**). You lose per-author
   attribution *inside* the realm — but for a sensor mesh, *"this came from a realm
   member"* is usually all that is wanted. **Reserve ECDSA for membership/certs**,
   which are rare.
2. **Batch-sign.** One signed object covering N readings, rather than N signatures.
3. **The ESP32-C3/S3 ECC accelerator** — hardware P-256 point multiplication. Cheap
   ECDSA, but it means PAL hooks into IDF, and it is chip-specific.

> **MEASURE FIRST.** The numbers above are estimates. The difference between 200 ms and
> 2 s changes the answer — but the *design* conclusion already holds: keep the sealed
> datagrams; do not ECDSA-sign every reading on a chip.

## 5. Phasing

**Phase 1 — sensors and chat: no ARQ at all.**
A reading is a few hundred bytes; a `HAVE` list is a few hundred. **Everything fits in
one datagram.** Lost? Re-offered next round. Duplicate? Idempotent. Reordered?
Irrelevant. **Almost no code beyond §4.**

**Phase 2 — only when an object exceeds an MTU** (files, big blobs). *Then* add
fragmentation + selective retransmit of missing fragments. Real ARQ, but scoped to a
single object transfer, not a general stream. **This is the only place that cost is
paid, and it is paid only if [0010](0010-file-sharing-in-realm.md) happens.**

Congestion control: at sensor/chat rates, pacing is enough. If Phase 2 lands, be a good
citizen — LEDBAT-style (µTP) background-friendly control, not a greedy loop.

## 6. Why this is unusually safe for us to build

The reliability/replay logic lives in the **pure core**
([architecture](../design/architecture.md)), so it can be tested against a **simulated
lossy, reordering, duplicating network — deterministically**, in memory, with no
sockets.

Most projects cannot do this, and end up debugging retransmit storms in production. We
can fuzz it. **That is the "protocol = pure functions" rule paying rent.**

## 7. Acceptance

- Two nodes gossip over UDP; killing 30% of datagrams at random still converges (the
  gossip loop *is* the reliability layer — prove it).
- A replayed datagram is **rejected** (replay window works).
- A node whose IP changes mid-session **keeps the session** (connection ID works).
- A NAT mapping stays open across an idle hour (keepalives work).
- **Amplification, tested with forged source addresses:** an unvalidated source cannot
  make a node emit more than 3× what it sent.
- Two peers behind ordinary NATs connect **directly**, with the rendezvous carrying no
  data.
- The same code runs on ESP32 (lwIP UDP) — *once frank2's riscv32 backend is fixed;
  that is not our problem here.*
