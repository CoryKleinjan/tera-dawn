# Tera's Dawn

A 2D side-scrolling action RPG in the spirit of MapleStory, built with **Godot 4.3** for desktop release on Steam (Windows, macOS, Linux and Steam Deck).

This is the first playable build. It uses an **HD-2D** look in the style of Octopath Traveler: painted sprites standing in a lit 3D diorama, with depth of field, tilt-shift blur, bloom, dynamic lights, real-time shadows and drifting particles. Gameplay is still a flat 2D side-scroller.

All the art comes from Cory's sheets in `art/source/`. `python3 tools/art/slice_sheets.py` cuts them into the sprites in `assets/sprites/` and the animations in `assets/animations/`, following one manifest per sheet in `art/sheets/` (see `art/sheets/README.md`). A new sheet needs a PNG and a manifest, no code.

The game is built to grow: monsters, NPCs, items, skills, effects, maps and biomes are all data files in `data/`. [ARCHITECTURE.md](ARCHITECTURE.md) explains how the code is laid out and how to add a monster, a map or a skill.

## How the HD-2D view works

- Game logic runs in 2D pixel coordinates exactly as before. `scripts/world/stage.gd` turns the map into 3D: one 3D unit is 32 game pixels, and one sprite texel is 1.25 game pixels.
- The floor and floating platforms are flat painted front skins. Props are lit `Sprite3D`s with smooth (mipmapped) filtering that cast shadows; characters, monsters and pets are lit the same way but cast none.
- A perspective camera tilted 9° down gives real parallax to trees, ridges and clouds placed at different depths.
- `WorldEnvironment` adds glow, SSAO, depth fog and filmic tonemapping; camera attributes add near and far depth of field. `shaders/post.gdshader` adds tilt-shift blur at the screen edges and a vignette.
- Portals, lanterns, Dawnshards, Ember Boar manes and skills carry their own lights and particles.
- Name tags, HP bars and damage numbers are projected to the screen and drawn in 2D so they stay crisp.
- The renderer is Forward+ (Vulkan, or Direct3D 12 on Windows), which the depth of field and SSAO need.

## What's in it

