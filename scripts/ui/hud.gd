class_name TDHud
extends CanvasLayer
## The screen UI: the status bar (level, HP, MP, EXP, skills, Dawnshards), the in-game
## overlay, the game windows (inventory, equipment, character), and the title / pause menu.
## Art comes from UiSkin.

## Input actions that open and close a window, in the order the status bar shows them.
const WINDOW_ACTIONS: Array[String] = ["inventory", "equipment", "stats", "skills", "quests", "worldmap", "community", "collection"]

var world: TDWorld
var overlay: TDOverlay
var status: TDStatusBar
var quickslots: TDQuickslots
var title: Control
## The title card (name, Play, Host, Join), hidden while the character creator is open.
var title_card: Control
var creator: TDCreator
var start_panel: Control
var pause_panel: Control
var resume_button: Button
var name_field: LineEdit
var address_field: LineEdit
## Shows why joining didn't work.
var message: Label
var ui_theme: Theme
## Holds the windows so raising one never lifts it above the tooltip or the title menu.
var window_layer: Control
## action -> TDWindow
var windows := {}
var tooltip: TDItemTooltip
var chat: TDChat
var invites: TDInvites
var prompt: TDPrompt

func _ready() -> void:
	layer = 10
	ui_theme = Theme.new()
	ui_theme.default_font = Game.ui_font
	ui_theme.default_font_size = 14
	UiSkin.use_cursor()

	overlay = TDOverlay.new()
	overlay.world = world
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)
	status = TDStatusBar.new()
	status.world = world
	status.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	status.offset_top = -TDStatusBar.HEIGHT
	status.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(status)
	quickslots = TDQuickslots.new()
	quickslots.world = world
	quickslots.hud = self
	add_child(quickslots)
	chat = TDChat.new()
	chat.world = world
	add_child(chat)
	_build_windows()
	invites = TDInvites.new()
	add_child(invites)
	prompt = TDPrompt.new()
	add_child(prompt)
	# clicking the minimap opens the world map
	var minimap := Button.new()
	minimap.flat = true
	minimap.focus_mode = Control.FOCUS_NONE
	minimap.position = Vector2(TDWorld.VIEW.x - 182, 10)
	minimap.size = Vector2(172, 50)
	minimap.tooltip_text = "World map (W)"
	minimap.pressed.connect(func() -> void:
		if world.started:
			toggle_window("worldmap"))
	add_child(minimap)
	move_child(minimap, window_layer.get_index())
	_build_title()

func _build_windows() -> void:
	window_layer = Control.new()
	window_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	window_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(window_layer)
	var view := TDWorld.VIEW
	var inventory := TDInventoryWindow.new()
	inventory.position = Vector2(view.x - inventory.size.x - 16, 70)
	var equipment := TDEquipmentWindow.new()
	equipment.position = Vector2(inventory.position.x - equipment.size.x - 10, 70)
	var stats := TDStatsWindow.new()
	stats.position = Vector2(16, 56)
	var quests := TDQuestWindow.new()
	quests.position = Vector2(16, 120)
	var worldmap := TDWorldMapWindow.new()
	worldmap.position = (view - worldmap.size) / 2.0 + Vector2(0, -20)
	var skills := TDSkillWindow.new()
	skills.position = Vector2(276, 56)
	# opened by talking to NPCs rather than by a key
	var dialogue := TDDialogueWindow.new()
	var shop := TDShopWindow.new()
	var storage := TDStorageWindow.new()
	var community := TDCommunityWindow.new()
	community.position = Vector2(300, 80)
	var collection := TDCollectionWindow.new()
	collection.position = Vector2(230, 60)
	# opened by other players
	var player := TDPlayerMenuWindow.new()
	var trade := TDTradeWindow.new()
	var player_shop := TDPlayerShopWindow.new()
	for pair in [["inventory", inventory], ["equipment", equipment], ["stats", stats], ["quests", quests], ["skills", skills], ["worldmap", worldmap],
			["community", community], ["collection", collection], ["dialogue", dialogue], ["shop", shop], ["storage", storage], ["player", player], ["trade", trade], ["player_shop", player_shop]]:
		var w: TDWindow = pair[1]
		w.hud = self
		windows[pair[0]] = w
		window_layer.add_child(w)
	tooltip = TDItemTooltip.new()
	tooltip.set_anchors_preset(Control.PRESET_FULL_RECT)
	tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tooltip)

