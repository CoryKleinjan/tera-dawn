# Tera Dawn architecture

Tera Dawn is meant to grow into a much larger game, so content lives in data files and the
code is split into small pieces that each do one job. Adding a monster, a map or a skill
should never mean editing game code.

## The big picture

```
data/*.tres  ──►  Content (autoload)  ──►  World loads a MapDef  ──►  Stage builds it in 3D
 (what exists)     (finds it by id)          (spawns actors)            (terrain, backdrop, scenery)
```

- **Data** (`scripts/data/`, saved as `.tres` in `data/`) says *what* things are: a monster's
  stats and sprite, a map's platforms and spawns, a skill's reach and damage. Every class is a
  Godot `Resource`, so it can be edited in the Godot inspector.
- **Components** (`scripts/components/`) are small reusable parts any actor can use: `Health`,
  `Hitbox` and `SpriteRig` (sprite, animation, shadow, light and aura).
- **Actors** (`scripts/actors/`) run things in the world: the player, monsters, NPCs and drops.
- **World** (`scripts/world/`) holds the rules and the map: `world.gd` loads maps and runs
  combat, `stage.gd` and its builders turn a map into the HD-2D diorama.
- **UI** (`scripts/ui/`) draws the HUD from the sliced UI sheet through `UiSkin`.
- **Art** comes from Cory's sheets in `art/source/`, cut by `tools/art/slice_sheets.py`
  (see `art/sheets/README.md`).

Game logic is 2D: positions are game pixels with y pointing down, and physics ticks 60 times a
second. Only the stage turns that into 3D (32 game pixels per 3D unit).

## Folders

```
data/                 Content, one .tres per thing
  monsters/ npcs/ items/ skills/ effects/   Looked up by id through Content
  maps/ biomes/ climb_styles/               Maps and how they look
scripts/
  autoload/           Content (data index), Game (player stats, save, input), SteamService
  data/               Resource classes for everything in data/
  components/         Health, Hitbox, SpriteRig
  actors/             Player, Mob, Npc, Drop
  world/              World (rules), Stage + Terrain/Backdrop/Scenery builders, Platform, Combat
  fx/                 Flipbook effects and floating text
  ui/                 HUD, status bar, overlay, UiSkin, Palette
assets/
  sprites/            Cut sprites, one folder per kind (generated, don't hand-edit)
  animations/         SpriteFrames for animated actors (generated)
art/
  source/             Cory's raw sheets
  sheets/             One manifest per sheet: how to cut it
  reference/          Style reference (the hero)
store/                Steam capsules and key art
tools/art/            Slicer, store-art cropper, fx texture generator, contact-sheet preview
tests/                Headless smoke test and screenshot scene
```

## How to add a monster

1. Get its sprite. A single image goes in `assets/sprites/monsters/<id>.png`; an animated
   one comes from a sheet with a `sets` block that writes `assets/animations/<id>.tres` with
   the animations `idle`, `move`, `attack`, `hurt` and `die` (any missing one falls back to
   `idle`; single images get a little procedural bob and squash instead).
2. Create `data/monsters/<id>.tres` as a **MonsterDef** (in the editor: right-click
   `data/monsters/` → New Resource → MonsterDef). Fill in `id`, name, level, HP, attack, EXP,
   speed, hitbox `size`, and either `texture` or `sprite_frames`. Use `sprite_scale` if the art
   is too big or small next to the hero.
3. Add drops: each `DropEntry` is an item, a chance and an amount range.
4. Optional: `flying` with `hover_height`, `boss`, a `light_color` or `aura_color` for
   glowing monsters, and `respawn_ticks`.
5. Put it on a map: add a **SpawnDef** to the map's `spawns` with the monster, a platform index
   and a count.

`Content` finds every `.tres` in `data/monsters/` on its own; there's no list to update.

## How to add a map

1. Create `data/maps/<id>.tres` as a **MapDef**. Give it an `id`, a display name, a size and
   a `biome` (`data/biomes/meadow.tres` or `ember.tres`, or a new BiomeDef).
2. Lay it out: `platforms` (one-way, numbered from 1; the floor is 0), `climbables` (x, top,
   bottom and a climb style: rope, vine, ladder or rope ladder) and `portals`.
3. Fill it: `spawns`, `npcs` (an **NpcPlacement** with an NpcDef and an x) and hand-placed
   `props` on top of the biome's random decoration.
4. Connect it: add a **PortalDef** on an existing map whose `target_map` is the new id, and a
   portal back.

The smoke test checks that every portal points at a real map and every spawn at a real
platform, so a typo fails the test instead of the game.

A **BiomeDef** is the look shared by many maps: sky and light colours, ground and platform
textures, parallax backdrop layers (`BackdropLayerDef`: a tiled strip or scattered pieces at a
depth), random decoration (`DecorDef`), lantern, signpost and portal art. A new region of the
world is usually a new biome plus a few maps that use it.

## How to add a skill

1. Create `data/skills/<id>.tres` as a **SkillDef**: MP cost, cooldown, how long the player is
   busy (`action_ticks`), the hit area (`reach`, `height`), `max_targets`, `hits`, the damage
   multiplier, the hero animation to play, and the effects to show (`effect` on the player,
   `hit_effect` on each target).
2. Effects are **EffectDef**s in `data/effects/`: a flipbook of frames from
   `assets/sprites/effects/`, its speed and size, an optional light and particle burst.
3. Bind it to a button in `Game.SKILL_BINDINGS` (`scripts/autoload/game_state.gd`). A new
   button also needs an input action in `Game`'s input bindings.

Damage is worked out in `scripts/world/combat.gd`, so balance changes stay in one place.

## How to add an NPC

Create `data/npcs/<id>.tres` as an **NpcDef** (name, title, sprite, and the `lines` they say,
one per press of Up), then place it on a map with an **NpcPlacement**.

## How to add art

Drop the sheet in `art/source/`, write a manifest in `art/sheets/`, and run
`python3 tools/art/slice_sheets.py <name>`. `art/sheets/README.md` explains the manifest. The
cut sprites land in `assets/sprites/`, ready to be referenced from data.

## Conventions

- Ids are `StringName`s in snake_case and match the file name (`data/monsters/ember_boar.tres`
  has `id = &"ember_boar"`).
- Data classes end in `Def`; placements on a map (`SpawnDef`, `NpcPlacement`, `PropPlacement`)
  point at a Def.
- Code never names a specific monster, map or item; it reads what it needs from the Def.
- Generated files (`assets/sprites/`, `assets/animations/`) are rebuilt by the tools, so fix
  art in the sheet or manifest rather than in the output.
