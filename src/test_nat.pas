program test_nat;
{ NAT TRAVERSAL (connect-back via rendezvous). Peer A is unreachable from the
  outside (behind NAT — here: it never listens for inbound). It keeps one
  outbound connection to a rendezvous R. Peer B wants to reach A but cannot dial
  it directly. B asks R; R signals A over the existing connection; A then dials
  B (connect-back), which B accepts. The data path A->B is established despite A
  being inbound-unreachable — the essence of hole-punch/connect-back relaying. }

uses sysutils, platform, scheduler;

const
  RPORT = 35800;   { rendezvous }
  BPORT = 35801;   { B's own listener (B is reachable; A is not) }
  result_ok: Integer = 0;

var
  gotAtB : AnsiString;
  aRegFd : Integer;    { A's connection at the rendezvous (set by R) }
  stop   : Integer;

procedure SendLine(fd: Integer; const s: AnsiString);
var msg: AnsiString; off,tot: Integer; n: Int64; begin
  msg := s + #10; off := 0; tot := Length(msg);
  while off<tot do begin WaitWritable(fd); n := PalSend(fd,@msg[off+1],tot-off);
    if n<=0 then Exit; off := off+Integer(n); end; end;
function RecvLine(fd: Integer): AnsiString;
var s: AnsiString; b: array[0..0] of Byte; n: Int64; begin s := '';
  while True do begin if not WaitReadableTimeout(fd,3000) then Break;
    n := PalRecv(fd,@b[0],1); if n<=0 then Break; if b[0]=10 then Break; s := s+Chr(b[0]); end;
  RecvLine := s; end;

function Pack2(a,b: Integer): Pointer; begin Pack2 := Pointer(PtrInt(a*65536+b)); end;

{ Rendezvous: first line "REG" => remember this fd as A; "REQ <bport>" => tell A
  to dial back to bport. }
procedure RServe(arg: Pointer);
var fd: Integer; line, rest: AnsiString; sp: Integer; begin
  fd := Integer(PtrInt(arg)); SetNonBlocking(fd);
  line := RecvLine(fd);
  if line = 'REG' then
  begin
    aRegFd := fd;                    { keep A's connection open }
    { block here holding the connection until told to signal (A waits on it) }
    while stop = 0 do CoSleep(50);
  end
  else if Copy(line,1,4) = 'REQ ' then
  begin
    rest := Copy(line,5,Length(line)-4);   { bport }
    { relay a DIAL instruction to A over its registration connection }
    if aRegFd >= 0 then SendLine(aRegFd, 'DIAL ' + rest);
    PalClose(fd);
  end;
end;

procedure Rendezvous(arg: Pointer);
var lfd, conn: Integer; begin
  lfd := PalSocket(PAL_NET_AF_INET,PAL_NET_SOCK_STREAM,0); PalSetSocketReuseAddr(lfd,1);
  PalBindIpv4(lfd,PAL_NET_IP_LOOPBACK,RPORT); PalListen(lfd,8); SetNonBlocking(lfd);
  while stop=0 do if WaitReadableTimeout(lfd,80) then begin conn := PalAccept(lfd);
    if conn>=0 then Spawn(@RServe, Pointer(PtrInt(conn))); end; PalClose(lfd); end;

{ A: never listens (unreachable). Registers at R, waits for DIAL, connects back. }
procedure PeerA(arg: Pointer);
var fd, dfd, sp: Integer; line, bport: AnsiString; begin
  CoSleep(200);
  fd := PalSocket(PAL_NET_AF_INET,PAL_NET_SOCK_STREAM,0); SetNonBlocking(fd);
  PalConnectIpv4(fd,PAL_NET_IP_LOOPBACK,RPORT); WaitWritable(fd);
  SendLine(fd, 'REG');
  line := RecvLine(fd);                 { blocks until R sends "DIAL <bport>" }
  if Copy(line,1,5) = 'DIAL ' then
  begin
    bport := Copy(line,6,Length(line)-5);
    { connect-back to B }
    dfd := PalSocket(PAL_NET_AF_INET,PAL_NET_SOCK_STREAM,0); SetNonBlocking(dfd);
    sp := 0; Val(bport, sp, sp);
    Val(bport, sp, sp);
    PalConnectIpv4(dfd, PAL_NET_IP_LOOPBACK, StrToInt(bport)); WaitWritable(dfd);
    SendLine(dfd, 'hello-from-A-behind-NAT');
    PalClose(dfd);
  end;
  PalClose(fd);
end;

{ B: reachable, listens; asks R to have A connect back; receives A's data. }
procedure PeerB(arg: Pointer);
var lfd, conn, rfd: Integer; begin
  lfd := PalSocket(PAL_NET_AF_INET,PAL_NET_SOCK_STREAM,0); PalSetSocketReuseAddr(lfd,1);
  PalBindIpv4(lfd,PAL_NET_IP_LOOPBACK,BPORT); PalListen(lfd,4); SetNonBlocking(lfd);
  CoSleep(500);   { let A register first }
  { ask rendezvous to trigger A's connect-back }
  rfd := PalSocket(PAL_NET_AF_INET,PAL_NET_SOCK_STREAM,0); SetNonBlocking(rfd);
  PalConnectIpv4(rfd,PAL_NET_IP_LOOPBACK,RPORT); WaitWritable(rfd);
  SendLine(rfd, 'REQ ' + IntToStr(BPORT));
  PalClose(rfd);
  { accept A's connect-back }
  if WaitReadableTimeout(lfd, 3000) then
  begin
    conn := PalAccept(lfd);
    if conn >= 0 then begin SetNonBlocking(conn); gotAtB := RecvLine(conn); PalClose(conn); end;
  end;
  PalClose(lfd);
  stop := 1;
end;

procedure IgnoreSigpipe;
const SYS_rt_sigaction=13; SIGPIPE=13; SIG_IGN=1;
var act: array[0..3] of Int64; rc: Int64;
begin act[0] := SIG_IGN; act[1] := 0; act[2] := 0; act[3] := 0;
  rc := __pxxrawsyscall(SYS_rt_sigaction,SIGPIPE,Int64(@act[0]),0,8,0,0); end;

begin
  IgnoreSigpipe; stop := 0; aRegFd := -1; gotAtB := '';
  Spawn(@Rendezvous, nil);
  Spawn(@PeerA, nil);
  Spawn(@PeerB, nil);
  RunUntilDone;
  WriteLn('A is inbound-unreachable; reached B via rendezvous connect-back.');
  WriteLn('B received: "', gotAtB, '"');
  if gotAtB = 'hello-from-A-behind-NAT' then WriteLn('NAT TRAVERSAL OK') else WriteLn('FAIL');
end.
