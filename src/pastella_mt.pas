program pastella_mt;
{$threadsafe on}
{ Multi-core pastella: N OS threads, each running its OWN coroutine reactor
  (per-thread scheduler), hosting a share of the peers. Peers gossip over real
  loopback TCP (kernel carries cross-thread traffic — shared-nothing in user
  memory). Proves async (coroutines) + multithreading (reactor-per-core) + the
  P2P protocol, all at once. Each of K nodes seeds one distinct object; they
  form a ring and converge to all K. }

uses sysutils, sha256, platform, scheduler, palthread;

const
  K       = 6;        { peer nodes }
  M       = 3;        { OS threads / cores (2 nodes each) }
  BASE    = 35100;    { node i listens on BASE+i }
  ROUNDS  = 10;

type
  TItem = record hash, data: AnsiString; end;
  TItemArr = array of TItem;

var
  nstore  : array[0..K-1] of TItemArr;  { per-node store (node i owns nstore[i]) }
  stopFlag: Integer;                          { atomic: workers wind down when set }
  threads : array[0..M-1] of TThreadHandle;

function HashOf(const d: AnsiString): AnsiString; begin HashOf := Sha256Hex(Sha256(d)); end;

function NHas(ni: Integer; const h: AnsiString): Boolean;
var i: Integer;
begin
  NHas := False;
  for i := 0 to High(nstore[ni]) do if nstore[ni][i].hash = h then NHas := True;
end;

procedure NPut(ni: Integer; const data: AnsiString);
var n: Integer;
begin
  if data = '' then Exit;
  if NHas(ni, HashOf(data)) then Exit;
  n := Length(nstore[ni]); SetLength(nstore[ni], n+1);
  nstore[ni][n].hash := HashOf(data); nstore[ni][n].data := data;
end;

function NGet(ni: Integer; const h: AnsiString): AnsiString;
var i: Integer;
begin
  NGet := '';
  for i := 0 to High(nstore[ni]) do if nstore[ni][i].hash = h then NGet := nstore[ni][i].data;
end;

function NHave(ni: Integer): AnsiString;
var i: Integer;
begin
  NHave := '';
  for i := 0 to High(nstore[ni]) do
  begin
    if i > 0 then NHave := NHave + #10;
    NHave := NHave + nstore[ni][i].hash;
  end;
end;

{ --- framed I/O on the reactor --- }
procedure SendFrame(fd: Integer; const s: AnsiString); async;
var hdr: AnsiString; off, tot, L: Integer; n: Int64;
begin
  L := Length(s);
  hdr := Chr((L shr 24)and 255)+Chr((L shr 16)and 255)+Chr((L shr 8)and 255)+Chr(L and 255)+s;
  off := 0; tot := Length(hdr);
  while off < tot do
  begin
    WaitWritable(fd);
    n := PalSend(fd, @hdr[off+1], tot-off);
    if n <= 0 then Exit;
    off := off + Integer(n);
  end;
end;

function RecvExact(fd, count: Integer): AnsiString; async;
var buf: AnsiString; got: Integer; n: Int64;
begin
  SetLength(buf, count); got := 0;
  while got < count do
  begin
    if not WaitReadableTimeout(fd, 3000) then Break;
    n := PalRecv(fd, @buf[got+1], count-got);
    if n <= 0 then Break;
    got := got + Integer(n);
  end;
  SetLength(buf, got); RecvExact := buf;
end;

function RecvFrame(fd: Integer): AnsiString; async;
var h: AnsiString; L: Integer;
begin
  h := await RecvExact(fd, 4);
  if Length(h) < 4 then begin RecvFrame := ''; Exit; end;
  L := (Ord(h[1])shl 24)or(Ord(h[2])shl 16)or(Ord(h[3])shl 8)or Ord(h[4]);
  RecvFrame := await RecvExact(fd, L);
end;

