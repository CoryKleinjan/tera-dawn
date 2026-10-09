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
	_quest_progress(p, p.character.quests.record_visit(id))
	store.save(p.character)

## Sends a fainted player back to town with half their HP and MP.
func revive(p: SimPlayer) -> void:
	var c := p.character
	c.health.reset(c.max_hp())
	c.health.set_hp(ceili(c.max_hp() / 2.0))
	c.mp = ceili(c.max_mp() / 2.0)
	p.inv = 120
	p.dirty_vitals = true
	var town := p.map.def.return_town() if p.map else Character.START_MAP
	if not Content.maps.has(town):
		town = Character.START_MAP
	_enter_map(p, town, Content.map(town).start_x)

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
	var c := p.character
	var problem := c.use_problem(skill)
	if problem != "":
		p.map.tell(p, problem, Color("8cc6ff"))
		return
	c.spend_mp(skill.mp_at(c.skill_level(skill)))
	if skill.uses_ammo:
		# the damage counts the ammo being fired, so spend it after the hit is worked out
		p.dirty_character = true
	p.report_move(at, face, skill.animation, false)
	p.cooldown = skill.cooldown
	p.dirty_vitals = true
	if skill.kind == SkillDef.Kind.BUFF:
		c.add_buff(skill)
		p.dirty_character = true
		p.map.broadcast(&"ev_skill", [p.peer, skill.id, p.position.x, p.position.y, p.face, []])
	else:
		p.map.use_skill(p, skill)
	if skill.uses_ammo:
		c.spend_ammo(skill.hits)

## Spends a Skill Point on `skill_id`.
func on_learn_skill(peer: int, skill_id: StringName) -> void:
	var p := _player(peer)
	var skill: SkillDef = Content.skills.get(skill_id)
	if p == null or skill == null:
		return
	var problem := p.character.learn(skill)
	if problem != "":
		p.map.tell(p, problem, MapInstance.BAD)
		return
	p.dirty_character = true
	p.dirty_vitals = true

## Puts a skill or item on a quickslot (an empty `kind` clears it).
func on_set_quickslot(peer: int, i: int, kind: StringName, id: StringName) -> void:
	var p := _player(peer)
	if p == null or not kind in [&"", &"skill", &"item"]:
		return
	if kind == &"skill" and not Content.skills.has(id) or kind == &"item" and not Content.items.has(id):
		return
	p.character.set_quickslot(i, kind, id)
	p.dirty_character = true

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
	var dest := &""
	if u.teleport != &"":
		dest = p.map.def.return_town() if u.teleport == &"town" else u.teleport
		if not Content.maps.has(dest):
			return
		if dest == p.map.def.id and p.map.def.town:
			p.map.tell(p, "You're already in town.", MapInstance.BAD)
			return
	c.health.heal(u.hp_for(c.max_hp()))
	c.restore_mp(u.mp_for(c.max_mp()))
	p.item_cd = u.cooldown
	c.inventory.take(ItemDef.Tab.USE, slot, 1)
	p.dirty_character = true
	if u.use_effect:
		p.map.broadcast(&"ev_effect", [u.use_effect.id, p.position.x, p.position.y - 40, p.face, peer])
	if dest != &"":
		_enter_map(p, dest, Content.map(dest).start_x)

## Uses the scroll in Use slot `use_slot` on the gear in Equip slot `equip_slot`.
func on_scroll(peer: int, use_slot: int, equip_slot: int) -> void:
	var p := _player(peer)
	if p == null or p.fainted():
		return
	var gear := p.character.inventory.at(ItemDef.Tab.EQUIP, equip_slot)
	var name := gear.item.display_name if gear else ""
	var result := p.character.use_scroll(use_slot, equip_slot)
	if result["problem"] != "":
		p.map.tell(p, result["problem"], MapInstance.BAD)
		return
	p.dirty_character = true
	if result["worked"]:
		p.map.tell(p, "The scroll worked! %s is now %s." % [name, gear.display_name()], Color("8cf0a6"))
		p.map.broadcast(&"ev_effect", [&"level_up", p.position.x, p.position.y, 1, peer])
	else:
		p.map.tell(p, "The scroll failed. %s has %d upgrades left." % [name, gear.slots_left()], MapInstance.BAD)
		p.map.broadcast(&"ev_effect", [&"monster_poof", p.position.x, p.position.y - 40, 1, 0])

## Stores bag slot `slot` of `tab` with the storage keeper `npc_id`.
func on_store(peer: int, npc_id: StringName, tab: int, slot: int) -> void:
	_at_storage(peer, npc_id, tab, slot, func(c: Character) -> String: return c.store(tab, slot))

