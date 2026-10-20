class_name TDOverlay
extends Control
## Screen-space drawing over the map: name tags, HP bars, speech bubbles,
## the map name, minimap, running buffs, message log, map banner and the faint screen.
## Things that follow the 3D stage are projected to the screen here so they stay crisp
## (no depth of field or fog on text).

## The game menu's cog in the top left corner (a button TDHud puts there); the map name sits right of it.
const MENU_BUTTON := Rect2(8, 6, 34, 34)
## The minimap's top left; it's drawn at its frame art's own size (see minimap_rect).
## Inside hud/minimap_frame, in art pixels: where the map is drawn, filling the frame's whole dark
## window (x 13 to 170, y 25 to 88).
const MINIMAP_INNER := Rect2(13, 25, 157, 63)
## The frame's sun medallion, which hangs down into the window: drawn again over the map.
const MINIMAP_MEDALLION := Rect2(72, 0, 39, 38)
## Minimap marks: texture, and its height in pixels.
const MINIMAP_PLAYER := ["hud/minimap_dot_1", 9.0]
const MINIMAP_NPC := ["hud/minimap_dot_2", 6.0]
const MINIMAP_OTHER := ["hud/minimap_dot_3", 6.0]
const MINIMAP_PORTAL := ["hud/minimap_portal", 10.0]
## The colour of land (platform tops, the floor's edge) on the minimap.
const MINIMAP_LAND := Color(0.93, 0.85, 0.62)
## How round the minimap's backdrop corners are, to sit inside the frame's window.
const MINIMAP_ROUND := 5.0
## The message log: text size, line spacing, the backdrop's margin around the text, and how
## far above the floor (where name tags start) its newest line sits.
const LOG_SIZE := 13
const LOG_LINE_H := 18.0
const LOG_PAD := 5.0
const LOG_ABOVE_TAGS := 10.0

## Where the map-name banner's middle is, normally and when a boss bar is at the top.
const BANNER_Y := 92.0
const BANNER_Y_BOSS := 150.0

var world: TDWorld
## Where the map-name banner's middle is this frame (lower while a boss bar shows).
var banner_y := BANNER_Y
## The name tags of the last frame drawn, where they ended up (for tests).
var last_tags: TDNameTags

## Where the minimap and its frame are on screen.
static func minimap_rect() -> Rect2:
	return Rect2(Vector2(TDWorld.VIEW.x - 189, 4), UiSkin.size_of("hud/minimap_frame"))

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if world == null or world.map == null:
		return
	var font := Game.ui_font
	var v := TDWorld.VIEW
	_draw_world_text()
	# map name
	var name_x := MENU_BUTTON.end.x + 6 if world.started else 16.0
	WorldSkin.draw_hint(self, Vector2(name_x + WorldSkin.hint_width(world.map.display_name) / 2.0, 34), world.map.display_name)
	var mm := minimap_rect()
	if world.started:
		_draw_minimap(mm)
	var boss_shown := world.started and _draw_boss_bar(Vector2(v.x / 2, 6))
	if world.started:
		_draw_party(Vector2(16, TDVitals.ORB.end.y + 14))
		_draw_buffs(Vector2(mm.position.x - 6, 10))
	_draw_log(v.x - 12 - (world.hud.quickslots.size.x + 6 if world.started else 0.0), log_bottom())
	# map banner
	banner_y = BANNER_Y_BOSS if boss_shown else BANNER_Y
	if world.banner_t > 0:
		var shown := float(TDWorld.BANNER_TICKS - world.banner_t)  # negative while it waits
		var a := clampf(minf(world.banner_t / 30.0, shown / 20.0), 0.0, 1.0)
		if a > 0.0:
			WorldSkin.draw_banner(self, Vector2(v.x / 2, banner_y - (1.0 - a) * 10.0), world.banner_text, a)
	if world.player.fainted():
		draw_rect(Rect2(Vector2.ZERO, v), Color(Palette.NIGHT, 0.45))
		DrawUtil.text(self, Game.num_font, Vector2(v.x / 2, v.y / 2 - 10), "You fainted", 40, Palette.MIST)
		DrawUtil.text(self, font, Vector2(v.x / 2, v.y / 2 + 22), "Returning to %s…" % Content.map(world.map.return_town()).display_name, 16, Palette.MIST)

