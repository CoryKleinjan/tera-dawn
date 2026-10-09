# Tera Dawn

A 2D side-scrolling action RPG in the spirit of MapleStory, built with **Godot 4.3** for desktop release on Steam (Windows, macOS, Linux and Steam Deck).

This is the first playable build. It uses an **HD-2D** look in the style of Octopath Traveler: pixel-art sprites standing in a lit 3D diorama, with depth of field, tilt-shift blur, bloom, dynamic lights, real-time shadows and drifting particles. Gameplay is still a flat 2D side-scroller.

All the art comes from Cory's sheets in `art/source/`. `python3 tools/art/slice_sheets.py` cuts them into the sprites in `assets/sprites/` and the animations in `assets/animations/`, following one manifest per sheet in `art/sheets/` (see `art/sheets/README.md`). A new sheet needs a PNG and a manifest, no code.

The game is built to grow: monsters, NPCs, items, skills, effects, maps and biomes are all data files in `data/`. [ARCHITECTURE.md](ARCHITECTURE.md) explains how the code is laid out and how to add a monster, a map or a skill.

## How the HD-2D view works

- Game logic runs in 2D pixel coordinates exactly as before. `scripts/world/stage.gd` turns the map into 3D: one 3D unit is 32 game pixels, and one sprite texel is 1.25 game pixels.
- Platforms are textured 3D blocks with depth. Characters, monsters and props are lit `Sprite3D`s with nearest-neighbour filtering that cast shadows.
- A perspective camera tilted 9° down gives real parallax to trees, ridges and clouds placed at different depths.
- `WorldEnvironment` adds glow, SSAO, depth fog and filmic tonemapping; camera attributes add near and far depth of field. `shaders/post.gdshader` adds tilt-shift blur at the screen edges and a vignette.
- Portals, lanterns, Dawnshards, Ember Boar manes and skills carry their own lights and particles.
- Name tags, HP bars and damage numbers are projected to the screen and drawn in 2D so they stay crisp.
- The renderer is Forward+ (Vulkan, or Direct3D 12 on Windows), which the depth of field and SSAO need.

## What's in it

