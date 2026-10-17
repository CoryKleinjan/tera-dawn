class_name MapInstance
extends RefCounted
## One map running on the server: its monsters, the items on the ground and the players
## on it. The server keeps one per map that has been visited and steps the ones with
## players on them. Everything the players see happen here (hits, kills, EXP, drops,
## pickups) is decided here and sent to the clients on this map as events.

## Game pixels between the items a monster drops.
const DROP_SPACING := 26.0
## How high above a player's feet a fake wall must reach for them to have stepped into it.
const WALK_IN_HEIGHT := 20.0
## How wide and how high above the feet a Slam's landing reaches, and how far below them
## (a cracked floor lies on the platform it lands on).
const SLAM_AREA := Vector2(90.0, 40.0)
const SLAM_DEPTH := 10.0
const BAD := Color("ff8a99")

var server: TDServer
var def: MapDef
var layout: MapLayout
var tick := 0
## peer id -> SimPlayer
var players := {}
var mobs: Array[SimMob] = []
## drop id -> SimDrop
var drops := {}
## The chests and walls players break (MapDef.breakables), in the map's order.
var breakables: Array[SimBreakable] = []
## Each monster's record as last sent in a snapshot, so unchanged ones can be left out.
var _sent_mobs: Array[PackedByteArray] = []
## peer -> the player info (info()) last sent to this map's players.
var _sent_info := {}
## Its tear (MapDef.tear_platform) has opened, and what came out of it has stepped out.
var tear_open := false
var _tear_woken := false

func _init(s: TDServer, map_def: MapDef) -> void:
	server = s
	def = map_def
	layout = MapLayout.new(map_def)
	var steps := WorldRoutes.steps_from_town()
	var strength := {}
	for r in def.roster():
		var plat := layout.platforms[r[1]]
		if not strength.has(r[0]):
			strength[r[0]] = MonsterStrength.on_map(r[0], def.id, steps)
		var m := SimMob.new(self, mobs.size(), r[0], plat, r[3].patrol_area(plat), strength[r[0]])
		if r[2] >= 0:
			m.sleep()
			m.parent = mobs[r[2]]
			mobs[r[2]].children.append(m)
		elif r[3].from_tear:
			m.sleep()
			m.from_tear = true
		mobs.append(m)
	for i in def.breakables.size():
		var b := def.breakables[i]
		breakables.append(SimBreakable.new(i, b, layout.platforms[b.platform].y))

func step() -> void:
	tick += 1
	for p in players.values():
		if p.step():
			server.revive(p)
		elif p.character.pet != &"":
			_pet_step(p)
	for m in mobs:
		m.step()
	for id in drops.keys():
		var d: SimDrop = drops[id]
		d.step()
		if d.expired():
			_remove_drop(d, 0)
		elif d.item.is_currency:
			for p in players.values():
				if d.can_loot(p):
					pick_up(p, d)
					break

# ---------- players coming and going ----------

## Puts the player on this map at `x`, standing on platform `platform` (0 is the floor).
func add_player(p: SimPlayer, x: float, platform := 0) -> void:
	p.map = self
	p.position = Vector2(x, layout.platforms[platform].y)
	p.since_move = 0
	p.hurt_here = false
	p.character.map_id = def.id
	players[p.peer] = p
	# the newcomer needs everyone's info, and everyone needs theirs: resend it all
	_sent_info.clear()

func remove_player(p: SimPlayer) -> void:
	players.erase(p.peer)
	_sent_info.erase(p.peer)
	for m in mobs:
		m.forget(p.peer)
	for b in breakables:
		b.forget(p.peer)

## Everything a client needs on arriving: monsters and items as they are right now, and
## whether the tear is open.
func full_state() -> Dictionary:
	return {"mobs": mobs.map(func(m: SimMob) -> Array: return m.snapshot()),
		"drops": drops.values().map(func(d: SimDrop) -> Array: return d.snapshot()),
		"tear": tear_open}

# ---------- the tear ----------

## Opens the map's tear when the player first stands on its platform: everyone here sees
## it, `tear_scene` plays for them, and what's waiting steps out once it ends.
func check_tear(p: SimPlayer) -> void:
	if tear_open or def.tear_platform < 0 or def.tear_platform >= layout.platforms.size():
		return
	if not p.stands_on(layout.platforms[def.tear_platform]):
		return
	tear_open = true
	broadcast(&"ev_tear", [])
	server.scenes.play(p, def.tear_scene)
	if p.scene == &"":
		wake_tear(p)

