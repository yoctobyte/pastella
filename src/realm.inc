{ realm.inc — PSK realm membership + AEAD-sealed transport over the reactor.
  See docs/tickets/0001-realms-and-secure-transport.md (Phase 1).

  Include after:
    uses sysutils, sha256, chacha20poly1305, random, platform, scheduler;

  Provides:
    RealmKey/RealmID          — derive a 32-byte realm key + short public id
    RealmBeacon/BeaconValid   — realm-scoped authenticated discovery beacon
    RealmHandshake            — mutual HMAC challenge-response; proves both sides
                                know the realm key WITHOUT revealing it, and
                                derives a per-session key
    SealSend/SealRecv         — ChaCha20-Poly1305 framed messages on the session

  No ECDSA needed (PSK tier). CA-realm / mTLS is Phase 2 (blocked on frank2
  ECDSA-sign). }

function RealmKey(const passphrase: AnsiString): AnsiString;
begin RealmKey := Sha256(passphrase); end;                 { 32 bytes }

function RealmID(const realmKey: AnsiString): AnsiString;
begin RealmID := Copy(Sha256Hex(realmKey), 1, 16); end;    { public 16-hex id }

function RandNonce(n: Integer): AnsiString;
var buf: AnsiString;
begin
  SetLength(buf, n);
  if not OSEntropyBytes(@buf[1], n) then
    buf := Copy(Sha256(RealmID(IntToStr(n)) + IntToStr(n)), 1, n);   { fallback }
  RandNonce := buf;
end;

{ --- plaintext framing (handshake messages) --- }
procedure RSendFrame(fd: Integer; const s: AnsiString); async;
var hdr: AnsiString; off, tot, L: Integer; n: Int64;
begin
  L := Length(s);
  hdr := Chr((L shr 24)and 255)+Chr((L shr 16)and 255)+Chr((L shr 8)and 255)+Chr(L and 255)+s;
  off := 0; tot := Length(hdr);
  while off < tot do
  begin WaitWritable(fd); n := PalSend(fd, @hdr[off+1], tot-off);
    if n <= 0 then Exit; off := off + Integer(n); end;
end;

function RRecvExact(fd, count: Integer): AnsiString; async;
var buf: AnsiString; got: Integer; n: Int64;
begin
  SetLength(buf, count); got := 0;
  while got < count do
  begin if not WaitReadableTimeout(fd, 4000) then Break;
    n := PalRecv(fd, @buf[got+1], count-got); if n <= 0 then Break; got := got + Integer(n); end;
  SetLength(buf, got); RRecvExact := buf;
end;

function RRecvFrame(fd: Integer): AnsiString; async;
var h: AnsiString; L: Integer;
begin
  h := await RRecvExact(fd, 4);
  if Length(h) < 4 then begin RRecvFrame := ''; Exit; end;
  L := (Ord(h[1])shl 24)or(Ord(h[2])shl 16)or(Ord(h[3])shl 8)or Ord(h[4]);
  RRecvFrame := await RRecvExact(fd, L);
end;

{ --- realm-scoped authenticated discovery beacon ---
  A beacon proves realm membership to listeners without a round-trip: it carries
  the realmID + the sender's TCP port + an HMAC over both under the realm key.
  An outsider (wrong key) cannot forge a valid MAC, so its beacon is ignored. }
function RealmBeacon(const realmKey: AnsiString; tcpPort: Integer): AnsiString;
var body: AnsiString;
begin
  body := RealmID(realmKey) + ' ' + IntToStr(tcpPort);
  RealmBeacon := body + ' ' + Copy(Sha256Hex(HmacSha256(realmKey, body)), 1, 16);
end;

function BeaconValid(const realmKey, beacon: AnsiString; var tcpPort: Integer): Boolean;
var p1, p2, code: Integer; rid, portS, mac, body: AnsiString;
begin
  BeaconValid := False;
  p1 := Pos(' ', beacon); if p1 < 1 then Exit;
  rid := Copy(beacon, 1, p1-1);
  if rid <> RealmID(realmKey) then Exit;                 { different realm }
  body := Copy(beacon, p1+1, Length(beacon)-p1);
  p2 := Pos(' ', body); if p2 < 1 then Exit;
  portS := Copy(body, 1, p2-1); mac := Copy(body, p2+1, Length(body)-p2);
  if mac <> Copy(Sha256Hex(HmacSha256(realmKey, rid + ' ' + portS)), 1, 16) then Exit;  { forged }
  Val(portS, tcpPort, code); if code <> 0 then Exit;
  BeaconValid := True;
end;

{ --- mutual membership handshake ---
  Proves both peers know realmKey without sending it; derives sessionKey. Wrong
  key => a proof mismatches => False (caller drops the connection). }
function RealmHandshake(fd: Integer; const realmKey: AnsiString; initiator: Boolean;
                        var sessionKey: AnsiString): Boolean; async;
var nonceA, nonceB, reply, proofB, proofA: AnsiString;
begin
  RealmHandshake := False; sessionKey := '';
  if initiator then
  begin
    nonceA := RandNonce(16);
    await RSendFrame(fd, nonceA);
    reply := await RRecvFrame(fd);                { proofB(32) + nonceB(16) }
    if Length(reply) < 48 then Exit;
    proofB := Copy(reply, 1, 32); nonceB := Copy(reply, 33, 16);
    if proofB <> HmacSha256(realmKey, nonceA) then Exit;   { peer failed proof }
    await RSendFrame(fd, HmacSha256(realmKey, nonceB));
  end
  else
  begin
    nonceA := await RRecvFrame(fd);
    if Length(nonceA) < 16 then Exit;
    nonceB := RandNonce(16);
    await RSendFrame(fd, HmacSha256(realmKey, nonceA) + nonceB);
    proofA := await RRecvFrame(fd);
    if proofA <> HmacSha256(realmKey, nonceB) then Exit;    { peer failed proof }
  end;
  sessionKey := HmacSha256(realmKey, nonceA + nonceB);      { shared 32-byte key }
  RealmHandshake := True;
end;

{ --- sealed transport (ChaCha20-Poly1305 per frame; 12-byte random nonce) --- }
procedure SealSend(fd: Integer; const sessionKey, plain: AnsiString); async;
var nonce, ct: AnsiString;
begin
  nonce := RandNonce(12);
  ct := Chacha20Poly1305Seal(sessionKey, nonce, '', plain);
  await RSendFrame(fd, nonce + ct);
end;

function SealRecv(fd: Integer; const sessionKey: AnsiString; var ok: Boolean): AnsiString; async;
var f, nonce, ct, plain: AnsiString;
begin
  ok := False; SealRecv := '';
  f := await RRecvFrame(fd);
  if Length(f) < 12 then Exit;
  nonce := Copy(f, 1, 12); ct := Copy(f, 13, Length(f)-12);
  if Chacha20Poly1305Open(sessionKey, nonce, '', ct, plain) then
  begin ok := True; SealRecv := plain; end;
end;
