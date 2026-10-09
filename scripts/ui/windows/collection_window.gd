class_name TDCollectionWindow
extends TDWindow
## The Monster Book and achievements (L). The book has a page for every monster: unmet
## ones are shadows, met ones show how many you've beaten and which of their five cards
## you've found, and found cards reveal what the monster drops. Completed pages raise the
## book's level, which adds to every main stat. Achievements lists every milestone and how
## close you are to it.

const TABS := ["Monster Book", "Achievements"]
const COLS := 6
const ROWS := 5
const CELL := 46.0
const GRID := Vector2(PAD, 96)
const DETAIL_X := PAD + COLS * CELL + 12

var tab := 0
var page := 0
var selected: MonsterDef
var _monsters: Array[MonsterDef] = []
## monster id -> names of the maps it lives on
var _homes := {}

func _init() -> void:
	super("Collection", Vector2(DETAIL_X + 196, GRID.y + ROWS * CELL + 52))

func _ready() -> void:
	super()
	for m: MonsterDef in Content.monsters.values():
		_monsters.append(m)
	_monsters.sort_custom(func(a: MonsterDef, b: MonsterDef) -> bool:
		return a.level < b.level or a.level == b.level and a.display_name < b.display_name)
	for map: MapDef in Content.maps.values():
		for r in map.roster():
			var list: Array = _homes.get(r[0].id, [])
			if not list.has(map.display_name):
				list.append(map.display_name)
			_homes[r[0].id] = list

static func monster_icon(m: MonsterDef) -> Texture2D:
	if m.texture:
		return m.texture
	if m.sprite_frames:
		var names := m.sprite_frames.get_animation_names()
		var anim: StringName = &"idle" if m.sprite_frames.has_animation(&"idle") else StringName(names[0])
		if m.sprite_frames.get_frame_count(anim) > 0:
			return m.sprite_frames.get_frame_texture(anim, 0)
	return null

func pages() -> int:
	return ceili(_monsters.size() / float(COLS * ROWS))

func cell_rect(i: int) -> Rect2:
	return Rect2(GRID.x + (i % COLS) * CELL, GRID.y + (i / COLS) * CELL, CELL - 4, CELL - 4)

func _arrow_rect(dir: int) -> Rect2:
	var y := GRID.y + ROWS * CELL + 6
	return Rect2(GRID.x + (0.0 if dir < 0 else COLS * CELL - 34), y, 30, 24)

func _draw_body() -> void:
	draw_tabs(TABS, tab)
	if tab == 0:
		_draw_book()
	else:
		_draw_achievements()

func _draw_book() -> void:
	var book := Game.me.book
	draw_label(Vector2(PAD, 84), "Book Lv. %d  ·  %d/%d pages  ·  %d cards" % [book.level(), book.completed(), _monsters.size(), book.total_cards()], Palette.SUN, 12)
	if book.level() > 1:
		draw_label(Vector2(size.x - PAD, 84), "+%d to every stat" % (book.level() - 1), Palette.GOOD, 11, -1)
	for i in COLS * ROWS:
		var k := page * COLS * ROWS + i
		if k >= _monsters.size():
			break
		var m := _monsters[k]
		var r := cell_rect(i)
		var hot := r.has_point(_hover) or m == selected
		draw_row(r, hot)
		var tex := monster_icon(m)
		if tex:
			var seen := book.seen(m)
			draw_texture_rect(tex, fit(tex, r.grow(-5)), false, m.tint if seen else Color(0.05, 0.03, 0.1, 0.8))
		for c in CardDef.SET:
			var dot := Vector2(r.position.x + 7 + c * 7, r.end.y - 4)
			draw_circle(dot, 2.2, Palette.CARD if c < book.cards(m) else Color(0.3, 0.25, 0.4))
		if book.complete(m):
			draw_rect(r, Palette.SUN, false, 1.5)
	if pages() > 1:
		for d in [-1, 1]:
			var step: int = d
			add_button(_arrow_rect(d), "<" if d < 0 else ">", func() -> void: page += step, page + d >= 0 and page + d < pages())
		draw_label(Vector2(GRID.x + COLS * CELL / 2.0, _arrow_rect(1).position.y + 17), "Page %d/%d" % [page + 1, pages()], Palette.MUTED, 11, 0)
	_draw_detail()

