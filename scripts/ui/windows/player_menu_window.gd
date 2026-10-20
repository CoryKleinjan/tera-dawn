class_name TDPlayerMenuWindow
extends TDWindow
## What you can do with another player: click them on the map. Whisper, invite them to a
## party, or trade.

const ROW_H := 34.0
const TOP := 64.0

var peer := 0
var who_name := ""
var job := &""

func _init() -> void:
	super("", Vector2(220, TOP + 3 * ROW_H + 10))

## Opens the menu for `a`.
func open(a: TDAvatar) -> void:
	peer = a.peer
	who_name = a.char_name
	job = a.job
	title = who_name
	position = Vector2(clampf(get_viewport().get_mouse_position().x + 12, 0, TDWorld.VIEW.x - size.x), 60)
	visible = true
	raise()

## [label, Callable, icon] for each thing you can do with them (the icon, from the UI art, is optional).
func actions() -> Array:
	var out := []
	out.append(["Whisper", func() -> void: hud.chat.open("/w %s " % who_name), "social/whisper_icon"])
	out.append(["Invite to party", func() -> void: Net.ask(&"req_social", [&"party", who_name])])
	out.append(["Trade", func() -> void: Net.ask(&"req_social", [&"trade", who_name])])
	return out

func row_rect(i: int) -> Rect2:
	return Rect2(PAD, TOP + i * ROW_H, size.x - PAD * 2, ROW_H - 6)

func _draw_body() -> void:
	var j: JobDef = Content.jobs.get(job)
	draw_label(Vector2(PAD, 46), j.display_name if j else "", Palette.MUTED)
	var list := actions()
	for i in list.size():
		var r := row_rect(i)
		add_button(r, list[i][0], _pick.bind(list[i][1]))
		if list[i].size() > 2:
			UiSkin.draw_icon(self, list[i][2], Rect2(r.position + Vector2(8, 4), Vector2(22, r.size.y - 8)))

## Closes the menu and does `action`.
func _pick(action: Callable) -> void:
	visible = false
	action.call()