## The monsters waiting for the tear step out of it, angry at `p` (once; when the tear
## scene ends, or right away if it didn't play).
func wake_tear(p: SimPlayer) -> void:
	if not tear_open or _tear_woken:
		return
	_tear_woken = true
	var x := def.tears[0].x if not def.tears.is_empty() else p.position.x
	for m in mobs:
		if m.from_tear:
			m.wake(x, p.peer)

## Where everyone and everything is, sent to this map's players many times a second as
## bytes (SnapshotCodec). Monsters that haven't changed since the last one are left out
## unless `full`, which the server asks for now and then in case an update was lost.
func snapshot(full := false) -> PackedByteArray:
	if _sent_mobs.size() != mobs.size():
		_sent_mobs.resize(mobs.size())
		full = true
	var records: Array[PackedByteArray] = []
	for i in mobs.size():
		var r := SnapshotCodec.mob_record(i, mobs[i].snapshot())
		if full or r != _sent_mobs[i]:
			records.append(r)
			_sent_mobs[i] = r
	return SnapshotCodec.encode(tick, records, players.values().map(func(p: SimPlayer) -> Array: return p.motion()))

## Sends this map's players the info (name, job, guild, pet, worn gear) of
## every player whose info changed since it was last sent. Reliable, unlike snapshots.
func send_player_info() -> void:
	for p: SimPlayer in players.values():
		var info := p.info()
		if _sent_info.get(p.peer) != info:
			_sent_info[p.peer] = info
			broadcast(&"ev_player_info", [p.peer, info])

## Sends an event to every player on this map (except `skip`).
func broadcast(event: StringName, args: Array, skip := 0) -> void:
	for peer in players:
		if peer != skip:
			Net.send(peer, event, args)

func tell(p: SimPlayer, text: String, col: Color) -> void:
	Net.send(p.peer, &"ev_log", [text, col.to_html()])

## Shows the player what they just gained (&"essence" or &"shards") as a small number rising
## over them, rather than a line in the message log.
func show_gain(p: SimPlayer, kind: StringName, amount: int) -> void:
	Net.send(p.peer, &"ev_gain", [kind, amount])

## The NPC with this id when the player is close enough to deal with them, or null. Only
## placements the player can see count (NpcPlacement.shown_to).
func npc_near(p: SimPlayer, npc_id: StringName, reach := 160.0) -> NpcDef:
	for placement in def.npcs:
		var at := Vector2(placement.x, layout.platforms[placement.platform].y)
		if placement.npc.id == npc_id and p.position.distance_to(at) <= reach and placement.shown_to(p.character):
			return placement.npc
	return null

## Tosses `item` down by the player's feet, theirs to pick up (a quest's gift_on_accept).
func toss_to(p: SimPlayer, item: ItemDef) -> void:
	var ground := layout.ground_below(p.position)
	var flight := DropFlight.create(p.position + Vector2(0, -90), ground, p.position.x + 24.0 * p.face)
	spawn_drop(item, 1, null, flight, p.peer)

# ---------- combat ----------

## How much harder a melee blow knocks a monster back than a shot does.
const MELEE_KNOCKBACK := 1.6

## Resolves a player's skill against the monsters in front of them (or above or below them,
## for an aimed attack, or all round for one that hits `around`). Returns how many were hit.
func use_skill(p: SimPlayer, skill: SkillDef, aim := Hitbox.Aim.AHEAD) -> int:
	_strike_breakables(p, skill, aim)
	if skill.ambush > 0.0:
		_ambush(p, skill)
	if skill.slam:
		_slam(p, skill)
	var targets := _targets(p, skill, aim)
	var lvl := p.character.skills.level(skill)
	var push := skill.knockback * (1.0 if skill.is_ranged() else MELEE_KNOCKBACK)
	# [mob index, [[damage, kind], ...]] for every monster hit, shown by every client
	var lines := []
	for m in targets:
		lines.append([m.index, _strike(p, skill, lvl, m)])
	var killed: Array[SimMob] = []
	for m in targets:
		if m.health.is_dead():
			killed.append(m)
			continue
		# up and down blows push it away from the player, whichever way they face
		var away := p.face
		if (aim != Hitbox.Aim.AHEAD or skill.around) and m.position.x != p.position.x:
			away = 1 if m.position.x > p.position.x else -1
		m.hurt(away, p.peer, push)
		_control(p, skill, lvl, m)
	broadcast(&"ev_skill", [p.peer, skill.id, p.position.x, p.position.y, p.face, lines, aim])
	for m in killed:
		kill_mob(m, p)
	return targets.size()

