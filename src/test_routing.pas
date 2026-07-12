program test_routing;
{ ROUTING. A message is addressed to a specific destination node and flooded
  with a TTL: each node forwards it to its neighbours (ttl-1, dedup by id) but
  only the DESTINATION delivers it. Proves directed multi-hop delivery distinct
  from gossip-to-all. Line topology 0-1-2-3-4-5; node0 routes to node5. }

uses sysutils, sha256, platform, scheduler;

const
  K = 6; TBASE = 35600; RUNTIME_MS = 2500;
  START_TTL = 16;

type
  TMsg = record id: Integer; dest: Integer; ttl: Integer; payload: AnsiString; end;
  TMsgArr = array of TMsg;
  TIntArr = array of Integer;

var
  seen     : array[0..K-1] of TIntArr;    { message ids each node has processed }
  outq     : array[0..K-1] of TMsgArr;    { messages queued for forwarding }
  delivered: array[0..K-1] of Integer;    { count delivered AS destination }
  stop     : Integer;

function HaveSeen(ni, id: Integer): Boolean;
var i: Integer; begin HaveSeen := False; for i := 0 to High(seen[ni]) do if seen[ni][i]=id then HaveSeen := True; end;
procedure MarkSeen(ni, id: Integer);
var n: Integer; begin n := Length(seen[ni]); SetLength(seen[ni],n+1); seen[ni][n] := id; end;
procedure Enqueue(ni: Integer; const m: TMsg);
var n: Integer; begin n := Length(outq[ni]); SetLength(outq[ni],n+1); outq[ni][n] := m; end;

{ frame: "R <id> <dest> <ttl>\n<payload>" }
procedure SendFrame(fd: Integer; const s: AnsiString); async;
var hdr: AnsiString; off,tot,L: Integer; n: Int64; begin
  L := Length(s); hdr := Chr((L shr 24)and 255)+Chr((L shr 16)and 255)+Chr((L shr 8)and 255)+Chr(L and 255)+s;
  off := 0; tot := Length(hdr); while off<tot do begin WaitWritable(fd);
    n := PalSend(fd,@hdr[off+1],tot-off); if n<=0 then Exit; off := off+Integer(n); end; end;
function RecvExact(fd,count: Integer): AnsiString; async;
var buf: AnsiString; got: Integer; n: Int64; begin SetLength(buf,count); got := 0;
  while got<count do begin if not WaitReadableTimeout(fd,2000) then Break;
    n := PalRecv(fd,@buf[got+1],count-got); if n<=0 then Break; got := got+Integer(n); end;
  SetLength(buf,got); RecvExact := buf; end;
function RecvFrame(fd: Integer): AnsiString; async;
var h: AnsiString; L: Integer; begin h := await RecvExact(fd,4); if Length(h)<4 then begin RecvFrame := ''; Exit; end;
  L := (Ord(h[1])shl 24)or(Ord(h[2])shl 16)or(Ord(h[3])shl 8)or Ord(h[4]); RecvFrame := await RecvExact(fd,L); end;

function Encode(const m: TMsg): AnsiString;
begin Encode := 'R ' + IntToStr(m.id) + ' ' + IntToStr(m.dest) + ' ' + IntToStr(m.ttl) + #10 + m.payload; end;

