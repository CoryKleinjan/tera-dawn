extends SmokeArea
## The field maps' monsters (splitters, hoppers, shooters).

## The new field maps: walking west out of the village, and monsters that split, hop and shoot.
func check() -> void:
	var ch := _me().character
	# a monster bumping you off the portal would make this flaky
	_me().inv = 100000
	var west: PortalDef = Content.map(Character.START_MAP).portals.filter(func(p: PortalDef) -> bool: return p.target_map == &"sunny_slope")[0]
	_teleport(Vector2(west.x, 620))
	await _ticks(2)
	await _tap("move_up")
	await _ticks(TDPlayer.PORTAL_FADE_TICKS + 4)
	_check(world.map.id == &"sunny_slope", "the village's west portal leads to Sunny Slope")
	_me().inv = 0
	# a Sporecap splits into Spore Puffs when it's defeated
	Net.server.enter_map(_me(), &"mushroom_dell", 300)
	await _ticks(3)
	var dell: MapInstance = Net.server.maps[&"mushroom_dell"]
	var cap: SimMob = dell.mobs.filter(func(m: SimMob) -> bool: return m.def.id == &"sporecap")[0]
	_check(cap.children.size() == 2 and cap.children.all(func(c: SimMob) -> bool: return c.dead and c.asleep), "a Sporecap's Spore Puffs wait asleep")
	_check(world.mobs().size() == dell.mobs.size(), "the client numbers split-off monsters the same way")
	dell.kill_mob(cap, _me())
	await _ticks(3)
	_check(cap.children.all(func(c: SimMob) -> bool: return not c.dead), "defeating a Sporecap releases its Spore Puffs")
	_check(not world.mobs()[cap.children[0].index].dead, "and the client sees them")
	for c in cap.children:
		dell.kill_mob(c, _me())
	await _ticks(60)
	_check(cap.children.all(func(c: SimMob) -> bool: return c.dead and c.asleep), "defeated Spore Puffs go back to sleep instead of respawning")
	# hoppers hop
	Net.server.enter_map(_me(), &"sunny_slope", 300)
	await _ticks(3)
	var slope: MapInstance = Net.server.maps[&"sunny_slope"]
	var hopper: SimMob = slope.mobs.filter(func(m: SimMob) -> bool: return m.def.jumps and not m.dead)[0]
	var hopped := false
	# a hop starts at random (1 in 80 a tick): give it plenty of ticks
	for i in 4000:
		hopper.step()
		hopped = hopped or hopper.hop > 0.0
		if hopped:
			break
	_check(hopped and hopper.body_position().y <= hopper.plat.y, "a Tide Dewling hops")
	# an Acorn Sentry never moves and shoots anyone near it; the shot lands where they stood
	Net.server.enter_map(_me(), &"thornwood", 300)
	await _ticks(3)
	var wood: MapInstance = Net.server.maps[&"thornwood"]
	var sentry: SimMob = wood.mobs.filter(func(m: SimMob) -> bool: return m.def.id == &"acorn_sentry" and not m.dead)[0]
	var x0 := sentry.position.x
	# only the sentry: another monster's touch would also leave the player blinking
	var others := _hold_mobs(wood, [sentry])
	_teleport(Vector2(sentry.position.x + 150, sentry.plat.y))
	ch.health.reset(ch.max_hearts())
	var hp: int = ch.health.hp
	sentry.moves.cool[0] = 0
	sentry.moves.gap = 0
	_me().inv = 0 # not still blinking from an earlier hit
	var shots := 0
	var landed := false
	for i in 400:
		await _ticks(1)
		_me().position = Vector2(x0 + 150, sentry.plat.y)
		world.player.position = _me().position
		shots += world.fx_layer.get_children().filter(func(n: Node) -> bool: return n is TDProjectile).size()
		# a hit costs HP; a dodge still leaves the player blinking
		landed = ch.health.hp < hp or _me().inv > 0
		if landed:
			break
	_check(shots > 0, "the client sees the sentry's shot fly")
	_check(landed, "the shot hits a player who stays put")
	_check(sentry.position.x == x0, "the sentry never moves")
	_release_mobs(others)
	_me().inv = 100000
	Net.server.enter_map(_me(), &"meadow", 300)
	await _ticks(3)
