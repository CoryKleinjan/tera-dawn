# Windows and settings

Part of the [architecture docs](../../ARCHITECTURE.md).

## How to add a window

Extend `TDWindow` (`scripts/ui/windows/window.gd`): draw in `_draw_body`, handle clicks in
`_click`, show tooltips from `_hovered`. Use `TDWindow`'s helpers rather than drawing your
own, so every window looks the same: `draw_tabs` / `tab_at`, `add_button` (drawn and clicked in
one call), `draw_row` for list rows, `draw_label`, `draw_hint` for empty lists, `draw_shards`
and `plus_button`. Colours come from `Palette` by meaning (`GOOD`, `BAD`, `MUTED`, `INFO`...),
never a hex value written in the window. Register it in `TDHud._build_windows` under an input
action, add the action to `TDHud.WINDOW_ACTIONS` and give it a line in `Keybinds.ACTIONS`.

## Settings

The `Settings` autoload loads `user://settings.cfg` before anything else starts and applies
it. Each group of settings is a `SettingsSection` (`scripts/settings/`) with its own
`[section]` in the file: `reset`, `load_from`, `save_to` and `apply`. Bad or missing values
keep the default, so an old or hand-edited file never breaks the game.

- **Keybinds** owns the input actions. `Keybinds.ACTIONS` lists each one with its name and
  group on the Controls tab, its default keys and its gamepad buttons; `apply` writes them to
  the `InputMap`. To add an action the player can press, add a line there and nothing else.
  Two actions never share a key: setting a used key swaps it. `pause` (Esc) can't be changed,
  so the menu is always reachable.
- **AudioSettings** sets the Master, Music and Effects buses (`default_bus_layout.tres`).
  Play music on the `Music` bus and sounds on `Effects` so the sliders reach them.
- **VideoSettings** sets the window, vsync and frame cap, and the stage's costly effects
  (bloom, ambient occlusion, fog). `TDStage` turns those on and off when `Settings.changed`
  fires.

The settings screen (`TDSettingsMenu`) changes a section, calls `Settings.apply(section)` so
the change shows at once, and `Settings.save()` when it closes. To add a setting, add the
field to its section (all four methods) and a widget on that section's tab; to add a group,
write a new `SettingsSection`, add it to `Settings.sections` and give it a tab. Game keeps its
`[player]` name and address in the same file through `Settings.file`.