function Decode(const s: AnsiString; var m: TMsg): Boolean;
var nl, p1, p2, p3, c: Integer; head: AnsiString;
begin
  Decode := False;
  nl := Pos(#10, s); if nl < 1 then Exit;
  head := Copy(s, 1, nl-1); m.payload := Copy(s, nl+1, Length(s)-nl);
  { head = "R id dest ttl" }
  if Copy(head,1,2) <> 'R ' then Exit;
  head := Copy(head, 3, Length(head)-2);
  p1 := Pos(' ', head); Val(Copy(head,1,p1-1), m.id, c); head := Copy(head,p1+1,Length(head)-p1);
  p2 := Pos(' ', head); Val(Copy(head,1,p2-1), m.dest, c); head := Copy(head,p2+1,Length(head)-p2);
  Val(head, m.ttl, c);
  Decode := True;
end;

{ on receiving a routed message: dedup, deliver if destination, else forward }
procedure OnRoute(ni: Integer; const m: TMsg);
var fwd: TMsg;
begin
  if HaveSeen(ni, m.id) then Exit;
  MarkSeen(ni, m.id);
  if m.dest = ni then begin delivered[ni] := delivered[ni] + 1; Exit; end;
  if m.ttl > 0 then begin fwd := m; fwd.ttl := m.ttl - 1; Enqueue(ni, fwd); end;
end;

function Pack(ni,fd: Integer): Pointer; begin Pack := Pointer(PtrInt(ni*65536+fd)); end;

procedure ServeConn(arg: Pointer); async;
var v,fd,ni: Integer; s: AnsiString; m: TMsg; begin
  v := Integer(PtrInt(arg)); ni := v div 65536; fd := v mod 65536; SetNonBlocking(fd);
  s := await RecvFrame(fd); PalClose(fd);
  if Decode(s, m) then OnRoute(ni, m);
end;

procedure TcpListener(arg: Pointer); async;
var ni,lfd,conn: Integer; begin ni := Integer(PtrInt(arg));
  lfd := PalSocket(PAL_NET_AF_INET,PAL_NET_SOCK_STREAM,0); PalSetSocketReuseAddr(lfd,1);
  PalBindIpv4(lfd,PAL_NET_IP_LOOPBACK,TBASE+ni); PalListen(lfd,16); SetNonBlocking(lfd);
  while stop=0 do if WaitReadableTimeout(lfd,80) then begin conn := PalAccept(lfd);
    if conn>=0 then Spawn(@ServeConn,Pack(ni,conn)); end; PalClose(lfd); end;

procedure PushTo(ni, peer: Integer; const m: TMsg); async;
var fd: Integer; begin
  fd := PalSocket(PAL_NET_AF_INET,PAL_NET_SOCK_STREAM,0); SetNonBlocking(fd);
  PalConnectIpv4(fd,PAL_NET_IP_LOOPBACK,TBASE+peer); WaitWritable(fd);
  await SendFrame(fd, Encode(m)); PalClose(fd); end;

{ forward queued messages to both line neighbours }
procedure Forwarder(arg: Pointer); async;
var ni, i: Integer; m: TMsg; begin ni := Integer(PtrInt(arg));
  while stop = 0 do
  begin
    while Length(outq[ni]) > 0 do
    begin
      m := outq[ni][0];
      { pop front }
      for i := 1 to High(outq[ni]) do outq[ni][i-1] := outq[ni][i];
      SetLength(outq[ni], Length(outq[ni])-1);
      if ni > 0   then await PushTo(ni, ni-1, m);
      if ni < K-1 then await PushTo(ni, ni+1, m);
    end;
    CoSleep(40);
  end;
end;

procedure Watchdog(arg: Pointer); begin CoSleep(RUNTIME_MS); stop := 1; end;
procedure IgnoreSigpipe;
const SYS_rt_sigaction=13; SIGPIPE=13; SIG_IGN=1;
var act: array[0..3] of Int64; rc: Int64;
begin act[0] := SIG_IGN; act[1] := 0; act[2] := 0; act[3] := 0;
  rc := __pxxrawsyscall(SYS_rt_sigaction,SIGPIPE,Int64(@act[0]),0,8,0,0); end;

procedure Originate(arg: Pointer); async;
var m: TMsg; begin CoSleep(250);
  m.id := 4242; m.dest := K-1; m.ttl := START_TTL; m.payload := 'hello node ' + IntToStr(K-1);
  MarkSeen(0, m.id);                 { origin has seen it }
  m.ttl := m.ttl - 1; Enqueue(0, m); { forward from node0 }
end;

var i, totalDelivered: Integer;
begin
  IgnoreSigpipe; stop := 0;
  for i := 0 to K-1 do delivered[i] := 0;
  for i := 0 to K-1 do begin Spawn(@TcpListener,Pointer(PtrInt(i))); Spawn(@Forwarder,Pointer(PtrInt(i))); end;
  Spawn(@Originate, nil);
  Spawn(@Watchdog, nil);
  RunUntilDone;

  totalDelivered := 0;
  for i := 0 to K-1 do totalDelivered := totalDelivered + delivered[i];
  WriteLn('nodes=', K, ' route 0 -> ', K-1, ' (ttl ', START_TTL, ')');
  WriteLn('dest delivered=', delivered[K-1], '  total deliveries=', totalDelivered, ' (expect 1 — only dest)');
  if (delivered[K-1] = 1) and (totalDelivered = 1) then WriteLn('ROUTING OK') else WriteLn('FAIL');
end.