## Hits `m` with `skill` (at `lvl`), its `hits` lines, and takes the damage off. Returns the
## lines as [[damage, kind], ...].
func _strike(p: SimPlayer, skill: SkillDef, lvl: int, m: SimMob) -> Array:
	var hits := []
	for i in skill.hits:
		if m.health.is_dead():
			break
		var hit := Combat.player_hit(skill, m.def, p.character)
		if hit["miss"]:
			hits.append([0, "miss"])
			continue
		var dmg: int = hit["damage"]
		m.health.damage(dmg)
		hits.append([dmg, "crit" if hit["crit"] else "hit"])
	return hits

## What `skill` does to a monster still standing beyond damage: slows, roots, pins,
## launches, stuns, pulls.
func _control(p: SimPlayer, skill: SkillDef, lvl: int, m: SimMob) -> void:
	if skill.slow_ticks(lvl) > 0:
		m.slow(skill.slow_ticks(lvl))
	if skill.root_ticks(lvl) > 0:
		m.root(skill.root_ticks(lvl))
	if skill.pin:
		m.hold_up(skill.root_ticks(lvl))
	if skill.launch > 0.0:
		m.launch(skill.launch)
	if skill.stun_ticks(lvl) > 0:
		m.stun(skill.stun_ticks(lvl))
	if skill.pull > 0.0:
		m.drag_to(p.position.x + p.face * skill.pull)

## An ambush (SkillDef.ambush): puts `p` in the middle of the biggest group of monsters
## ahead, where their own screen already put them (SkillDef.ambush_spot), and tells them
## when this map sees it differently.
func _ambush(p: SimPlayer, skill: SkillDef) -> void:
	var bodies: Array[Vector2] = []
	for m in mobs:
		if not m.dead:
			bodies.append(m.body_position())
	var to := skill.ambush_spot(p.position, p.face, bodies)
	if to == Vector2.INF:
		return
	to = Vector2(clampf(to.x, TDPlayer.EDGE, def.width - TDPlayer.EDGE), clampf(to.y, 0.0, def.ground_y))
	if to.distance_to(p.position) > 0.5:
		p.position = to
		Net.send(p.peer, &"ev_place", [to.x, to.y])

## A slam (SkillDef.slam): yanks every monster in the air within the skill's reach on both
## sides of `p` down to the ground before the blow lands.
func _slam(p: SimPlayer, skill: SkillDef) -> void:
	var area := Hitbox.attack_area(p.position, p.face, skill.reach, skill.height)
	area = area.merge(Hitbox.attack_area(p.position, -p.face, skill.reach, skill.height))
	for m in mobs:
		if not m.dead and area.intersects(m.hurtbox.rect_at(m.body_position())):
			m.slam_down()

## Where a skill reaches: ahead of the player (or above or below them, for an aimed attack),
## or both ways for one that hits `around`.
static func _skill_area(p: SimPlayer, skill: SkillDef, aim: Hitbox.Aim) -> Rect2:
	var area := Hitbox.aimed_area(p.position, p.face, aim, skill.reach, skill.height)
	if skill.around:
		area = area.merge(Hitbox.aimed_area(p.position, -p.face, aim, skill.reach, skill.height))
	return area

## The monsters a skill hits, nearest first: those in its area, or for a splash, the nearest
## one in its area and every monster within `splash` of it.
func _targets(p: SimPlayer, skill: SkillDef, aim: Hitbox.Aim) -> Array[SimMob]:
	var area := _skill_area(p, skill, aim)
	var targets: Array[SimMob] = []
	for m in mobs:
		if m.dead or skill.slam and m.controllable() and not m.grounded():
			continue
		if area.intersects(m.hurtbox.rect_at(m.body_position())):
			targets.append(m)
	var from := p.position
	if skill.splash > 0.0 and not targets.is_empty():
		var first: SimMob = targets[0]
		for m in targets:
			if m.position.distance_to(p.position) < first.position.distance_to(p.position):
				first = m
		from = first.position
		targets.clear()
		targets.append(first)
		for m in mobs:
			if m != first and not m.dead and m.body_position().distance_to(first.body_position()) <= skill.splash:
				targets.append(m)
	targets.sort_custom(func(a: SimMob, b: SimMob) -> bool:
		return a.position.distance_to(from) < b.position.distance_to(from))
	if targets.size() > skill.max_targets:
		targets.resize(skill.max_targets)
	return targets

