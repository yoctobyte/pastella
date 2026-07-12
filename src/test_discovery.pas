program test_discovery;
{ ZERO-SEED AUTO-BOOTSTRAP. K nodes start knowing NO peers. Each broadcasts a
  UDP beacon (its TCP port) on a well-known discovery port; each hears the others
  and dials them. No seed list, no bootstrap node — the network assembles itself,
  then content-addressed gossip converges. Coroutine reactor, single process. }

uses sysutils, sha256, platform, scheduler;

const
  K      = 5;
  DP     = 34999;      { well-known discovery port (UDP broadcast) }
  TBASE  = 35200;      { node i TCP-listens on TBASE+i }
  ROUNDS = 12;
  SOL_SOCKET = 1; SO_BROADCAST = 6; SO_REUSEPORT = 15;

type
  TItem = record hash, data: AnsiString; end;
  TItemArr = array of TItem;
  TIntArr  = array of Integer;

var
  nstore : array[0..K-1] of TItemArr;
  peers  : array[0..K-1] of TIntArr;    { discovered peer TCP ports, per node }
  stop   : Integer;
  LB_BCAST: LongWord;

function HashOf(const d: AnsiString): AnsiString; begin HashOf := Sha256Hex(Sha256(d)); end;

function NHas(ni: Integer; const h: AnsiString): Boolean;
var i: Integer; begin NHas := False;
  for i := 0 to High(nstore[ni]) do if nstore[ni][i].hash = h then NHas := True; end;

procedure NPut(ni: Integer; const data: AnsiString);
var n: Integer; begin
  if data = '' then Exit; if NHas(ni, HashOf(data)) then Exit;
  n := Length(nstore[ni]); SetLength(nstore[ni], n+1);
  nstore[ni][n].hash := HashOf(data); nstore[ni][n].data := data; end;

function NGet(ni: Integer; const h: AnsiString): AnsiString;
var i: Integer; begin NGet := '';
  for i := 0 to High(nstore[ni]) do if nstore[ni][i].hash = h then NGet := nstore[ni][i].data; end;

function NHave(ni: Integer): AnsiString;
var i: Integer; begin NHave := '';
  for i := 0 to High(nstore[ni]) do begin
    if i > 0 then NHave := NHave + #10; NHave := NHave + nstore[ni][i].hash; end; end;

function KnowsPeer(ni, port: Integer): Boolean;
var i: Integer; begin KnowsPeer := False;
  for i := 0 to High(peers[ni]) do if peers[ni][i] = port then KnowsPeer := True; end;

procedure AddPeer(ni, port: Integer);
var n: Integer; begin
  if (port = TBASE+ni) or KnowsPeer(ni, port) then Exit;
  n := Length(peers[ni]); SetLength(peers[ni], n+1); peers[ni][n] := port; end;

{ --- framed TCP I/O --- }
procedure SendFrame(fd: Integer; const s: AnsiString); async;
var hdr: AnsiString; off, tot, L: Integer; n: Int64; begin
  L := Length(s);
  hdr := Chr((L shr 24)and 255)+Chr((L shr 16)and 255)+Chr((L shr 8)and 255)+Chr(L and 255)+s;
  off := 0; tot := Length(hdr);
  while off < tot do begin WaitWritable(fd); n := PalSend(fd, @hdr[off+1], tot-off);
    if n <= 0 then Exit; off := off + Integer(n); end; end;

function RecvExact(fd, count: Integer): AnsiString; async;
var buf: AnsiString; got: Integer; n: Int64; begin
  SetLength(buf, count); got := 0;
  while got < count do begin if not WaitReadableTimeout(fd, 3000) then Break;
    n := PalRecv(fd, @buf[got+1], count-got); if n <= 0 then Break; got := got + Integer(n); end;
  SetLength(buf, got); RecvExact := buf; end;

