program gossip_mem;
{ Pastella spine, in-memory: content-addressed anti-entropy proven deterministic,
  no sockets. The pure core — a content store + offer/fetch reconciliation. If N
  peers gossip pairwise, every object reaches every peer. This IS the N-peer
  test harness. }

uses sysutils, sha256;

type
  TItem  = record hash, data: AnsiString; end;
  TStore = record items: array of TItem; end;

function HashOf(const data: AnsiString): AnsiString;
begin
  HashOf := Sha256Hex(Sha256(data));
end;

function StoreHas(const s: TStore; const h: AnsiString): Boolean;
var i: Integer;
begin
  StoreHas := False;
  for i := 0 to High(s.items) do
    if s.items[i].hash = h then StoreHas := True;
end;

procedure StorePut(var s: TStore; const data: AnsiString);
var h: AnsiString; n: Integer;
begin
  h := HashOf(data);
  if StoreHas(s, h) then exit;
  n := Length(s.items);
  SetLength(s.items, n + 1);
  s.items[n].hash := h;
  s.items[n].data := data;
end;

function StoreGet(const s: TStore; const h: AnsiString): AnsiString;
var i: Integer;
begin
  StoreGet := '';
  for i := 0 to High(s.items) do
    if s.items[i].hash = h then StoreGet := s.items[i].data;
end;

{ --- reconciliation (pure) ---
  dst offers nothing; src offers its hash list (HAVE); dst returns the subset it
  lacks (WANT). Then src hands over the DATA. One direction of anti-entropy. }
procedure SyncOneWay(const src: TStore; var dst: TStore);
var i: Integer; h: AnsiString;
begin
  for i := 0 to High(src.items) do
  begin
    h := src.items[i].hash;          // HAVE
    if not StoreHas(dst, h) then     // WANT (dst lacks it)
      StorePut(dst, StoreGet(src, h)); // DATA
  end;
end;

procedure GossipPair(var a, b: TStore);
begin
  SyncOneWay(a, b);
  SyncOneWay(b, a);
end;

var
  peer: array[0..2] of TStore;
  i, round: Integer;

begin
  { seed peer0 with two objects, peer2 with one; peers 0..2 in a line: 0-1, 1-2 }
  StorePut(peer[0], 'hello from peer0');
  StorePut(peer[0], 'second object');
  StorePut(peer[2], 'a message that starts at peer2');

  WriteLn('before gossip:');
  for i := 0 to 2 do WriteLn('  peer', i, ' has ', Length(peer[i].items), ' objects');

  { a couple of pairwise rounds along the line — convergence }
  for round := 1 to 2 do
  begin
    GossipPair(peer[0], peer[1]);
    GossipPair(peer[1], peer[2]);
  end;

  WriteLn('after gossip:');
  for i := 0 to 2 do WriteLn('  peer', i, ' has ', Length(peer[i].items), ' objects');

  { every peer should now hold all 3 distinct objects }
  if (Length(peer[0].items) = 3) and (Length(peer[1].items) = 3)
     and (Length(peer[2].items) = 3) then
    WriteLn('CONVERGED — content-addressed gossip works')
  else
    WriteLn('FAIL — did not converge');
end.