- **Online multiplayer.** Play alone, host a game friends can join, or log in to someone's server. Each server has its own accounts (username and password) and characters, up to 6 per account, picked on character select. Other players walk, climb and fight on the same map, with their names over their heads. A dedicated server can run with no window (see below).
- **A sprawling world**: 44 maps. Dawnrise Isle (Dawnrise Village, the meadow, Ember Hollow and three fields west to the Tidal Flats), Dawnharbor, five job towns, a ring road of twelve fields joining the towns, and four hunting grounds behind each job town that end in a boss. Every map is joined to its neighbours by portals at its edges.
- Platforms, ropes and ladders, and dropping down through platforms.
- **Skills**: Skill Points every level (1 as a Beginner, 3 after), a skill book (K) with a tab per job, and eight quickslots for skills and potions. Beginners have Pebble Toss, Second Wind (HP recovery) and Quick Step (a speed buff); Warriors have Power Strike, Dawn Slash (hits up to 4 monsters twice), Iron Body (a defense buff) and Toughness (Max HP). Archers shoot arrows (Double Shot, Arrow Blow, Focus, Critical Shot), Magicians cast spells from Magic Attack (Energy Bolt, Arcane Claw, Magic Armor, Mana Well), Thieves throw stars (Lucky Seven, Star Scatter, Haste, Nimble Body) and Pirates brawl or shoot (Somersault Kick, Flash Fist, Quick Draw, Bullet Time).
- **Ranged combat**: bows, claws and pistols fire arrows, throwing stars and bullets that fly to their target. Ammo sits in the Use tab, is bought from Mira, and runs out. Running buffs show next to the minimap with their time left.
- **59 monsters** from level 1 to 35, with patrol and chase behavior plus: hoppers (Tide Dewlings, Glowcaps), turrets that never move but shoot anyone who comes close (Acorn Sentries, Coral Turrets), shooters whose shots fly to where you stood so you can dodge them (Star Bats, Fire Imp Archers, Lantern Wisps), and slimes that burst into smaller slimes when defeated (Sporecaps, Prism, Slag and Tide Slimes). Seven bosses: the Flame Boar Chief, Old Clawbeard, the Elder Treant, the Arcane Sentinel, the Molten King, the Lantern Wraith and the Reef Titan.
- **Upgrade scrolls**: double-click a scroll in the Use tab, then click a piece of gear. Each scroll spends one of the gear's upgrade slots and, at its success rate (60% or 10%), adds its stats; upgraded gear shows "+N" after its name. Juno's outfitter in Dawnharbor sells every scroll (1,000 Dawnshards at 60%, 3,000 at 10%). There are scrolls for weapon attack and magic attack, armor defense, helmet HP, top stats, gloves, shoes, capes, earrings and shields.
- **About 240 items**: job gear sets at levels 25, 30 and 35 for every job, gloves, capes, earrings, pendants, rings and shields for anyone, new potions and food, a scroll back to every town, and a monster part from every monster. Every monster drops Dawnshards, its part, potions for its level, gear near its level and, rarely, scrolls.
- **Playing together**: press Enter to chat with everyone on the map (it shows in a bubble over your head), or start the line with /w Name to whisper, /p for your party, /g for your guild or /b for your buddies (/help lists every command). Click another player to whisper, invite them to a party, add them as a buddy, trade, invite them to your guild or give them fame.
- **Parties** of up to six: members on the same map get 40% of each other's kill EXP, and their HP shows under the map name. **Buddies** (up to 20) show who's online and where. **Guilds**: found one with the Guild Clerk in Dawnharbor (15,000 Dawnshards, level 10); its name shows under every member's name. The community window (O) has a tab for each.
- **Trading**: drag items onto your side of the trade window and set your Dawnshards; nothing changes hands until both players press Trade. **Fame**: from level 15, once a day, and the same player once a month, shown on the character window.
- **The Free Market** (through the portal on Dawnharbor's east dock): the Market Clerk helps you set up a shop. Price your goods, name the stall and stand behind it; other players click your sign to buy, and anything unsold comes back when you close.
- **Chairs**: double-click one in the new Setup tab to sit on it; you recover extra HP and MP until you move. Pip in the Free Market sells a stool and a cushion chair, and every boss can drop its own chair (the Ember Throne, the Coral Seat, the Lantern Bench...).
- **Pets**: Puffpaw, Sproutling and Emberkit, from Pip. A pet follows you, picks up anything near you that fits in your bag, and chats now and then. It gets hungry: feed it Pet Snacks (Pip and every general store) or it goes home.
- **The Monster Book** (L): a page for every monster with how many you've beaten. Monsters drop cards; five complete a page and reveal its drops, and every three complete pages raise the book's level, which adds a point to STR, DEX, INT and LUK.
- **Achievements**: 24 milestones (kills, bosses, levels, quests, maps visited, cards, scrolls, fame, guilds, trades, pets and chairs), shown in the collection window (L) and unlocked on Steam.
- **Balance**: monsters from level 10 up have HP that keeps pace with player damage (3 to 5 hits of your main attack at your level), EXP to match, a level curve paced for about 2 hours to Lv 10 and 40 to the Lv 35 cap (a few hundred kills a level from the job on), monsters from Lv 10 that hit harder, job weapons above the starter one that come only from monster drops, and spells that grow as fast as weapons. `tests/balance_report.tscn` prints the whole table.
- NPCs in Dawnrise Village, the start town (no monsters; the hunting starts in the meadow next door). Press Up to talk: a dialogue window shows what they offer.
- **Quests**: six to start, from Elder Rowan and Mira, with kill, collect and visit objectives, a quest item that only drops while you're on its quest, and a repeatable one. A "!" over an NPC means they have a quest for you, "?" means you can hand one in. The quest log (Q) lists what's in progress, available and done, and a tracker under the minimap shows your progress.
- **Jobs**: everyone starts as a Beginner. Each job town's instructor turns a level 10 Beginner into their job once they have the stat the job asks for, and hands over the job's first weapon. A Beginner who spent their Ability Points the wrong way can ask any instructor for one free reset. Beginners hit with whichever of STR, DEX, INT or LUK is highest. Some gear can only be worn by one job line.
- **Field quests**: each job town has a patrol quest, a supplies quest and a boss quest; on Dawnrise Isle, Mira wants the Sporecaps thinned and Elder Rowan wants Old Clawbeard's pearl; the harbormaster sends you round the whole ring road.
- **Hub towns**: Dawnharbor (the port, reached by Captain Marlo's ship from Dawnrise Village) and five job towns: Greenbough Village (Archers), Lumewood Sanctum (Magicians), Emberforge (Warriors), Lanternfall (Thieves) and Driftcove (Pirates). Each is one street of five buildings with open ground between them (towns have no monsters), and you can walk into two of them: the instructor's hall and the general store (in Dawnharbor the store and the Guild Hall; in Dawnrise Village Mira's shop and Elder Rowan's house). Each town also has a job equipment shop, a coach back to Dawnharbor, chairs for sale and Brin's storage (shared across towns, 10 Dawnshards a stack). Rook's coach in Dawnharbor goes to every town. New quests: Choosing a Path, The Grand Tour, and a Proof quest from each instructor.
- **World map** (W, or click the minimap): seven regions with their level ranges, every map placed and joined by its roads, and where you are. Fainting wakes you in the map's town, **Return Scrolls** take you back to town, and **Hobb**'s wagon carries you to Ember Hollow for a fare.
- **Mira's General Store**: buy potions and starter gear, sell anything (1, 10 or 100 at a time, or all your Etc items at once).
- EXP, leveling, HP and MP regen, fainting and respawn.
- **Dawnshards** (currency) dropped by monsters, plus potions, monster parts and gear from per-monster drop tables.
- MapleStory-style stats: STR, DEX, INT and LUK, 5 Ability Points per level, and a damage range worked out from your main stat and weapon.
- An **inventory** with Equip, Use, Etc and Setup tabs, **equipment** in 12 slots that changes your stats, and a **character** window.
- Characters saved by the server, one file per name in `user://characters/`, each owned by one account on that server.
- Keyboard and gamepad controls, fullscreen toggle, title and pause menu.

## Controls

These are the defaults. Every key can be changed under **Settings > Controls** (from the title
screen or the Esc menu), and each action can have two keys.

| Action | Keyboard | Gamepad |
| --- | --- | --- |
| Move / climb | Arrow keys | Left stick or d-pad |
| Jump | Space or Alt | A |
| Drop through a platform | Down + Jump | Down + A |
| Attack | X or Ctrl | X |
| Quickslots (skills, potions) | A, D, F, G, V, B, N, M | Y, RB, LB |
| Pick up items (hold to keep looting) | Z | B |
| Inventory | I | Back |
| Equipment | E | |
| Character info | S | |
| Quest log | Q | |
| Skills | K | |
| World map | W | |
| Community (buddies, party, guild) | O | |
| Monster Book and achievements | L | |
| Chat | Enter | |
| Enter a portal, talk to an NPC | Up | Up |
| Pick a dialogue option | 1 to 9, or click | |
| Close a window, or open the menu | Esc | Start |
| Fullscreen | F11 | |

The Esc menu has **Resume**, **Settings**, **Leave to title** and **Quit to desktop**. Settings
also has volume (master, music, effects, mute) and video (window mode and size, vsync, frame
rate limit, and bloom, ambient occlusion and fog for slower computers). They're saved in
`user://settings.cfg`.

## Running it

1. Install [Godot 4.3](https://godotengine.org/download) (the standard build; C# isn't needed).
2. In the Project Manager, choose **Import** and pick this folder's `project.godot`.
3. Press **F5** to play. On the title screen, pick **Play solo** (just you), **Host** (friends can join you on port 7350), or type a server's address, a username and a password and pick **Log in** (or **Register** the first time on that server). Then pick, make or delete characters on character select.

Run a dedicated server, with no window and no player of its own:

```sh
godot --headless --path . -- --server --port 7350
```

Players register and log in with the server's address. It keeps accounts and characters in its own `user://characters/` folder (accounts in `accounts/`, deleted characters in `deleted/`) and saves every 10 seconds, on every map change and when they leave. Passwords are stored only as salted PBKDF2 hashes, and the connection is encrypted (DTLS) with the key and certificate in `user://characters/tls/`, made the first time the server starts. To let players verify an official server, put its real certificate there and ship it with the game as `certs/<address>.crt`. Hosting over the internet needs UDP port 7350 forwarded to the host.

## Tests

Run every test headless (this is what CI runs on every pull request):

```sh
tests/run_all.sh              # everything, about a minute
tests/run_all.sh inventory    # only tests whose file or name contains "inventory"
```

It fails if any test fails or if Godot prints a script error. There are two kinds of test:

- **The test runner** (`tests/run_tests.tscn`) runs every `*_test.gd` file in four folders, in under half a minute:
  - `tests/unit/`: the game's rules on their own (stats and damage, inventory, gear, scrolls, skills, buffs, EXP, quests, the Monster Book, achievements, saving and loading, combat, drop flight, map layout and balance).
  - `tests/server/`: the server driven directly with pretend players, ticked one step at a time with no window: joining, movement checks, combat, kills, drops, monsters, items, quickslots, shops, storage, travel, job advancement, fainting, quests, chairs, pets, achievements, chat, parties, buddies, trades, guilds, fame and player shops.
  - `tests/content/`: every file in `data/`: ids, names, references between things, numbers in range, maps that join up and items that can be obtained.
  - `tests/ui/`: every window opened with something in every tab, drawn, clicked, dragged and closed, plus every NPC dialogue, shop and tooltip.
- **The smoke test** (`tests/smoke_test.tscn`) plays a scripted single-player session through the real game: walking, talking, shopping, fighting, quests, jobs, skills, travel, the social systems, chairs, pets and achievements. Then it hosts a game and has a second copy of the game (`tests/bot_client.tscn`) join over the network.

To add tests, drop a file ending in `_test.gd` into one of the four folders. It `extends TestCase` (`tests/framework/test_case.gd`), and every method starting with `test_` is a test: check things with `check`, `check_eq` and the other checks there. `UnitHelpers`, `ServerHelpers` (`tests/framework/server_helpers.gd`) and `UiHelpers` set up test content, a server or a running game. Every test starts from the same random seed, so tests must not depend on timing or luck.

The art tools in `tools/art/` have their own tests (`tools/art/tests/`, Python's built-in `unittest`, needing only numpy and Pillow). They draw small sheets in code, so they read no real art and never call Gemini. CI runs them too:

```sh
python3 -m unittest discover -s tools/art/tests -t tools/art/tests
```

Render screenshots of the title, both maps, a Dawn Slash and other players (needs a GPU or software Vulkan, and a display; `xvfb-run` works on a headless Linux box):

```sh
godot --path . --resolution 1600x900 res://tests/screenshot.tscn -- /path/to/output
```

## Project layout

```
scenes/main.tscn   Entry scene (World)
data/              Content: monsters, NPCs, items, skills, effects, maps, biomes, climb styles
scripts/           Code, by layer: autoload, data, components, actors, world, fx, ui
assets/            Cut sprites and animations (generated from art/), fonts
art/source/        Cory's raw sheets; art/sheets/ says how to cut each one
shaders/           Sky and screen post-process
store/             Steam capsules and key art
tests/             Test runner and suites, smoke test, screenshot scene
tools/art/         Sheet slicer, store-art cropper, fx textures, contact-sheet preview
```

[docs/architecture/folders.md](docs/architecture/folders.md) goes through each folder.

## Store art

`python3 tools/art/make_store_art.py` cuts the key art sheet into `store/source/` and writes the Steam capsules into `store/` at Steam's sizes. Before uploading: the capsules still need the Tera's Dawn logo laid over them; `main_capsule`, `vertical_capsule` and `library_capsule` are slightly upscaled from the key art; and `library_hero.png` is 1920x620, half of Steam's 3840x1240, so it needs larger key art.

## Shipping on Steam

1. **Steamworks.** Sign up at partner.steamgames.com, pay the Steam Direct fee for an app, and note the app ID.
2. **GodotSteam.** Install the GodotSteam GDExtension from the Godot Asset Library into `addons/godotsteam`. Then set `APP_ID` in `scripts/autoload/steam_service.gd`. Define the achievements in the Steamworks dashboard with the `steam` ids of the achievements in `data/achievements/` (`REACH_LEVEL_5`, `ACH_FIRST_HUNT`, ...); the game unlocks each one when the server says it was reached.
3. **Export.** In Godot, install the export templates (Editor → Manage Export Templates). Then use **Project → Export**: presets for Windows, Linux and macOS are already in `export_presets.cfg`. macOS builds need signing and notarization with an Apple Developer account.
4. **Upload.** Upload the builds with SteamPipe (`steamcmd` + an app build VDF), set up the store page, and submit for review.

In the windows: double-click gear to wear it or a potion to drink it, drag items to rearrange them or onto the equipment window, and drag an item out of every window to drop it on the ground. Hovering over gear in the inventory shows how it compares with what you're wearing in that slot. The equipment window lists what all your gear adds to each stat; click a worn item to see just its stats.
