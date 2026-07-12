# 0001 — Realms & secure transport

- **Status:** Phase 1 **done**; Phase 2 **in progress** — ECDSA-sign gap closed
  in frank2, CA-realm membership landed; mTLS + revocation remain.
- **Depends:** Phase 2 needs frank2 **ECDSA-P256 signing** (only `Verify` exists
  in `lib/rtl/ecdsa_p256.pas`).

## Why

The 2005 Gnutella model was internet-wide-open: connect to anyone, flood the
planet. In 2026 that is a liability — scanning/abuse magnet, DDoS-amplification
vector, illegal-content relay, legal exposure. Every modern mesh (Tailscale,
Nebula, WireGuard, Nostr) abandoned it. **Pastella has no global mode. The unit
of a network is a *realm* — a network gated by a cryptographic credential.**

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

### Known follow-up (frank2, not blocking)
- **ECDSA-P256 is slow** (~1-2 s/op): naive bignum, Fermat inverse (256-bit
  modexp), bit-by-bit scalar mult. Fine for occasional auth handshakes; needs
  Montgomery/windowed mult + binary-GCD inverse before high-rate signing. Also:
  RFC-6979 deterministic nonces + constant-time hardening.