{ want = hashes in `have` that node ni lacks }
function WantFrom(ni: Integer; const have: AnsiString): AnsiString;
var i, start: Integer; line, want: AnsiString;
begin
  want := ''; start := 1;
  for i := 1 to Length(have)+1 do
    if (i > Length(have)) or (have[i] = #10) then
    begin
      line := Copy(have, start, i-start);
      if (line <> '') and (not NHas(ni, line)) then
      begin
        if want <> '' then want := want + #10;
        want := want + line;
      end;
      start := i+1;
    end;
  WantFrom := want;
end;

function CountLines(const s: AnsiString): Integer;
var i, c: Integer;
begin
  if s = '' then begin CountLines := 0; Exit; end;
  c := 1;
  for i := 1 to Length(s) do if s[i] = #10 then c := c + 1;
  CountLines := c;
end;

{ pack (nodeIndex, fd) into one pointer arg }
function Pack(ni, fd: Integer): Pointer; begin Pack := Pointer(PtrInt(ni*65536 + fd)); end;

{ Responder half of the initiator-driven exchange (mirrors Dialer step-for-step):
  1 recv peer HAVE   2 send my HAVE   3 recv peer WANT, serve DATA
  4 send my WANT     5 recv my DATA }
procedure ServeConn(arg: Pointer); async;
var v, fd, ni, i, start, nwant: Integer; phave, pwant, mywant, line, data: AnsiString;
begin
  v := Integer(PtrInt(arg)); ni := v div 65536; fd := v mod 65536;
  SetNonBlocking(fd);
  phave := await RecvFrame(fd);                          { 1 peer HAVE }
  await SendFrame(fd, NHave(ni));                        { 2 my HAVE }
  pwant := await RecvFrame(fd);                          { 3 peer WANT }
  start := 1;                                      {   serve it }
  for i := 1 to Length(pwant)+1 do
    if (i > Length(pwant)) or (pwant[i] = #10) then
    begin
      line := Copy(pwant, start, i-start);
      if line <> '' then await SendFrame(fd, NGet(ni, line));
      start := i+1;
    end;
  mywant := WantFrom(ni, phave); nwant := CountLines(mywant);
  await SendFrame(fd, mywant);                           { 4 my WANT }
  for i := 1 to nwant do begin data := await RecvFrame(fd); NPut(ni, data); end;  { 5 my DATA }
  PalClose(fd);
end;

procedure Listener(arg: Pointer); async;
var ni, lfd, conn: Integer;
begin
  ni := Integer(PtrInt(arg));
  lfd := PalSocket(PAL_NET_AF_INET, PAL_NET_SOCK_STREAM, 0);
  PalSetSocketReuseAddr(lfd, 1);
  PalBindIpv4(lfd, PAL_NET_IP_LOOPBACK, BASE+ni);
  PalListen(lfd, 16);
  SetNonBlocking(lfd);
  while __pxxatomic_cas(@stopFlag, 2, 2) = 0 do   { spin-free read: cas(2,2) leaves 0 as 0 }
  begin
    if WaitReadableTimeout(lfd, 150) then
    begin
      conn := PalAccept(lfd);
      if conn >= 0 then Spawn(@ServeConn, Pack(ni, conn));
    end;
  end;
  PalClose(lfd);
end;

{ Initiator half. One round = pull what I lack from peer, then push what peer
  lacks. Ordering mirrors ServeConn exactly:
  1 send HAVE   2 recv peer HAVE   3 send WANT, recv my DATA
  4 recv peer WANT, serve DATA }
procedure Dialer(arg: Pointer); async;
var ni, peer, fd, r, i, nwant: Integer; phave, mywant, pwant, data, line: AnsiString; start: Integer;
begin
  ni := Integer(PtrInt(arg));
  peer := (ni + 1) mod K;
  CoSleep(200);
  for r := 1 to ROUNDS do
  begin
    fd := PalSocket(PAL_NET_AF_INET, PAL_NET_SOCK_STREAM, 0);
    SetNonBlocking(fd);
    PalConnectIpv4(fd, PAL_NET_IP_LOOPBACK, BASE+peer);
    WaitWritable(fd);
    await SendFrame(fd, NHave(ni));                       { 1 my HAVE }
    phave := await RecvFrame(fd);                         { 2 peer HAVE }
    mywant := WantFrom(ni, phave); nwant := CountLines(mywant);
    await SendFrame(fd, mywant);                          { 3 my WANT }
    for i := 1 to nwant do begin data := await RecvFrame(fd); NPut(ni, data); end;
    pwant := await RecvFrame(fd);                         { 4 peer WANT }
    start := 1;                                     {   serve it }
    for i := 1 to Length(pwant)+1 do
      if (i > Length(pwant)) or (pwant[i] = #10) then
      begin
        line := Copy(pwant, start, i-start);
        if line <> '' then await SendFrame(fd, NGet(ni, line));
        start := i+1;
      end;
    PalClose(fd);
    CoSleep(120);
  end;
end;

{ each worker thread hosts nodes  t, t+M, t+2M, ... and runs its own reactor }
procedure Worker(arg: Pointer);
var t, ni: Integer;
begin
  t := Integer(PtrInt(arg));
  ni := t;
  while ni < K do
  begin
    Spawn(@Listener, Pointer(PtrInt(ni)));
    Spawn(@Dialer, Pointer(PtrInt(ni)));
    ni := ni + M;
  end;
  RunUntilDone;
end;

var i, total, converged: Integer; ig: Int64;
begin
  { seed: node i gets one distinct object }
  for i := 0 to K-1 do NPut(i, 'object-from-node-' + IntToStr(i));
  stopFlag := 0;

  for i := 0 to M-1 do
    PalThreadCreate(threads[i], @Worker, Pointer(PtrInt(i)), 262144);

  { let the ring converge, then signal listeners to wind down }
  { main thread: crude sleep via repeated short syscalls is unavailable here;
    use nanosleep through a busy sequence of PalPoll on nothing — simplest is a
    blocking poll timeout. }
  PalPoll(0, 0, 2500);            { ~2.5s wall time for gossip to converge }
  ig := __pxxatomic_xchg(@stopFlag, 1);

  for i := 0 to M-1 do PalThreadJoin(threads[i]);

  total := 0; converged := 0;
  for i := 0 to K-1 do
  begin
    total := total + Length(nstore[i]);
    if Length(nstore[i]) = K then converged := converged + 1;
  end;
  WriteLn('nodes=', K, ' threads=', M, ' converged=', converged, '/', K,
          ' total-objects=', total, ' (expect ', K*K, ')');
  if converged = K then WriteLn('MULTI-CORE PASTELLA OK') else WriteLn('FAIL');
end.