func _draw_detail() -> void:
	var r := Rect2(DETAIL_X, GRID.y, size.x - DETAIL_X - PAD, ROWS * CELL - 4)
	draw_row(r)
	var m := selected
	if m == null:
		draw_hint(r.position + Vector2(10, 22), "Pick a monster.")
		return
	var book := Game.me.book
	var x := r.position.x + 10
	var y := r.position.y + 20
	if not book.seen(m):
		draw_label(Vector2(x, y), "???", Palette.SUN, 14)
		draw_hint(Vector2(x, y + 20), "Defeat one to fill in this page.")
		return
	draw_label(Vector2(x, y), m.display_name, Palette.SUN, 14)
	y += 18
	draw_label(Vector2(x, y), "Lv. %d%s" % [m.level, "  ·  BOSS" if m.boss else ""], Palette.WARN if m.boss else Palette.MUTED, 11)
	y += 18
	for line in ["HP %d  ·  EXP %d" % [m.max_hp, m.exp_reward], "Defeated: %d" % book.kills(m), "Cards: %d/%d" % [book.cards(m), CardDef.SET]]:
		draw_label(Vector2(x, y), line, Palette.MIST, 11)
		y += 16
	y += 4
	draw_label(Vector2(x, y), "Found in", Palette.MUTED, 11)
	y += 15
	for name in (_homes.get(m.id, []) as Array).slice(0, 3):
		draw_label(Vector2(x + 6, y), name, Palette.MIST, 11)
		y += 14
	y += 4
	draw_label(Vector2(x, y), "Drops", Palette.MUTED, 11)
	y += 15
	if book.cards(m) == 0:
		draw_hint(Vector2(x + 6, y), "Find a card to reveal")
		return
	var shown := 0
	for d in m.drops:
		if d.item == null or d.item.is_currency or shown >= 4:
			continue
		if d.item.icon:
			draw_texture_rect(d.item.icon, fit(d.item.icon, Rect2(x + 4, y - 11, 14, 14)), false)
		draw_label(Vector2(x + 22, y), d.item.display_name, Palette.MIST, 11)
		y += 15
		shown += 1

func _draw_achievements() -> void:
	var got := Game.me.achievements.size()
	draw_label(Vector2(PAD, 84), "%d of %d reached" % [got, Achievements.LIST.size()], Palette.SUN, 12)
	var per := ceili(Achievements.LIST.size() / 2.0)
	var w := (size.x - PAD * 2 - 8) / 2.0
	var row_h := (size.y - GRID.y - 16) / per
	for i in Achievements.LIST.size():
		var a: Dictionary = Achievements.LIST[i]
		var r := Rect2(PAD + (i / per) * (w + 8), GRID.y + (i % per) * row_h, w, row_h - 2)
		var done := Game.me.achievements.has(a["id"])
		draw_row(r, done)
		draw_circle(r.position + Vector2(9, r.size.y / 2.0), 4, Palette.SUN if done else Color(0.4, 0.35, 0.5))
		draw_label(r.position + Vector2(18, 13), a["title"], Palette.SUN if done else Palette.MIST, 11)
		var have := mini(Achievements.measure(Game.me, a["kind"]), a["goal"])
		var tail := "Done" if done else "%d/%d" % [have, a["goal"]]
		draw_label(Vector2(r.end.x - 6, r.position.y + 13), tail, Palette.GOOD if done else Palette.MUTED, 10, -1)
		if r.has_point(_hover):
			draw_label(Vector2(size.x - PAD, 84), a["text"], Palette.MIST, 11, -1)

func _click(at: Vector2, button: int, _double: bool) -> void:
	if button != MOUSE_BUTTON_LEFT:
		return
	var t := tab_at(at)
	if t >= 0:
		tab = t
		return
	if tab != 0:
		return
	for i in COLS * ROWS:
		var k := page * COLS * ROWS + i
		if k < _monsters.size() and cell_rect(i).has_point(at):
			selected = _monsters[k]
			return

## Shows a monster's page (for the screenshot tour and tests).
func show_monster(m: MonsterDef) -> void:
	tab = 0
	selected = m
	var k := _monsters.find(m)
	if k >= 0:
		page = k / (COLS * ROWS)
