class_name TDDialogueWindow
extends TDWindow
## Talking to an NPC (Up next to them): their portrait and name, what they're saying, and a
## numbered list of what you can do with them (chat, open their shop, ...). Click an option
## or press its number. It closes when you walk away.
##
## To give NPCs something new to offer (quests, storage, travel), add it in `_options()`.

const PORTRAIT := 96.0
const TEXT_X := PAD + PORTRAIT + 16
const OPTION_H := 26.0
## Walk this far from the NPC and the window closes.
const REACH := 170.0

var npc: TDNpc
var text := ""
## [label, Callable] for each thing the player can pick.
var options: Array = []
var _line := -1

func _init() -> void:
	super("", Vector2(470, 250))

## Opens the window for `who`, starting with their greeting.
func open(who: TDNpc) -> void:
	npc = who
	title = who.def.display_name
	_line = -1
	text = who.def.greeting if who.def.greeting != "" else _next_line()
	options = _options()
	position = (TDWorld.VIEW - size) / 2.0 + Vector2(0, -40)
	visible = true
	raise()

## What this NPC offers, in order. Goodbye is always last.
func _options() -> Array:
	var out := []
	var def := npc.def
	if not def.lines.is_empty():
		out.append(["Chat", func() -> void: text = _next_line()])
	if def.shop:
		out.append(["Open shop", func() -> void:
			visible = false
			hud.open_shop(npc)])
	out.append(["Goodbye", func() -> void: visible = false])
	return out

func _next_line() -> String:
	if npc.def.lines.is_empty():
		return ""
	_line = (_line + 1) % npc.def.lines.size()
	return npc.def.lines[_line]

## Picks option `i` (0-based), as clicking it or pressing its number does.
func choose(i: int) -> void:
	if i >= 0 and i < options.size():
		options[i][1].call()

func _option_rect(i: int) -> Rect2:
	return Rect2(TEXT_X - 6, size.y - PAD - (options.size() - i) * OPTION_H, size.x - TEXT_X - PAD + 6, OPTION_H - 2)

func _process(delta: float) -> void:
	super(delta)
	if visible and (npc == null or not is_instance_valid(npc) or hud.world.player.position.distance_to(npc.position) > REACH):
		visible = false

func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if visible and k and k.pressed and not k.echo and k.keycode >= KEY_1 and k.keycode <= KEY_9:
		choose(k.keycode - KEY_1)
		get_viewport().set_input_as_handled()

func _draw_body() -> void:
	if npc == null:
		return
	# portrait
	var box := Rect2(PAD, TITLE_H + 10, PORTRAIT, PORTRAIT + 20)
	DrawUtil.round_rect(self, box, 8, Color(Palette.NIGHT, 0.45))
	var tex := npc.portrait()
	if tex:
		draw_texture_rect(tex, fit(tex, box.grow(-6)), false)
	if npc.def.title != "":
		DrawUtil.text(self, Game.ui_font, Vector2(box.get_center().x, box.end.y + 16), npc.def.title, 11, Color("c9b8d9"), 0, 3, Palette.NIGHT)
	# what they say
	var y := TITLE_H + 26
	for l in UiSkin.wrap_text(Game.ui_font, text, 14, size.x - TEXT_X - PAD):
		DrawUtil.text(self, Game.ui_font, Vector2(TEXT_X, y), l, 14, Palette.MIST, 1, 3, Palette.NIGHT)
		y += 20
	# what you can do
	for i in options.size():
		var r := _option_rect(i)
		if r.has_point(_hover):
			DrawUtil.round_rect(self, r, 6, Color(1, 0.85, 0.45, 0.18))
		DrawUtil.text(self, Game.ui_font, Vector2(r.position.x + 8, r.end.y - 7), "%d.  %s" % [i + 1, options[i][0]], 14, Palette.SUN, 1, 3, Palette.NIGHT)

func _click(at: Vector2, button: int, _double: bool) -> void:
	if button != MOUSE_BUTTON_LEFT:
		return
	for i in options.size():
		if _option_rect(i).has_point(at):
			choose(i)
			return