function RecvFrame(fd: Integer): AnsiString; async;
var h: AnsiString; L: Integer; begin
  h := await RecvExact(fd, 4); if Length(h) < 4 then begin RecvFrame := ''; Exit; end;
  L := (Ord(h[1])shl 24)or(Ord(h[2])shl 16)or(Ord(h[3])shl 8)or Ord(h[4]); RecvFrame := await RecvExact(fd, L); end;

function WantFrom(ni: Integer; const have: AnsiString): AnsiString;
var i, start: Integer; line, want: AnsiString; begin want := ''; start := 1;
  for i := 1 to Length(have)+1 do
    if (i > Length(have)) or (have[i] = #10) then begin
      line := Copy(have, start, i-start);
      if (line <> '') and (not NHas(ni, line)) then begin
        if want <> '' then want := want + #10; want := want + line; end;
      start := i+1; end;
  WantFrom := want; end;

function CountLines(const s: AnsiString): Integer;
var i, c: Integer; begin if s = '' then begin CountLines := 0; Exit; end;
  c := 1; for i := 1 to Length(s) do if s[i] = #10 then c := c + 1; CountLines := c; end;

procedure ServeWants(ni, fd: Integer; const w: AnsiString); async;
var i, start: Integer; line: AnsiString; begin start := 1;
  for i := 1 to Length(w)+1 do
    if (i > Length(w)) or (w[i] = #10) then begin
      line := Copy(w, start, i-start); if line <> '' then await SendFrame(fd, NGet(ni, line)); start := i+1; end; end;

function Pack(ni, fd: Integer): Pointer; begin Pack := Pointer(PtrInt(ni*65536 + fd)); end;

procedure ServeConn(arg: Pointer); async;
var v, fd, ni, i, nwant: Integer; phave, pwant, mywant, data: AnsiString; begin
  v := Integer(PtrInt(arg)); ni := v div 65536; fd := v mod 65536; SetNonBlocking(fd);
  phave := await RecvFrame(fd);                 { 1 peer HAVE }
  await SendFrame(fd, NHave(ni));               { 2 my HAVE }
  pwant := await RecvFrame(fd); await ServeWants(ni, fd, pwant);   { 3 serve peer WANT }
  mywant := WantFrom(ni, phave); nwant := CountLines(mywant); await SendFrame(fd, mywant);  { 4 my WANT }
  for i := 1 to nwant do begin data := await RecvFrame(fd); NPut(ni, data); end;            { 5 my DATA }
  PalClose(fd); end;

procedure GossipOnce(ni, peerPort: Integer); async;
var fd, i, nwant: Integer; phave, mywant, pwant, data: AnsiString; begin
  fd := PalSocket(PAL_NET_AF_INET, PAL_NET_SOCK_STREAM, 0); SetNonBlocking(fd);
  PalConnectIpv4(fd, PAL_NET_IP_LOOPBACK, peerPort); WaitWritable(fd);
  await SendFrame(fd, NHave(ni));                { 1 }
  phave := await RecvFrame(fd);                  { 2 }
  mywant := WantFrom(ni, phave); nwant := CountLines(mywant); await SendFrame(fd, mywant);  { 3 }
  for i := 1 to nwant do begin data := await RecvFrame(fd); NPut(ni, data); end;
  pwant := await RecvFrame(fd); await ServeWants(ni, fd, pwant);   { 4 }
  PalClose(fd); end;

procedure TcpListener(arg: Pointer); async;
var ni, lfd, conn: Integer; begin ni := Integer(PtrInt(arg));
  lfd := PalSocket(PAL_NET_AF_INET, PAL_NET_SOCK_STREAM, 0);
  PalSetSocketReuseAddr(lfd, 1); PalBindIpv4(lfd, PAL_NET_IP_LOOPBACK, TBASE+ni);
  PalListen(lfd, 16); SetNonBlocking(lfd);
  while stop = 0 do
    if WaitReadableTimeout(lfd, 150) then begin
      conn := PalAccept(lfd); if conn >= 0 then Spawn(@ServeConn, Pack(ni, conn)); end;
  PalClose(lfd); end;

{ broadcast my TCP port on the discovery port }
procedure Beacon(arg: Pointer); async;
var ni, sock, one, r: Integer; msg: AnsiString; begin ni := Integer(PtrInt(arg));
  sock := PalSocket(PAL_NET_AF_INET, PAL_NET_SOCK_DGRAM, 0);
  one := 1; PalSetSockOpt(sock, SOL_SOCKET, SO_BROADCAST, @one, 4);
  msg := 'PAS ' + IntToStr(TBASE+ni);
  for r := 1 to ROUNDS do begin
    PalSendToIpv4(sock, @msg[1], Length(msg), LB_BCAST, DP);
    CoSleep(150); end;
  PalClose(sock); end;

{ hear beacons, learn peers, and gossip with each known peer every round }
procedure DiscoAndGossip(arg: Pointer); async;
var ni, sock, one, pr, pa, pp, port, i, code: Integer; buf: array[0..63] of Byte; n: Int64; s: AnsiString; begin
  ni := Integer(PtrInt(arg));
  sock := PalSocket(PAL_NET_AF_INET, PAL_NET_SOCK_DGRAM, 0);
  PalSetSocketReuseAddr(sock, 1); one := 1; PalSetSockOpt(sock, SOL_SOCKET, SO_REUSEPORT, @one, 4);
  PalBindIpv4(sock, 0, DP); SetNonBlocking(sock);
  while stop = 0 do
  begin
    { drain any beacons }
    if WaitReadableTimeout(sock, 120) then
    begin
      pa := 0; pp := 0; n := PalRecvFromIpv4(sock, @buf[0], 64, pa, pp);
      if n > 4 then begin
        s := ''; for i := 0 to Integer(n)-1 do s := s + Chr(buf[i]);
        if Copy(s,1,4) = 'PAS ' then begin
          Val(Copy(s,5,Length(s)-4), port, code);
          if code = 0 then AddPeer(ni, port);
        end;
      end;
    end;
    { gossip with everyone we know }
    for i := 0 to High(peers[ni]) do await GossipOnce(ni, peers[ni][i]);
  end;
  PalClose(sock); end;

procedure Watchdog(arg: Pointer); async;
begin CoSleep(ROUNDS*160 + 800); stop := 1; end;

{ Ignore SIGPIPE — a peer that closes mid-exchange must not kill us; PalSend
  then just returns an error and we move on. (x86-64 rt_sigaction, SIG_IGN.) }
procedure IgnoreSigpipe;
const SYS_rt_sigaction = 13; SIGPIPE = 13; SIG_IGN = 1;
var act: array[0..3] of Int64; rc: Int64;
begin
  act[0] := SIG_IGN; act[1] := 0; act[2] := 0; act[3] := 0;
  rc := __pxxrawsyscall(SYS_rt_sigaction, SIGPIPE, Int64(@act[0]), 0, 8, 0, 0);
end;

var i, conv, total: Integer;
begin
  IgnoreSigpipe;
  LB_BCAST := (127 shl 24) or (255 shl 16) or (255 shl 8) or 255;
  for i := 0 to K-1 do NPut(i, 'seed-object-' + IntToStr(i));
  stop := 0;

  for i := 0 to K-1 do begin
    Spawn(@TcpListener, Pointer(PtrInt(i)));
    Spawn(@Beacon, Pointer(PtrInt(i)));
    Spawn(@DiscoAndGossip, Pointer(PtrInt(i)));
  end;
  Spawn(@Watchdog, nil);
  RunUntilDone;

  conv := 0; total := 0;
  for i := 0 to K-1 do begin total := total + Length(nstore[i]);
    if Length(nstore[i]) = K then conv := conv + 1; end;
  WriteLn('zero-seed nodes=', K, ' discovered+converged=', conv, '/', K,
          ' total-objects=', total, ' (expect ', K*K, ')');
  if conv = K then WriteLn('ZERO-SEED AUTO-DISCOVERY OK') else WriteLn('FAIL');
end.
