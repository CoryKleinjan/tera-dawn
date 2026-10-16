# Folders

Part of the [architecture docs](../../ARCHITECTURE.md).

```
data/                 Content, one .tres per thing
  monsters/ npcs/ items/ skills/ effects/ jobs/   Looked up by id through Content
  monster_moves/      Monster attacks, shared by monster families (MonsterMove)
  achievements/       Milestones, unlocked on Steam too (AchievementDef)
  quests/ shops/ regions/ cutscenes/ projectiles/    Also looked up by id
  items/use/ items/etc/ items/scrolls/ items/setup/ items/equips/  Subfolders are scanned too
  hero/               HeroLookDef (look.tres: his layers and animations); held/ has each held
                      weapon or off-hand's pins per frame (HeldDef), set in the pose editor
  maps/ biomes/ climb_styles/ buildings/    Maps and how they look (maps/rooms/ and
                                            biomes/rooms/: the insides of buildings)
scripts/
  autoload/           Settings (controls, audio, video, saved to settings.cfg), Content (data
                      index), Game (your character copy, name and server address), Net
                      (connections and the protocol), SteamService, Sound (music and effects)
  settings/           SettingsSection and its sections: Keybinds, AudioSettings, VideoSettings,
                      DevSettings
  server/             TDServer, TDLobby, MapInstance, SimPlayer, SimMob (+ MobMoves), SimDrop,
                      ServerMoves (job movement skills), TDSocial
  server/social/      TDSocial's parts: chat, parties, trade, guilds
  server/services/    TDServer's parts (ServerPart): items, NPC shops, storage, travel, quests, jobs,
                      cutscenes
  net/                SnapshotFlags (the bits both sides read in snapshots), SnapshotCodec (packs them)
  data/               Resource classes for everything in data/
  systems/            Character (and CharacterCodec, its save format; CharacterStore keeps them
                      on this computer) and its parts SkillBook,
                      AbilityPoints and Gear (CharacterPart), NewCharacter,
                      Inventory, Equipment,
                      ItemStack, CharacterStats, MonsterBook, Achievements, Counters, Balance
  components/         Health, Hitbox, JumpGrace, SpriteRig, HeroBody (how a hero shows: his painted
                      layers and his companion)
  actors/             Player (you), Avatar (other players), Companion (pets), Mob, Npc, Drop views
  world/              World (what you see), WorldCamera, SnapshotSync (server views), WorldFx (hits, numbers, effects), Stage +
                      Terrain/Backdrop/Scenery builders, MapLayout, Platform, DropFlight, Combat
  fx/                 Flipbook effects and floating text
  ui/                 HUD, title screen, status bar, overlay, quickslots, character
                      creator, game menu, settings screen, modals (TDModal), UiSkin, UiStyle,
                      WorldSkin, UiBuild, Palette
  ui/windows/         Every draggable window (all extend TDWindow), SlotGrid, ScrollList,
                      DragPayload
  ui/widgets/         UI pieces that aren't windows: item tooltip, chat, invites, prompt
  dev/                Tools played in Godot, not part of the game: the hero pose editor
                      (scenes/dev/hero_pose_editor.tscn)
assets/
  sprites/            Cut sprites, one folder per kind (generated, don't hand-edit)
  animations/         SpriteFrames for animated actors (generated)
  audio/music/        Looping tracks and jingles (.ogg, named by id; tools/audio/make_music.py)
  audio/sfx/          Sound effects (.wav, named by id, _1 _2 for variants; tools/audio/make_sfx.py)
art/
  source/             The art sheets (Gemini batch output, painted)
  sheets/             One manifest per sheet: how to cut it
  reference/          hero.png (Cory's original hero: proportions, and the start of his new look)
store/                Steam capsules and key art
tools/art/            Slicer and its helpers (platform_pieces, climb_pieces, clean_sheet, land_pixels),
                      Gemini batch runner (gemini_pass.py + gemini_pass.json), store-art
                      cropper, fx textures, contact-sheet preview;
                      sheet_check.py (checks Gemini results), rekey_sheet.py, strip_template.py,
                      gemini_sheet.py (Gemini API helpers)
tools/audio/          Lyria music runner (lyria_pass.py + lyria_cues.json), make_music.py (loops, jingles), make_sfx.py
docs/architecture/    One page per system (linked from ARCHITECTURE.md)
tests/                Test runner (unit/, server/, content/, ui/ suites on framework/), smoke test
                      (`smoke_test.gd` runs the checks in `smoke/`, with a second game joining),
                      bot client, screenshot scene, balance report, run_all.sh; fixtures/ holds the
                      tests' own wider set of gear (TestGear); the game itself has only starter sets
```