## Takes storage slot `slot` of `tab` back from the storage keeper `npc_id`.
func on_retrieve(peer: int, npc_id: StringName, tab: int, slot: int) -> void:
	_at_storage(peer, npc_id, tab, slot, func(c: Character) -> String: return c.retrieve(tab, slot))

func _at_storage(peer: int, npc_id: StringName, tab: int, slot: int, change: Callable) -> void:
	var p := _player(peer)
	var npc := p.map.npc_near(p, npc_id) if p else null
	if npc == null or not npc.storage or tab < 0 or tab >= ItemDef.Tab.size() or slot < 0 or slot >= Inventory.SLOTS:
		return
	var problem: String = change.call(p.character)
	if problem != "":
		p.map.tell(p, problem, MapInstance.BAD)
	p.dirty_character = true
	p.dirty_vitals = true
	store.save(p.character)

## Takes the player on trip `index` of the NPC `npc_id` they stand by, if they can pay.
func on_travel(peer: int, npc_id: StringName, index: int) -> void:
	var p := _player(peer)
	var npc := p.map.npc_near(p, npc_id) if p and not p.fainted() else null
	if npc == null or index < 0 or index >= npc.travel.size():
		return
	var route := npc.travel[index]
	if not Content.maps.has(route.target_map):
		return
	if p.character.shards < route.price:
		p.map.tell(p, "You don't have enough Dawnshards.", MapInstance.BAD)
		return
	p.character.shards -= route.price
	p.dirty_vitals = true
	_enter_map(p, route.target_map, route.target_x)
	p.map.tell(p, "%s to %s." % [route.by, Content.map(route.target_map).display_name], Palette.SUN)

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
	var held := p.character.inventory.at(tab, slot)
	if held and held.item.quest_item:
		p.map.tell(p, "Quest items can't be dropped.", MapInstance.BAD)
		return
	var stack := p.character.inventory.take(tab, slot)
	if stack:
		p.dirty_character = true
		p.map.drop_from_player(p, stack)

# ---------- quests ----------

func record_kill(p: SimPlayer, monster: MonsterDef) -> void:
	_quest_progress(p, p.character.quests.record_kill(monster))

## Shows how quests that collect `item` are going after picking one up.
func picked_up(p: SimPlayer, item: ItemDef) -> void:
	var c := p.character
	for id in c.quests.active:
		var q: QuestDef = Content.quests.get(id)
		for i in q.objectives.size():
			var o := q.objectives[i]
			if o.kind == QuestObjective.Kind.COLLECT and o.item == item:
				p.map.tell(p, "%s: %s %d/%d" % [q.title, o.item.display_name, c.quests.progress(q, i, c), o.count], Color("a8e6ff"))

## Tells the player how the quests that just moved on are going.
func _quest_progress(p: SimPlayer, moved: Array[QuestDef]) -> void:
	for q in moved:
		p.dirty_character = true
		var c := p.character
		for i in q.objectives.size():
			var o := q.objectives[i]
			if o.kind != QuestObjective.Kind.COLLECT:
				p.map.tell(p, "%s: %s %d/%d" % [q.title, o.describe(), c.quests.progress(q, i, c), o.count], Color("a8e6ff"))
		if c.quests.is_ready(q, c):
			p.map.tell(p, "%s is ready to hand in." % q.title, Palette.SUN)

func on_quest_accept(peer: int, npc_id: StringName, quest_id: StringName) -> void:
	var p := _player(peer)
	var q: QuestDef = Content.quests.get(quest_id)
	if p == null or q == null or q.giver != npc_id or p.map.npc_near(p, npc_id) == null:
		return
	var c := p.character
	if c.quests.status(q, c) != QuestLog.Status.AVAILABLE:
		return
	c.quests.accept(q)
	p.dirty_character = true
	p.map.tell(p, "New quest: %s" % q.title, Palette.SUN)
	_quest_progress(p, c.quests.record_visit(p.map.def.id))

func on_quest_complete(peer: int, npc_id: StringName, quest_id: StringName) -> void:
	var p := _player(peer)
	var q: QuestDef = Content.quests.get(quest_id)
	if p == null or q == null or q.turn_in_npc() != npc_id or p.map.npc_near(p, npc_id) == null:
		return
	var problem := p.character.quests.complete(q, p.character)
	p.dirty_character = true
	if problem != "":
		p.map.tell(p, problem, MapInstance.BAD)
		return
	p.map.tell(p, "Quest complete: %s" % q.title, Palette.SUN)
	if q.reward_xp > 0:
		give_xp(p, q.reward_xp)

