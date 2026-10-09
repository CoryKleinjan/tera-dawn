class_name TDServer
extends Node
## The authoritative game server. It holds every connected player's Character, runs a
## MapInstance for each map with players on it 60 times a second, and answers the
## requests clients send through Net. A dedicated server runs only this; a host or a
## single-player game runs it next to its own client.

## Ticks between position snapshots (60 / 3 = 20 a second).
const SNAPSHOT_EVERY := 3
## Ticks between saving everyone.
const SAVE_EVERY := 600
## Attack requests may arrive this many ticks early, to allow for network jitter.
const COOLDOWN_SLACK := 4

var store: CharacterStore
## Import the single-player save (user://save.json) as a player's character the first time
## they play on this machine. On for a host or single player, off for dedicated servers.
var import_legacy_save := false
## peer id -> SimPlayer
var sessions := {}
## map id -> MapInstance
var maps := {}
var tick := 0
var _drop_ids := 0

func _init(save_dir := "user://characters") -> void:
	store = CharacterStore.new(save_dir)

func _physics_process(_delta: float) -> void:
	tick += 1
	for m: MapInstance in maps.values():
		if not m.players.is_empty():
			m.step()
	for p: SimPlayer in sessions.values():
		_flush(p)
	if tick % SNAPSHOT_EVERY == 0:
		for m: MapInstance in maps.values():
			if not m.players.is_empty():
				m.broadcast(&"ev_snapshot", [m.snapshot()])
	if tick % SAVE_EVERY == 0:
		save_all()

func save_all() -> void:
	for p: SimPlayer in sessions.values():
		store.save(p.character)

func next_drop_id() -> int:
	_drop_ids += 1
	return _drop_ids

func map_instance(id: StringName) -> MapInstance:
	if not maps.has(id):
		maps[id] = MapInstance.new(self, Content.map(id))
	return maps[id]

## Sends the player what changed about their character this tick.
func _flush(p: SimPlayer) -> void:
	if p.dirty_character:
		Net.send(p.peer, &"ev_character", [p.character.to_dict()])
	elif p.dirty_vitals:
		var c := p.character
		Net.send(p.peer, &"ev_vitals", [c.health.hp, c.mp, c.xp, c.level, c.shards])
	p.dirty_character = false
	p.dirty_vitals = false

# ---------- joining and leaving ----------

func join(peer: int, raw_name: String) -> void:
	var char_name := CharacterStore.clean_name(raw_name)
	if char_name == "":
		Net.send(peer, &"ev_join_failed", ["Please pick a name."])
		return
	for p: SimPlayer in sessions.values():
		if p.character.name.to_lower() == char_name.to_lower():
			Net.send(peer, &"ev_join_failed", ["%s is already playing." % char_name])
			return
	var c := store.load_character(char_name)
	if c == null and import_legacy_save:
		c = CharacterStore.load_file("user://save.json", char_name)
		import_legacy_save = false
	if c == null:
		c = Character.create(char_name)
	var p := SimPlayer.new(peer, c)
	sessions[peer] = p
	Net.send(peer, &"ev_joined", [c.to_dict()])
	_enter_map(p, c.map_id, Content.map(c.map_id).start_x)
	print("%s joined (peer %d)" % [char_name, peer])

func leave(peer: int) -> void:
	var p: SimPlayer = sessions.get(peer)
	if p == null:
		return
	sessions.erase(peer)
	p.map.remove_player(p)
	p.map.broadcast(&"ev_player_left", [peer])
	store.save(p.character)
	print("%s left" % p.character.name)

func _enter_map(p: SimPlayer, id: StringName, x: float) -> void:
	if p.map:
		p.map.remove_player(p)
		p.map.broadcast(&"ev_player_left", [p.peer])
	var m := map_instance(id)
	m.add_player(p, x)
	Net.send(p.peer, &"ev_enter_map", [id, x, m.full_state()])
	store.save(p.character)

## Sends a fainted player back to town with half their HP and MP.
func revive(p: SimPlayer) -> void:
	var c := p.character
	c.health.reset(c.max_hp())
	c.health.set_hp(ceili(c.max_hp() / 2.0))
	c.mp = ceili(c.max_mp() / 2.0)
	p.inv = 120
	p.dirty_vitals = true
	_enter_map(p, Character.START_MAP, Content.map(Character.START_MAP).start_x)

