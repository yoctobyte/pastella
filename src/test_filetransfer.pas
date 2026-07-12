program test_filetransfer;
{ FILE TRANSFER over multi-hop. A large object (256 KB) is seeded at node0 of a
  5-node line (0-1-2-3-4). Only neighbours gossip, so the object must travel hop
  by hop to node4. Verified by content hash at every node — proves large,
  chunked, framed transfer survives multiple hops intact. }

uses sysutils, sha256, platform, scheduler;

const
  K = 5; TBASE = 35400; ROUNDS = 14; BIGN = 262144;   { 256 KB }

type TItem = record hash, data: AnsiString; end; TItemArr = array of TItem;
var
  nstore : array[0..K-1] of TItemArr;
  stop   : Integer;
  bigHash: AnsiString;

function HashOf(const d: AnsiString): AnsiString; begin HashOf := Sha256Hex(Sha256(d)); end;
function NHas(ni: Integer; const h: AnsiString): Boolean;
var i: Integer; begin NHas := False; for i := 0 to High(nstore[ni]) do if nstore[ni][i].hash=h then NHas := True; end;
procedure NPut(ni: Integer; const data: AnsiString);
var n: Integer; begin if data='' then Exit; if NHas(ni,HashOf(data)) then Exit;
  n := Length(nstore[ni]); SetLength(nstore[ni],n+1); nstore[ni][n].hash := HashOf(data); nstore[ni][n].data := data; end;
function NGet(ni: Integer; const h: AnsiString): AnsiString;
var i: Integer; begin NGet := ''; for i := 0 to High(nstore[ni]) do if nstore[ni][i].hash=h then NGet := nstore[ni][i].data; end;
function NHave(ni: Integer): AnsiString;
var i: Integer; begin NHave := ''; for i := 0 to High(nstore[ni]) do begin
  if i>0 then NHave := NHave+#10; NHave := NHave+nstore[ni][i].hash; end; end;

procedure SendFrame(fd: Integer; const s: AnsiString); async;
var hdr: AnsiString; off,tot,L: Integer; n: Int64; begin
  L := Length(s); hdr := Chr((L shr 24)and 255)+Chr((L shr 16)and 255)+Chr((L shr 8)and 255)+Chr(L and 255)+s;
  off := 0; tot := Length(hdr);
  while off<tot do begin WaitWritable(fd); n := PalSend(fd,@hdr[off+1],tot-off); if n<=0 then Exit; off := off+Integer(n); end; end;
function RecvExact(fd,count: Integer): AnsiString; async;
var buf: AnsiString; got: Integer; n: Int64; begin SetLength(buf,count); got := 0;
  while got<count do begin if not WaitReadableTimeout(fd,4000) then Break; n := PalRecv(fd,@buf[got+1],count-got);
    if n<=0 then Break; got := got+Integer(n); end; SetLength(buf,got); RecvExact := buf; end;
function RecvFrame(fd: Integer): AnsiString; async;
var h: AnsiString; L: Integer; begin h := await RecvExact(fd,4); if Length(h)<4 then begin RecvFrame := ''; Exit; end;
  L := (Ord(h[1])shl 24)or(Ord(h[2])shl 16)or(Ord(h[3])shl 8)or Ord(h[4]); RecvFrame := await RecvExact(fd,L); end;
