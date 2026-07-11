program disco_probe;
{ Does loopback UDP broadcast (127.255.255.255) reach a listener bound on the
  same port? Foundation check for zero-seed discovery. }
uses sysutils, platform;
const DP = 34999; SOL_SOCKET = 1; SO_BROADCAST = 6; SO_REUSEPORT = 15;
var srv, cli, one, pr, pa, pp: Integer; msg, buf: array[0..15] of Byte; n: Int64; i: Integer;
    LB_BCAST: LongWord;
begin
  LB_BCAST := (127 shl 24) or (255 shl 16) or (255 shl 8) or 255;  { 127.255.255.255 }
  for i := 0 to 7 do msg[i] := Ord('D');

  srv := PalSocket(PAL_NET_AF_INET, PAL_NET_SOCK_DGRAM, 0);
  PalSetSocketReuseAddr(srv, 1);
  one := 1; PalSetSockOpt(srv, SOL_SOCKET, SO_REUSEPORT, @one, 4);
  if PalBindIpv4(srv, 0, DP) < 0 then begin WriteLn('FAIL bind (0.0.0.0)'); Halt(2); end;
  PalSetSocketNonBlocking(srv, 1);

  cli := PalSocket(PAL_NET_AF_INET, PAL_NET_SOCK_DGRAM, 0);
  one := 1; PalSetSockOpt(cli, SOL_SOCKET, SO_BROADCAST, @one, 4);

  n := PalSendToIpv4(cli, @msg[0], 8, LB_BCAST, DP);
  WriteLn('broadcast sent n=', n);

  pr := PalPoll(srv, PAL_POLL_IN, 1000);
  if (pr and PAL_POLL_IN) = 0 then begin WriteLn('DISCO BROADCAST: no delivery (loopback bcast blocked)'); Halt(1); end;
  pa := 0; pp := 0;
  n := PalRecvFromIpv4(srv, @buf[0], 8, pa, pp);
  WriteLn('received n=', n, ' from-port=', pp);
  if n = 8 then WriteLn('DISCO BROADCAST OK') else WriteLn('FAIL recv');
end.
