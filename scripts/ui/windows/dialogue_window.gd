class_name TDDialogueWindow
extends TDWindow
## Talking to an NPC (Up next to them): their portrait and name, what they're saying, and a
## numbered list of what you can do with them (chat, quests, their shop, ...). Click an
## option or press its number. Some options open a page of their own (a quest's offer, with
## Accept and Decline). It closes when you walk away.
##
## To give NPCs something new to offer (storage, travel, ...), add it in `_options()`.

const WIDTH := 540.0
## The dialogue frame (UiSkin.DIALOGUE_FRAME) is drawn at this many pixels per texel, and
## grows taller for long speeches.
const FRAME_SCALE := 0.8
const FRAME_X := PAD - 6
## Inside the frame's art, in texels: where the portrait niche's opening is (left, top,
## right, and how far up from the bottom), and where the text starts and ends.
const NICHE := Vector4(28, 72, 125, 39)
const TEXT_LEFT := 168.0
const TEXT_RIGHT := 36.0
const TEXT_TOP := 58.0
const TEXT_BOTTOM := 36.0
const LINE_H := 17.0
const ROW_H := 26.0
## Option rows: pixels per texel of the option row art.
const ROW_SCALE := 0.6
## Walk this far from the NPC and the window closes.
const REACH := 170.0

var npc: TDNpc
var text := ""
## [label, Callable] for each thing the player can pick.
var options: Array = []
var _line := -1

func _init() -> void:
	super("", Vector2(WIDTH, 330))

func _ready() -> void:
	super()
	# quests and items change while the window is open: keep the list up to date
	Game.character_changed.connect(func() -> void:
		if visible and _on_main_page:
			options = _options())

var _on_main_page := true

## Opens the window for `who`, starting with their greeting.
func open(who: TDNpc) -> void:
	npc = who
	title = who.def.display_name
	_line = -1
	_main_page(who.def.greeting if who.def.greeting != "" else _next_line())
	_fit()
	position = (TDWorld.VIEW - size) / 2.0 + Vector2(0, -40)
	visible = true
	raise()

func _main_page(say: String) -> void:
	_on_main_page = true
	text = say
	options = _options()

## A page of its own: different text and options, until one of them goes back.
func _page(say: String, page_options: Array) -> void:
	_on_main_page = false
	text = say
	options = page_options

## What this NPC offers, in order. Goodbye is always last.
func _options() -> Array:
	var out := []
	var def := npc.def
	out.append_array(_quest_options())
	if def.storage:
		out.append(["Open storage", func() -> void:
			visible = false
			hud.windows["storage"].open(npc)])
	if def.guild:
		out.append(["Found a guild", _guild_page])
	if def.market:
		out.append(["Set up a shop", func() -> void:
			visible = false
			hud.windows["player_shop"].setup()])
	if not def.travel.is_empty():
		out.append(["Travel", _travel_list])
	if not _jobs_offered().is_empty():
		out.append(["Choose a job", _job_list])
	if not def.lines.is_empty():
		out.append(["Chat", func() -> void: text = _next_line()])
	if def.shop:
		out.append(["Open shop", func() -> void:
			visible = false
			hud.open_shop(npc)])
	out.append(["Goodbye", func() -> void: visible = false])
	return out

## One option per quest this NPC has something to say about.
func _quest_options() -> Array:
	var out := []
	var me := Game.me
	var greeting := npc.def.greeting
	for q in Content.quests_of(npc.def.id):
		var status := me.quests.status(q, me)
		if status == QuestLog.Status.READY and q.turn_in_npc() == npc.def.id:
			out.append(["Hand in: %s" % q.title, func() -> void:
				_page("%s\n\nReward: %s" % [q.complete_text, q.describe_rewards()], [
					["Complete the quest", func() -> void:
						Net.ask(&"req_quest_complete", [npc.def.id, q.id])
						_main_page(greeting)],
					["Not yet", func() -> void: _main_page(greeting)]])])
		elif status == QuestLog.Status.AVAILABLE and q.giver == npc.def.id:
			out.append(["New quest: %s" % q.title, func() -> void:
				_page("%s%s\n\n%s\nReward: %s" % [q.offer_text, _job_paths(q), _objective_list(q), q.describe_rewards()], [
					["Accept", func() -> void:
						Net.ask(&"req_quest_accept", [npc.def.id, q.id])
						_main_page(greeting)],
					["Decline", func() -> void: _main_page(greeting)]])])
		elif status in [QuestLog.Status.ACTIVE, QuestLog.Status.READY]:
			out.append(["In progress: %s" % q.title, func() -> void:
				_page("%s%s\n\n%s" % [q.progress_text, _job_paths(q), _objective_list(q)], [
					["Back", func() -> void: _main_page(greeting)]])])
	return out

