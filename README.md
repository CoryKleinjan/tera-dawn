# Tera's Dawn

A 2D side-scrolling online action RPG inspired by MapleStory, built with **Godot 4.3** for
Steam (Windows, macOS, Linux and Steam Deck).

It has an **HD-2D** look in the style of Octopath Traveler: painted sprites in a lit 3D diorama
with depth of field, tilt-shift blur, bloom, dynamic lights and shadows. Gameplay stays a flat
2D side-scroller; only `scripts/world/stage.gd` turns the map into 3D (see
[rendering](docs/architecture/rendering.md)). The renderer is Forward+ (Vulkan, or Direct3D 12
on Windows).

**What's in it:** play solo, host, or log in to a server with accounts and up to six characters
each; a world of regions, towns, fields and boss hunting grounds joined by portals, ships and
coaches; a Beginner and five jobs (Warrior, Archer, Magician, Thief, Pirate) with skill books,
quickslots, melee, ranged and magic combat; MapleStory-style stats, gear, upgrade scrolls and
drops; NPCs, shops, storage and quests; chat, parties, buddies, guilds, trades, fame and player
shops in the Free Market; chairs, pets, the Monster Book and Steam achievements.

All content is data in `data/`, and all art is painted sheets in `art/source/` cut into
`assets/` by `tools/art/slice_sheets.py`. [ARCHITECTURE.md](ARCHITECTURE.md) explains how the
code is laid out and links a page per system, with how to add a monster, map, item, skill and so on.

## Running it

1. Install [Godot 4.3](https://godotengine.org/download) (the standard build; C# isn't needed).
2. In the Project Manager, choose **Import** and pick this folder's `project.godot`.
3. Press **F5**. On the title screen pick **Play solo**, **Host** (friends join on UDP port
   7350, which must be forwarded to host over the internet), or enter a server address,
   username and password and **Log in** (or **Register**). Then pick or make a character.

Dedicated server, with no window and no player of its own:

```sh
godot --headless --path . -- --server --port 7350
```

It keeps accounts and characters under its own `user://characters/` and saves every 10
seconds, on map changes and when players leave. Passwords are stored only as salted PBKDF2
hashes, and the connection is encrypted (DTLS) with a key and certificate in
`user://characters/tls/`, made on first start. To let players verify an official server, put
its real certificate there and ship it as `certs/<address>.crt`. See
[multiplayer](docs/architecture/multiplayer.md).

## Controls

Defaults; every key can be changed under **Settings > Controls**, with two keys per action.

| Action | Keyboard | Gamepad |
| --- | --- | --- |
| Move / climb | Arrow keys | Left stick or d-pad |
| Jump | Space or Alt | A |
| Drop through a platform | Down + Jump | Down + A |
| Attack | X or Ctrl | X |
| Quickslots (skills, potions) | A, D, F, G, V, B, N, M | Y, RB, LB |
| Pick up items (hold to keep looting) | Z | B |
| Inventory / Equipment / Character | I / E / S | Back (inventory) |
| Quests / Skills / World map | Q / K / W | |
| Community / Monster Book and achievements | O / L | |
| Chat | Enter | |
| Enter a portal, talk to an NPC | Up | Up |
| Pick a dialogue option | 1 to 9, or click | |
| Close a window, or open the menu | Esc | Start |
| Fullscreen | F11 | |

Settings (controls, volume, video quality) are saved in `user://settings.cfg`.

## Tests

```sh
tests/run_all.sh              # everything, as CI runs it on every pull request
tests/run_all.sh inventory    # only tests whose file or name contains "inventory"
python3 -m unittest discover -s tools/art/tests -t tools/art/tests   # art tools (numpy, Pillow)
```

`run_all.sh` fails if any test fails or Godot prints a script error. It runs:

- **The test runner** (`tests/run_tests.tscn`): every `*_test.gd` in `tests/unit/` (rules on
  their own), `tests/server/` (the server driven with pretend players, no window),
  `tests/content/` (every file in `data/`) and `tests/ui/` (every window opened, drawn and clicked).
- **The smoke test** (`tests/smoke_test.tscn`, checks in `tests/smoke/`): a scripted session
  through the real game, then a second copy (`tests/bot_client.tscn`) joining over the network.

To add a test, drop a `*_test.gd` into one of the four folders that `extends TestCase`
(`tests/framework/test_case.gd`); every `test_` method is a test. `tests/framework/` also has
helpers that set up content, a server or a running game. Tests start from a fixed random seed
and must not depend on timing or luck. `tests/balance_report.tscn` prints the balance table.

Screenshots (needs a GPU or software Vulkan and a display; `xvfb-run` works headless; an
optional second argument renders one part, such as `subzones`):

```sh
godot --path . --resolution 1600x900 res://tests/screenshot.tscn -- /path/to/output
```

## Shipping on Steam

1. **Steamworks**: sign up at partner.steamgames.com, pay the Steam Direct fee and note the app ID.
2. **GodotSteam**: install the GodotSteam GDExtension into `addons/godotsteam` and set `APP_ID`
   in `scripts/autoload/steam_service.gd`. Define achievements in Steamworks with the `steam`
   ids from `data/achievements/`.
3. **Store art**: `python3 tools/art/make_store_art.py` cuts `art/source/key_art.png` into the
   capsules in `store/`. They still need the logo laid over them; `main_capsule`,
   `vertical_capsule` and `library_capsule` are slightly upscaled, and `library_hero.png` is
   1920x620 (half of Steam's 3840x1240), so it needs larger key art.
4. **Export**: install the export templates, then **Project > Export** (Windows, Linux and macOS
   presets are in `export_presets.cfg`). macOS needs signing and notarization.
5. **Upload** with SteamPipe (`steamcmd` and an app build VDF), set up the store page and submit.
