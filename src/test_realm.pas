program test_realm;
{ REALMS + SECURE TRANSPORT (Phase 1, PSK). Two peers sharing a realm passphrase
  complete an HMAC challenge-response handshake (proving membership without
  revealing the key), derive a session key, and exchange a ChaCha20-Poly1305
  SEALED object. A peer with the WRONG passphrase is rejected at the handshake.
  Also checks realm-scoped authenticated discovery beacons (forged/foreign
  beacons rejected). See docs/tickets/0001. }

uses sysutils, sha256, chacha20poly1305, random, platform, scheduler;

{$I realm.inc}

const PORT = 35900;
var
  realmKey, wrongKey: AnsiString;
  serverGot: AnsiString;
  goodOk, badRejected, stop: Integer;

procedure IgnoreSigpipe;
var rc: Integer;
begin rc := PalIgnoreSignal(PAL_SIGPIPE); end;

{ server: handshake as responder; a member gets to deliver one sealed object }
procedure ServeConn(arg: Pointer); async;
var fd: Integer; sess, msg: AnsiString; ok, member: Boolean;
begin
  fd := Integer(PtrInt(arg)); SetNonBlocking(fd);
  member := await RealmHandshake(fd, realmKey, False, sess);
  if member then
  begin
    msg := await SealRecv(fd, sess, ok);
    if ok then serverGot := msg;
  end;
  PalClose(fd);
end;

procedure Listener(arg: Pointer); async;
var lfd, conn: Integer;
begin
  lfd := PalSocket(PAL_NET_AF_INET, PAL_NET_SOCK_STREAM, 0);
  PalSetSocketReuseAddr(lfd, 1);
  PalBindIpv4(lfd, PAL_NET_IP_LOOPBACK, PORT);
  PalListen(lfd, 8); SetNonBlocking(lfd);
  while stop = 0 do
    if WaitReadableTimeout(lfd, 120) then
    begin conn := PalAccept(lfd); if conn >= 0 then Spawn(@ServeConn, Pointer(PtrInt(conn))); end;
  PalClose(lfd);
end;

{ good peer: correct realm key -> handshake ok -> send a sealed object }
procedure GoodPeer(arg: Pointer); async;
var fd: Integer; sess: AnsiString;
begin
  CoSleep(200);
  fd := PalSocket(PAL_NET_AF_INET, PAL_NET_SOCK_STREAM, 0); SetNonBlocking(fd);
  PalConnectIpv4(fd, PAL_NET_IP_LOOPBACK, PORT); WaitWritable(fd);
  if await RealmHandshake(fd, realmKey, True, sess) then
  begin
    goodOk := 1;
    await SealSend(fd, sess, 'secret-object-in-realm');
  end;
  PalClose(fd);
end;

{ impostor: wrong realm key -> handshake must fail -> rejected }
procedure BadPeer(arg: Pointer); async;
var fd: Integer; sess: AnsiString;
begin
  CoSleep(500);
  fd := PalSocket(PAL_NET_AF_INET, PAL_NET_SOCK_STREAM, 0); SetNonBlocking(fd);
  PalConnectIpv4(fd, PAL_NET_IP_LOOPBACK, PORT); WaitWritable(fd);
  if not await RealmHandshake(fd, wrongKey, True, sess) then
    badRejected := 1;
  PalClose(fd);
end;

procedure Watchdog(arg: Pointer); begin CoSleep(1400); stop := 1; end;

{ --- beacon checks (pure, no network) --- }
function Tamper(const s: AnsiString): AnsiString;
var t: AnsiString;
begin
  t := s;
  if Length(t) > 0 then
    if t[Length(t)] = 'a' then t[Length(t)] := 'b' else t[Length(t)] := 'a';
  Tamper := t;
end;

var beaconOk, beaconForeignRej, beaconForgeRej, port: Integer; b: AnsiString;
begin
  IgnoreSigpipe;
  realmKey := RealmKey('correct horse battery staple');
  wrongKey := RealmKey('hunter2');
  serverGot := ''; goodOk := 0; badRejected := 0; stop := 0;

  { beacon: valid accepted, foreign-realm rejected, forged MAC rejected }
  b := RealmBeacon(realmKey, 4321);
  beaconOk := 0; beaconForeignRej := 0; beaconForgeRej := 0;
  if BeaconValid(realmKey, b, port) and (port = 4321) then beaconOk := 1;
  if not BeaconValid(wrongKey, b, port) then beaconForeignRej := 1;
  if not BeaconValid(realmKey, Tamper(b), port) then beaconForgeRej := 1;

  Spawn(@Listener, nil);
  Spawn(@GoodPeer, nil);
  Spawn(@BadPeer, nil);
  Spawn(@Watchdog, nil);
  RunUntilDone;

  WriteLn('member handshake ok=', goodOk, '  impostor rejected=', badRejected);
  WriteLn('sealed object at server="', serverGot, '"');
  WriteLn('beacon valid=', beaconOk, ' foreign-rejected=', beaconForeignRej, ' forge-rejected=', beaconForgeRej);
  if (goodOk = 1) and (badRejected = 1) and (serverGot = 'secret-object-in-realm')
     and (beaconOk = 1) and (beaconForeignRej = 1) and (beaconForgeRej = 1) then
    WriteLn('REALM + SECURE TRANSPORT OK')
  else
    WriteLn('FAIL');
end.