## Founding a guild: the price, then a name.
func _guild_page() -> void:
	var greeting := npc.def.greeting
	var who := npc.def.id
	if Game.me.guild != "":
		_page("You're already in %s. Leave it first if you want to found your own." % Game.me.guild, [["Back", func() -> void: _main_page(greeting)]])
		return
	_page("A guild of your own costs %d Dawnshards, and you must be level %d. Its name shows under every member's name, and members can talk with /g." % [TDSocial.GUILD_COST, TDSocial.GUILD_LEVEL], [
		["Name the guild", func() -> void:
			visible = false
			hud.prompt.ask("Name your guild", "", func(n: String) -> void: Net.ask(&"req_guild_create", [who, n]))],
		["Back", func() -> void: _main_page(greeting)]])

## Where this NPC can take you, and the fare.
func _travel_list() -> void:
	var greeting := npc.def.greeting
	var opts := []
	for i in npc.def.travel.size():
		var r := npc.def.travel[i]
		var dest: MapDef = Content.maps.get(r.target_map)
		if dest == null:
			continue
		var fare := "free" if r.price == 0 else "%d Dawnshards" % r.price
		opts.append(["%s to %s (%s)" % [r.by, dest.display_name, fare], func() -> void:
			Net.ask(&"req_travel", [npc.def.id, i])
			visible = false])
	opts.append(["Back", func() -> void: _main_page(greeting)])
	_page("Where to?", opts)

## The jobs this instructor teaches that the player could advance into from their job.
func _jobs_offered() -> Array[JobDef]:
	var out: Array[JobDef] = []
	for id in npc.def.instructs:
		var j: JobDef = Content.jobs.get(id)
		if j and j.advances_from == Game.me.job.id:
			out.append(j)
	return out

func _job_list() -> void:
	var greeting := npc.def.greeting
	var opts := []
	for j in _jobs_offered():
		opts.append([j.display_name, _job_page.bind(j)])
	opts.append(["Back", func() -> void: _main_page(greeting)])
	_page("Which path calls to you?", opts)

## One job: what it is, what it takes (in red what you don't have yet), and the choice.
## A Beginner without the stats it asks for may also take the one free AP reset.
func _job_page(j: JobDef) -> void:
	var problem := Game.me.advance_problem(j)
	var say := "%s\n\nRequires: %s" % [j.description, ", ".join(j.requirement_lines())]
	if problem != "":
		say += "\n\n" + problem
	var opts := []
	if problem == "":
		opts.append(["Become a %s" % j.display_name, func() -> void:
			Net.ask(&"req_advance", [npc.def.id, j.id])
			visible = false])
	if Game.me.ap_reset_problem(j) == "":
		opts.append(["Reset my Ability Points", _reset_ap_page.bind(j)])
	opts.append(["Back", _job_list])
	_page(say, opts)

## The free AP reset: what it does, once, and the choice.
func _reset_ap_page(j: JobDef) -> void:
	_page("Built the wrong way? Once, and only once, I can give back all %d Ability Points you've spent. Your stats go back to where you started, so you can put them where a %s needs them." % [Game.me.spent_ap(), j.display_name], [
		["Reset them", func() -> void:
			Net.ask(&"req_reset_ap", [npc.def.id, j.id])
			visible = false],
		["Back", _job_page.bind(j)]])

## For a quest that lists the job paths: a paragraph naming each job a Beginner can
## advance into and what it takes ("Warrior: Level 10, 35 STR"). "" for other quests.
static func _job_paths(q: QuestDef) -> String:
	if not q.lists_job_paths:
		return ""
	var lines := ["", "", "The paths ahead:"]
	for j in JobDef.paths_from(Character.START_JOB):
		lines.append(j.path_line())
	return "\n".join(lines)

