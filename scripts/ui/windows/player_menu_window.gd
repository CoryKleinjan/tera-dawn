class_name TDPlayerMenuWindow
extends TDWindow
## What you can do with another player: click them on the map. Whisper, invite them to a
## party, add them as a buddy, trade, invite them to your guild, or give them fame.

const ROW_H := 34.0
const TOP := 64.0

var peer := 0
var who_name := ""
var level := 1
var job := &""
var guild := ""

func _init() -> void:
	super("", Vector2(220, TOP + 7 * ROW_H + 10))

## Opens the menu for `a`.
func open(a: TDAvatar) -> void:
	peer = a.peer
	who_name = a.char_name
	level = a.level
	job = a.job
	guild = a.guild
	title = who_name
	position = Vector2(clampf(get_viewport().get_mouse_position().x + 12, 0, TDWorld.VIEW.x - size.x), 60)
	visible = true
	raise()

## [label, Callable] for each thing you can do with them.
func actions() -> Array:
	var out := []
	out.append(["Whisper", func() -> void: hud.chat.open("/w %s " % who_name)])
	out.append(["Invite to party", func() -> void: Net.ask(&"req_social", [&"party", who_name])])
	var buddies: Array = Game.social.get("buddies", [])
	if not buddies.any(func(b: Array) -> bool: return b[0] == who_name):
		out.append(["Add buddy", func() -> void: Net.ask(&"req_social", [&"buddy", who_name])])
	out.append(["Trade", func() -> void: Net.ask(&"req_social", [&"trade", who_name])])
	var g: Dictionary = Game.social.get("guild", {})
	if not g.is_empty() and g["master"] == Game.me.name and guild == "":
		out.append(["Invite to guild", func() -> void: Net.ask(&"req_social", [&"guild", who_name])])
	out.append(["Fame +1", func() -> void: Net.ask(&"req_fame", [peer, true])])
	out.append(["Fame -1", func() -> void: Net.ask(&"req_fame", [peer, false])])
	return out

func _row_rect(i: int) -> Rect2:
	return Rect2(PAD, TOP + i * ROW_H, size.x - PAD * 2, ROW_H - 6)

func _draw_body() -> void:
	var j: JobDef = Content.jobs.get(job)
	draw_label(Vector2(PAD, 46), "Lv. %d %s%s" % [level, j.display_name if j else "", "  ·  " + guild if guild != "" else ""], Palette.MUTED)
	var list := actions()
	for i in list.size():
		add_button(_row_rect(i), list[i][0], _pick.bind(list[i][1]))

## Closes the menu and does `action`.
func _pick(action: Callable) -> void:
	visible = false
	action.call()