func give_xp(p: SimPlayer, amount: int) -> void:
	var c := p.character
	var levels := c.gain_xp(amount)
	p.dirty_vitals = true
	p.map.tell(p, "+%d EXP" % amount, Color("ffe39a"))
	if levels > 0:
		p.dirty_character = true
		p.map.broadcast(&"ev_level_up", [p.peer, c.level])
		p.map.tell(p, "Level up! You reached Lv. %d" % c.level, Palette.SUN)
		store.save(c)

# ---------- requests from clients (see Net) ----------

func _player(peer: int) -> SimPlayer:
	return sessions.get(peer)

func on_move(peer: int, at: Vector2, face: int, anim: StringName, climbing: bool) -> void:
	var p := _player(peer)
	if p and not p.report_move(at, face, anim, climbing) and not p.fainted():
		Net.send(peer, &"ev_place", [p.position.x, p.position.y])

func on_skill(peer: int, skill_id: StringName, at: Vector2, face: int) -> void:
	var p := _player(peer)
	var skill: SkillDef = Content.skills.get(skill_id)
	if p == null or skill == null or p.fainted() or p.cooldown > COOLDOWN_SLACK:
		return
	if not p.character.spend_mp(skill.mp_cost):
		p.map.tell(p, "Not enough MP for %s." % skill.display_name, Color("8cc6ff"))
		return
	p.report_move(at, face, skill.animation, false)
	p.cooldown = skill.cooldown
	p.dirty_vitals = true
	p.map.use_skill(p, skill)

func on_portal(peer: int) -> void:
	var p := _player(peer)
	if p == null or p.fainted():
		return
	var portal := p.map.layout.portal_at(p.position)
	if portal and Content.maps.has(portal.target_map):
		_enter_map(p, portal.target_map, portal.target_x)

func on_loot(peer: int) -> void:
	var p := _player(peer)
	if p and not p.climbing:
		p.map.loot_near(p)

func on_use_item(peer: int, slot: int) -> void:
	var p := _player(peer)
	if p == null:
		return
	var stack := p.character.inventory.at(ItemDef.Tab.USE, slot)
	if stack == null or not stack.item is UseDef:
		return
	if p.fainted():
		p.map.tell(p, "You can't do that right now.", MapInstance.BAD)
		return
	if p.item_cd > 0:
		p.map.tell(p, "You can't use another item yet.", MapInstance.BAD)
		return
	var u := stack.item as UseDef
	var c := p.character
	c.health.heal(u.hp_for(c.max_hp()))
	c.restore_mp(u.mp_for(c.max_mp()))
	p.item_cd = u.cooldown
	c.inventory.take(ItemDef.Tab.USE, slot, 1)
	p.dirty_character = true
	if u.use_effect:
		p.map.broadcast(&"ev_effect", [u.use_effect.id, p.position.x, p.position.y - 40, p.face, peer])

func on_equip(peer: int, slot: int, place: StringName) -> void:
	_change(peer, func(c: Character) -> String: return c.equip(slot, place))

func on_unequip(peer: int, place: StringName, slot: int) -> void:
	_change(peer, func(c: Character) -> String: return c.unequip(place, slot))

func on_move_item(peer: int, tab: int, from: int, to: int) -> void:
	if tab >= 0 and tab < ItemDef.Tab.size() and from >= 0 and from < Inventory.SLOTS and to >= 0 and to < Inventory.SLOTS:
		_change(peer, func(c: Character) -> String:
			c.inventory.move(tab, from, to)
			return "")

func on_add_ap(peer: int, stat: StringName) -> void:
	_change(peer, func(c: Character) -> String:
		c.add_ap(stat)
		return "")

func on_drop_item(peer: int, tab: int, slot: int) -> void:
	var p := _player(peer)
	if p == null or p.fainted() or tab < 0 or tab >= ItemDef.Tab.size() or slot < 0 or slot >= Inventory.SLOTS:
		return
	var stack := p.character.inventory.take(tab, slot)
	if stack:
		p.dirty_character = true
		p.map.drop_from_player(p, stack)

## Runs a change to the player's character and sends them the result, or why it failed.
func _change(peer: int, change: Callable) -> void:
	var p := _player(peer)
	if p == null:
		return
	var problem: String = change.call(p.character)
	if problem != "":
		p.map.tell(p, problem, MapInstance.BAD)
	p.dirty_character = true
