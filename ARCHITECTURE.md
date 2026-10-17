# Tera's Dawn architecture

Tera's Dawn is meant to grow into a much larger game, so content lives in data files and the
code is split into small pieces that each do one job. Adding a monster, a map or a skill
should never mean editing game code.

Each system has its own page in `docs/architecture/`; add new systems as new pages and link them here.

## The big picture

```
data/*.tres  ──►  Content (autoload)  ──►  World loads a MapDef  ──►  Stage builds it in 3D
 (what exists)     (finds it by id)          (spawns actors)            (terrain, backdrop, scenery)
```

- **Data** (`scripts/data/`, saved as `.tres` in `data/`) says *what* things are: a monster's
  stats and sprite, a map's platforms and spawns, a skill's reach and damage. Every class is a
  Godot `Resource`, so it can be edited in the Godot inspector.
- **Systems** (`scripts/systems/`) are the character's rules that aren't tied to the world:
  `Character` (level, EXP, Dawn Essence, stats, bag, HP, MP) with its parts `SkillBook` (`c.skills`:
  skills bought, buffs) and `Gear` (`c.gear`: wearing gear), `Inventory`, `Equipment`, `ItemStack`
  (one slot's worth of an item, with its own rolled stats for gear) and `CharacterStats` (the
  MapleStory formulas). The server owns each player's `Character`; `Game.me` is your copy.
- **Components** (`scripts/components/`) are small reusable parts any actor can use: `Health`,
  `Hitbox`, `SpriteRig` (sprite, animation, light and aura) and `HeroBody` (how every hero shows: his
  painted layers and pet; see [characters](docs/architecture/characters.md)).
- **Server** (`scripts/server/`) runs the game for everyone (see [multiplayer](docs/architecture/multiplayer.md)).
- **Actors** (`scripts/actors/`) are what you see in the world: your hero, other players,
  monsters, NPCs and drops.
- **World** (`scripts/world/`) shows the map you're on: `world.gd` builds it and shows the
  server's events (camera in `WorldCamera`, snapshots through `SnapshotSync`), `stage.gd` and its builders turn a map into the lit diorama.
- **UI** (`scripts/ui/`) draws the HUD (`TDHud`) and the title screen (`TDTitleScreen`,
  solo, host or join) from the sliced UI sheets through `UiSkin` (art), `UiStyle` (styled controls) and
  `WorldSkin` (bars, tags and bubbles over the world).
- **Art** is painted sheets in `art/source/`, cut by `tools/art/slice_sheets.py`
  (see [art](docs/architecture/art.md) and `art/sheets/README.md`).

Game logic is 2D: positions are game pixels with y pointing down, and physics ticks 60 times a
second. Only the stage turns that into 3D (32 game pixels per 3D unit).

## Pages

- [Game rules](docs/game-rules.md): how the game should look and play; read it before any change.
- [Multiplayer and players together](docs/architecture/multiplayer.md): the server, client, snapshots, co-op and characters saved on each computer, parties and trades.
- [Characters: creation, extras, balance and player actions](docs/architecture/characters.md): character creation, how heroes show, sitting, pets, Monster Book, achievements, balance, how to add a player action.
- [Folders](docs/architecture/folders.md): what lives in each folder.
- [Draw order and the stage](docs/architecture/rendering.md): the 3D layers, depths and pixel size of the diorama, world-anchored text.
- [Monsters](docs/architecture/monsters.md): how to add a monster.
- [Maps, buildings and towns](docs/architecture/maps.md): how to add a map or a building, town layout, rooms.
- [Skills](docs/architecture/skills.md): how to add a skill.
- [Items, gear and weapons](docs/architecture/items.md): stats, equipment, how to add an item or a weapon.
- [Jobs](docs/architecture/jobs.md): how to add a job.
- [Windows and settings](docs/architecture/ui.md): how to add a window, the HUD and the title
  screen, the settings menu.
- [NPCs, quests and shops](docs/architecture/npcs-quests-shops.md): how to add an NPC, a quest or a shop.
- [Cutscenes](docs/architecture/cutscenes.md): how to add a cutscene and play it on a map or quest.
- [Tears](docs/architecture/tears.md): hidden tear zones and how a finished one turns its zone; how to add a tear.
- [Art](docs/architecture/art.md): how to add art, the slicer, Gemini batch generation.
- [Zone vibes](docs/zone-vibes.md): each zone's style and music guide, and how its town and sub-zones vary it.
- [Music and sound](docs/architecture/audio.md): how to add music or a sound effect, where they play, making music with Lyria.

## Conventions

- Ids are `StringName`s in snake_case and match the file name (`data/monsters/ember_boar.tres`
  has `id = &"ember_boar"`).
- Data classes end in `Def`; placements on a map (`SpawnDef`, `NpcPlacement`, `PropPlacement`)
  point at a Def.
- Code never names a specific monster, map or item; it reads what it needs from the Def.
- Class names: nodes and the server's top-level objects use the `TD` prefix (`TDWorld`,
  `TDServer`, `TDSocial`, `TDWindow`); data classes, systems and helpers don't (`MonsterDef`,
  `Character`, `SimMob`, `Palette`).
- Numbers that tune how something plays (speeds, timers, ranges) are named constants at the
  top of their file. A value both server and client need lives in one place (`SimPlayer`,
  `SimMob` or `SnapshotFlags`) and the other side reads it from there.
- Generated files (`assets/sprites/`, `assets/animations/`) are rebuilt by the tools, so fix
  art in the sheet or manifest rather than in the output.