func kill_mob(m: SimMob, killer: SimPlayer) -> void:
	m.die()
	broadcast(&"ev_mob_died", [m.index])
	for i in m.children.size():
		m.children[i].wake(m.position.x + (i - (m.children.size() - 1) / 2.0) * 30.0, killer.peer)
	var from := m.body_position()
	# a kill pays as much EXP as Dawn Essence
	server.give_essence(killer, m.essence(), from)
	server.give_xp(killer, m.essence())
	# the killer's party on this map shares both, and the kill counts for their quests too
	var credited: Array[SimPlayer] = [killer]
	for share in server.social.party_shares(killer, m.essence()):
		server.give_essence(share[0], share[1], from)
		server.give_xp(share[0], share[1])
		credited.append(share[0])
	for p in credited:
		server.quests.record_kill(p, m.def)
	if m.def.boss:
		# everyone at the fight beat it: its Monster Book page (and the arena's way home)
		for p: SimPlayer in players.values():
			if not p in credited:
				p.character.book.record_kill(m.def)
			p.dirty_character = true
	# a boss's relic, for each one at the fight who hasn't unlocked its move yet
	if m.def.relic:
		for p: SimPlayer in players.values():
			if not p.character.has_relic(m.def.relic):
				spawn_drop(m.def.relic, 1, null, DropFlight.create(m.position + Vector2(0, -20), m.plat.y, m.position.x), p.peer)
	var loot := []
	# its own loot, and its zone's runes
	var table: Array[DropEntry] = m.def.drops.duplicate()
	var region: RegionDef = Content.regions.get(def.region)
	if region:
		table.append_array(region.drops)
	for entry in table:
		var amount := entry.roll()
		if amount > 0:
			loot.append([entry.item, amount])
	# a Monster Book card, until the killer's page for it is complete
	if not killer.character.book.complete(m.def) and randf() < CardDef.CHANCE:
		loot.append([Content.card(m.def), 1])
	# quest items only drop for someone on that quest
	for pair in killer.character.quests.quest_drops(m.def, killer.character):
		if randf() < pair[1]:
			loot.append([pair[0], 1])
	# spread out in a row under the monster, like MapleStory
	for i in loot.size():
		var x := clampf(m.position.x + (i - (loot.size() - 1) / 2.0) * DROP_SPACING, m.plat.x + 8, m.plat.x + m.plat.w - 8)
		spawn_drop(loot[i][0], loot[i][1], null, DropFlight.create(m.position + Vector2(0, -20), m.plat.y, x), killer.peer)

# ---------- chests and walls ----------

## Lands the skill's blow on every chest or wall in its area that still stands whole for `p`
## (a fake wall lets it through), and breaks open each one that has taken its last
## (BreakableDef.hits). Only `p` sees it shake or break: everyone breaks their own.
func _strike_breakables(p: SimPlayer, skill: SkillDef, aim: Hitbox.Aim) -> void:
	if breakables.is_empty():
		return
	var area := _skill_area(p, skill, aim)
	for b in breakables:
		if not b.def.walk_through and b.whole_for(p) and area.intersects(b.def.rect(b.foot)):
			# a cracked floor only shakes: it takes a Slam
			if not b.def.slam_only and b.strike(p):
				_break_open(p, b)
			else:
				Net.send(p.peer, &"ev_struck", [b.index, false])

## `p` landed a Slam (RelicDef.Move.SLAM) with their feet at `at`: every chest, wall or
## cracked floor (BreakableDef.slam_only) the landing meets breaks open for them at once.
func slam(p: SimPlayer, at: Vector2) -> void:
	var area := Rect2(at.x - SLAM_AREA.x / 2.0, at.y - SLAM_AREA.y, SLAM_AREA.x, SLAM_AREA.y + SLAM_DEPTH)
	for b in breakables:
		if not b.def.walk_through and b.whole_for(p) and area.intersects(b.def.rect(b.foot)):
			b.forget(p.peer)
			_break_open(p, b)