## "Defeat 8 Dewlings (3/8)", one per line.
static func _objective_list(q: QuestDef) -> String:
	var me := Game.me
	var lines := []
	for i in q.objectives.size():
		var o := q.objectives[i]
		lines.append("%s (%d/%d)" % [o.describe(), me.quests.progress(q, i, me) if me.quests.active.has(q.id) else 0, o.count])
	return "\n".join(lines)

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
	return Rect2(PAD, size.y - PAD - (options.size() - i) * ROW_H, size.x - PAD * 2, ROW_H - 2)

## The frame with the portrait and what they say: tall enough for the text.
func _frame_rect() -> Rect2:
	var w := size.x - FRAME_X * 2
	var natural := UiSkin.tex(UiSkin.DIALOGUE_FRAME[0]).get_height() * FRAME_SCALE
	var text_h := _lines().size() * LINE_H + (TEXT_TOP + TEXT_BOTTOM) * FRAME_SCALE
	return Rect2(FRAME_X, TITLE_H + 2, w, maxf(natural, text_h))

## What they say, wrapped to the frame ("" is a paragraph break).
func _lines() -> PackedStringArray:
	var out := PackedStringArray()
	var w := size.x - FRAME_X * 2 - (TEXT_LEFT + TEXT_RIGHT) * FRAME_SCALE
	for paragraph in text.split("\n"):
		out.append_array(UiSkin.wrap_text(Game.ui_font, paragraph, 13, w))
		if paragraph == "":
			out.append("")
	return out

## Sizes the window to the frame and the options (the speech and options change as you pick).
func _fit() -> void:
	var h := _frame_rect().end.y + 8 + options.size() * ROW_H + PAD - 4
	if not is_equal_approx(h, size.y):
		size.y = h
		position.y = clampf(position.y, 0.0, TDWorld.VIEW.y - h)

func _process(delta: float) -> void:
	super(delta)
	if visible and (npc == null or not is_instance_valid(npc) or hud.world.player.position.distance_to(npc.position) > REACH):
		visible = false
	if visible:
		_fit()

func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if visible and k and k.pressed and not k.echo and k.keycode >= KEY_1 and k.keycode <= KEY_9:
		choose(k.keycode - KEY_1)
		get_viewport().set_input_as_handled()

func _draw_body() -> void:
	if npc == null:
		return
	var frame := _frame_rect()
	UiSkin.draw_panel(self, UiSkin.DIALOGUE_FRAME, frame, FRAME_SCALE)
	# their portrait in the niche, their title at its foot
	var niche := Rect2(frame.position + Vector2(NICHE.x, NICHE.y) * FRAME_SCALE, Vector2.ZERO)
	niche.end = Vector2(frame.position.x + NICHE.z * FRAME_SCALE, frame.end.y - NICHE.w * FRAME_SCALE)
	var tex := npc.portrait()
	if tex:
		draw_texture_rect(tex, fit(tex, niche.grow(-4)), false, npc.def.tint)
	if npc.def.title != "":
		DrawUtil.text(self, Game.ui_font, Vector2(niche.get_center().x, niche.end.y - 4), npc.def.title, 11, Palette.MIST, 0, 4, Palette.NIGHT)
	# what they say
	var y := frame.position.y + TEXT_TOP * FRAME_SCALE
	for l in _lines():
		if l != "":
			DrawUtil.text(self, Game.ui_font, Vector2(frame.position.x + TEXT_LEFT * FRAME_SCALE, y), l, 13, Palette.MIST, 1, 3, Palette.NIGHT)
		y += LINE_H if l != "" else LINE_H / 2.0
	# what you can do
	for i in options.size():
		var r := _option_rect(i)
		var hot := r.has_point(_hover)
		UiSkin.draw_box(self, UiSkin.option_row(hot), r, ROW_SCALE)
		DrawUtil.text(self, Game.ui_font, Vector2(r.position.x + 16, r.end.y - 7), "%d.  %s" % [i + 1, options[i][0]], 14,
			Palette.INK if hot else Palette.SUN, 1, 0 if hot else 3, Palette.NIGHT)

func _click(at: Vector2, button: int, _double: bool) -> void:
	if button != MOUSE_BUTTON_LEFT:
		return
	for i in options.size():
		if _option_rect(i).has_point(at):
			choose(i)
			return
