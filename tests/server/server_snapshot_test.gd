extends TestCase
## Map updates (snapshots) are packed small enough to fit in one network packet on every
## map, even full of players, and come out the other side as they went in.

const ServerHarness := preload("res://tests/framework/server_helpers.gd")
## A packet carries about 1,392 bytes; leave room for the RPC's own header.
const MAX_BYTES := 1200

var h: ServerHarness

func before_each() -> void:
	h = ServerHarness.new()

func after_each() -> void:
	h.close()

func test_a_full_update_of_every_map_fits_in_one_packet_with_six_players() -> void:
	var worst := [0, &""]
	for id: StringName in Content.maps.keys():
		var mi := h.server.map_instance(id)
		for i in 6:
			var p := SimPlayer.new(100 + i, Character.create("Long Name %d" % i))
			p.animation = &"climb_idle"
			mi.players[p.peer] = p
		var size := mi.snapshot(true).size()
		if size > worst[0]:
			worst = [size, id]
		mi.players.clear()
	check(worst[0] <= MAX_BYTES, "the biggest full update (%s, %d bytes) fits in %d" % [worst[1], worst[0], MAX_BYTES])

func test_monsters_and_players_survive_the_trip() -> void:
	var mob := SnapshotCodec.mob_record(7, [1234.4, 619.6, -1, 640, SnapshotFlags.MOB_HURT | SnapshotFlags.MOB_AGGRO, 2])
	check_eq(mob.size(), SnapshotCodec.MOB_BYTES, "a monster is %d bytes" % SnapshotCodec.MOB_BYTES)
	var records: Array[PackedByteArray] = [mob]
	var snap := SnapshotCodec.decode(SnapshotCodec.encode(4242, records, [[1918316577, 300.2, 820.0, -1, &"walk", SnapshotFlags.PLAYER_CLIMBING]]))
	check_eq(snap["tick"], 4242, "tick")
	check_eq(snap["mobs"], [[7, [1234.0, 620.0, -1, 640, SnapshotFlags.MOB_HURT | SnapshotFlags.MOB_AGGRO, 2]]], "the monster, to the nearest pixel, and its move")
	check_eq(snap["players"], [[1918316577, 300.0, 820.0, -1, &"walk", SnapshotFlags.PLAYER_CLIMBING]], "the player")