## Where the message log's newest line sits (its baseline): above the status bar, and above
## the name tags of anyone standing on the floor when the floor is in view.
func log_bottom() -> float:
	var v := TDWorld.VIEW
	var bottom := v.y - TDStatusBar.HEIGHT - 12
	var floor_y := world.stage.screen(Vector2(world.cam.x + TDWorld.world_view().x / 2.0, world.map.ground_y), TDStage.Z_NPC).y
	return minf(bottom, floor_y - LOG_ABOVE_TAGS)

## The message log, newest at the bottom, right-aligned to `right`, on a faint backdrop.
func _draw_log(right: float, bottom: float) -> void:
	var n := world.log_lines.size()
	if n == 0:
		return
	var font := Game.ui_font
	var w := 0.0
	var fade := 0.0
	for line in world.log_lines:
		w = maxf(w, DrawUtil.text_width(font, line["text"], LOG_SIZE))
		fade = maxf(fade, minf(1.0, line["t"] / 40.0))
	var top := bottom - (n - 1) * LOG_LINE_H - LOG_SIZE
	DrawUtil.backdrop(self, Rect2(right - w, top, w, bottom - top).grow(LOG_PAD), fade)
	for i in n:
		var line: Dictionary = world.log_lines[i]
		var col: Color = line["color"]
		col.a = minf(1.0, line["t"] / 40.0)
		DrawUtil.text(self, font, Vector2(right, bottom - (n - 1 - i) * LOG_LINE_H), line["text"], LOG_SIZE, col, -1, 4, Color(Palette.NIGHT, 0.8 * col.a))

func _draw_minimap(mm: Rect2) -> void:
	draw_texture_rect(UiSkin.tex("hud/minimap_frame"), mm, false)
	var inner := Rect2(mm.position + MINIMAP_INNER.position, MINIMAP_INNER.size)
	var sx := inner.size.x / float(world.map.width)
	var sy := inner.size.y / float(world.map.height)
	var biome := world.map.look()
	# the map's own sky behind it, and its floor
	var sky_top := Color(biome.sky_mid.darkened(0.35), 0.85)
	var sky_low := Color(biome.sky_low.darkened(0.2), 0.85)
	var sky := DrawUtil.round_rect_points(inner.grow(1.0), MINIMAP_ROUND)
	var shades := PackedColorArray()
	for pt in sky:
		shades.append(sky_top.lerp(sky_low, (pt.y - inner.position.y) / inner.size.y))
	draw_polygon(sky, shades)
	var floor_y := inner.position.y + world.map.ground_y * sy
	var ground := Rect2(inner.position.x - 1.0, floor_y, inner.size.x + 2.0, inner.end.y + 1.0 - floor_y)
	DrawUtil.round_rect(self, ground, minf(MINIMAP_ROUND, ground.size.y / 2.0), Color(0.32, 0.22, 0.14, 0.9))
	draw_line(Vector2(inner.position.x, floor_y), Vector2(inner.end.x, floor_y), MINIMAP_LAND, 1.5)
	for i in range(1, world.platforms.size()):
		if i <= world.map.platforms.size() and world.map.platforms[i - 1].secret:
			continue # secret ledges stay off the map (a platform added at runtime has no def)
		var pl := world.platforms[i]
		var r := Rect2(inner.position.x + pl.x * sx, inner.position.y + pl.y * sy - 1.0, maxf(3.0, pl.w * sx), 3.0)
		draw_rect(r, MINIMAP_LAND)
		draw_rect(Rect2(r.position + Vector2(0, 2), Vector2(r.size.x, 1)), Color(0.35, 0.24, 0.14, 0.9))
	for p in world.map.portals:
		if not p.shows_to(Game.me):
			continue
		var at := inner.position + Vector2(p.x * sx, world.platforms[p.platform].y * sy - 5)
		if p.door:
			_minimap_door(at)
		else:
			_minimap_mark(MINIMAP_PORTAL, at)
	for n in world.npcs():
		var at := inner.position + Vector2(n.position.x * sx, n.position.y * sy - 3)
		_minimap_mark(MINIMAP_NPC, at)
		var marker := n.quest_marker()
		if marker == "!" or marker == "?":
			# quest givers stand out: a little "!" (new quest) or "?" (ready to hand in) over them
			DrawUtil.text(self, Game.num_font, at + Vector2(0, -4), marker, 11, Palette.SUN if marker == "!" else Palette.GOOD, 0, 3, Palette.NIGHT)
	var party := {}
	for row: Array in Game.social.get("party", {}).get("members", []):
		party[row[0]] = true
	for a in world.avatars.values():
		var at := inner.position + Vector2(a.position.x * sx, a.position.y * sy - 3)
		if party.has(a.char_name):
			draw_circle(at, 3.5, Palette.GOOD)  # party members in green
			draw_arc(at, 3.5, 0, TAU, 12, Palette.NIGHT, 1.0)
		else:
			_minimap_mark(MINIMAP_OTHER, at)
	var pp := world.player.position
	var you := inner.position + Vector2(pp.x * sx, pp.y * sy - 4)
	var pulse := fmod(Time.get_ticks_msec() / 1000.0, 1.4) / 1.4
	draw_arc(you, 4.0 + pulse * 6.0, 0, TAU, 16, Color(Palette.SUN, 0.8 * (1.0 - pulse)), 1.5)
	_minimap_mark(MINIMAP_PLAYER, you)
	draw_texture_rect(_medallion(), Rect2(mm.position + MINIMAP_MEDALLION.position, MINIMAP_MEDALLION.size), false)

