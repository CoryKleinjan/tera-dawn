class_name SnapshotCodec
extends RefCounted
## Packs the map update the server sends many times a second (see TDServer.SNAPSHOT_EVERY)
## into bytes, so even a busy map fits in one network packet (about 1,400 bytes; a lost
## piece of a bigger one loses the whole update). Only what changes every tick goes in it:
## where monsters and players are, which way they face, HP, animation and flags. Names,
## levels, jobs and pets go separately, reliably and only when they change
## (MapInstance.send_player_info, ev_player_info).
##
## Layout (little-endian):
##   u32 tick, u16 monster count, then per monster: u16 index, s16 x, s16 y, s8 dir,
##   u16 hp (0..1000), u16 flags, u8 move (1 + its index in MonsterDef.moves, 0 for none);
##   u8 player count, then per player: u32 peer, s16 x, s16 y, s8 face, u8 flags,
##   u8 animation name length, the name's UTF-8 bytes.

## Bytes one monster takes.
const MOB_BYTES := 12

## One monster's record, from SimMob.snapshot() ([x, y, dir, hp, flags, move]).
static func mob_record(index: int, state: Array) -> PackedByteArray:
	var b := StreamPeerBuffer.new()
	b.put_u16(index)
	b.put_16(_coord(state[0]))
	b.put_16(_coord(state[1]))
	b.put_8(int(state[2]))
	b.put_u16(clampi(int(state[3]), 0, 1000))
	b.put_u16(int(state[4]))
	b.put_u8(int(state[5]) if state.size() > 5 else 0)
	return b.data_array

## The whole update: `mob_records` joined from mob_record(), and players as
## SimPlayer.motion() rows ([peer, x, y, face, animation, flags]).
static func encode(tick: int, mob_records: Array[PackedByteArray], players: Array) -> PackedByteArray:
	var b := StreamPeerBuffer.new()
	b.put_u32(tick)
	b.put_u16(mob_records.size())
	for r in mob_records:
		b.put_data(r)
	b.put_u8(players.size())
	for row: Array in players:
		b.put_u32(int(row[0]))
		b.put_16(_coord(row[1]))
		b.put_16(_coord(row[2]))
		b.put_8(int(row[3]))
		b.put_u8(int(row[5]))
		var anim := String(row[4]).to_utf8_buffer()
		b.put_u8(anim.size())
		b.put_data(anim)
	return b.data_array

## The update as {"tick", "mobs": [[index, [x, y, dir, hp, flags, move]], ...],
## "players": [[peer, x, y, face, animation, flags], ...]}.
static func decode(data: PackedByteArray) -> Dictionary:
	var b := StreamPeerBuffer.new()
	b.data_array = data
	var out := {"tick": b.get_u32(), "mobs": [], "players": []}
	for i in b.get_u16():
		var index := b.get_u16()
		out["mobs"].append([index, [float(b.get_16()), float(b.get_16()), b.get_8(), b.get_u16(), b.get_u16(), b.get_u8()]])
	for i in b.get_u8():
		var peer := b.get_u32()
		var x := float(b.get_16())
		var y := float(b.get_16())
		var face := b.get_8()
		var flags := b.get_u8()
		var anim := StringName((b.get_data(b.get_u8())[1] as PackedByteArray).get_string_from_utf8())
		out["players"].append([peer, x, y, face, anim, flags])
	return out

## Positions are whole game pixels; maps are far smaller than ±32,767.
static func _coord(v: float) -> int:
	return clampi(roundi(v), -32768, 32767)
