class_name TDWorld
extends Node2D
## Owns the current map: platforms, monsters, NPCs, drops, effects, camera and combat.
## Game logic steps once per physics tick (60 Hz) in 2D game pixels (y down);
## TDStage renders it as an HD-2D diorama.

const VIEW := Vector2(960, 540)
## Game pixels between the items a monster drops.
const DROP_SPACING := 26.0

var map: MapDef
var platforms: Array[Platform] = []
var started := false
var tick := 0
var cam := Vector2.ZERO
var banner_text := ""
var banner_t := 0
var log_lines: Array[Dictionary] = []

var player: TDPlayer
var stage: TDStage
var mob_layer: Node2D
var npc_layer: Node2D
var drop_layer: Node2D
var fx_layer: Node2D
var hud: TDHud

func _ready() -> void:
	stage = TDStage.new()
	stage.world = self
	add_child(stage)
	mob_layer = _layer()
	npc_layer = _layer()
	drop_layer = _layer()
	player = TDPlayer.new()
	player.world = self
	add_child(player)
	fx_layer = _layer()
	hud = TDHud.new()
	hud.world = self
	add_child(hud)
	load_map(Game.map_id)

func _layer() -> Node2D:
	var n := Node2D.new()
	add_child(n)
	return n

func start() -> void:
	started = true
	show_banner(map.display_name)

## Loads a map by id and puts the player on its floor at `x` (or the map's start).
func load_map(id: StringName, x := -1.0) -> void:
	map = Content.map(id)
	if map == null:
		map = Content.map(Game.START_MAP)
	Game.map_id = map.id
	platforms.clear()
	platforms.append(Platform.floor_of(map))
	for d in map.platforms:
		platforms.append(Platform.from_def(d))
	for layer in [mob_layer, npc_layer, drop_layer, fx_layer]:
		for c in layer.get_children():
			layer.remove_child(c)
			c.queue_free()
	for s in map.spawns:
		for i in s.count:
			mob_layer.add_child(TDMob.create(self, s.monster, platforms[s.platform]))
	for p in map.npcs:
		npc_layer.add_child(TDNpc.create(self, p, platforms[p.platform]))
	player.place(x if x >= 0.0 else map.start_x, platforms[0].y)
	cam = _camera_target()
	stage.build()
	if started:
		show_banner(map.display_name)
	Game.save_game()

func show_banner(text: String) -> void:
	banner_text = text
	banner_t = 180

func add_log(text: String, col: Color) -> void:
	if not log_lines.is_empty() and log_lines[-1]["text"] == text:
		log_lines[-1]["t"] = 300
		return
	log_lines.append({"text": text, "color": col, "t": 300})
	if log_lines.size() > 6:
		log_lines.pop_front()

# ---------- queries ----------

func mobs() -> Array[TDMob]:
	var out: Array[TDMob] = []
	for c in mob_layer.get_children():
		out.append(c as TDMob)
	return out

func npcs() -> Array[TDNpc]:
	var out: Array[TDNpc] = []
	for c in npc_layer.get_children():
		out.append(c as TDNpc)
	return out

func climbable_near(pos: Vector2) -> ClimbableDef:
	for c in map.climbables:
		if absf(pos.x - c.x) < 16 and pos.y > c.top - 2 and pos.y <= c.bottom + 2:
			return c
	return null

func portal_at(pos: Vector2) -> PortalDef:
	for p in map.portals:
		if absf(pos.x - p.x) < 34 and absf(pos.y - platforms[p.platform].y) < 4:
			return p
	return null

func npc_near(pos: Vector2) -> TDNpc:
	for n in npcs():
		if absf(pos.x - n.position.x) < 50 and absf(pos.y - n.position.y) < 8:
			return n
	return null

func _camera_target() -> Vector2:
	return Vector2(
		clampf(player.position.x - VIEW.x / 2.0, 0, float(map.width) - VIEW.x),
		clampf(player.position.y - VIEW.y * 0.62, 0, float(map.height) - VIEW.y))

# ---------- loop ----------

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_fullscreen"):
		var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)
	elif event.is_action_pressed("pause") and started:
		if not hud.close_top_window():
			started = false
			hud.show_title(true)
	elif started:
		for action in TDHud.WINDOW_ACTIONS:
			if event.is_action_pressed(action):
				hud.toggle_window(action)

func _physics_process(_delta: float) -> void:
	tick += 1
	if started:
		player.step()
	for m in mobs():
		m.step()
	for n in npcs():
		n.step()
	for d in drop_layer.get_children():
		(d as TDDrop).step()
	for f in fx_layer.get_children():
		f.step()
	for i in range(log_lines.size() - 1, -1, -1):
		log_lines[i]["t"] -= 1
		if log_lines[i]["t"] <= 0:
			log_lines.remove_at(i)
	if banner_t > 0:
		banner_t -= 1
	cam += (_camera_target() - cam) * Vector2(0.12, 0.1)
	stage.follow(cam)
	if tick % 300 == 0:
		Game.save_game()

# ---------- combat ----------