## The frame's sun medallion with the window's dark leather around it cut away, so it hangs
## over the map without a dark box behind it.
static var _medallion_tex: Texture2D
static func _medallion() -> Texture2D:
	if _medallion_tex == null:
		var frame := UiSkin.tex("hud/minimap_frame").get_image()
		frame.decompress()
		var d := UiSkin.density("hud/minimap_frame")
		var img := frame.get_region(UiSkin.region("hud/minimap_frame", MINIMAP_MEDALLION))
		var window := frame.get_pixelv(MINIMAP_INNER.get_center() * d)
		img.convert(Image.FORMAT_RGBA8)
		for y in range(int((MINIMAP_INNER.position.y - MINIMAP_MEDALLION.position.y) * d), img.get_height()):
			for x in img.get_width():
				var c := img.get_pixel(x, y)
				if maxf(maxf(absf(c.r - window.r), absf(c.g - window.g)), absf(c.b - window.b)) <= 6.0 / 255.0:
					img.set_pixel(x, y, Color.TRANSPARENT)
		_medallion_tex = ImageTexture.create_from_image(img)
	return _medallion_tex

## One of the minimap's marks ([texture, height]) centred on `at`.
func _minimap_mark(mark: Array, at: Vector2) -> void:
	var h: float = mark[1]
	UiSkin.draw_icon(self, mark[0], Rect2(at - Vector2(h, h) / 2.0, Vector2(h, h)))

## What the hint over a portal or door says.
func _portal_hint(portal: PortalDef, target: MapDef) -> String:
	var name := target.display_name if target else "?"
	if portal.door:
		return ("↑ Out to %s" if world.map.interior else "↑ Enter %s") % name
	match world.layout.side_of(portal):
		RoomExits.Side.TOP:
			return "Jump up to %s" % name
		RoomExits.Side.BOTTOM:
			return "↓ + Jump to %s" % name
	return "↑ to %s" % name

## A building's door on the minimap: a little lit doorway.
func _minimap_door(at: Vector2) -> void:
	var r := Rect2(at + Vector2(-2.5, -3.0), Vector2(5.0, 7.0))
	draw_rect(r.grow(1.0), Palette.NIGHT)
	draw_rect(r, Palette.SUN)

## The first living boss on the map, at the top centre where it can't run off the screen.
## Returns whether there was one.
func _draw_boss_bar(top_center: Vector2) -> bool:
	for m in world.mobs():
		if m.draws_boss_bar():
			WorldSkin.draw_boss_bar(self, top_center, m.def.display_name, m.hp)
			return true
	return false

## Running buffs left of the minimap, newest on the left, with the seconds they have left.
func _draw_buffs(right_top: Vector2) -> void:
	var x := right_top.x
	for id in Game.me.skills.buffs:
		var s: SkillDef = Content.skills.get(id)
		if s == null:
			continue
		x -= 32
		var r := Rect2(x, right_top.y, 30, 30)
		UiSkin.draw_icon(self, "hud/buff_frame", r)
		if s.icon:
			draw_texture_rect(s.icon, TDWindow.fit(s.icon, r.grow(-7)), false)
		var left := ceili(Game.me.skills.buffs[id][1] / 60.0)
		DrawUtil.text(self, Game.num_font, Vector2(r.get_center().x, r.end.y + 9), str(left), 11,
			Palette.MIST if left > 10 else Palette.WARN, 0, 4, Palette.NIGHT)

