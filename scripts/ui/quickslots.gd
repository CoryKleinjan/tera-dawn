class_name TDQuickslots
extends Control
## The eight quickslots above the right end of the status bar, like MapleStory's key
## setup: each holds a skill or an item and is used with its key (Game.QUICKSLOT_ACTIONS)
## or a click. Drag a skill or an item from the inventory onto a
## slot, drag slots to swap them, and right-click or drag one off to clear it. The slots
## are saved with the character (Character.quickslots). The panel fades to see-through while
## the hero or an NPC near them is behind it (TDHud.fade_over_people).

const COLS := 4
const SLOT := 36.0
const GAP := 3.0
const PAD := 5.0
## How far in from the screen's right edge, and up from the status bar, the panel sits.
const MARGIN := Vector2(6, 4)
## How dark the slots on the pad's other page are.
const OFF_PAGE_DIM := 0.6

var world: TDWorld
var hud: TDHud
var _hover := -1
var grid := SlotGrid.new(Vector2(PAD, PAD), COLS, Character.QUICKSLOTS, SLOT, GAP)
## The drag this panel started, for when it ends (see `_notification`).
var _drag := DragPayload.Tracker.new()
## What was last drawn (_drawn_state).
var _drawn := []

## The panel's size: COLS slots across, as many rows as it takes.
static func panel_size() -> Vector2:
	var rows := ceili(Character.QUICKSLOTS / float(COLS))
	return Vector2(PAD * 2 + COLS * (SLOT + GAP) - GAP, PAD * 2 + rows * (SLOT + GAP) - GAP)

func _ready() -> void:
	size = panel_size()
	fit_view()
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_exited.connect(func() -> void:
		_hover = -1
		hud.tooltip.clear(self))

## Bottom right, above the status bar (called again when the window is resized).
func fit_view() -> void:
	position = TDWorld.VIEW - size - Vector2(MARGIN.x, TDStatusBar.HEIGHT + MARGIN.y)

func _process(delta: float) -> void:
	visible = world != null and world.started
	if visible:
		hud.fade_over_people(self, delta)
	# drawn again only when something it shows changed
	var state := _drawn_state()
	if state != _drawn:
		_drawn = state
		queue_redraw()

## Everything _draw shows, to tell when it needs drawing again.
func _drawn_state() -> Array:
	if not visible:
		return []
	var p := world.player
	var out := [_hover, size, Game.me.quickslots.duplicate(true), p.cooldown if p else 0, p.recharge.duplicate() if p else {}, TDPad.using_pad, Keybinds.pad_page]
	for i in Character.QUICKSLOTS:
		var thing := content(i)
		if thing is SkillDef:
			out.append(Game.me.skills.use_problem(thing))
		elif thing is ItemDef:
			out.append(Game.me.inventory.count_of(thing))
		out.append(key_label(i))
	return out

## The key or pad button shown on slot `i`. With the pad, the page shows as which slots are
## lit (off_page), so only the button is named ("Y", not "LT+Y").
static func key_label(i: int) -> String:
	var action := Game.QUICKSLOT_ACTIONS[i]
	var text := TDStatusBar._key_name(action)
	if TDPad.using_pad and Keybinds.pad_page_of(action) == 1:
		text = text.trim_prefix(Keybinds.PAD_AXIS_NAMES[Keybinds.PAGE_AXIS] + "+")
	return text

## Whether slot `i` is dimmed because the pad is on the other page (the left trigger turns it).
static func off_page(i: int) -> bool:
	return TDPad.using_pad and Keybinds.pad_page_of(Game.QUICKSLOT_ACTIONS[i]) != Keybinds.pad_page

func slot_rect(i: int) -> Rect2:
	return grid.rect(i)

func slot_at(at: Vector2) -> int:
	return grid.at(at)

## What's on slot `i`: a SkillDef, an ItemDef or null.
static func content(i: int) -> Resource:
	var q: Array = Game.me.quickslots[i]
	if q.is_empty():
		return null
	return Content.skills.get(q[1]) if q[0] == &"skill" else Content.items.get(q[1])