## Opens an NPC's dialogue window.
func open_dialogue(npc: TDNpc) -> void:
	windows["dialogue"].open(npc)

## Opens an NPC's shop, with the bag beside it.
func open_shop(npc: TDNpc) -> void:
	windows["shop"].open(npc)

## The server's latest on your trade ({} when it's over).
func show_trade(state: Dictionary) -> void:
	windows["trade"].show_state(state)

## A player shop you're looking at (or your own).
func show_player_shop(owner: int, owner_name: String, title_text: String, items: Array) -> void:
	windows["player_shop"].show_shop(owner, owner_name, title_text, items)

## Typing in the chat box or a text prompt: keys shouldn't move the player.
func typing() -> bool:
	return chat.typing() or prompt.visible

## Minding your own shop: you stay put.
func selling() -> bool:
	return windows["player_shop"].selling()

func toggle_window(action: String) -> void:
	if windows.has(action):
		windows[action].toggle()

## Closes the window on top (Esc). False if none was open.
func close_top_window() -> bool:
	for i in range(window_layer.get_child_count() - 1, -1, -1):
		var w := window_layer.get_child(i) as TDWindow
		if w.visible:
			w.toggle()
			return true
	return false

## The open window under a screen point, or null.
func window_at(pos: Vector2) -> TDWindow:
	for i in range(window_layer.get_child_count() - 1, -1, -1):
		var w := window_layer.get_child(i) as TDWindow
		if w.visible and w.get_global_rect().has_point(pos):
			return w
	return null

func _build_title() -> void:
	title = ColorRect.new()
	(title as ColorRect).color = Color(Palette.NIGHT, 0.45)
	title.theme = ui_theme
	title.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(title)
	title_card = CenterContainer.new()
	title_card.set_anchors_preset(Control.PRESET_FULL_RECT)
	title.add_child(title_card)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 10)
	title_card.add_child(col)

	var heading := Label.new()
	heading.text = "Tera Dawn"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_override("font", Game.num_font)
	heading.add_theme_font_size_override("font_size", 96)
	heading.add_theme_color_override("font_color", Palette.SUN)
	heading.add_theme_color_override("font_outline_color", Palette.PLUM)
	heading.add_theme_constant_override("outline_size", 18)
	heading.add_theme_color_override("font_shadow_color", Palette.EMBER)
	heading.add_theme_constant_override("shadow_offset_y", 6)
	heading.add_theme_constant_override("shadow_offset_x", 0)
	col.add_child(heading)

	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiSkin.panel())
	col.add_child(card)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 12)
	card.add_child(inner)

	var blurb := Label.new()
	blurb.text = "The sun is rising over Dawnrise Meadow. Clear out the Dewlings, climb the ropes, and follow the portal east to Ember Hollow."
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.custom_minimum_size.x = 500
	blurb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	blurb.add_theme_color_override("font_color", Palette.MIST)
	blurb.add_theme_font_size_override("font_size", 16)
	inner.add_child(blurb)

	# before playing: a name, then single player, host, or join an address
	start_panel = VBoxContainer.new()
	start_panel.add_theme_constant_override("separation", 10)
	inner.add_child(start_panel)
	name_field = _field(Game.player_name, "Your character's name", CharacterStore.MAX_NAME)
	start_panel.add_child(_row([_label("Name"), name_field]))
	var play := _menu_button("Play")
	play.pressed.connect(_on_play)
	var host := _menu_button("Host")
	host.tooltip_text = "Play and let friends join you (port %d)" % Net.DEFAULT_PORT
	host.pressed.connect(_on_host)
	start_panel.add_child(_row([play, host]))
	address_field = _field(Game.last_address, "Server address", 64)
	var join := _menu_button("Join")
	join.pressed.connect(_on_join)
	start_panel.add_child(_row([_label("Server"), address_field, join]))
	message = _label("")
	message.add_theme_color_override("font_color", Palette.BAD)
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	start_panel.add_child(message)

	# while playing: the pause menu
	pause_panel = HBoxContainer.new()
	pause_panel.alignment = BoxContainer.ALIGNMENT_CENTER
	pause_panel.add_theme_constant_override("separation", 16)
	resume_button = _menu_button("Resume")
	resume_button.pressed.connect(func() -> void: title.hide())
	pause_panel.add_child(resume_button)
	var leave := _menu_button("Leave")
	leave.pressed.connect(_on_leave)
	pause_panel.add_child(leave)
	pause_panel.hide()
	inner.add_child(pause_panel)

	var quit := _menu_button("Quit")
	quit.pressed.connect(func() -> void:
		Net.stop()
		get_tree().quit())
	inner.add_child(_row([quit]))

	var keys := Label.new()
	keys.text = "Arrows move and climb · Space jump · X attack · A Dawn Slash · Z loot · Up talks and enters portals\nI inventory · E equipment · S character · Esc menu · F11 fullscreen\nGamepad: stick · A jump · X attack · Y Dawn Slash · B loot · Back inventory · Start menu"
	keys.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	keys.add_theme_font_size_override("font_size", 12)
	keys.add_theme_color_override("font_color", Palette.MUTED)
	inner.add_child(keys)
	name_field.call_deferred("grab_focus")

	# a name with no character yet: the creator takes the title card's place
	creator = TDCreator.new()
	creator.hide()
	title.add_child(creator)
	Net.new_character.connect(func(char_name: String) -> void:
		title_card.hide()
		creator.open(char_name))
	creator.created.connect(func(made: NewCharacter) -> void: Net.create(made))
	creator.cancelled.connect(func() -> void:
		Net.stop()
		_close_creator())

	Net.joined.connect(_on_joined)
	Net.join_failed.connect(func(reason: String) -> void:
		_close_creator()
		_show_message(reason))
	Net.disconnected.connect(func() -> void:
		world.stop()
		show_title(false)
		_show_message("Lost the connection to the server."))