- **Online multiplayer.** Play alone, host a game friends can join, or join someone's server. Other players walk, climb and fight on the same map, with their names over their heads. A dedicated server can run with no window (see below).
- **A sprawling world**: 43 maps. Dawnrise Isle (the meadow, Ember Hollow and three fields west to the Tidal Flats), Dawnharbor, five job towns, a ring road of twelve fields joining the towns, and four hunting grounds behind each job town that end in a boss. Every map is joined to its neighbours by portals at its edges.
- Platforms, ropes and ladders, and dropping down through platforms.
- **Skills**: Skill Points every level (1 as a Beginner, 3 after), a skill book (K) with a tab per job, and eight quickslots for skills and potions. Beginners have Pebble Toss, Second Wind (HP recovery) and Quick Step (a speed buff); Warriors have Power Strike, Dawn Slash (hits up to 4 monsters twice), Iron Body (a defense buff) and Toughness (Max HP). Archers shoot arrows (Double Shot, Arrow Blow, Focus, Critical Shot), Magicians cast spells from Magic Attack (Energy Bolt, Arcane Claw, Magic Armor, Mana Well), Thieves throw stars (Lucky Seven, Star Scatter, Haste, Nimble Body) and Pirates brawl or shoot (Somersault Kick, Flash Fist, Quick Draw, Bullet Time).
- **Ranged combat**: bows, claws and pistols fire arrows, throwing stars and bullets that fly to their target. Ammo sits in the Use tab, is bought from Mira, and runs out. Running buffs show next to the minimap with their time left.
- **59 monsters** from level 1 to 35, with patrol and chase behavior plus: hoppers (Tide Dewlings, Glowcaps), turrets that never move but shoot anyone who comes close (Acorn Sentries, Coral Turrets), shooters whose shots fly to where you stood so you can dodge them (Star Bats, Fire Imp Archers, Lantern Wisps), and slimes that burst into smaller slimes when defeated (Sporecaps, Prism, Slag and Tide Slimes). Seven bosses: the Flame Boar Chief, Old Clawbeard, the Elder Treant, the Arcane Sentinel, the Molten King, the Lantern Wraith and the Reef Titan.
- **Upgrade scrolls**: double-click a scroll in the Use tab, then click a piece of gear. Each scroll spends one of the gear's upgrade slots and, at its success rate (60% or 10%), adds its stats; upgraded gear shows "+N" after its name. There are scrolls for weapon attack and magic attack, armor defense, helmet HP, top stats, gloves, shoes, capes, earrings and shields.
- **About 240 items**: job gear sets at levels 25, 30 and 35 for every job, gloves, capes, earrings, pendants, rings and shields for anyone, new potions and food, a scroll back to every town, and a monster part from every monster. Every monster drops Dawnshards, its part, potions for its level, gear near its level and, rarely, scrolls.
- Two NPCs in the meadow village. Press Up to talk: a dialogue window shows what they offer.
- **Quests**: six to start, from Elder Rowan and Mira, with kill, collect and visit objectives, a quest item that only drops while you're on its quest, and a repeatable one. A "!" over an NPC means they have a quest for you, "?" means you can hand one in. The quest log (Q) lists what's in progress, available and done, and a tracker under the minimap shows your progress.
- **Jobs**: everyone starts as a Beginner. Each job town's instructor turns a level 10 Beginner into their job (a Magician from level 8) once they have the stat the job asks for, and hands over the job's first weapon. Some gear can only be worn by one job line.
- **Field quests**: each job town has a patrol quest, a supplies quest and a boss quest; on Dawnrise Isle, Mira wants the Sporecaps thinned and Elder Rowan wants Old Clawbeard's pearl; the harbormaster sends you round the whole ring road.
- **Hub towns**: Dawnharbor (the port, reached by Captain Marlo's ship from the meadow) and five job towns: Greenbough Village (Archers), Lumewood Sanctum (Magicians), Emberforge (Warriors), Lanternfall (Thieves) and Driftcove (Pirates). Each has its instructor, a job equipment shop, a general store, a coach back to Dawnharbor and Brin's storage (shared across towns, 10 Dawnshards a stack). Rook's coach in Dawnharbor goes to every town. New quests: Choosing a Path, The Grand Tour, and a Proof quest from each instructor.
- **World map** (W, or click the minimap): seven regions with their level ranges, every map placed and joined by its roads, and where you are. Fainting wakes you in the map's town, **Return Scrolls** take you back to town, and **Hobb**'s wagon carries you to Ember Hollow for a fare.
- **Mira's General Store**: buy potions and starter gear, sell anything (1, 10 or 100 at a time, or all your Etc items at once).
- EXP, leveling, HP and MP regen, fainting and respawn.
- **Dawnshards** (currency) dropped by monsters, plus potions, monster parts and gear from per-monster drop tables.
- MapleStory-style stats: STR, DEX, INT and LUK, 5 Ability Points per level, and a damage range worked out from your main stat and weapon.
- An **inventory** with Equip, Use and Etc tabs, **equipment** in 12 slots that changes your stats, and a **character** window.
- Characters saved by the server, one file per name in `user://characters/` (a single-player save from before multiplayer is brought in the first time you play).
- Keyboard and gamepad controls, fullscreen toggle, title and pause menu.

## Controls

| Action | Keyboard | Gamepad |
| --- | --- | --- |
| Move / climb | Arrow keys | Left stick or d-pad |
| Jump | Space, C or Alt | A |
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
| Enter a portal, talk to an NPC | Up | Up |
| Pick a dialogue option | 1 to 9, or click | |
| Close a window, or the menu | Esc | Start |
| Fullscreen | F11 | |

## Running it

1. Install [Godot 4.3](https://godotengine.org/download) (the standard build; C# isn't needed).
2. In the Project Manager, choose **Import** and pick this folder's `project.godot`.
3. Press **F5** to play. On the title screen, type a name and pick **Play** (just you), **Host** (friends can join you on port 7350) or **Join** (type the host's address).

Run a dedicated server, with no window and no player of its own:

```sh
godot --headless --path . -- --server --port 7350
```

Players join it with **Join** and the server's address. It keeps their characters in its own `user://characters/` folder and saves every 10 seconds, on every map change and when they leave. Hosting over the internet needs UDP port 7350 forwarded to the host.

Run the gameplay smoke test headless:

```sh
godot --headless --path . res://tests/smoke_test.tscn
```

It checks that all content loads and references real maps, monsters and items, then plays a short scripted single-player session (inventory stacking, equipping and stat changes, Ability Points, saving and loading, then walk, jump, talk to an NPC, kill a monster, loot with the loot key, drink a potion, change gear, open the windows, use Dawn Slash, climb, take a portal, faint and wake in town). Then it hosts a game and starts a second copy (`tests/bot_client.tscn`) that joins over the network: each must see the other, and the second player's attacks must defeat a monster on the server. It exits non-zero on failure.

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
shaders/           Sky, portal, sword trail, level-up beam and screen post-process
store/             Steam capsules and key art
tests/             Headless smoke test and screenshot scene
tools/art/         Sheet slicer, store-art cropper, fx textures, contact-sheet preview
```

[ARCHITECTURE.md](ARCHITECTURE.md) goes through each folder.

## Store art

`python3 tools/art/make_store_art.py` cuts the key art sheet into `store/source/` and writes the Steam capsules into `store/` at Steam's sizes. Before uploading: the capsules still need the Tera Dawn logo laid over them; `main_capsule`, `vertical_capsule` and `library_capsule` are slightly upscaled from the key art; and `library_hero.png` is 1920x620, half of Steam's 3840x1240, so it needs larger key art.

## Shipping on Steam

1. **Steamworks.** Sign up at partner.steamgames.com, pay the Steam Direct fee for an app, and note the app ID.
2. **GodotSteam.** Install the GodotSteam GDExtension from the Godot Asset Library into `addons/godotsteam`. Then set `APP_ID` in `scripts/autoload/steam_service.gd`. Achievements (for example `REACH_LEVEL_5`, which the game already unlocks) are defined in the Steamworks dashboard.
3. **Export.** In Godot, install the export templates (Editor → Manage Export Templates). Then use **Project → Export**: presets for Windows, Linux and macOS are already in `export_presets.cfg`. macOS builds need signing and notarization with an Apple Developer account.
4. **Upload.** Upload the builds with SteamPipe (`steamcmd` + an app build VDF), set up the store page, and submit for review.

In the windows: double-click gear to wear it or a potion to drink it, drag items to rearrange them or onto the equipment window, and drag an item out of every window to drop it on the ground. Hovering over gear in the inventory shows how it compares with what you're wearing in that slot. The equipment window lists what all your gear adds to each stat; click a worn item to see just its stats.
