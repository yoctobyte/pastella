# 0001 — Realms & secure transport

- **Status:** Phase 1 **done**; Phase 2 **in progress** — ECDSA-sign gap closed
  in frank2, CA-realm membership landed; mTLS + revocation remain.
- **Depends:** Phase 2 needs frank2 **ECDSA-P256 signing** (only `Verify` exists
  in `lib/rtl/ecdsa_p256.pas`).

## Why

The 2005 Gnutella model was internet-wide-open: connect to anyone, flood the
planet. In 2026 that is a liability — scanning/abuse magnet, DDoS-amplification
vector, illegal-content relay, legal exposure. Every modern mesh (Tailscale,
Nebula, WireGuard, Nostr) abandoned it. **The unit of a network is a *realm* — a
network gated by a cryptographic credential.**

> **AMENDED by [0002](0002-layering-node-topic-membership.md) (2026-07-12).** This
> ticket originally said *"Pastella has no global mode"*, and gated even DISCOVERY
> behind the realm key. That was too strong: it forbids a subject-independent
> discovery layer that every node serves for everybody, which is a thing we want.
>
> The replacement rule keeps everything this paragraph was actually protecting:
>
> > **Nodes route metadata for everyone. Nodes store content only for realms they
> > belong to.** The global layer is a **phonebook, never a filestore**.
>
> The liability that destroyed the Gnutella model attaches to **content**, not to
> **addresses** — handing out a phone number is not warehousing the goods. So a
> global *discovery* layer is safe; a global *content* mesh never was.

Two features collapse into one mechanism: *secure sockets* (transport
encryption/auth) and *membership* are the same handshake.

## Model

- **Realm identity** — a key. `realmKey = SHA-256(passphrase)` (Phase 1, PSK) or a
  realm CA keypair (Phase 2). `realmID = short hash of the realm public value`.
- **Membership grades:**
  - **PSK realm (Phase 1, this ticket)** — shared passphrase. Join = prove
    knowledge via HMAC challenge-response, without revealing the key. One leak
    burns the realm (no per-member revocation) — acceptable for personal/small
    meshes.
  - **CA realm (Phase 2)** — realm founder key = CA; members hold a cert (their
    identity pubkey signed by the CA). Per-identity, revocable. This is the right
    default beyond a friend group. **Needs ECDSA-P256 signing.**
- **Secure transport = the same credential.** Phase 1: after the PSK handshake,
  frames are AEAD-sealed (ChaCha20-Poly1305) under a per-session key derived from
  the handshake nonces. Phase 2: mutual-TLS with the realm CA as the trust root —
  one handshake gives encryption + membership + per-peer identity.
- **Tiers = per-realm policy, not code forks:**
  - `open` — no membership check (LAN/testing only; never internet-exposed)
  - `public` — anyone joins, but only signed/vouched content is persisted (needs
    Phase 2 identity)
  - `closed` — must present a valid realm credential to complete the handshake
- **Scoped, authenticated discovery** — beacons carry `realmID` + an HMAC under
  the realm key, so outsiders cannot enumerate or join. Extends the zero-seed
  beacon.
- **Trust graph operates *within* a realm** — membership is the coarse gate; the
  subjective trust-graph/`ignore` is the fine-grained intra-realm reputation.

## Phase 1 — PSK realms + sealed transport (buildable now, no ECDSA)

- [x] `src/realm.inc` — `RealmKey`/`RealmID`, CSPRNG nonces (`OSEntropyBytes`),
      `RealmHandshake` (HMAC mutual challenge-response, derives a session key),
      `SealSend`/`SealRecv` (ChaCha20-Poly1305 framed).
- [x] `src/test_realm.pas` — same-realm peers handshake + exchange sealed gossip
      and converge; wrong-passphrase peer is rejected at the handshake.
- [x] Realm-scoped authenticated discovery beacon (realmID + HMAC), outsider
      beacon rejected.

## Phase 2 — CA realms + mTLS

- [x] Add `EcdsaP256Sign` + `PubFromPriv` + `GenKey` to frank2
      `lib/rtl/ecdsa_p256.pas` (was verify-only) — the keystone. Round-trip
      tested (`test/test_ecdsa_sign.pas`). Committed to frank2.
- [x] Realm CA: founder key signs member certs; join proves cert validity AND
      key ownership (challenge-response) — replay-proof. `src/realm_ca.inc` +
      `src/test_realm_ca.pas` (legit admitted, replay rejected).
- [ ] Mutual-TLS transport (`tls13_hs` + realm CA trust root) replacing/augmenting
      the PSK sealed transport. (Or simpler: ECDH shared-secret from the member
      keys → session key, instead of PSK-derived.)
- [ ] `public`-tier content signing + trust-graph vouching.
- [ ] Revocation list gossiped in-realm.

### Known follow-up (frank2) — **ECDSA perf: DONE 2026-07-12, ~25x**

ECDSA-P256 was ~1-2 s/op: naive bignum, Fermat inverse (256-bit modexp),
bit-by-bit scalar mult. Now:

| op | before | after |
| --- | --- | --- |
| keygen | 244 ms | ~7 ms |
| sign | 257 ms | ~12 ms |
| verify | 482 ms | ~19 ms |

A realm join / mTLS handshake is no longer dominated by signature work. For
scale: the TLS *key exchange* (x25519) was always ~5-10 ms; it was the
certificate signature checks that cost half a second each.

Three steps, all in frank2:
1. **`BigDivMod` -> Knuth algorithm D** (`bac1de95`). It was picking each
   quotient limb by a 30-step binary search — a full bignum multiply per step.
   7.6x on its own; division sits under everything else.
2. **Dedicated P-256 field arithmetic** — new `lib/rtl/p256field.pas`:
   Montgomery/CIOS over four saturated 64-bit limbs, no division at all on the
   hot path. Needed a new compiler intrinsic (`__pxxmulhi_u64`, widening
   64x64->128 multiply: x86-64 `mul` / aarch64 `umulh`) so multi-precision code
   can use full 2^64 limbs instead of bignum's 1e9-per-limb radix.
3. **Euclid instead of Fermat** for the inverse mod n (`8deeb3e2`) — once the
   field was fast, that one 256-bit modexp was the biggest cost left.

Correctness held throughout: the known-answer vectors (`lib_ecdsa_p256`), the
sign/verify round-trip with tampered-message / tampered-sig / wrong-key
rejections, and the X.509 chain verify all still pass, on x86-64 and aarch64.

Still open: RFC-6979 deterministic nonces + constant-time hardening (both
security, not speed), and windowed/wNAF scalar multiplication (another ~2-4x if
ever wanted).

**ESP32 caveat.** Writing p256field flushed out three real compiler bugs, one of
which matters here: 64-bit named constants were silently TRUNCATED on the 32-bit
targets, so any crypto constant table computed garbage on i386/arm32/riscv32
while being perfect on the dev box. Fixed. But `p256field` still core-dumps on
riscv32 (frank2 ticket `bug-riscv32-p256field-coredump`), and ESP32 is
riscv32/xtensa — so realm crypto on device is not proven yet. That is the gate
for any "same protocol on a $3 chip" demo.
