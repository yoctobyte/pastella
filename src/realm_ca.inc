{ realm_ca.inc — CA-realm membership (ticket 0001 Phase 2).
  A realm CA (an ECDSA-P256 keypair) signs member certificates. To join, a member
  proves BOTH:
    (a) the CA vouched for its identity  — cert is a CA signature over
        (realmID + memberPub), and
    (b) it actually owns that identity   — it signs a fresh challenge nonce with
        its own private key (defeats replay of someone else's cert).
  Per-identity + revocable (drop a memberPub from an in-realm revocation list),
  unlike the flat PSK realm.

  Include AFTER realm.inc (uses its RSendFrame/RRecvFrame/RandNonce) and with:
    uses sysutils, sha256, ecdsa_p256, chacha20poly1305, random, platform, scheduler; }

function CaRealmID(const caPub: AnsiString): AnsiString;
begin CaRealmID := Copy(Sha256Hex(caPub), 1, 16); end;

{ CA issues a membership cert: signature over realmID+memberPub }
function IssueCert(const caPriv, realmID, memberPub: AnsiString): AnsiString;
begin IssueCert := EcdsaP256Sign(caPriv, realmID + memberPub); end;

function CertValid(const caPub, realmID, memberPub, cert: AnsiString): Boolean;
begin CertValid := EcdsaP256Verify(caPub, realmID + memberPub, cert); end;

{ member side: answer the peer's challenge with (pub, cert, ownership-proof) }
function CaProve(fd: Integer; const memberPriv, memberPub, cert: AnsiString): Boolean; async;
var nonce, proof: AnsiString;
begin
  CaProve := False;
  nonce := await RRecvFrame(fd);                 { peer challenge }
  if Length(nonce) < 16 then Exit;
  proof := EcdsaP256Sign(memberPriv, nonce);     { prove ownership of memberPub }
  await RSendFrame(fd, memberPub + cert + proof);        { 64 + 64 + 64 }
  CaProve := True;
end;

{ peer side: challenge, then admit iff CA vouched AND key ownership proven }
function CaAdmit(fd: Integer; const caPub, realmID: AnsiString; var memberPub: AnsiString): Boolean; async;
var nonce, resp, cert, proof: AnsiString;
begin
  CaAdmit := False; memberPub := '';
  nonce := RandNonce(16);
  await RSendFrame(fd, nonce);
  resp := await RRecvFrame(fd);
  if Length(resp) < 192 then Exit;
  memberPub := Copy(resp, 1, 64);
  cert      := Copy(resp, 65, 64);
  proof     := Copy(resp, 129, 64);
  if not CertValid(caPub, realmID, memberPub, cert) then Exit;   { CA did not vouch }
  if not EcdsaP256Verify(memberPub, nonce, proof) then Exit;     { does not own key (replay) }
  CaAdmit := True;
end;
