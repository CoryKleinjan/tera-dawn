# Tera Dawn

A 2D side-scrolling action RPG in the spirit of MapleStory, built with **Godot 4.3** for desktop release on Steam (Windows, macOS, Linux and Steam Deck).

This is the first playable build. All art is drawn in code as placeholders until real sprites exist.

## What's in it

- Two maps: **Dawnrise Meadow** and **Ember Hollow**, joined by portals.
- Platforms, ropes and ladders, and dropping down through platforms.
- Basic attack and **Dawn Slash**, a skill that costs 8 MP and hits up to 4 monsters twice.
- Three monsters (Dewling, Sproutcap, Ember Boar) with patrol and chase behavior.
- EXP, leveling, HP and MP regen, fainting and respawn.
- **Dawnshards** (currency) dropped by monsters.
- Saving to `user://save.json`.
- Keyboard and gamepad controls, fullscreen toggle, title and pause menu.

## Controls

| Action | Keyboard | Gamepad |
| --- | --- | --- |
| Move / climb | Arrow keys | Left stick or d-pad |
| Jump | Space, C or Alt | A |
| Drop through a platform | Down + Jump | Down + A |
| Attack | X, Z or Ctrl | X |
| Dawn Slash | A or Shift | Y |
| Enter a portal | Up | Up |
| Menu | Esc | Start |
| Fullscreen | F11 | |

## Running it

1. Install [Godot 4.3](https://godotengine.org/download) (the standard build; C# isn't needed).
2. In the Project Manager, choose **Import** and pick this folder's `project.godot`.
3. Press **F5** to play.

Run the gameplay smoke test headless:

```sh
godot --headless --path . res://tests/smoke_test.tscn
```

It plays a short scripted session (walk, jump, kill a monster, loot, climb, take a portal) and exits non-zero on failure.

## Project layout

```
scenes/main.tscn        Entry scene (World)
scripts/world.gd        Map loading, camera, combat rules, terrain drawing
scripts/player.gd       Movement, climbing, attacks
scripts/mob.gd          Monster AI
scripts/drop.gd         Dawnshard drops
scripts/hud.gd          Status bar, title/pause menu
scripts/overlay.gd      Map name, minimap, message log, banners
scripts/background.gd   Sky and parallax
scripts/game_data.gd    Monsters, maps and color themes (all content lives here)
scripts/game_state.gd   Autoload "Game": stats, save file, input bindings
scripts/steam_service.gd  Autoload "SteamService": optional Steam hooks
tests/                  Headless smoke test
assets/fonts/           Baloo 2 and Lilita One (SIL Open Font License)
```

To add a map, monster or platform layout, edit `scripts/game_data.gd`.

## Shipping on Steam

1. **Steamworks.** Sign up at partner.steamgames.com, pay the Steam Direct fee for an app, and note the app ID.
2. **GodotSteam.** Install the GodotSteam GDExtension from the Godot Asset Library into `addons/godotsteam`. Then set `APP_ID` in `scripts/steam_service.gd`. Achievements (for example `REACH_LEVEL_5`, which the game already unlocks) are defined in the Steamworks dashboard.
3. **Export.** In Godot, install the export templates (Editor → Manage Export Templates). Then use **Project → Export**: presets for Windows, Linux and macOS are already in `export_presets.cfg`. macOS builds need signing and notarization with an Apple Developer account.
4. **Upload.** Upload the builds with SteamPipe (`steamcmd` + an app build VDF), set up the store page, and submit for review.