## `b` breaks open for `p`, for good: its loot spills out for them, a wall opens its
## shortcut (the portal behind it, and its far end on the other map, show from now on), and
## a lever swings over and lifts the gate on the doors with its id (PortalDef.gate).
func _break_open(p: SimPlayer, b: SimBreakable) -> void:
	p.character.find_secret(b.def.id)
	p.dirty_character = true
	Net.send(p.peer, &"ev_struck", [b.index, true])
	var loot := []
	for entry in b.def.loot:
		var amount := entry.roll()
		if amount > 0:
			loot.append([entry.item, amount])
	if b.def.card and not p.character.book.complete(b.def.card):
		loot.append([Content.card(b.def.card), 1])
	var plat := layout.platforms[b.def.platform]
	for i in loot.size():
		var x := clampf(b.foot.x + (i - (loot.size() - 1) / 2.0) * DROP_SPACING, plat.x + 8, plat.x + plat.w - 8)
		spawn_drop(loot[i][0], loot[i][1], null, DropFlight.create(b.foot + Vector2(0, -20), plat.y, x), p.peer)
	if def.portals.any(func(o: PortalDef) -> bool: return o.shortcut == b.def.id):
		tell(p, "You found a hidden way." if b.def.walk_through else "You found a shortcut.", Palette.SUN)
	elif def.portals.any(func(o: PortalDef) -> bool: return o.gate == b.def.id):
		tell(p, "The gate opened.", Palette.SUN)

## What `p` finds by walking: a fake wall they step into fades for them and opens the way
## behind it, like a broken wall, and a secret ledge they stand on is theirs to see on the
## zone map from then on (MapDef.ledge_secret).
func check_secrets(p: SimPlayer) -> void:
	for b in breakables:
		if b.def.walk_through and b.whole_for(p) and b.def.rect(b.foot).has_point(p.position + Vector2(0, -WALK_IN_HEIGHT)):
			_break_open(p, b)
	for i in def.platforms.size():
		if def.platforms[i].secret and p.stands_on(layout.platforms[i + 1]) and p.character.find_secret(def.ledge_secret(i + 1)):
			p.dirty_character = true

## A monster touched a player.
func touch_player(p: SimPlayer, m: SimMob) -> void:
	hurt_player(p, m.def, m.position.x, m.strength)

## A monster (`def`, standing at `from_x`) hit a player, by touch or with one of its
## moves (`power` times its attack, see MonsterMove).
func hurt_player(p: SimPlayer, def: MonsterDef, from_x: float, power := 1.0) -> void:
	if p.inv > 0 or p.fainted() or p.in_scene() or p.hidden():
		return
	var hearts := Combat.monster_hit(def, p.character, power)
	p.inv = 40 if hearts == 0 else SimPlayer.HURT_INV
	if p.sitting: # any hit, even a miss, gets you up
		p.sitting = false
		Net.send(p.peer, &"ev_sit", [false])
	if hearts == 0:
		broadcast(&"ev_number", [p.position.x, p.position.y - 70, 0, "miss"])
		return
	# a guard (Magic Guard) may soak a heart with MP while there's MP to pay for it
	var guard_mp := Combat.guard_mp(p.character)
	if randf() < p.character.skills.mp_guard() and p.character.mp >= guard_mp:
		p.character.spend_mp(guard_mp)
		hearts -= 1
	p.character.health.damage(hearts)
	p.dirty_vitals = true
	p.hurt_here = true
	Net.send(p.peer, &"ev_hurt", [from_x])
	if p.character.health.is_dead():
		p.faint_t = SimPlayer.FAINT_TICKS
		var lost := Combat.faint_penalty(p.character.xp)
		p.character.xp -= lost
		Net.send(p.peer, &"ev_fainted", [])
		tell(p, "You fainted and lost %d EXP." % lost, BAD)

# ---------- items ----------

func spawn_drop(item: ItemDef, amount: int, stack: ItemStack, flight: DropFlight, owner: int) -> void:
	var d := SimDrop.new(server.next_drop_id(), item, amount, flight, owner)
	d.stack = stack
	drops[d.id] = d
	broadcast(&"ev_drop", [d.snapshot()])

func _remove_drop(d: SimDrop, by: int) -> void:
	d.taken = true
	drops.erase(d.id)
	broadcast(&"ev_drop_gone", [d.id, by])

## Picks up the nearest drop the player is standing by (the loot key). True if one was taken.
func loot_near(p: SimPlayer) -> bool:
	var best: SimDrop = null
	for d in drops.values():
		if d.can_loot(p) and (best == null or absf(d.flight.position.x - p.position.x) < absf(best.flight.position.x - p.position.x)):
			best = d
	return best != null and pick_up(p, best)