function WantFrom(ni: Integer; const have: AnsiString): AnsiString;
var i,start: Integer; line,want: AnsiString; begin want := ''; start := 1;
  for i := 1 to Length(have)+1 do if (i>Length(have)) or (have[i]=#10) then begin
    line := Copy(have,start,i-start); if (line<>'') and (not NHas(ni,line)) then begin
      if want<>'' then want := want+#10; want := want+line; end; start := i+1; end; WantFrom := want; end;
function CountLines(const s: AnsiString): Integer;
var i,c: Integer; begin if s='' then begin CountLines := 0; Exit; end; c := 1;
  for i := 1 to Length(s) do if s[i]=#10 then c := c+1; CountLines := c; end;
procedure ServeWants(ni,fd: Integer; const w: AnsiString); async;
var i,start: Integer; line: AnsiString; begin start := 1;
  for i := 1 to Length(w)+1 do if (i>Length(w)) or (w[i]=#10) then begin
    line := Copy(w,start,i-start); if line<>'' then await SendFrame(fd,NGet(ni,line)); start := i+1; end; end;
function Pack(ni,fd: Integer): Pointer; begin Pack := Pointer(PtrInt(ni*65536+fd)); end;

procedure ServeConn(arg: Pointer); async;
var v,fd,ni,i,nwant: Integer; phave,pwant,mywant,data: AnsiString; begin
  v := Integer(PtrInt(arg)); ni := v div 65536; fd := v mod 65536; SetNonBlocking(fd);
  phave := await RecvFrame(fd); await SendFrame(fd,NHave(ni)); pwant := await RecvFrame(fd); await ServeWants(ni,fd,pwant);
  mywant := WantFrom(ni,phave); nwant := CountLines(mywant); await SendFrame(fd,mywant);
  for i := 1 to nwant do begin data := await RecvFrame(fd); NPut(ni,data); end; PalClose(fd); end;

procedure GossipOnce(ni,peerPort: Integer); async;
var fd,i,nwant: Integer; phave,mywant,pwant,data: AnsiString; begin
  fd := PalSocket(PAL_NET_AF_INET,PAL_NET_SOCK_STREAM,0); SetNonBlocking(fd);
  PalConnectIpv4(fd,PAL_NET_IP_LOOPBACK,peerPort); WaitWritable(fd);
  await SendFrame(fd,NHave(ni)); phave := await RecvFrame(fd);
  mywant := WantFrom(ni,phave); nwant := CountLines(mywant); await SendFrame(fd,mywant);
  for i := 1 to nwant do begin data := await RecvFrame(fd); NPut(ni,data); end;
  pwant := await RecvFrame(fd); await ServeWants(ni,fd,pwant); PalClose(fd); end;

procedure TcpListener(arg: Pointer); async;
var ni,lfd,conn: Integer; begin ni := Integer(PtrInt(arg));
  lfd := PalSocket(PAL_NET_AF_INET,PAL_NET_SOCK_STREAM,0); PalSetSocketReuseAddr(lfd,1);
  PalBindIpv4(lfd,PAL_NET_IP_LOOPBACK,TBASE+ni); PalListen(lfd,16); SetNonBlocking(lfd);
  while stop=0 do if WaitReadableTimeout(lfd,150) then begin conn := PalAccept(lfd);
    if conn>=0 then Spawn(@ServeConn,Pack(ni,conn)); end; PalClose(lfd); end;

{ line topology: each node gossips only with ni-1 and ni+1 }
procedure Neighbour(arg: Pointer); async;
var ni,r: Integer; begin ni := Integer(PtrInt(arg)); CoSleep(200);
  for r := 1 to ROUNDS do begin
    if ni > 0   then await GossipOnce(ni, TBASE+ni-1);
    if ni < K-1 then await GossipOnce(ni, TBASE+ni+1);
    CoSleep(120); end; end;

procedure Watchdog(arg: Pointer); begin CoSleep(ROUNDS*260+900); stop := 1; end;
procedure IgnoreSigpipe;
const SYS_rt_sigaction=13; SIGPIPE=13; SIG_IGN=1;
var act: array[0..3] of Int64; rc: Int64;
begin act[0] := SIG_IGN; act[1] := 0; act[2] := 0; act[3] := 0;
  rc := __pxxrawsyscall(SYS_rt_sigaction,SIGPIPE,Int64(@act[0]),0,8,0,0); end;

var i,haveBig,okHash: Integer; big: AnsiString;
begin
  IgnoreSigpipe;
  { build a deterministic 256 KB object }
  SetLength(big, BIGN);
  for i := 1 to BIGN do big[i] := Chr((i * 37 + 11) and 255);
  bigHash := HashOf(big);
  NPut(0, big);                        { seed the big object only at node0 (far end) }
  NPut(K-1, 'small-marker-object');    { a small object seeded at the other end }
  stop := 0;

  for i := 0 to K-1 do begin Spawn(@TcpListener,Pointer(PtrInt(i))); Spawn(@Neighbour,Pointer(PtrInt(i))); end;
  Spawn(@Watchdog,nil);
  RunUntilDone;

  { every node must hold the big object with the exact content hash }
  haveBig := 0; okHash := 0;
  for i := 0 to K-1 do
    if NHas(i, bigHash) then begin haveBig := haveBig + 1;
      if HashOf(NGet(i, bigHash)) = bigHash then okHash := okHash + 1; end;
  WriteLn('nodes=', K, ' hops=', K-1, ' bigobj-bytes=', BIGN);
  WriteLn('reached=', haveBig, '/', K, ' integrity-ok=', okHash, '/', K);
  if (haveBig = K) and (okHash = K) then WriteLn('FILE TRANSFER OK') else WriteLn('FAIL');
end.
