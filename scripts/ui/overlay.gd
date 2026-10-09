class_name TDOverlay
extends Control
## Screen-space drawing over the map: name tags, HP bars, damage numbers, speech bubbles,
## the map name, minimap, running buffs, message log, map banner and the faint screen.
## Things that follow the 3D stage are projected to the screen here so they stay crisp
## (no depth of field or fog on text).

var world: TDWorld

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if world == null or world.map == null:
		return
	var font := Game.ui_font
	var v := TDWorld.VIEW
	_draw_world_text()
	# map name
	UiSkin.draw_hint(self, Vector2(16 + (DrawUtil.text_width(font, world.map.display_name, 13) + 26) / 2.0, 36), world.map.display_name)
	_draw_minimap(Rect2(v.x - 182, 10, 172, 50))
	if world.started:
		_draw_party(Vector2(16, 56))
		_draw_quest_tracker(Vector2(v.x - 178, 82))
		_draw_buffs(Vector2(v.x - 192, 12))
	# message log, newest at the bottom, above the status bar and left of the quickslots
	var log_right := v.x - 12 - (world.hud.quickslots.size.x + 6 if world.started else 0.0)
	var n := world.log_lines.size()
	for i in n:
		var line: Dictionary = world.log_lines[i]
		var y := v.y - TDStatusBar.HEIGHT - 12 - (n - 1 - i) * 18
		var col: Color = line["color"]
		col.a = minf(1.0, line["t"] / 40.0)
		DrawUtil.text(self, font, Vector2(log_right, y), line["text"], 13, col, -1, 4, Color(Palette.NIGHT, 0.8 * col.a))
	# map banner
	if world.banner_t > 0:
		var a := minf(1.0, minf(world.banner_t / 30.0, (180 - world.banner_t) / 20.0))
		UiSkin.draw_banner(self, Vector2(v.x / 2, 110), world.banner_text, a)
	if world.player.fainted():
		draw_rect(Rect2(Vector2.ZERO, v), Color(Palette.NIGHT, 0.45))
		DrawUtil.text(self, Game.num_font, Vector2(v.x / 2, v.y / 2 - 10), "You fainted", 40, Palette.MIST)
		DrawUtil.text(self, font, Vector2(v.x / 2, v.y / 2 + 22), "Returning to %s…" % Content.map(world.map.return_town()).display_name, 16, Palette.MIST)

func _draw_minimap(mm: Rect2) -> void:
	UiSkin.box("name_tag", 12, 8).draw(get_canvas_item(), mm)
	var inner := mm.grow(-8)
	var sx := inner.size.x / float(world.map.width)
	var sy := inner.size.y / float(world.map.height)
	for pl in world.platforms:
		draw_rect(Rect2(inner.position.x + pl.x * sx, inner.position.y + pl.y * sy, maxf(2, pl.w * sx), 2), Color(1, 0.95, 0.9, 0.5))
	for p in world.map.portals:
		draw_rect(Rect2(inner.position.x + p.x * sx - 2, inner.position.y + world.platforms[p.platform].y * sy - 6, 4, 6), Color("aa8cff"))
	for n in world.npcs():
		draw_circle(inner.position + Vector2(n.position.x * sx, n.position.y * sy - 3), 2, Palette.GOOD)
	for a in world.avatars.values():
		draw_circle(inner.position + Vector2(a.position.x * sx, a.position.y * sy - 3), 2.5, Palette.INFO)
	var pp := world.player.position
	draw_circle(inner.position + Vector2(pp.x * sx, pp.y * sy - 3), 3, Palette.SUN)

## Running buffs left of the minimap, newest on the left, with the seconds they have left.
func _draw_buffs(right_top: Vector2) -> void:
	var x := right_top.x
	for id in Game.me.buffs:
		var s: SkillDef = Content.skills.get(id)
		if s == null:
			continue
		x -= 30
		var r := Rect2(x, right_top.y, 26, 26)
		if s.icon:
			draw_texture_rect(s.icon, r, false)
		var left := ceili(Game.me.buffs[id][1] / 60.0)
		DrawUtil.text(self, Game.num_font, Vector2(r.get_center().x, r.end.y + 11), str(left), 11,
			Palette.MIST if left > 10 else Palette.WARN, 0, 4, Palette.NIGHT)

## Your party under the map name: each other member's name and HP.
func _draw_party(at: Vector2) -> void:
	var party: Dictionary = Game.social.get("party", {})
	var y := at.y
	for m in party.get("members", []):
		if m[0] == Game.me.name:
			continue
		var here: bool = StringName(m[5]) == world.map.id
		DrawUtil.text(self, Game.ui_font, Vector2(at.x, y + 10), "%s  Lv.%d" % [m[0], m[2]], 11, Palette.MIST if here else Color(Palette.MIST, 0.55), 1, 3, Palette.NIGHT)
		var bar := Rect2(at.x, y + 14, 90, 5)
		draw_rect(bar, Color(Palette.NIGHT, 0.6))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * float(m[4]), bar.size.y)), Palette.HP)
		y += 24

