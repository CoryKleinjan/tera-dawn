class_name TDCommunityWindow
extends TDWindow
## Your party (O), from the server's summary in Game.social: each member's job, map and HP.
## Invite people from here by name, or click them on the map.

const LIST_Y := 52.0
const ROW_H := 30.0
const ROWS := TDSocial.PARTY_MAX
## A party row: the member's HP bar, the Kick button, and the space between them.
const PARTY_HP_W := 80.0
const KICK_W := 38.0
const BUTTON_GAP := 8.0

func _init() -> void:
	super("Party", Vector2(340, LIST_Y + ROWS * ROW_H + 56))

func row_rect(i: int) -> Rect2:
	return Rect2(PAD, LIST_Y + i * ROW_H, size.x - PAD * 2, ROW_H - 4)

func _draw_body() -> void:
	_draw_party()

func _bottom_button(label: String, action: Callable, slot := 0) -> void:
	add_button(bottom_half_rect(slot), label, action)

func _draw_party() -> void:
	var party: Dictionary = Game.social.get("party", {})
	var members: Array = party.get("members", [])
	if party.is_empty():
		draw_hint(Vector2(PAD, LIST_Y + 18), "You're not in a party. Invite someone to start one.")
	var lead: bool = party.get("leader", "") == Game.me.name or party.is_empty()
	for i in mini(members.size(), ROWS):
		var m: Array = members[i]
		var r := row_rect(i)
		draw_row(r)
		var j: JobDef = Content.jobs.get(StringName(m[2]))
		var x := 6.0
		if m[0] == party["leader"]:
			UiSkin.draw_icon(self, "social/leader_star", Rect2(r.position + Vector2(4, 1), Vector2(14, 14)))
			x = 20.0
		draw_label(r.position + Vector2(x, 12), m[0], Palette.SUN, 12)
		draw_label(r.position + Vector2(6, 24), "%s  ·  %s" % [j.display_name if j else "", Content.map(StringName(m[4])).display_name if Content.maps.has(StringName(m[4])) else ""], Palette.MUTED, 10)
		WorldSkin.draw_party_hp(self, party_hp_rect(r).position, PARTY_HP_W, float(m[3]))
		var who: String = m[0]
		if lead and who != Game.me.name:
			add_button(kick_rect(r), "Kick", func() -> void: Net.ask(&"req_social", [&"kick", who]), true, true)
	if lead:
		_bottom_button("Invite", func() -> void:
			hud.prompt.ask("Who do you want to invite?", "", func(n: String) -> void: Net.ask(&"req_social", [&"party", n])))
	if not party.is_empty():
		_bottom_button("Leave party", func() -> void: Net.ask(&"req_social", [&"leave_party", ""]), 1)

## Where a party row's Kick button goes.
func kick_rect(row: Rect2) -> Rect2:
	return Rect2(row.end.x - KICK_W - 2, row.position.y + 3, KICK_W, 20)

## Where a party row's HP bar goes: a gap short of the Kick button, whether or not it's there.
func party_hp_rect(row: Rect2) -> Rect2:
	var art := UiSkin.tex("social/party_hp_frame")
	return Rect2(kick_rect(row).position.x - BUTTON_GAP - PARTY_HP_W, row.position.y + 4, PARTY_HP_W, art.get_height() * PARTY_HP_W / art.get_width())