func _menu_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(150, 48)
	b.add_theme_font_override("font", Game.num_font)
	b.add_theme_font_size_override("font_size", 22)
	UiSkin.style_button(b)
	return b

func _field(text: String, hint: String, max_length: int) -> LineEdit:
	var f := LineEdit.new()
	f.text = text
	f.placeholder_text = hint
	f.max_length = max_length
	f.custom_minimum_size = Vector2(220, 40)
	return f

func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.custom_minimum_size.x = 60
	l.add_theme_color_override("font_color", Palette.MIST)
	return l

func _row(children: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	for c in children:
		row.add_child(c)
	return row

## The name typed in, remembered for next time. "" (with a message) if it's no good.
func _chosen_name() -> String:
	var n := CharacterStore.clean_name(name_field.text)
	if n == "":
		_show_message("Please pick a name.")
		return ""
	Game.player_name = n
	Game.save_settings()
	return n

func _on_play() -> void:
	var n := _chosen_name()
	if n != "":
		Net.play_single(n)

func _on_host() -> void:
	var n := _chosen_name()
	if n != "":
		_show_message(Net.host(n))

func _on_join() -> void:
	var n := _chosen_name()
	var address := address_field.text.strip_edges()
	if n == "" or address == "":
		return
	Game.last_address = address
	Game.save_settings()
	var problem := Net.join(n, address)
	_show_message(problem if problem != "" else "Connecting to %s…" % address)

func _on_joined() -> void:
	_show_message("")
	_close_creator()
	title.hide()
	world.start()

func _close_creator() -> void:
	creator.hide()
	title_card.show()

func _on_leave() -> void:
	world.stop()
	show_title(false)

func _show_message(text: String) -> void:
	message.text = text

## The title screen (not playing yet) or the pause menu (playing).
func show_title(paused: bool) -> void:
	start_panel.visible = not paused
	pause_panel.visible = paused
	title.show()
	if paused:
		resume_button.grab_focus()
	else:
		name_field.grab_focus()
