# Windows and settings

Part of the [architecture docs](../../ARCHITECTURE.md).

## How to add a window

Extend `TDWindow` (`scripts/ui/windows/window.gd`): draw in `_draw_body`, handle clicks in
`_click` and tab clicks in `_tab_clicked(i)` (the base finds the tab), and say what the item
tooltip shows by returning a `Tip` (stack, hint, compare with worn) from `_tooltip_at(at)`;
the base shows and hides `hud.tooltip` for you. Use `TDWindow`'s helpers rather than drawing
your own, so every window looks the same: `draw_tabs` / `tab_at`, `add_button` (drawn and
clicked in one call), `bottom_button_rect` / `bottom_half_rect` for buttons along the bottom,
`draw_row` for list rows, `draw_label`, `draw_hint` for empty lists, `draw_slot`,
`draw_shards` and `plus_button`. Colours come from `Palette` by meaning (`GOOD`, `BAD`,
`MUTED`, `INFO`...), never a hex value written in the window. Register it in
`TDHud._build_windows` under an input action, add the action to `TDHud.WINDOW_ACTIONS` and
give it a line in `Keybinds.ACTIONS`.

Shared pieces for what's inside a window (`scripts/ui/windows/`):

- **`SlotGrid`**: a grid of item slots (origin, columns, count, slot size, gap): `rect(i)`,
  `cell_rect(cell)`, `at(pos)`, `bounds()`. The bag, shop, storage, trade, equipment and
  quickslots all use one.
- **`ScrollList`**: a list showing `rows` rows at a time that the mouse wheel scrolls:
  `row_rect(i)` (by index in the whole list), `shown(count)`, `row_at`, `wheel(button, count)`
  and the "scroll for more" line (`draw_more`). Windows call their rows' rect `row_rect(i)`.
- **`DragPayload`**: what's dragged between windows and the quickslots (`bag_item`, `worn`,
  `skill`, `quickslot`); read it back with `DragPayload.of(data)`. A control that needs to know
  where its drag ended keeps a `DragPayload.Tracker` (`start` in `_get_drag_data`,
  `ended_unplaced` on `NOTIFICATION_DRAG_END`). `TDWindow.drag_preview(icon)` is the icon
  under the mouse.

## The HUD and the title screen

`TDHud` (`scripts/ui/hud.gd`) is the screen UI while playing: the status bar, overlay,
quickslots, chat, the windows (the window manager above), a quest step's key hint, the game
menu (Esc) and the settings screen, and Esc and pausing (`escape`, `show_title`, `resume`).

`TDTitleScreen` (`scripts/ui/title_screen.gd`, `hud.title`) is the dimmed layer over the game
before you play and while paused: the key art, the title card (the logo over Play, Settings and
Quit; Play opens Solo and Co-op, Co-op opens Host and Join, and Join asks for the host's
address; Back and Esc step back one page),
character select, the creator and their questions. It runs everything from the first button
to `Net.joined` (see [multiplayer](multiplayer.md)) and tells the HUD through signals:
`settings_requested`, `quit_requested` and `left_game` (left, dropped or turned away: show
the title card again). The HUD puts the game menu and settings screen on it. Esc goes to
`TDTitleScreen.escape` first, which handles the title screens' own steps back and returns false
when Esc belongs to the game. A new screen before the game goes on the title screen; a new
in-game piece goes on the HUD.

`TDPad` (`scripts/ui/pad.gd`, `hud.pad`) makes the gamepad work everywhere: it turns the pad's
page with the left trigger, opens `TDPadMenu` (Back, a button per `TDHud.WINDOW_ACTIONS`), and
while a window is open and the pad was used last it draws a cursor that pushes real mouse
events through the viewport, so a new window works on the pad with no extra code. While it's
busy (`blocking`) the hero stands still (`TDWorld.input_blocked`). Pad A presses focused menu
buttons (`ui_accept`).

## UI art and building blocks

- **`UiSkin`**: the UI textures (`tex`, `sized`), nine-patch styles (`box`, `draw_box`), the
  ornate panels (`ARCH_PANEL`, `draw_panel`, `use_panel`) and list-row art.
- **`UiStyle`**: styles Godot controls with that art: `style_button`, `style_tab`, keycaps,
  fields, sliders, check boxes, dropdowns, scroll bars, `menu_button` and the button motion.
- **`WorldSkin`**: what's drawn over the world every frame: HP/MP/EXP bars, party, monster
  and boss bars, name and guild tags, quest markers, speech bubbles, hints and
  the map-name banner.
- **`UiBuild`**: makes the menus' controls: `label`, `heading`, `small_title`, `button` (a
  menu button that calls a function), `gold_button`, `centered_row`, `column`, `field`,
  `titled`. Pass a screen's own sizes and colours; don't write another `_label` helper.
- **`TDModal`**: a question over everything (dimmed screen, panel, question, optional text box,
  button row); `TDConfirm`, `TDDeleteConfirm` and `TDPrompt` extend it. `remember_focus` /
  `restore_focus` put the keyboard focus back when it closes.
- `DrawUtil.wrap_text` breaks text into lines for drawn text.

## Settings

The `Settings` autoload loads `user://settings.cfg` before anything else starts and applies
it. Each group of settings is a `SettingsSection` (`scripts/settings/`) with its own
`[section]` in the file: `reset`, `load_from`, `save_to` and `apply`. Bad or missing values
keep the default, so an old or hand-edited file never breaks the game.

- **Keybinds** owns the input actions. `Keybinds.ACTIONS` lists each one with its name and
  group on the Controls tab, its default keys and its gamepad buttons; `apply` writes them to
  the `InputMap`. To add an action the player can press, add a line there and nothing else.
  Two actions never share a key: setting a used key swaps it. `pause` (Esc) can't be changed,
  so the menu is always reachable. Pad buttons sit on two pages: `pad`/`axis` normally,
  `pad2`/`axis2` while the left trigger is held (`Keybinds.use_pad_page`); `pad_text` names
  them, and `TDStatusBar._key_name` uses it while the pad is in use (`TDPad.using_pad`).
- **AudioSettings** sets the Master, Music and Effects buses (`default_bus_layout.tres`); the
  Sound autoload plays everything on them (see [music and sound](audio.md)).
- **VideoSettings** sets the window, vsync and frame cap, and the stage's costly effects
  (bloom, ambient occlusion, fog). `TDStage` turns those on and off when `Settings.changed`
  fires.
- **DevSettings** holds developer-only switches, on a Developer tab that only debug builds
  (the editor, a debug export) show; a release build ignores them. `test_characters` makes
  character select (solo, host or join) list the test characters, saved in their own folder
  (`TestCharacters.FOLDER`): a `Character.MAX_LEVEL` character of every job in the best gear
  it can wear, every skill at its highest level and `TestCharacters.SHARDS` Dawnshards.
  They're made the first time (`TestCharacters.prepare`, from `Net.open_saves`), kept as
  played after that (but put back in their job's town), and made again after "Rebuild test
  characters". Everything is picked from the data (`TestCharacters.best_gear_for`), so new
  jobs, skills and gear show up with no code change. The player's own characters stay as
  they are. Character select shows `CharacterStore.MAX_CHARACTERS` slots, so raise it when
  there are more jobs than that.

The settings screen (`TDSettingsMenu`) changes a section, calls `Settings.apply(section)` so
the change shows at once, and `Settings.save()` when it closes. To add a setting, add the
field to its section (all four methods) and a widget on that section's tab; to add a group,
write a new `SettingsSection`, add it to `Settings.sections` and give it a tab. Game keeps its
`[player]` name and address in the same file through `Settings.file`.
