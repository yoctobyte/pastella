program pastella_node;
{ A real async pastella node. Coroutine reactor (pxx scheduler), native PAL
  sockets. Listens for peers AND periodically dials one neighbour, running
  symmetric offer/fetch. Run several as separate processes in a ring and the
  whole set converges — content-addressed gossip over real TCP, multi-CPU by
  the OS scheduling the processes.

  usage: pastella_node <myPort> <peerPort> <seedText> <rounds>
  (peerPort 0 = dial nobody; seedText '' = seed nothing) }

uses sysutils, sha256, platform, scheduler;

type
  TItem  = record hash, data: AnsiString; end;

var
  store   : array of TItem;
  myPort, peerPort, rounds: Integer;
  myName  : AnsiString;

function HashOf(const d: AnsiString): AnsiString;
begin HashOf := Sha256Hex(Sha256(d)); end;

function Has(const h: AnsiString): Boolean;
var i: Integer;
begin
  Has := False;
  for i := 0 to High(store) do if store[i].hash = h then Has := True;
end;

procedure Put(const data: AnsiString);
var n: Integer;
begin
  if data = '' then exit;
  if Has(HashOf(data)) then exit;
  n := Length(store); SetLength(store, n+1);
  store[n].hash := HashOf(data); store[n].data := data;
end;

function GetByHash(const h: AnsiString): AnsiString;
var i: Integer;
begin
  GetByHash := '';
  for i := 0 to High(store) do if store[i].hash = h then GetByHash := store[i].data;
end;

{ ---- framed I/O on the reactor ---- }
procedure SendFrame(fd: Integer; const s: AnsiString);
var hdr: AnsiString; off, tot, L: Integer; n: Int64;
begin
  L := Length(s);
  hdr := Chr((L shr 24)and 255)+Chr((L shr 16)and 255)+Chr((L shr 8)and 255)+Chr(L and 255)+s;
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
    if not WaitReadableTimeout(fd, 3000) then break;
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
  L := (Ord(h[1])shl 24)or(Ord(h[2])shl 16)or(Ord(h[3])shl 8)or Ord(h[4]);
  RecvFrame := RecvExact(fd, L);
end;

function MyHaveList: AnsiString;
var i: Integer;
begin
  MyHaveList := '';
  for i := 0 to High(store) do
  begin
    if i > 0 then MyHaveList := MyHaveList + #10;
    MyHaveList := MyHaveList + store[i].hash;
  end;
end;

{ split a #10-joined hash list, request the ones we lack (WANT), get DATA back.
  `initiator` sends first to avoid lockstep deadlock on tiny buffers. }
procedure SyncConn(fd: Integer; initiator: Boolean);
var peerHave, want, line, data: AnsiString; i, start, nwant, got: Integer;

  procedure DoSend;
  begin
    SendFrame(fd, MyHaveList);          { HAVE }
    peerHave := RecvFrame(fd);          { peer HAVE }
    { build WANT = peer hashes we lack }
    want := ''; nwant := 0;
    start := 1;
    for i := 1 to Length(peerHave)+1 do
      if (i > Length(peerHave)) or (peerHave[i] = #10) then
      begin
        line := Copy(peerHave, start, i-start);
        if (line <> '') and (not Has(line)) then
        begin
          if nwant > 0 then want := want + #10;
          want := want + line; nwant := nwant + 1;
        end;
        start := i+1;
      end;
    SendFrame(fd, want);                { WANT }
    for i := 1 to nwant do
    begin
      data := RecvFrame(fd);            { DATA }
      Put(data);
    end;
  end;

  procedure DoServe;
  var pwant: AnsiString;
  begin
    { symmetric: also answer peer's WANT }
    pwant := RecvFrame(fd);             { peer WANT }
    start := 1;
    for i := 1 to Length(pwant)+1 do
      if (i > Length(pwant)) or (pwant[i] = #10) then
      begin
        line := Copy(pwant, start, i-start);
        if line <> '' then SendFrame(fd, GetByHash(line));   { DATA }
        start := i+1;
      end;
  end;

begin
  { one clean ordering both ends follow: HAVE<->HAVE, WANT->, then DATA.
    initiator does the want/fetch pass first, then serves; server mirrors. }
  if initiator then begin DoSend; DoServe; end
  else begin
    { server: recv HAVE first isn't needed distinctly; reuse DoSend/DoServe
      in mirrored order }
    peerHave := RecvFrame(fd);          { peer HAVE }
    SendFrame(fd, MyHaveList);          { HAVE }
    { serve peer WANT }
    DoServe;
    { now fetch what we lack from peerHave }
    want := ''; nwant := 0; start := 1;
    for i := 1 to Length(peerHave)+1 do
      if (i > Length(peerHave)) or (peerHave[i] = #10) then
      begin
        line := Copy(peerHave, start, i-start);
        if (line <> '') and (not Has(line)) then
        begin
          if nwant>0 then want := want + #10;
          want := want + line; nwant := nwant + 1;
        end;
        start := i+1;
      end;
    SendFrame(fd, want);                { WANT }
    for i := 1 to nwant do begin data := RecvFrame(fd); Put(data); end;
  end;
  got := 0;
end;

procedure ServeConn(arg: Pointer);
var fd: Integer;
begin
  fd := Integer(PtrInt(arg));
  SetNonBlocking(fd);
  SyncConn(fd, False);
  PalClose(fd);
end;

procedure Listener(arg: Pointer);
var lfd, conn: Integer;
begin
  lfd := PalSocket(PAL_NET_AF_INET, PAL_NET_SOCK_STREAM, 0);
  PalSetSocketReuseAddr(lfd, 1);
  PalBindIpv4(lfd, PAL_NET_IP_LOOPBACK, myPort);
  PalListen(lfd, 16);
  SetNonBlocking(lfd);
  while True do
  begin
    WaitReadable(lfd);
    conn := PalAccept(lfd);
    if conn >= 0 then Spawn(@ServeConn, Pointer(PtrInt(conn)));
  end;
end;

procedure Dialer(arg: Pointer);
var fd, r: Integer;
begin
  if peerPort = 0 then exit;
  CoSleep(200);   { let listeners come up }
  for r := 1 to rounds do
  begin
    fd := PalSocket(PAL_NET_AF_INET, PAL_NET_SOCK_STREAM, 0);
    SetNonBlocking(fd);
    PalConnectIpv4(fd, PAL_NET_IP_LOOPBACK, peerPort);
    WaitWritable(fd);
    SyncConn(fd, True);
    PalClose(fd);
    CoSleep(150);
  end;
end;

procedure Watchdog(arg: Pointer);
begin
  { Listener loops forever, so RunUntilDone never returns; this ends the
    process after the gossip rounds have had time to converge. }
  CoSleep(rounds*400 + 1500);
  WriteLn(myName, ' final store: ', Length(store), ' objects');
  Halt(0);
end;

var argc: Integer;
begin
  argc := ParamCount;
  if argc < 4 then begin WriteLn('usage: pastella_node myPort peerPort seed rounds'); Halt(1); end;
  myPort   := StrToInt(ParamStr(1));
  peerPort := StrToInt(ParamStr(2));
  Put(ParamStr(3));
  rounds   := StrToInt(ParamStr(4));
  myName   := 'node:' + ParamStr(1);

  Spawn(@Listener, nil);
  Spawn(@Dialer, nil);
  Spawn(@Watchdog, nil);
  RunUntilDone;
end.
