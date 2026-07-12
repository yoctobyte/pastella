program test_realm_ca;
{ CA-REALM MEMBERSHIP (ticket 0001 Phase 2 — uses the new ECDSA-P256 signing).
  A realm CA issues member A a certificate. On join, a peer must prove BOTH cert
  validity (CA vouched) AND key ownership (sign a fresh challenge). Cases:
    - legit member A -> admitted
    - REPLAY attacker: presents A's pub+cert but signs the nonce with its OWN
      key -> ownership proof fails -> rejected.
  Completion-based (the listener serves exactly N connections then stops) so the
  slow bignum ECDSA never races a wall-clock watchdog. NOTE: P-256 here is naive
  bignum (~1-2s/op) — a frank2 perf follow-up; correctness only for this test. }

uses sysutils, sha256, ecdsa_p256, chacha20poly1305, random, platform, scheduler;

{$I realm.inc}
{$I realm_ca.inc}

const PORT = 35950; EXPECTED = 2;
var
  caPriv, caPub, realmID: AnsiString;
  mAPriv, mAPub, mACert: AnsiString;   { legit member A }
  mXPriv, mXPub, mXCert: AnsiString;   { attacker's own key }
  admitted, admittedTotal, served: Integer;

procedure IgnoreSigpipe;
const SYS_rt_sigaction=13; SIGPIPE=13; SIG_IGN=1;
var act: array[0..3] of Int64; rc: Int64;
begin act[0] := SIG_IGN; act[1] := 0; act[2] := 0; act[3] := 0;
  rc := __pxxrawsyscall(SYS_rt_sigaction,SIGPIPE,Int64(@act[0]),0,8,0,0); end;

procedure ServeConn(arg: Pointer); async;
var fd: Integer; who: AnsiString;
begin
  fd := Integer(PtrInt(arg)); SetNonBlocking(fd);
  if await CaAdmit(fd, caPub, realmID, who) then
  begin
    admittedTotal := admittedTotal + 1;
    if who = mAPub then admitted := admitted + 1;
  end;
  PalClose(fd);
  served := served + 1;
end;

procedure Listener(arg: Pointer); async;
var lfd, conn, got: Integer;
begin
  lfd := PalSocket(PAL_NET_AF_INET, PAL_NET_SOCK_STREAM, 0);
  PalSetSocketReuseAddr(lfd, 1); PalBindIpv4(lfd, PAL_NET_IP_LOOPBACK, PORT);
  PalListen(lfd, 8); SetNonBlocking(lfd);
  got := 0;
  while got < EXPECTED do
  begin
    WaitReadable(lfd);
    conn := PalAccept(lfd);
    if conn >= 0 then begin Spawn(@ServeConn, Pointer(PtrInt(conn))); got := got + 1; end;
  end;
  PalClose(lfd);
end;

function Dial: Integer; async;
var fd: Integer;
begin
  fd := PalSocket(PAL_NET_AF_INET, PAL_NET_SOCK_STREAM, 0); SetNonBlocking(fd);
  PalConnectIpv4(fd, PAL_NET_IP_LOOPBACK, PORT); WaitWritable(fd);
  Dial := fd;
end;

procedure GoodMember(arg: Pointer); async;      { valid cert + owns key }
var fd: Integer;
begin CoSleep(100); fd := await Dial; await CaProve(fd, mAPriv, mAPub, mACert); PalClose(fd); end;

procedure ReplayPeer(arg: Pointer); async;      { A's identity, attacker's signature }
var fd: Integer;
begin CoSleep(150); fd := await Dial; await CaProve(fd, mXPriv, mAPub, mACert); PalClose(fd); end;

begin
  IgnoreSigpipe;
  EcdsaP256GenKey(caPriv, caPub); realmID := CaRealmID(caPub);
  EcdsaP256GenKey(mAPriv, mAPub); mACert := IssueCert(caPriv, realmID, mAPub);
  EcdsaP256GenKey(mXPriv, mXPub);
  admitted := 0; admittedTotal := 0; served := 0;

  Spawn(@Listener, nil);
  Spawn(@GoodMember, nil);
  Spawn(@ReplayPeer, nil);
  RunUntilDone;

  WriteLn('admitted(legit)=', admitted, ' admitted(total)=', admittedTotal,
          ' served=', served, ' (expect legit=1 total=1 — replay rejected)');
  if (admitted = 1) and (admittedTotal = 1) then WriteLn('CA-REALM MEMBERSHIP OK') else WriteLn('FAIL');
end.