func _draw() -> void:
	DrawUtil.round_rect(self, Rect2(Vector2.ZERO, size), 8, Color(Palette.NIGHT, 0.55))
	var p := world.player if world else null
	for i in Character.QUICKSLOTS:
		var r := slot_rect(i)
		draw_texture_rect(UiSkin.tex("skill_slot"), r, false, Color(1.3, 1.2, 1.0) if i == _hover else Color.WHITE)
		var thing := content(i)
		var icon: Texture2D = thing.get("icon") if thing else null
		if icon:
			draw_texture_rect(icon, TDWindow.fit(icon, r.grow(-4)), false)
		if thing is SkillDef:
			var skill := thing as SkillDef
			var k := 0.0
			if p and p.cooldown > 0:
				k = clampf(float(p.cooldown) / skill.cooldown, 0, 1)
			# its own recharge, when longer: how much of it is left
			var full := skill.recharge_ticks(Game.me.skills.level(skill))
			if p and full > 0 and p.recharge.has(skill.id):
				k = maxf(k, clampf(float(p.recharge[skill.id]) / full, 0, 1))
			if k > 0.0:
				var cover := UiSkin.tex("hud/cooldown_cover")
				var part := Rect2(Vector2.ZERO, cover.get_size() * Vector2(1, k))
				draw_texture_rect_region(cover, Rect2(r.position + Vector2(3, 3), Vector2(SLOT - 6, (SLOT - 6) * k)), part, Color(1, 1, 1, 0.75))
			if Game.me.skills.use_problem(skill) != "":
				draw_rect(r.grow(-3), Color(0.05, 0.02, 0.15, 0.55))
		elif thing is ItemDef:
			var n := Game.me.inventory.count_of(thing)
			if n == 0:
				draw_rect(r.grow(-3), Color(0.05, 0.02, 0.15, 0.55))
			DrawUtil.text(self, Game.num_font, r.position + Vector2(4, 13), str(n), 11, Palette.MIST, 1, 4, Palette.NIGHT)
		if off_page(i):
			draw_rect(r.grow(-3), Color(0.05, 0.02, 0.15, OFF_PAGE_DIM))
		DrawUtil.text(self, Game.num_font, r.end + Vector2(-3, -2), key_label(i), 11, Palette.MIST, -1, 4, Palette.NIGHT)

func _gui_input(event: InputEvent) -> void:
	var mm := event as InputEventMouseMotion
	if mm:
		_hover = slot_at(mm.position)
		var thing := content(_hover) if _hover >= 0 else null
		if thing is ItemDef:
			hud.tooltip.show_item(self, ItemStack.unrolled(thing), get_global_mouse_position(), "Right-click to clear")
		else:
			hud.tooltip.clear(self)
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed:
		return
	var i := slot_at(mb.position)
	if i < 0:
		return
	if mb.button_index == MOUSE_BUTTON_RIGHT:
		clear_slot(i)
	elif mb.button_index == MOUSE_BUTTON_LEFT and mb.double_click:
		world.player.use_quickslot(i)
	accept_event()

## Puts `kind` ("skill" or "item") `id` on slot `i` here at once and on the server.
func assign(i: int, kind: StringName, id: StringName) -> void:
	Game.me.set_quickslot(i, kind, id)
	Net.ask(&"req_set_quickslot", [i, kind, id])

func clear_slot(i: int) -> void:
	assign(i, &"", &"")

func _get_drag_data(at: Vector2) -> Variant:
	var i := slot_at(at)
	var thing := content(i) if i >= 0 else null
	if thing == null:
		return null
	hud.tooltip.clear(self)
	return _drag.start(self, DragPayload.quickslot(i), TDWindow.drag_preview(thing.get("icon"), SLOT - 8, 1.0, false))

func _can_drop_data(at: Vector2, data: Variant) -> bool:
	var d := DragPayload.of(data)
	if d == null or slot_at(at) < 0:
		return false
	match d.from:
		DragPayload.From.SKILLS, DragPayload.From.QUICKSLOT:
			return true
		DragPayload.From.INVENTORY:
			return d.tab in [ItemDef.Tab.USE, ItemDef.Tab.SETUP]
	return false

func _drop_data(at: Vector2, data: Variant) -> void:
	var d := DragPayload.of(data)
	var i := slot_at(at)
	match d.from:
		DragPayload.From.SKILLS:
			assign(i, &"skill", d.id)
		DragPayload.From.INVENTORY:
			var stack := Game.me.inventory.at(d.tab, d.index)
			if stack:
				assign(i, &"item", stack.item.id)
		DragPayload.From.QUICKSLOT:
			var q: Array = Game.me.quickslots[d.index]
			if not q.is_empty() and d.index != i:
				assign(i, q[0], q[1])

func _notification(what: int) -> void:
	# a slot dragged off the panel and dropped anywhere else is cleared
	if what != NOTIFICATION_DRAG_END:
		return
	var d := _drag.ended_unplaced(self)
	if d != null:
		clear_slot(d.index)