## Your party under the map name: each other member's name and HP.
func _draw_party(at: Vector2) -> void:
	var party: Dictionary = Game.social.get("party", {})
	var y := at.y
	for m in party.get("members", []):
		if m[0] == Game.me.name:
			continue
		var here: bool = StringName(m[4]) == world.map.id
		var x := at.x
		if m[0] == party["leader"]:
			UiSkin.draw_icon(self, "social/leader_star", Rect2(x, y, 12, 12))
			x += 14
		DrawUtil.text(self, Game.ui_font, Vector2(x, y + 10), m[0], 11, Palette.MIST if here else Color(Palette.MIST, 0.55), 1, 3, Palette.NIGHT)
		WorldSkin.draw_party_hp(self, Vector2(at.x - 2, y + 12), 100, float(m[3]))
		y += 30

## A pet's name under it (into `tags`) and what it's saying over it.
func _draw_pet(c: TDCompanion, z: float, shown: bool, tags: TDNameTags) -> void:
	if c == null or c.pet == null or not shown or not world.stage.in_view(c.pet_pos, z):
		return
	tags.add_name(world.stage.screen(c.pet_pos, z) + Vector2(0, 4), c.pet.display_name, Palette.PET)
	if c.speech_t > 0:
		WorldSkin.draw_speech(self, world.stage.screen(c.pet_head(), z) + Vector2(0, -6), c.speech)

## Everything drawn at a spot in the world: name tags (gathered first and
## nudged apart, yours on top), HP bars, quest markers, speech, floating numbers and portal hints.
func _draw_world_text() -> void:
	var st := world.stage
	var tags := TDNameTags.new()
	last_tags = tags
	for m in world.mobs():
		var body := m.drawn_body_position()
		if not st.in_view(body, m.z):
			continue
		m.draw_tag(self, st.screen(world.drawn(m), m.z), st.screen(body + Vector2(0, -m.def.size.y), m.z), tags)
	for n in world.npcs():
		if st.in_view(n.position, 0.1):
			n.draw_tag(self, st.screen(n.position, 0.1), st.screen(n.position + Vector2(0, -n.body_size().y), 0.1), tags)
	for a in world.avatars.values():
		if st.in_view(a.position, TDStage.Z_OTHER_PLAYER):
			var feet := st.screen(world.drawn(a), TDStage.Z_OTHER_PLAYER)
			a.draw_tag(tags, feet)
			if a.speech_t > 0:
				WorldSkin.draw_speech(self, feet + Vector2(0, -TDPlayer.HEIGHT - 1), a.speech)
	var p := world.player
	if world.started and not p.fainted():
		var feet := st.screen(world.drawn(p), TDPlayer.Z)
		tags.add_name(feet + Vector2(0, 4), Game.me.name, Palette.SUN, true)
		if p.speech_t > 0:
			WorldSkin.draw_speech(self, feet + Vector2(0, -TDPlayer.HEIGHT - 1), p.speech)
	_draw_pet(world.player.companion, TDPlayer.Z, world.started and not p.fainted(), tags)
	for a in world.avatars.values():
		_draw_pet(a.companion, TDStage.Z_OTHER_PLAYER, a.known, tags)
	tags.draw(self)
	for f in world.fx_layer.get_children():
		if f is TDFloatText:
			(f as TDFloatText).draw_at(self, st.screen(world.drawn(f), 0.6))
		elif f is TDEffect:
			(f as TDEffect).draw_caption(self, st.screen(f.position, 0.2))
	var rest := world.layout.rest_at(p.position) if world.started and not p.sitting else -1
	if rest >= 0:
		var spot: Vector2i = world.map.rest_spots[rest]
		WorldSkin.draw_hint(self, st.screen(Vector2(spot.x, world.platforms[spot.y].y - 128), -0.3), "Sit to rest")
	for portal in world.map.portals:
		var side := world.layout.side_of(portal)
		if side == RoomExits.Side.LEFT or side == RoomExits.Side.RIGHT:
			continue # an opening in the room's side: you just walk through
		var base := Vector2(portal.x, world.platforms[portal.platform].y)
		if world.started and portal.open_to(Game.me) and absf(p.position.x - base.x) < 60 and absf(p.position.y - base.y) < 8:
			var target := Content.map(portal.target_map)
			WorldSkin.draw_hint(self, st.screen(base + Vector2(0, -128), -0.3), _portal_hint(portal, target))
