class_name TDQuickslots
extends Control
## The eight quickslots above the right end of the status bar, like MapleStory's key
## setup: each holds a skill or an item and is used with its key (Game.QUICKSLOT_ACTIONS)
## or a click. Drag a skill from the skill window or a potion from the inventory onto a
## slot, drag slots to swap them, and right-click or drag one off to clear it. The slots
## are saved with the character (Character.quickslots).

const COLS := 4
const SLOT := 36.0
const GAP := 3.0
const PAD := 5.0

var world: TDWorld
var hud: TDHud
var _hover := -1
## The drag this panel started, kept for NOTIFICATION_DRAG_END.
var _pending: Variant = null

func _ready() -> void:
	var rows := ceili(Character.QUICKSLOTS / float(COLS))
	size = Vector2(PAD * 2 + COLS * (SLOT + GAP) - GAP, PAD * 2 + rows * (SLOT + GAP) - GAP)
	position = TDWorld.VIEW - size - Vector2(6, TDStatusBar.HEIGHT + 4)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_exited.connect(func() -> void:
		_hover = -1
		hud.tooltip.clear(self))

func _process(_delta: float) -> void:
	visible = world != null and world.started
	queue_redraw()

func slot_rect(i: int) -> Rect2:
	return Rect2(PAD + (i % COLS) * (SLOT + GAP), PAD + (i / COLS) * (SLOT + GAP), SLOT, SLOT)

func slot_at(at: Vector2) -> int:
	for i in Character.QUICKSLOTS:
		if slot_rect(i).has_point(at):
			return i
	return -1

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
			if p and p.cooldown > 0:
				var k := clampf(float(p.cooldown) / skill.cooldown, 0, 1)
				draw_rect(Rect2(r.position + Vector2(3, 3), Vector2(SLOT - 6, (SLOT - 6) * k)), Color(0.05, 0.02, 0.1, 0.6))
			if Game.me.use_problem(skill) != "":
				draw_rect(r.grow(-3), Color(0.05, 0.02, 0.15, 0.55))
		elif thing is ItemDef:
			var n := Game.me.inventory.count_of(thing)
			if n == 0:
				draw_rect(r.grow(-3), Color(0.05, 0.02, 0.15, 0.55))
			DrawUtil.text(self, Game.num_font, r.position + Vector2(4, 13), str(n), 11, Palette.MIST, 1, 4, Palette.NIGHT)
		DrawUtil.text(self, Game.num_font, r.end + Vector2(-3, -2), TDStatusBar._key_name(Game.QUICKSLOT_ACTIONS[i]), 11, Palette.MIST, -1, 4, Palette.NIGHT)

func _gui_input(event: InputEvent) -> void:
	var mm := event as InputEventMouseMotion
	if mm:
		_hover = slot_at(mm.position)
		var thing := content(_hover) if _hover >= 0 else null
		if thing is ItemDef:
			hud.tooltip.show_item(self, ItemStack.exact(thing), get_global_mouse_position(), "Right-click to clear")
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
	var preview := TextureRect.new()
	preview.texture = thing.get("icon")
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.size = Vector2(SLOT, SLOT) - Vector2(8, 8)
	preview.position = -preview.size / 2.0
	var holder := Control.new()
	holder.add_child(preview)
	set_drag_preview(holder)
	hud.tooltip.clear(self)
	_pending = {"from": "quickslot", "index": i}
	return _pending

func _can_drop_data(at: Vector2, data: Variant) -> bool:
	if not data is Dictionary or slot_at(at) < 0:
		return false
	match data.get("from"):
		"skills", "quickslot":
			return true
		"inventory":
			return data["tab"] in [ItemDef.Tab.USE, ItemDef.Tab.SETUP]
	return false

func _drop_data(at: Vector2, data: Variant) -> void:
	var i := slot_at(at)
	match data["from"]:
		"skills":
			assign(i, &"skill", data["id"])
		"inventory":
			var stack := Game.me.inventory.at(data["tab"], data["index"])
			if stack:
				assign(i, &"item", stack.item.id)
		"quickslot":
			var q: Array = Game.me.quickslots[data["index"]]
			if not q.is_empty() and data["index"] != i:
				assign(i, q[0], q[1])

func _notification(what: int) -> void:
	# a slot dragged off the panel and dropped anywhere else is cleared
	if what != NOTIFICATION_DRAG_END:
		return
	var d: Variant = _pending
	_pending = null
	if d != null and not get_viewport().gui_is_drag_successful():
		clear_slot(d["index"])
