# Folders

Part of the [architecture docs](../../ARCHITECTURE.md).

## Folders

```
data/                 Content, one .tres per thing
  monsters/ npcs/ items/ skills/ effects/ jobs/ looks/   Looked up by id through Content
  items/equips/ items/use/ items/etc/ items/setup/   Subfolders are scanned too
  maps/ biomes/ climb_styles/ buildings/    Maps and how they look (maps/rooms/ and
                                            biomes/rooms/: the insides of buildings)
scripts/
  autoload/           Settings (controls, audio, video, saved to settings.cfg), Content (data
                      index), Game (your character copy, name and server address), Net
                      (connections and the protocol), SteamService, Sound (music and effects)
  settings/           SettingsSection and its sections: Keybinds, AudioSettings, VideoSettings
  server/             TDServer, MapInstance, SimPlayer, SimMob, SimDrop, CharacterStore, TDSocial
  server/social/      TDSocial's parts: chat, parties, trade, guilds, player shops
  server/services/    TDServer's parts (ServerPart): items, NPC shops, storage, travel, quests, jobs
  net/                SnapshotFlags (the bits both sides read in snapshots), SnapshotCodec (packs them)
  data/               Resource classes for everything in data/
  systems/            Character (and CharacterCodec, its save format) and its parts SkillBook,
                      AbilityPoints and Gear (CharacterPart), Appearance, NewCharacter,
                      Inventory, Equipment,
                      ItemStack, CharacterStats, MonsterBook, Achievements, Balance
  components/         Health, Hitbox, SpriteRig, HeroBody (a hero's rig and companion), Paperdoll (+ Sprite, View)
  actors/             Player (you), Avatar (other players), Companion (chairs, pets), Mob, Npc, Drop views
  world/              World (what you see), WorldCamera, SnapshotSync (server views), WorldFx (hits, numbers, effects), Stage +
                      Terrain/Backdrop/Scenery builders, MapLayout, Platform, DropFlight, Combat
  fx/                 Flipbook effects and floating text
  ui/                 HUD, title screen (login), status bar, overlay, quickslots, character
                      creator, game menu, settings screen, modals (TDModal), UiSkin, UiStyle,
                      WorldSkin, UiBuild, Palette
  ui/windows/         Every draggable window (all extend TDWindow), SlotGrid, ScrollList,
                      DragPayload
  ui/widgets/         UI pieces that aren't windows: item tooltip, chat, invites, prompt
assets/
  sprites/            Cut sprites, one folder per kind (generated, don't hand-edit)
  animations/         SpriteFrames for animated actors (generated)
  audio/music/        Looping tracks and jingles (.ogg, named by id; tools/audio/make_music.py)
  audio/sfx/          Sound effects (.ogg, named by id, _1 _2 for variants; tools/audio/make_sfx.py)
art/
  source/             The art sheets (Gemini batch output, painted)
  sheets/             One manifest per sheet: how to cut it
  reference/          Style reference (the hero)
store/                Steam capsules and key art
tools/art/            Slicer, store-art cropper, fx texture and item placeholder generators, contact-sheet preview, Gemini batch runner (gemini_pass.py + gemini_pass.json), paperdoll layers
tools/audio/          Lyria music runner (lyria_pass.py + lyria_cues.json), make_music.py (loops, jingles), make_sfx.py
docs/architecture/    One page per system (linked from ARCHITECTURE.md)
tests/                Test runner (unit/, server/, content/, ui/ suites on framework/), smoke test
                      (with a second game joining), bot client, screenshot scene, run_all.sh
```
