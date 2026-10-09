class_name TDCommunityWindow
extends TDWindow
## Buddies, party and guild (O), from the server's summary in Game.social. Buddies shows
## who's online and where; Party shows each member's level, job and HP; Guild lists its
## members. Invite people from here by name, or click them on the map.

const TABS := ["Buddies", "Party", "Guild"]
const LIST_Y := 72.0
const ROW_H := 30.0
const ROWS := 8

var tab := 0

func _init() -> void:
	super("Community", Vector2(340, LIST_Y + ROWS * ROW_H + 56))

func _row(i: int) -> Rect2:
	return Rect2(PAD, LIST_Y + i * ROW_H, size.x - PAD * 2, ROW_H - 4)

func _draw_body() -> void:
	draw_tabs(TABS, tab)
	match tab:
		0:
			_draw_buddies()
		1:
			_draw_party()
		2:
			_draw_guild()

func _bottom_button(label: String, action: Callable, slot := 0) -> void:
	var w := (size.x - PAD * 2 - 8) / 2.0
	var r := Rect2(PAD + slot * (w + 8), size.y - 44, w, 32)
	add_button(r, label, action)

func _draw_buddies() -> void:
	var list: Array = Game.social.get("buddies", [])
	if list.is_empty():
		draw_hint(Vector2(PAD, LIST_Y + 18), "No buddies yet. Click a player, or Add.")
	for i in mini(list.size(), ROWS):
		var b: Array = list[i]
		var r := _row(i)
		draw_row(r)
		draw_circle(r.position + Vector2(10, r.size.y / 2.0), 4, Palette.GOOD if b[1] else Color(0.5, 0.45, 0.6))
		draw_label(r.position + Vector2(20, 18), b[0], Palette.SUN if b[1] else Palette.MIST, 13)
		draw_label(r.position + Vector2(112, 18), b[2] if b[1] else "Offline", Palette.MUTED, 11)
		var who: String = b[0]
		if b[1]:
			add_button(Rect2(r.end.x - 98, r.position.y + 3, 46, 20), "Whisper", func() -> void: hud.chat.open("/w %s " % who), true, true)
		add_button(Rect2(r.end.x - 48, r.position.y + 3, 46, 20), "Remove", func() -> void: Net.ask(&"req_social", [&"unbuddy", who]), true, true)
	_bottom_button("Add buddy", func() -> void:
		hud.prompt.ask("Who do you want as a buddy?", "", func(n: String) -> void: Net.ask(&"req_social", [&"buddy", n])))

func _draw_party() -> void:
	var party: Dictionary = Game.social.get("party", {})
	var members: Array = party.get("members", [])
	if party.is_empty():
		draw_hint(Vector2(PAD, LIST_Y + 18), "You're not in a party. Invite someone to start one.")
	var lead: bool = party.get("leader", "") == Game.me.name or party.is_empty()
	for i in mini(members.size(), ROWS):
		var m: Array = members[i]
		var r := _row(i)
		draw_row(r)
		var j: JobDef = Content.jobs.get(StringName(m[3]))
		draw_label(r.position + Vector2(6, 12), ("★ " if m[0] == party["leader"] else "") + m[0], Palette.SUN, 12)
		draw_label(r.position + Vector2(6, 24), "Lv. %d %s  ·  %s" % [m[2], j.display_name if j else "", Content.map(StringName(m[5])).display_name if Content.maps.has(StringName(m[5])) else ""], Palette.MUTED, 10)
		var bar := Rect2(r.position.x + 196, r.position.y + 8, 70, 8)
		draw_rect(bar, Color(Palette.NIGHT, 0.6))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * float(m[4]), bar.size.y)), Palette.HP)
		var who: String = m[0]
		if lead and who != Game.me.name:
			add_button(Rect2(r.end.x - 40, r.position.y + 3, 38, 20), "Kick", func() -> void: Net.ask(&"req_social", [&"kick", who]), true, true)
	if lead:
		_bottom_button("Invite", func() -> void:
			hud.prompt.ask("Who do you want to invite?", "", func(n: String) -> void: Net.ask(&"req_social", [&"party", n])))
	if not party.is_empty():
		_bottom_button("Leave party", func() -> void: Net.ask(&"req_social", [&"leave_party", ""]), 1)

func _draw_guild() -> void:
	var g: Dictionary = Game.social.get("guild", {})
	if g.is_empty():
		for k in 3:
			draw_hint(Vector2(PAD, LIST_Y + 18 + k * 18), ["You're not in a guild.", "Found one with the Guild Clerk in Dawnharbor", "(%d Dawnshards, level %d), or get invited." % [TDSocial.GUILD_COST, TDSocial.GUILD_LEVEL]][k])
		return
	draw_label(Vector2(PAD, LIST_Y - 2), "%s  ·  master %s" % [g["name"], g["master"]], Palette.SUN, 13)
	var members: Array = g["members"]
	for i in mini(members.size(), ROWS - 1):
		var m: Array = members[i]
		var r := _row(i)
		r.position.y += 10
		draw_row(r)
		draw_circle(r.position + Vector2(10, r.size.y / 2.0), 4, Palette.GOOD if m[1] else Color(0.5, 0.45, 0.6))
		draw_label(r.position + Vector2(20, 18), m[0], Palette.SUN if m[1] else Palette.MIST, 13)
	if g["master"] == Game.me.name:
		_bottom_button("Invite", func() -> void:
			hud.prompt.ask("Who do you want in the guild?", "", func(n: String) -> void: Net.ask(&"req_social", [&"guild", n])))
	_bottom_button("Leave guild", func() -> void: Net.ask(&"req_social", [&"leave_guild", ""]), 1)

func _click(at: Vector2, button: int, _double: bool) -> void:
	if button != MOUSE_BUTTON_LEFT:
		return
	var t := tab_at(at)
	if t >= 0:
		tab = t