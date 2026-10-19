extends TestCase
## Going from room to room the Hollow Knight way in a running game (RoomExits): walking off a
## room's side where a way is takes you to the facing side of the next room, still walking in;
## Down + Jump at a bottom way drops you into the room below; jumping up at a top way takes you
## into the room above. A side of the room with no way stays a stop, and Up does nothing at a way.
## Picks open ways (no lock, gate or shortcut) on real maps of the shaped zones.

var ui: UiHelpers
var me: TDPlayer

func before_each() -> void:
	ui = UiHelpers.new(self)
	await ui.start()
	me = ui.world.player

func after_each() -> void:
	for a in ["jump", "move_left", "move_right", "move_down", "move_up"]:
		Input.action_release(a)
	ui.stop()

## An open way out through `side` with a way back, as [map, portal, the way back], from a
## field of a shaped zone.
func _find(side: RoomExits.Side) -> Array:
	var ids := Content.maps.keys()
	ids.sort()
	for id in ids:
		var m: MapDef = Content.maps[id]
		if m.town:
			continue
		for p in m.portals:
			if p.locked() or RoomExits.side_of(m, p) != side:
				continue
			var back := RoomExits.way_back(m, p)
			if back and not back.locked():
				return [m, p, back]
	return []

## Ticks until the map is `id` (at most `n`), or false.
func _arrive_in(id: StringName, n := 120) -> bool:
	for i in n:
		await ui.ticks(1)
		if ui.world.map.id == id and me._portal_t == 0:
			return true
	return false

func _ledge_y(p: PortalDef) -> float:
	return ui.world.platforms[p.platform].y

func test_walking_off_a_side_way_comes_out_walking_in_at_the_facing_side() -> void:
	for side in [RoomExits.Side.RIGHT, RoomExits.Side.LEFT]:
		var w := _find(side)
		if not check(not w.is_empty(), "a field has a %s way" % RoomExits.Side.keys()[side]):
			continue
		var m: MapDef = w[0]
		var p: PortalDef = w[1]
		var back: PortalDef = w[2]
		await ui.enter_map(m.id, p.x)
		var right: bool = side == RoomExits.Side.RIGHT
		ui.teleport(Vector2(m.width - 40.0 if right else 40.0, _ledge_y(p)))
		me.on_ground = true
		var key := "move_right" if right else "move_left"
		Input.action_press(key)
		var came := await _arrive_in(p.target_map)
		Input.action_release(key)
		if not check(came, "walked off %s's %s side into %s" % [m.id, RoomExits.Side.keys()[side], p.target_map]):
			continue
		var to: MapDef = Content.maps[p.target_map]
		var edge := me.position.x if right else to.width - me.position.x
		check(edge < RoomExits.ARRIVE_IN + 40.0, "came out by the facing edge of %s (%d px in)" % [to.id, edge])
		check(absf(me.position.y - _ledge_y(back)) < 2.0, "on the way back's ledge")
		check(signf(me.vel.x) == (1.0 if right else -1.0), "still walking into the room")
		await ui.ticks(TDPlayer.ARRIVE_TICKS + 10)
		check(ui.world.map.id == to.id, "walking in doesn't walk straight back out")

func test_a_side_with_no_way_stays_a_stop() -> void:
	await ui.enter_map(&"meadow", 200)
	ui.teleport(Vector2(30, 620))
	me.on_ground = true
	Input.action_press("move_left")
	await ui.ticks(40)
	Input.action_release("move_left")
	check(ui.world.map.id == &"meadow" and me._portal_t == 0, "still on the map")
	check(me.position.x >= TDPlayer.EDGE, "stopped at the edge")

func test_down_and_jump_at_a_bottom_way_drops_into_the_room_below() -> void:
	var w := _find(RoomExits.Side.BOTTOM)
	if not check(not w.is_empty(), "a field has a bottom way"):
		return
	var m: MapDef = w[0]
	var p: PortalDef = w[1]
	var back: PortalDef = w[2]
	await ui.enter_map(m.id, p.x)
	ui.teleport(Vector2(p.x, _ledge_y(p)))
	me.on_ground = true
	await ui.ticks(2)
	Input.action_press("move_up")
	await ui.ticks(2)
	Input.action_release("move_up")
	await ui.ticks(20)
	check(ui.world.map.id == m.id, "still here after pressing Up")
	ui.teleport(Vector2(p.x, _ledge_y(p)))
	me.on_ground = true
	await ui.ticks(2)
	Input.action_press("move_down")
	Input.action_press("jump")
	var came := await _arrive_in(p.target_map)
	Input.action_release("jump")
	Input.action_release("move_down")
	if not check(came, "dropped from %s into %s" % [m.id, p.target_map]):
		return
	check(absf(me.position.x - back.x) < RoomExits.SPOT, "came in over the top way of the room below")
	check(me.position.y < _ledge_y(back) and not me.on_ground, "dropping in from above")
	await ui.ticks(60)
	check(me.on_ground, "landed")

func test_jumping_up_at_a_top_way_climbs_into_the_room_above() -> void:
	var w := _find(RoomExits.Side.TOP)
	if not check(not w.is_empty(), "a field has a top way"):
		return
	var m: MapDef = w[0]
	var p: PortalDef = w[1]
	var back: PortalDef = w[2]
	await ui.enter_map(m.id, p.x)
	ui.teleport(Vector2(p.x, _ledge_y(p)))
	me.on_ground = true
	await ui.ticks(2)
	Input.action_press("jump")
	var came := await _arrive_in(p.target_map)
	Input.action_release("jump")
	if not check(came, "jumped up from %s into %s" % [m.id, p.target_map]):
		return
	check(absf(me.position.x - back.x) < RoomExits.SPOT, "came up at the bottom way of the room above")
	check(me.vel.y < 0.0, "hopping up out of it")
