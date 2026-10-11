class_name TDChat
extends Control
## The chat box at the bottom left. Enter opens a line to type in; what you type is said
## to everyone on the map (it also shows in a bubble over your head). Start with a command
## for other channels: /w Name (whisper), /p (party), /g (guild), /b (buddies). /help lists
## the rest. Lines fade after a while unless the box is open.

const W := 380.0
const LINES := 7
const LINE_H := 17.0
const FADE_TICKS := 900
const COLORS := {"all": Color("f4ecff"), "pet": Palette.PET, "whisper": Color("ff9ee6"), "whisper_sent": Color("ff9ee6"),
	"party": Color("ffb36b"), "guild": Palette.GUILD, "buddy": Color("8fe0ff"), "system": Palette.MUTED}

var world: TDWorld
var field: LineEdit
## {"text", "color", "t"}
var lines: Array = []

## Bottom left, above the status bar (called again when the window is resized).
func fit_view() -> void:
	position = Vector2(8, TDWorld.VIEW.y - TDStatusBar.HEIGHT - size.y - 4)

func _ready() -> void:
	size = Vector2(W, LINES * LINE_H + 38)
	fit_view()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	field = LineEdit.new()
	UiStyle.set_hint(field, "Say something (Enter)  ·  /w Name, /p, /g, /b, /help")
	field.max_length = TDSocial.CHAT_MAX
	field.position = Vector2(0, size.y - 32)
	field.size = Vector2(W, 30)
	field.add_theme_font_size_override("font_size", 13)
	UiStyle.style_field(field, "social/chat_input", Vector4(34, 8, 14, 8), 0.85)
	field.visible = false
	field.text_submitted.connect(_send)
	field.gui_input.connect(func(e: InputEvent) -> void:
		if e.is_action_pressed("pause"):
			close()
			field.accept_event())
	add_child(field)

func _process(_delta: float) -> void:
	visible = world != null and world.started
	for l in lines:
		l["t"] = maxi(0, l["t"] - 1)
	queue_redraw()

func typing() -> bool:
	return field.visible and field.has_focus()

## Opens the line to type in (Enter).
func open(start := "") -> void:
	field.visible = true
	field.text = start
	field.grab_focus()
	field.caret_column = start.length()

func close() -> void:
	field.visible = false
	field.release_focus()

## Forgets every line and closes the box (leaving the world: the next character starts clean).
func clear() -> void:
	lines.clear()
	field.text = ""
	close()

func _send(text: String) -> void:
	if text.strip_edges() != "":
		Net.ask(&"req_chat", [text])
	field.text = ""
	close()

## A new line: `kind` is the channel, `from` who said it.
func add(kind: String, from: String, text: String) -> void:
	var shown := text
	match kind:
		"whisper":
			shown = "%s whispers: %s" % [from, text]
		"whisper_sent":
			shown = "To %s: %s" % [from, text]
		"party":
			shown = "[Party] %s: %s" % [from, text]
		"guild":
			shown = "[Guild] %s: %s" % [from, text]
		"buddy":
			shown = "[Buddy] %s: %s" % [from, text]
		"system":
			shown = text
		_:
			shown = "%s: %s" % [from, text]
	for l in DrawUtil.wrap_text(Game.ui_font, shown, 13, W - 12):
		lines.append({"text": l, "color": COLORS.get(kind, Palette.MIST), "t": FADE_TICKS})
	while lines.size() > 60:
		lines.pop_front()

func _draw() -> void:
	var open_box := field.visible
	var shown := lines.slice(maxi(0, lines.size() - LINES))
	if open_box:
		var frame := UiSkin.box("social/chat_frame", 20, 14)
		frame.modulate_color = Color(1, 1, 1, 0.85)
		UiSkin.draw_box(self, frame, Rect2(-6, -6, W + 12, LINES * LINE_H + 16), 0.7)
	elif not shown.is_empty():
		_draw_backdrop(shown)
	for i in shown.size():
		var l: Dictionary = shown[i]
		var a := 1.0 if open_box else minf(1.0, l["t"] / 60.0)
		if a <= 0.0:
			continue
		var col: Color = l["color"]
		col.a = a
		DrawUtil.text(self, Game.ui_font, Vector2(6, 16 + (LINES - shown.size() + i) * LINE_H), l["text"], 13, col, 1, 4, Color(Palette.NIGHT, 0.8 * a))

## A faint dark backdrop behind the lines still showing while the box is closed, fading with them.
func _draw_backdrop(shown: Array) -> void:
	var w := 0.0
	var first := -1
	var fade := 0.0
	for i in shown.size():
		var a := minf(1.0, shown[i]["t"] / 60.0)
		if a <= 0.0:
			continue
		if first < 0:
			first = i
		fade = maxf(fade, a)
		w = maxf(w, DrawUtil.text_width(Game.ui_font, shown[i]["text"], 13))
	if first < 0:
		return
	var top := 16 + (LINES - shown.size() + first) * LINE_H - 13
	var bottom := 16 + (LINES - 1) * LINE_H
	DrawUtil.backdrop(self, Rect2(6, top, w, bottom - top).grow(5), fade)
