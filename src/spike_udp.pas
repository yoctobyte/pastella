program spike_udp;
{ Pastella capability spike — proves the toolchain and the two primitives the
  spine needs, on NATIVE PAL (no Synapse, no wrapper):
    * PAL_NET sockets  (PalSocket / PalBind / PalSendTo / PalPoll / PalRecvFrom)
      — the same calls run on desktop POSIX and on ESP32 lwIP.
    * SHA-256 content hashing (lib/rtl/sha256).
  A UDP loopback round-trip whose payload we then content-hash. If this builds
  with the pinned pxx compiler and prints a matching hash, the spine is buildable.

  Axis that matters in 2026: POSIX-or-not, kernel-or-not. PAL is that seam.
  Windows is not a target. }

uses platform, sha256;

const
  SPIKE_PORT = 34700;

var
  srv, cli: Integer;
  msg, buf: array[0..7] of Byte;
  peerAddr: LongWord;
  peerPort, pr, rc, i: Integer;
  n: Int64;
  got, want: AnsiString;

begin
  { payload = "PASTELLA" }
  msg[0]:=Ord('P'); msg[1]:=Ord('A'); msg[2]:=Ord('S'); msg[3]:=Ord('T');
  msg[4]:=Ord('E'); msg[5]:=Ord('L'); msg[6]:=Ord('L'); msg[7]:=Ord('A');

  srv := PalSocket(PAL_NET_AF_INET, PAL_NET_SOCK_DGRAM, 0);
  if srv < 0 then begin WriteLn('FAIL: server socket'); Halt(2); end;
  PalSetSocketReuseAddr(srv, 1);
  rc := PalBindIpv4(srv, PAL_NET_IP_LOOPBACK, SPIKE_PORT);
  if rc < 0 then begin WriteLn('FAIL: bind'); Halt(3); end;
  PalSetSocketNonBlocking(srv, 1);

  cli := PalSocket(PAL_NET_AF_INET, PAL_NET_SOCK_DGRAM, 0);
  if cli < 0 then begin WriteLn('FAIL: client socket'); Halt(4); end;

  n := PalSendToIpv4(cli, @msg[0], 8, PAL_NET_IP_LOOPBACK, SPIKE_PORT);
  if n <> 8 then begin WriteLn('FAIL: sendto n=', n); Halt(5); end;

  pr := PalPoll(srv, PAL_POLL_IN, 1000);
  if (pr and PAL_POLL_IN) = 0 then begin WriteLn('FAIL: poll timeout'); Halt(6); end;

  peerAddr := 0; peerPort := 0;
  n := PalRecvFromIpv4(srv, @buf[0], 8, peerAddr, peerPort);
  if n <> 8 then begin WriteLn('FAIL: recvfrom n=', n); Halt(7); end;

  { content-hash the received datagram }
  got := '';
  for i := 0 to 7 do got := got + Chr(buf[i]);
  want := 'PASTELLA';

  PalClose(cli); PalClose(srv);

  if got <> want then begin WriteLn('FAIL: payload mismatch'); Halt(8); end;

  WriteLn('PAL_NET loopback ok: ', got);
  { Sha256 -> raw 32-byte digest; Sha256Hex hex-encodes it (it is NOT a hasher). }
  WriteLn('SHA-256(payload) = ', Sha256Hex(Sha256(got)));
  WriteLn('SPIKE OK');
end.
