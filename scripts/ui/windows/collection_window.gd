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
## The open book (UiSkin.draw_book) the Monster Book is drawn in: its top left, how many
## pixels per texel, and its page margins in pixels at that scale.
const BOOK_AT := Vector2(PAD - 6, 92)
const BOOK_SCALE := 0.5
const PAGE_MARGIN := Vector2(20, 22)
const GRID := BOOK_AT + PAGE_MARGIN + Vector2(2, 2)
## The left page holds the grid; the right page (from DETAIL_X) a monster's details.
const LEFT_PAGE_W := PAGE_MARGIN.x + COLS * CELL + 12
const DETAIL_X := BOOK_AT.x + LEFT_PAGE_W + 12
const DETAIL_W := 176.0
const BOOK_H := PAGE_MARGIN.y + ROWS * CELL + 28
## Card pips under each cell, and how big.
const PIP := 8.0

var tab := 0
var page := 0
var selected: MonsterDef
var _monsters: Array[MonsterDef] = []
## monster id -> names of the maps it lives on
var _homes := {}

func _init() -> void:
	super("Collection", Vector2(DETAIL_X + DETAIL_W + PAGE_MARGIN.x + BOOK_AT.x, BOOK_AT.y + BOOK_H + 40))

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
	var y := BOOK_AT.y + BOOK_H + 6
	return Rect2(GRID.x + (0.0 if dir < 0 else COLS * CELL - 34), y, 30, 24)

## The whole open book.
func _book_rect() -> Rect2:
	return Rect2(BOOK_AT, Vector2(size.x - BOOK_AT.x * 2, BOOK_H))

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
	UiSkin.draw_book(self, _book_rect(), LEFT_PAGE_W, BOOK_SCALE)
	for i in COLS * ROWS:
		var k := page * COLS * ROWS + i
		if k >= _monsters.size():
			break
		var m := _monsters[k]
		var r := cell_rect(i)
		var done := book.complete(m)
		UiSkin.draw_icon(self, "book/page_cell_complete" if done else "book/page_cell", r.grow(2.0 if done else 0.0))
		if r.has_point(_hover) or m == selected:
			draw_hilite(r.grow(-2), 4)
		if book.seen(m):
			var tex := monster_icon(m)
			if tex:
				draw_texture_rect(tex, fit(tex, r.grow(-6)), false, m.tint)
		else:
			UiSkin.draw_icon(self, "book/unseen_monster", r.grow(-7), Color(1, 1, 1, 0.8))
		for c in CardDef.SET:
			var at := Vector2(r.get_center().x + (c - (CardDef.SET - 1) / 2.0) * (PIP - 1), r.end.y - 4)
			UiSkin.draw_icon(self, "book/pip_on" if c < book.cards(m) else "book/pip_off", Rect2(at - Vector2(PIP, PIP) / 2.0, Vector2(PIP, PIP)))
	if pages() > 1:
		for d in [-1, 1]:
			var step: int = d
			add_button(_arrow_rect(d), "<" if d < 0 else ">", func() -> void: page += step, page + d >= 0 and page + d < pages())
		draw_label(Vector2(GRID.x + COLS * CELL / 2.0, _arrow_rect(1).position.y + 17), "Page %d/%d" % [page + 1, pages()], Palette.MUTED, 11, 0)
	_draw_detail()

## Dark ink on the book's paper. align: -1 right, 0 center, 1 left.
func _ink(at: Vector2, s: String, col := Palette.INK, sz := 11, align := 1) -> void:
	DrawUtil.text(self, Game.ui_font, at, s, sz, col, align)

func _draw_detail() -> void:
	var m := selected
	var x := DETAIL_X
	var y := GRID.y + 14
	if m == null:
		_ink(Vector2(x, y), "Pick a monster.", Palette.INK_SOFT, 12)
		return
	var book := Game.me.book
	if not book.seen(m):
		_ink(Vector2(x, y), "???", Palette.INK, 14)
		_ink(Vector2(x, y + 20), "Defeat one to fill in this page.", Palette.INK_SOFT, 11)
		return
	DrawUtil.text(self, Game.num_font, Vector2(x, y), m.display_name, 15, Palette.INK, 1)
	y += 18
	_ink(Vector2(x, y), "Lv. %d%s" % [m.level, "  ·  BOSS" if m.boss else ""], Palette.EMBER if m.boss else Palette.INK_SOFT)
	y += 18
	for line in ["HP %d  ·  EXP %d" % [m.max_hp, m.exp_reward], "Defeated: %d" % book.kills(m), "Cards: %d/%d" % [book.cards(m), CardDef.SET]]:
		_ink(Vector2(x, y), line)
		y += 16
	y += 4
	_ink(Vector2(x, y), "Found in", Palette.INK_SOFT)
	y += 15
	for name in (_homes.get(m.id, []) as Array).slice(0, 3):
		_ink(Vector2(x + 6, y), name)
		y += 14
	y += 4
	_ink(Vector2(x, y), "Drops", Palette.INK_SOFT)
	y += 15
	if book.cards(m) == 0:
		_ink(Vector2(x + 6, y), "Find a card to reveal", Palette.INK_SOFT)
		return
	var shown := 0
	for d in m.drops:
		if d.item == null or d.item.is_currency or shown >= 4:
			continue
		if d.item.icon:
			draw_texture_rect(d.item.icon, fit(d.item.icon, Rect2(x + 4, y - 11, 14, 14)), false)
		_ink(Vector2(x + 22, y), d.item.display_name)
		y += 15
		shown += 1

func _draw_achievements() -> void:
	var got := Game.me.achievements.size()
	UiSkin.draw_icon(self, "book/badge", Rect2(PAD, 68, 20, 20))
	draw_label(Vector2(PAD + 24, 84), "%d of %d reached" % [got, Achievements.LIST.size()], Palette.SUN, 12)
	var per := ceili(Achievements.LIST.size() / 2.0)
	var w := (size.x - PAD * 2 - 8) / 2.0
	var top := BOOK_AT.y + 4
	var row_h := (size.y - top - 16) / per
	for i in Achievements.LIST.size():
		var a: Dictionary = Achievements.LIST[i]
		var r := Rect2(PAD + (i / per) * (w + 8), top + (i % per) * row_h, w, row_h - 2)
		var done := Game.me.achievements.has(a["id"])
		var k := r.size.y / UiSkin.tex("book/achievement_row").get_height()
		UiSkin.draw_box(self, UiSkin.achievement_row(done), r, k)
		if not done:
			var niche := Rect2(r.position + Vector2(10, 12) * k, Vector2(62, 56) * k)
			UiSkin.draw_icon(self, "book/badge_locked", niche, Color(1, 1, 1, 0.7))
		var x := r.position.x + 86 * k
		draw_label(Vector2(x, r.end.y - r.size.y / 2.0 + 4), a["title"], Palette.SUN if done else Palette.MIST, 11)
		var have := mini(Achievements.measure(Game.me, a["kind"]), a["goal"])
		var tail := "Done" if done else "%d/%d" % [have, a["goal"]]
		draw_label(Vector2(r.end.x - 8, r.end.y - r.size.y / 2.0 + 4), tail, Palette.GOOD if done else Palette.MUTED, 10, -1)
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
