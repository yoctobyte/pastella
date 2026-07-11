program gossip_tcp;
{ Pastella spine over REAL PAL TCP (loopback, one process, non-blocking poll).
  Server holds two objects; client connects and fetches via offer/fetch:
  server sends HAVE (hashes), client sends WANT (what it lacks), server sends
  DATA. Client verifies each object's content hash. Native PAL sockets, no
  Synapse — the same calls run on ESP32 lwIP. }

uses sysutils, sha256, platform;

const PORT = 34711;

function HashOf(const d: AnsiString): AnsiString;
begin HashOf := Sha256Hex(Sha256(d)); end;

{ length-prefixed frame: 4-byte big-endian length + payload }
function SendFrame(fd: Integer; const s: AnsiString): Boolean;
var hdr: AnsiString; off, tot: Integer; n: Int64; L: Integer;
begin
  L := Length(s);
  hdr := Chr((L shr 24) and 255) + Chr((L shr 16) and 255) +
         Chr((L shr 8) and 255) + Chr(L and 255);
  hdr := hdr + s;
  off := 0; tot := Length(hdr); SendFrame := False;
  while off < tot do
  begin
    PalPoll(fd, PAL_POLL_OUT, 2000);
    n := PalSend(fd, @hdr[off + 1], tot - off);
    if n <= 0 then exit;
    off := off + Integer(n);
  end;
  SendFrame := True;
end;

function RecvExact(fd, count: Integer): AnsiString;
var buf: AnsiString; got: Integer; n: Int64;
begin
  SetLength(buf, count); got := 0;
  while got < count do
  begin
    PalPoll(fd, PAL_POLL_IN, 2000);
    n := PalRecv(fd, @buf[got + 1], count - got);
    if n <= 0 then break;
    got := got + Integer(n);
  end;
  SetLength(buf, got);
  RecvExact := buf;
end;

function RecvFrame(fd: Integer): AnsiString;
var h: AnsiString; L: Integer;
begin
  h := RecvExact(fd, 4);
  if Length(h) < 4 then begin RecvFrame := ''; exit; end;
  L := (Ord(h[1]) shl 24) or (Ord(h[2]) shl 16) or (Ord(h[3]) shl 8) or Ord(h[4]);
  RecvFrame := RecvExact(fd, L);
end;

var
  srv, cli, conn: Integer;
  objA, objB, gotA, gotB, have, want: AnsiString;
  rc, pr, i, okcount: Integer;

begin
  objA := 'first object over the wire';
  objB := 'second object over the wire';

  { server: bind/listen, non-blocking }
  srv := PalSocket(PAL_NET_AF_INET, PAL_NET_SOCK_STREAM, 0);
  PalSetSocketReuseAddr(srv, 1);
  if PalBindIpv4(srv, PAL_NET_IP_LOOPBACK, PORT) < 0 then begin WriteLn('FAIL bind'); Halt(2); end;
  if PalListen(srv, 4) < 0 then begin WriteLn('FAIL listen'); Halt(3); end;
  PalSetSocketNonBlocking(srv, 1);

  { client: connect (non-blocking) }
  cli := PalSocket(PAL_NET_AF_INET, PAL_NET_SOCK_STREAM, 0);
  PalSetSocketNonBlocking(cli, 1);
  PalConnectIpv4(cli, PAL_NET_IP_LOOPBACK, PORT);

  { accept the connection }
  conn := -1;
  for i := 1 to 200 do
  begin
    pr := PalPoll(srv, PAL_POLL_IN, 20);
    if (pr and PAL_POLL_IN) <> 0 then begin conn := PalAccept(srv); if conn >= 0 then break; end;
  end;
  if conn < 0 then begin WriteLn('FAIL accept'); Halt(4); end;
  PalSetSocketNonBlocking(conn, 1);
  { make sure client finished connecting }
  PalPoll(cli, PAL_POLL_OUT, 2000);

  { ---- offer/fetch over the wire ---- }
  { server -> HAVE (two hashes, newline-separated) }
  have := HashOf(objA) + #10 + HashOf(objB);
  SendFrame(conn, have);

  { client receives HAVE, wants both (has nothing), sends WANT }
  have := RecvFrame(cli);
  want := have;                 { client lacks all → wants everything offered }
  SendFrame(cli, want);

  { server receives WANT, sends DATA for each requested hash }
  want := RecvFrame(conn);
  { we know the two objects; send both as DATA frames }
  SendFrame(conn, objA);
  SendFrame(conn, objB);

  { client receives DATA, verifies content hashes }
  gotA := RecvFrame(cli);
  gotB := RecvFrame(cli);

  PalClose(cli); PalClose(conn); PalClose(srv);

  okcount := 0;
  if HashOf(gotA) = HashOf(objA) then okcount := okcount + 1;
  if HashOf(gotB) = HashOf(objB) then okcount := okcount + 1;

  WriteLn('client fetched ', okcount, ' / 2 objects, content-hash verified');
  WriteLn('  objA: ', gotA);
  WriteLn('  objB: ', gotB);
  if okcount = 2 then WriteLn('TCP GOSSIP OK') else WriteLn('FAIL');
end.
