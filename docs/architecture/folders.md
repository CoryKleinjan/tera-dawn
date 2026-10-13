# Folders

Part of the [architecture docs](../../ARCHITECTURE.md).

```
data/                 Content, one .tres per thing
  monsters/ npcs/ items/ skills/ effects/ jobs/ looks/   Looked up by id through Content
  achievements/       Milestones, unlocked on Steam too (AchievementDef)
  items/equips/ items/use/ items/etc/ items/setup/   Subfolders are scanned too
  maps/ biomes/ climb_styles/ buildings/    Maps and how they look (maps/rooms/ and
                                            biomes/rooms/: the insides of buildings)
scripts/
  autoload/           Settings (controls, audio, video, saved to settings.cfg), Content (data
                      index), Game (your character copy, name and server address), Net
                      (connections and the protocol), SteamService, Sound (music and effects)
  settings/           SettingsSection and its sections: Keybinds, AudioSettings, VideoSettings
  server/             TDServer, TDLobby, MapInstance, SimPlayer, SimMob, SimDrop, TDSocial
  server/social/      TDSocial's parts: chat, parties, trade, guilds, player shops
  server/services/    TDServer's parts (ServerPart): items, NPC shops, storage, travel, quests, jobs
  net/                SnapshotFlags (the bits both sides read in snapshots), SnapshotCodec (packs them)
  data/               Resource classes for everything in data/
  systems/            Character (and CharacterCodec, its save format; CharacterStore keeps them
                      on this computer) and its parts SkillBook,
                      AbilityPoints and Gear (CharacterPart), Appearance, NewCharacter,
                      Inventory, Equipment,
                      ItemStack, CharacterStats, MonsterBook, Achievements, Counters, Balance
  components/         Health, Hitbox, SpriteRig, HeroBody (a hero's rig and companion), Paperdoll (+ Sprite, View)
  actors/             Player (you), Avatar (other players), Companion (chairs, pets), Mob, Npc, Drop views
  world/              World (what you see), WorldCamera, SnapshotSync (server views), WorldFx (hits, numbers, effects), Stage +
                      Terrain/Backdrop/Scenery builders, MapLayout, Platform, DropFlight, Combat
  fx/                 Flipbook effects and floating text
  ui/                 HUD, title screen, status bar, overlay, quickslots, character
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
  reference/          hero.png, the reference for hero proportions
store/                Steam capsules and key art
tools/art/            Slicer and its helpers (platform_pieces, climb_pieces, clean_sheet, land_pixels),
                      Gemini batch runner (gemini_pass.py + gemini_pass.json), paperdoll layers
                      (paperdoll_layers.py, entry point for the paperdoll/ package), store-art
                      cropper, fx textures, contact-sheet preview
tools/audio/          Lyria music runner (lyria_pass.py + lyria_cues.json), make_music.py (loops, jingles), make_sfx.py
docs/architecture/    One page per system (linked from ARCHITECTURE.md)
tests/                Test runner (unit/, server/, content/, ui/ suites on framework/), smoke test
                      (`smoke_test.gd` runs the checks in `smoke/`, with a second game joining),
                      bot client, screenshot scene, balance report, run_all.sh
```
