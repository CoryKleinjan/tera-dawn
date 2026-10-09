class_name TDDialogueWindow
extends TDWindow
## Talking to an NPC (Up next to them): their portrait and name, what they're saying, and a
## numbered list of what you can do with them (chat, quests, their shop, ...). Click an
## option or press its number. Some options open a page of their own (a quest's offer, with
## Accept and Decline). It closes when you walk away.
##
## To give NPCs something new to offer (storage, travel, ...), add it in `_options()`.

const PORTRAIT := 96.0
const TEXT_X := PAD + PORTRAIT + 16
const ROW_H := 26.0
## Walk this far from the NPC and the window closes.
const REACH := 170.0
## The window fits its page: never shorter than the portrait needs, never taller than this.
const MIN_H := 200.0
const MAX_H := 440.0
const TEXT_TOP := TITLE_H + 26
const LINE_H := 18.0

var npc: TDNpc
var text := ""
## [label, Callable] for each thing the player can pick.
var options: Array = []
var _line := -1

func _init() -> void:
	super("", Vector2(520, MIN_H))

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
	position = (TDWorld.VIEW - size) / 2.0 + Vector2(0, -40)
	visible = true
	raise()

func _main_page(say: String) -> void:
	_on_main_page = true
	text = say
	options = _options()
	_fit()

## A page of its own: different text and options, until one of them goes back.
func _page(say: String, page_options: Array) -> void:
	_on_main_page = false
	text = say
	options = page_options
	_fit()

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
	opts.append(["Back", _job_list])
	_page(say, opts)

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
	return Rect2(TEXT_X - 6, size.y - PAD - (options.size() - i) * ROW_H, size.x - TEXT_X - PAD + 6, ROW_H - 2)

func _process(delta: float) -> void:
	if visible:
		_fit()
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
	draw_row(box)
	var tex := npc.portrait()
	if tex:
		draw_texture_rect(tex, fit(tex, box.grow(-6)), false, npc.def.tint)
	if npc.def.title != "":
		DrawUtil.text(self, Game.ui_font, Vector2(box.get_center().x, box.end.y + 16), npc.def.title, 11, Palette.MUTED, 0, 3, Palette.NIGHT)
	# what they say
	for l in _text_lines():
		DrawUtil.text(self, Game.ui_font, Vector2(TEXT_X, l[1]), l[0], 13, Palette.MIST, 1, 3, Palette.NIGHT)
	# what you can do
	for i in options.size():
		var r := _option_rect(i)
		if r.has_point(_hover):
			draw_hilite(r)
		DrawUtil.text(self, Game.ui_font, Vector2(r.position.x + 8, r.end.y - 7), "%d.  %s" % [i + 1, options[i][0]], 14, Palette.SUN, 1, 3, Palette.NIGHT)

## The page's text wrapped to the window, as [line, baseline y].
func _text_lines() -> Array:
	var out := []
	var y := TEXT_TOP
	for paragraph in text.split("\n"):
		for l in UiSkin.wrap_text(Game.ui_font, paragraph, 13, size.x - TEXT_X - PAD):
			out.append([l, y])
			y += LINE_H
		if paragraph == "":
			y += 8
	return out

## How tall the window needs to be for this page: its text, then its options, and room for
## the portrait.
func wanted_height() -> float:
	var lines := _text_lines()
	var text_end: float = lines[-1][1] + 10.0 if not lines.is_empty() else TEXT_TOP
	return clampf(text_end + options.size() * ROW_H + PAD, MIN_H, MAX_H)

## Resizes to the page, keeping the window above the status bar.
func _fit() -> void:
	size.y = wanted_height()
	position.y = minf(position.y, TDWorld.VIEW.y - TDStatusBar.HEIGHT - size.y - 4)

func _click(at: Vector2, button: int, _double: bool) -> void:
	if button != MOUSE_BUTTON_LEFT:
		return
	for i in options.size():
		if _option_rect(i).has_point(at):
			choose(i)
			return
