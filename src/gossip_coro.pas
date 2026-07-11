program gossip_coro;
{ Pastella spine as a COROUTINE REACTOR (model 3): one OS thread, one coroutine
  per connection, epoll-driven via the pxx scheduler. Linear per-peer code, no
  locks (single thread owns all state), tiny stacks. Exercises frank2's
  scheduler (Spawn/CoYield/WaitReadable/RunUntilDone) with many concurrent
  coroutines — the single-core half of the multi-CPU story.

  Topology: 1 server (holds seed objects) + N client coroutines connect and
  fetch via offer/fetch. All driven by one RunUntilDone. Converges => the
  coroutine reactor handles concurrent gossip. }

uses sysutils, sha256, platform, scheduler;

const
  PORT     = 34720;
  NCLIENTS = 8;

type
  TItem  = record hash, data: AnsiString; end;
  TStore = record items: array of TItem; end;

var
  server: TStore;
  fetched: array[0..NCLIENTS-1] of Integer;   { objects each client got }
  clientsDone: Integer;

function HashOf(const d: AnsiString): AnsiString;
begin HashOf := Sha256Hex(Sha256(d)); end;

procedure Put(var s: TStore; const data: AnsiString);
var n: Integer;
begin
  n := Length(s.items); SetLength(s.items, n+1);
  s.items[n].hash := HashOf(data); s.items[n].data := data;
end;

{ ---- framed I/O on the reactor (WaitWritable/WaitReadable, never block) ---- }
procedure SendFrame(fd: Integer; const s: AnsiString);
var hdr: AnsiString; off, tot, L: Integer; n: Int64;
begin
  L := Length(s);
  hdr := Chr((L shr 24) and 255)+Chr((L shr 16) and 255)+Chr((L shr 8) and 255)+Chr(L and 255)+s;
  off := 0; tot := Length(hdr);
  while off < tot do
  begin
    WaitWritable(fd);
    n := PalSend(fd, @hdr[off+1], tot-off);
    if n <= 0 then exit;
    off := off + Integer(n);
  end;
end;

function RecvExact(fd, count: Integer): AnsiString;
var buf: AnsiString; got: Integer; n: Int64;
begin
  SetLength(buf, count); got := 0;
  while got < count do
  begin
    WaitReadable(fd);
    n := PalRecv(fd, @buf[got+1], count-got);
    if n <= 0 then break;
    got := got + Integer(n);
  end;
  SetLength(buf, got); RecvExact := buf;
end;

function RecvFrame(fd: Integer): AnsiString;
var h: AnsiString; L: Integer;
begin
  h := RecvExact(fd, 4);
  if Length(h) < 4 then begin RecvFrame := ''; exit; end;
  L := (Ord(h[1]) shl 24) or (Ord(h[2]) shl 16) or (Ord(h[3]) shl 8) or Ord(h[4]);
  RecvFrame := RecvExact(fd, L);
end;

{ server side: one coroutine per accepted connection — offer everything }
procedure ServeConn(arg: Pointer);
var fd, i: Integer; have: AnsiString;
begin
  fd := Integer(PtrInt(arg));
  SetNonBlocking(fd);
  have := '';
  for i := 0 to High(server.items) do
  begin
    if i > 0 then have := have + #10;
    have := have + server.items[i].hash;
  end;
  SendFrame(fd, have);         { HAVE }
  RecvFrame(fd);               { WANT (ignored — we just send all data) }
  for i := 0 to High(server.items) do
    SendFrame(fd, server.items[i].data);   { DATA }
  PalClose(fd);
end;

procedure Listener(arg: Pointer);
var lfd, conn, accepted: Integer;
begin
  lfd := PalSocket(PAL_NET_AF_INET, PAL_NET_SOCK_STREAM, 0);
  PalSetSocketReuseAddr(lfd, 1);
  PalBindIpv4(lfd, PAL_NET_IP_LOOPBACK, PORT);
  PalListen(lfd, 32);
  SetNonBlocking(lfd);
  accepted := 0;
  while accepted < NCLIENTS do
  begin
    WaitReadable(lfd);
    conn := PalAccept(lfd);
    if conn >= 0 then
    begin
      Spawn(@ServeConn, Pointer(PtrInt(conn)));
      accepted := accepted + 1;
    end;
  end;
  PalClose(lfd);
end;

procedure Client(arg: Pointer);
var id, fd, i, nobj: Integer; have, want, data: AnsiString;
begin
  id := Integer(PtrInt(arg));
  fd := PalSocket(PAL_NET_AF_INET, PAL_NET_SOCK_STREAM, 0);
  SetNonBlocking(fd);
  PalConnectIpv4(fd, PAL_NET_IP_LOOPBACK, PORT);
  WaitWritable(fd);            { connected }

  have := RecvFrame(fd);       { HAVE }
  want := have;                { we lack everything }
  SendFrame(fd, want);         { WANT }

  { count offered objects = newlines+1, then read that many DATA frames }
  nobj := 1;
  for i := 1 to Length(have) do if have[i] = #10 then nobj := nobj + 1;
  if Length(have) = 0 then nobj := 0;

  for i := 1 to nobj do
  begin
    data := RecvFrame(fd);
    if HashOf(data) <> '' then fetched[id] := fetched[id] + 1;
  end;
  PalClose(fd);
  clientsDone := clientsDone + 1;
end;

var i, total: Integer;
begin
  Put(server, 'alpha object');
  Put(server, 'beta object');
  Put(server, 'gamma object');

  for i := 0 to NCLIENTS-1 do fetched[i] := 0;
  clientsDone := 0;

  Spawn(@Listener, nil);
  for i := 0 to NCLIENTS-1 do
    Spawn(@Client, Pointer(PtrInt(i)));

  RunUntilDone;

  total := 0;
  for i := 0 to NCLIENTS-1 do total := total + fetched[i];
  WriteLn(NCLIENTS, ' clients, ', clientsDone, ' finished, ', total, ' objects fetched (expect ', NCLIENTS*3, ')');
  if (clientsDone = NCLIENTS) and (total = NCLIENTS*3) then
    WriteLn('COROUTINE REACTOR OK')
  else
    WriteLn('FAIL');
end.
