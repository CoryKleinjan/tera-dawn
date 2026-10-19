class_name TDCommunityWindow
extends TDWindow
## Buddies, party and guild (O), from the server's summary in Game.social. Buddies shows
## who's online and where; Party shows each member's job and HP; Guild lists its
## members. Invite people from here by name, or click them on the map.

const TABS := ["Buddies", "Party", "Guild"]
const LIST_Y := 72.0
const ROW_H := 30.0
const ROWS := 8
## A party row: the member's HP bar, the Kick button, and the space between them.
const PARTY_HP_W := 80.0
const KICK_W := 38.0
const BUTTON_GAP := 8.0
## Pixels per art pixel of the friend row art, and the middle of its round niche in art pixels.
const ROW_SCALE := (ROW_H - 4) / 61.0
const NICHE_CENTER := Vector2(42, 30)

var tab := 0

func _init() -> void:
	super("Community", Vector2(340, LIST_Y + ROWS * ROW_H + 56))

func row_rect(i: int) -> Rect2:
	return Rect2(PAD, LIST_Y + i * ROW_H, size.x - PAD * 2, ROW_H - 4)

## A buddy or guild member's row with their online dot in its niche.
func _friend_row(r: Rect2, online: bool) -> void:
	UiSkin.draw_box(self, UiSkin.friend_row(), r, ROW_SCALE)
	var c := r.position + NICHE_CENTER * ROW_SCALE
	UiSkin.draw_icon(self, "social/online_dot" if online else "social/offline_dot", Rect2(c - Vector2(7, 7), Vector2(14, 14)))

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
	add_button(bottom_half_rect(slot), label, action)

func _draw_buddies() -> void:
	var list: Array = Game.social.get("buddies", [])
	if list.is_empty():
		draw_hint(Vector2(PAD, LIST_Y + 18), "No buddies yet. Click a player, or Add.")
	for i in mini(list.size(), ROWS):
		var b: Array = list[i]
		var r := row_rect(i)
		_friend_row(r, b[1])
		draw_label(r.position + Vector2(36, 18), b[0], Palette.SUN if b[1] else Palette.MIST, 13)
		draw_label(r.position + Vector2(124, 18), b[2] if b[1] else "Offline", Palette.MUTED, 11)
		var who: String = b[0]
		if b[1]:
			icon_button(Rect2(r.end.x - 78, r.position.y + 2, 24, 22), "social/whisper_icon", func() -> void: hud.chat.open("/w %s " % who))
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

func _draw_guild() -> void:
	var g: Dictionary = Game.social.get("guild", {})
	if g.is_empty():
		for k in 3:
			draw_hint(Vector2(PAD, LIST_Y + 18 + k * 18), ["You're not in a guild.", "Found one with the Guild Clerk in Dawnharbor", "(%d Dawnshards), or get invited." % TDSocial.GUILD_COST][k])
		return
	UiSkin.draw_icon(self, "social/guild_emblem", Rect2(PAD, LIST_Y - 12, 20, 20))
	WorldSkin.draw_guild_tag(self, Vector2(PAD + 26 + (DrawUtil.text_width(Game.ui_font, g["name"], 11) + 34) / 2.0, LIST_Y - 10), g["name"])
	draw_label(Vector2(size.x - PAD, LIST_Y + 4), "master %s" % g["master"], Palette.MUTED, 11, -1)
	var members: Array = g["members"]
	for i in mini(members.size(), ROWS - 1):
		var m: Array = members[i]
		var r := row_rect(i)
		r.position.y += 10
		_friend_row(r, m[1])
		draw_label(r.position + Vector2(36, 18), m[0], Palette.SUN if m[1] else Palette.MIST, 13)
	if g["master"] == Game.me.name:
		_bottom_button("Invite", func() -> void:
			hud.prompt.ask("Who do you want in the guild?", "", func(n: String) -> void: Net.ask(&"req_social", [&"guild", n])))
	_bottom_button("Leave guild", func() -> void: Net.ask(&"req_social", [&"leave_guild", ""]), 1)

func _tab_clicked(i: int) -> void:
	tab = i