## Quests in progress and how far along they are, under the minimap.
func _draw_quest_tracker(at: Vector2) -> void:
	var me := Game.me
	var y := at.y
	var shown := 0
	for id in me.quests.active:
		var q: QuestDef = Content.quests.get(id)
		if q == null or shown >= 4:
			continue
		shown += 1
		var ready := me.quests.is_ready(q, me)
		DrawUtil.text(self, Game.ui_font, Vector2(at.x, y), q.title, 12, Palette.SUN, 1, 4, Palette.NIGHT)
		y += 15
		if ready:
			DrawUtil.text(self, Game.ui_font, Vector2(at.x + 8, y), "Ready to hand in", 11, Palette.GOOD, 1, 4, Palette.NIGHT)
			y += 15
		else:
			for i in q.objectives.size():
				var o := q.objectives[i]
				var have := me.quests.progress(q, i, me)
				DrawUtil.text(self, Game.ui_font, Vector2(at.x + 8, y), "%s %d/%d" % [o.describe(), have, o.count], 11,
					Palette.GOOD if have >= o.count else Palette.MIST, 1, 4, Palette.NIGHT)
				y += 15
		y += 4

## A pet's name under it and what it's saying over it.
func _draw_pet(c: TDCompanion, z: float, shown: bool) -> void:
	if c == null or c.pet == null or not shown or not world.stage.in_view(c.pet_pos, z):
		return
	UiSkin.draw_name_tag(self, world.stage.screen(c.pet_pos, z) + Vector2(0, 4), c.pet.display_name, Palette.PET)
	if c.speech_t > 0:
		UiSkin.draw_speech(self, world.stage.screen(c.pet_head(), z) + Vector2(0, -6), c.speech)

func _draw_world_text() -> void:
	var st := world.stage
	for m in world.mobs():
		var body := m.body_position()
		if not st.in_view(body, m.z):
			continue
		m.draw_tag(self, st.screen(m.position, m.z), st.screen(body + Vector2(0, -m.def.size.y), m.z))
	for n in world.npcs():
		if st.in_view(n.position, 0.1):
			n.draw_tag(self, st.screen(n.position, 0.1), st.screen(n.position + Vector2(0, -n.rig.body.get_item_rect().size.y * n.rig.body.pixel_size * TDStage.PX), 0.1))
	for a in world.avatars.values():
		if st.in_view(a.position, TDStage.Z_OTHER_PLAYER):
			var feet := st.screen(a.position, TDStage.Z_OTHER_PLAYER)
			a.draw_tag(self, feet)
			if a.shop_title != "":
				UiSkin.draw_hint(self, feet + Vector2(0, -84), "Shop: " + a.shop_title)
			elif a.speech_t > 0:
				UiSkin.draw_speech(self, feet + Vector2(0, -84), a.speech)
	var p := world.player
	if world.started and not p.fainted():
		var feet := st.screen(p.position, TDPlayer.Z)
		UiSkin.draw_name_tag(self, feet + Vector2(0, 4), Game.me.name, Palette.SUN)
		if Game.me.guild != "":
			UiSkin.draw_name_tag(self, feet + Vector2(0, 26), Game.me.guild, Palette.GUILD)
		if world.hud.selling():
			UiSkin.draw_hint(self, feet + Vector2(0, -84), "Shop: " + world.hud.windows["player_shop"].shop_title)
		elif p.speech_t > 0:
			UiSkin.draw_speech(self, feet + Vector2(0, -84), p.speech)
	_draw_pet(world.player.companion, TDPlayer.Z, world.started and not p.fainted())
	for a in world.avatars.values():
		_draw_pet(a.companion, TDStage.Z_OTHER_PLAYER, a.known)
	for f in world.fx_layer.get_children():
		if f is TDFloatText:
			(f as TDFloatText).draw_at(self, st.screen(f.position, 0.6))
		elif f is TDEffect:
			(f as TDEffect).draw_caption(self, st.screen(f.position, 0.2))
	for portal in world.map.portals:
		var base := Vector2(portal.x, world.platforms[portal.platform].y)
		if world.started and absf(p.position.x - base.x) < 60 and absf(p.position.y - base.y) < 8:
			var target := Content.map(portal.target_map)
			UiSkin.draw_hint(self, st.screen(base + Vector2(0, -128), -0.3), "↑ to %s" % (target.display_name if target else "?"))