func on_quest_forfeit(peer: int, quest_id: StringName) -> void:
	var p := _player(peer)
	var q: QuestDef = Content.quests.get(quest_id)
	if p and q and p.character.quests.active.has(q.id):
		p.character.quests.forfeit(q)
		p.dirty_character = true
		p.map.tell(p, "Gave up on %s." % q.title, Palette.MIST)

## Advances the player to `job_id` through the instructor `npc_id` they stand by.
func on_advance(peer: int, npc_id: StringName, job_id: StringName) -> void:
	var p := _player(peer)
	var npc := p.map.npc_near(p, npc_id) if p else null
	var next: JobDef = Content.jobs.get(job_id)
	if npc == null or next == null or not job_id in npc.instructs:
		return
	var problem := p.character.advance(next)
	if problem != "":
		p.map.tell(p, problem, MapInstance.BAD)
		return
	p.dirty_character = true
	p.dirty_vitals = true
	p.map.broadcast(&"ev_effect", [&"level_up", p.position.x, p.position.y, 1, p.peer])
	p.map.tell(p, "You are now a %s!" % next.display_name, Palette.SUN)
	store.save(p.character)

## Buys `count` of a shop's entry `index` from the NPC `npc_id` the player stands by.
func on_buy(peer: int, npc_id: StringName, index: int, count: int) -> void:
	var p := _player(peer)
	var npc := p.map.npc_near(p, npc_id) if p else null
	if npc == null or npc.shop == null or index < 0 or index >= npc.shop.items.size():
		return
	var entry := npc.shop.items[index]
	count = clampi(count, 1, entry.item.stack_size())
	var c := p.character
	var total := entry.cost() * count
	if c.shards < total:
		p.map.tell(p, "You don't have enough Dawnshards.", MapInstance.BAD)
	elif not c.inventory.has_room(entry.item, count):
		p.map.tell(p, "Your %s inventory is full." % ItemDef.TAB_NAMES[entry.item.tab()], MapInstance.BAD)
	else:
		c.shards -= total
		c.inventory.add_stack(ItemStack.unrolled(entry.item, count))
		p.dirty_character = true
		p.map.tell(p, "Bought %s for %d Dawnshards." % [MapInstance.amount_name(entry.item, count), total], Palette.MIST)

## Sells up to `count` from a bag slot to the NPC `npc_id`'s shop.
func on_sell(peer: int, npc_id: StringName, tab: int, slot: int, count: int) -> void:
	var p := _player(peer)
	var npc := p.map.npc_near(p, npc_id) if p else null
	if npc == null or npc.shop == null or tab < 0 or tab >= ItemDef.Tab.size() or slot < 0 or slot >= Inventory.SLOTS:
		return
	var stack := p.character.inventory.at(tab, slot)
	if stack == null:
		return
	if stack.item.quest_item:
		p.map.tell(p, "You can't sell quest items.", MapInstance.BAD)
		return
	var sold := p.character.inventory.take(tab, slot, clampi(count, 1, stack.count))
	var total := sold.item.sell_price * sold.count
	p.character.shards += total
	p.dirty_character = true
	p.map.tell(p, "Sold %s for %d Dawnshards." % [MapInstance.amount_name(sold.item, sold.count), total], Palette.MIST)

## Sells everything in the Etc tab to the NPC `npc_id`'s shop.
func on_sell_all_etc(peer: int, npc_id: StringName) -> void:
	var p := _player(peer)
	var npc := p.map.npc_near(p, npc_id) if p else null
	if npc == null or npc.shop == null:
		return
	var total := 0
	for i in Inventory.SLOTS:
		var held := p.character.inventory.at(ItemDef.Tab.ETC, i)
		if held and not held.item.quest_item:
			var s := p.character.inventory.take(ItemDef.Tab.ETC, i)
			total += s.item.sell_price * s.count
	if total > 0:
		p.character.shards += total
		p.dirty_character = true
		p.map.tell(p, "Sold all your Etc items for %d Dawnshards." % total, Palette.MIST)

## Runs a change to the player's character and sends them the result, or why it failed.
func _change(peer: int, change: Callable) -> void:
	var p := _player(peer)
	if p == null:
		return
	var problem: String = change.call(p.character)
	if problem != "":
		p.map.tell(p, problem, MapInstance.BAD)
	p.dirty_character = true