## Resolves a player skill against the monsters in front of them. Returns how many were hit.
func use_skill(skill: SkillDef) -> int:
	var feet := player.position
	var area := Hitbox.attack_area(feet, player.face, skill.reach, skill.height)
	var targets: Array[TDMob] = []
	for m in mobs():
		if not m.dead and area.intersects(m.hurtbox.rect_at(m.body_position())):
			targets.append(m)
	targets.sort_custom(func(a: TDMob, b: TDMob) -> bool:
		return absf(a.position.x - feet.x) < absf(b.position.x - feet.x))
	if targets.size() > skill.max_targets:
		targets.resize(skill.max_targets)
	for m in targets:
		for i in skill.hits:
			if m.dead:
				break
			var hit := Combat.player_hit(skill, m.def)
			var at := m.body_position() + Vector2(0, -m.def.size.y - 10 - i * 30)
			if hit["miss"]:
				add_number(at, 0, "miss")
				continue
			m.health.damage(hit["damage"])
			add_number(at, hit["damage"], "crit" if hit["crit"] else "hit")
			if hit["crit"]:
				add_effect(Content.effect(&"critical"), m.body_position() + Vector2(0, -m.def.size.y / 2.0), player.face)
		if m.health.is_dead():
			kill_mob(m)
		else:
			m.hurt(player.face)
		add_effect(skill.hit_effect, m.body_position() + Vector2(0, -m.def.size.y / 2.0), player.face)
	return targets.size()

func kill_mob(m: TDMob) -> void:
	m.die()
	add_effect(Content.effect(&"monster_poof"), m.body_position() + Vector2(0, -m.def.size.y / 2.0), 1)
	var levels := Game.gain_xp(m.def.exp_reward)
	add_log("+%d EXP" % m.def.exp_reward, Color("ffe39a"))
	if levels > 0:
		player.level_up()
		add_effect(Content.effect(&"level_up"), player.position, 1)
		add_log("Level up! You reached Lv. %d" % Game.level, Palette.SUN)
		if Game.level >= 5:
			SteamService.unlock_achievement("REACH_LEVEL_5")
	var loot := []
	for entry in m.def.drops:
		var amount := entry.roll()
		if amount > 0:
			loot.append([entry.item, amount])
	# spread out in a row under the monster, like MapleStory
	for i in loot.size():
		var x := clampf(m.position.x + (i - (loot.size() - 1) / 2.0) * DROP_SPACING, m.plat.x + 8, m.plat.x + m.plat.w - 8)
		var d := TDDrop.create(self, loot[i][0], loot[i][1], m.position + Vector2(0, -20), m.plat.y)
		d.land_x = x
		drop_layer.add_child(d)

## Drops a stack from the bag onto the ground at the player's feet.
func drop_from_player(stack: ItemStack) -> void:
	var d := TDDrop.create(self, stack.item, stack.count, player.position + Vector2(0, -30), player.platform.y if player.platform else player.position.y)
	d.stack = stack
	d.land_x = player.position.x + player.face * 14
	drop_layer.add_child(d)
	add_log("Dropped %s" % _amount_name(stack.item, stack.count), Palette.MIST)

## Picks up the nearest drop the player is standing by (the loot key). True if one was taken.
func loot_near(pos: Vector2) -> bool:
	var best: TDDrop = null
	for d in drop_layer.get_children():
		var drop := d as TDDrop
		if drop.can_loot(pos) and (best == null or absf(drop.position.x - pos.x) < absf(best.position.x - pos.x)):
			best = drop
	return best != null and best.pick_up()

## Puts a picked-up item in the bag. False (with a message) if there's no room.
func collect(item: ItemDef, amount: int, stack: ItemStack = null) -> bool:
	if item.is_currency:
		Game.shards += amount
	elif stack:
		if not Game.inventory.add_stack(stack):
			add_log("Your %s inventory is full." % ItemDef.TAB_NAMES[item.tab()], Color("ff8a99"))
			return false
	elif not Game.inventory.has_room(item, amount):
		add_log("Your %s inventory is full." % ItemDef.TAB_NAMES[item.tab()], Color("ff8a99"))
		return false
	else:
		Game.inventory.add(item, amount)
	add_log("Picked up %s" % _amount_name(item, amount), Palette.MIST)
	return true

## Uses the item in Use slot `i` (a potion). Returns why it couldn't, or "".
func use_item(i: int) -> String:
	var stack := Game.inventory.at(ItemDef.Tab.USE, i)
	if stack == null or not stack.item is UseDef:
		return ""
	if player.fainted():
		return "You can't do that right now."
	if player.item_cd > 0:
		return "You can't use another item yet."
	var u := stack.item as UseDef
	Game.health.heal(u.hp_for(Game.max_hp()))
	Game.mp = mini(Game.max_mp(), Game.mp + u.mp_for(Game.max_mp()))
	player.item_cd = u.cooldown
	Game.inventory.take(ItemDef.Tab.USE, i, 1)
	add_effect(u.use_effect, player.position + Vector2(0, -40), player.face)
	return ""

func _amount_name(item: ItemDef, amount: int) -> String:
	return "%d %s" % [amount, item.display_name] if amount > 1 or item.is_currency else item.display_name

func hurt_player(monster: MonsterDef, from_x: float) -> void:
	if not started or player.inv > 0 or player.fainted():
		return
	var dmg := Combat.monster_hit(monster)
	if dmg == 0:
		player.inv = 40
		add_number(player.position + Vector2(0, -70), 0, "miss")
		return
	Game.health.damage(dmg)
	player.inv = 90
	add_number(player.position + Vector2(0, -70), dmg, "taken")
	if not player.is_climbing():
		player.vel = Vector2(-3.5 if player.position.x < from_x else 3.5, -4.5)
		player.on_ground = false
	if Game.health.is_dead():
		player.faint()
		var lost := Combat.faint_penalty(Game.xp)
		Game.xp -= lost
		add_log("You fainted and lost %d EXP." % lost, Color("ff8a99"))

func add_number(pos: Vector2, value: int, kind: String) -> void:
	var n := TDFloatText.new()
	n.world = self
	n.position = pos
	n.value = value
	n.kind = kind
	fx_layer.add_child(n)

func add_effect(def: EffectDef, pos: Vector2, face: int) -> void:
	if def == null:
		return
	fx_layer.add_child(TDEffect.create(self, def, pos, face))