## Puts a drop in the player's wallet or bag. False (with a message) if there's no room.
func pick_up(p: SimPlayer, d: SimDrop) -> bool:
	var ch := p.character
	var full := "Your %s inventory is full." % ItemDef.TAB_NAMES[d.item.tab()]
	if d.item is CardDef:
		_remove_drop(d, p.peer)
		_add_card(p, (d.item as CardDef).monster)
		return true
	if d.item is RelicDef:
		_remove_drop(d, p.peer)
		_learn_relic(p, d.item as RelicDef)
		return true
	var found := d.amount
	if d.item.is_currency:
		ch.shards += found
		p.dirty_vitals = true
	elif d.stack:
		if not ch.inventory.add_stack(d.stack):
			tell(p, full, BAD)
			return false
		p.dirty_character = true
	elif not ch.inventory.has_room(d.item, d.amount):
		tell(p, full, BAD)
		return false
	else:
		ch.inventory.add(d.item, d.amount)
		p.dirty_character = true
	_remove_drop(d, p.peer)
	if d.item.is_currency:
		show_gain(p, &"shards", found)
	else:
		# the client merges pickups of the same item into one log line
		Net.send(p.peer, &"ev_pickup", [d.item.id, d.amount])
	server.quests.picked_up(p, d.item)
	return true

## Whether the player has room for a drop (a pet only picks up what fits).
func has_room(p: SimPlayer, d: SimDrop) -> bool:
	if d.item.is_currency or d.item is CardDef or d.item is RelicDef:
		return true
	if d.stack:
		return p.character.inventory.room_for([d.stack])
	return p.character.inventory.has_room(d.item, d.amount)

## `p` picked up relic `r`: its move is theirs for good, on every job.
func _learn_relic(p: SimPlayer, r: RelicDef) -> void:
	if not p.character.learn_relic(r):
		return
	p.dirty_character = true
	tell(p, "New move: %s." % r.move_name, Palette.SUN)
	broadcast(&"ev_effect", [EffectDef.CELEBRATE, p.position.x, p.position.y, 1, p.peer])

func _add_card(p: SimPlayer, m: MonsterDef) -> void:
	var book := p.character.book
	var rank := book.rank()
	if not book.add_card(m):
		tell(p, "Your %s page is already complete." % m.display_name, Palette.MIST)
		return
	p.dirty_character = true
	tell(p, "Monster Book: %s card (%d/%d)" % [m.display_name, book.cards(m), CardDef.SET], Palette.CARD)
	if book.complete(m):
		tell(p, "You completed the %s page!" % m.display_name, Palette.SUN)
	if book.rank() > rank:
		p.character.recalc()
		tell(p, "Your Monster Book reached rank %d: +%d Power." % [book.rank(), book.rank() - 1], Palette.SUN)
		broadcast(&"ev_effect", [EffectDef.CELEBRATE, p.position.x, p.position.y, 1, p.peer])

## The pet that's out gets hungrier, and picks up what it can reach.
func _pet_step(p: SimPlayer) -> void:
	var c := p.character
	var pet := c.pet_def()
	if pet == null:
		c.pet = &""
		return
	if tick % pet.hunger_ticks == 0:
		c.pet_full = maxi(0, c.pet_full - PetDef.HUNGER_STEP)
		p.dirty_character = true
		if c.pet_full == 0:
			c.pet = &""
			tell(p, "%s got hungry and went home." % pet.display_name, BAD)
			return
		if c.pet_full == PetDef.HUNGRY:
			tell(p, "%s is getting hungry. Feed it some pet food." % pet.display_name, BAD)
	if tick % 2400 == 0 and not pet.chatter.is_empty() and randf() < 0.5:
		broadcast(&"ev_chat", ["pet", pet.display_name, pet.chatter.pick_random(), p.peer])
	if tick % pet.loot_every != 0:
		return
	var best: SimDrop = null
	for d in drops.values():
		if d.can_loot(p, pet.loot_reach) and has_room(p, d) \
				and (best == null or absf(d.flight.position.x - p.position.x) < absf(best.flight.position.x - p.position.x)):
			best = d
	if best:
		pick_up(p, best)

## Drops a stack from the player's bag onto the ground at their feet.
func drop_from_player(p: SimPlayer, stack: ItemStack) -> void:
	var ground := layout.ground_below(p.position)
	spawn_drop(stack.item, stack.count, stack, DropFlight.create(p.position + Vector2(0, -30), ground, p.position.x + p.face * 14), 0)
	tell(p, "Dropped %s" % amount_name(stack.item, stack.count), Palette.MIST)

static func amount_name(item: ItemDef, amount: int) -> String:
	return "%d %s" % [amount, item.display_name] if amount > 1 or item.is_currency else item.display_name
