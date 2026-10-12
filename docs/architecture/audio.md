# Music and sound

Part of the [architecture docs](../../ARCHITECTURE.md).

The **Sound** autoload (`scripts/autoload/sound.gd`) plays all music and sound effects. Sounds
are files named by id, and data names the ids, so adding a sound means adding a file and,
at most, setting a field. An id with no file plays nothing, so a sound can be wired up before
it exists; `tests/content/content_audio_test.gd` fails until every id has its file.

| Kind | File | Played by |
|---|---|---|
| Track (loops) | `assets/audio/music/<id>.ogg` | `Sound.music(id)`: crossfades from the last track; the same id again keeps playing |
| Jingle (once) | `assets/audio/music/<id>.ogg` | `Sound.jingle(id)`: over the music, which dips while it plays |
| Sound effect | `assets/audio/sfx/<id>.ogg`, or `<id>_1.ogg`, `<id>_2.ogg` ... for variants | `Sound.play(id)`, or `TDWorld.sound_at(id, pos)` for a sound in the world (quieter with distance) |

Music plays on the **Music** bus and effects on the **Effects** bus, so the settings sliders
(AudioSettings) reach them. Effects play a little higher or lower each time.

Music volume is one fade level per player plus a jingle dip, both moved each frame by
`Sound.advance` (not tweens), so a track change during a fade or a jingle retargets the fade
instead of racing it. Tests drive `Sound.advance` by hand (`tests/unit/sound_music_test.gd`).

## Where sounds come from

- **Map music**: `MapDef.music_id()`. A map's own `music` (boss lairs: `boss`; dark caves and
  woods: `dungeon`), else its region's `town_music` (towns, markets and rooms) or
  `field_music` (everywhere else; `RegionDef`). The title screen and character select play
  `TDWorld.TITLE_MUSIC`.
- **Effects**: `EffectDef.sound` plays wherever the effect appears (hits, crits, heals, buffs,
  pickups, portals, a monster's death, the level-up sparkle).
- **Skills**: `SkillDef.cast_sound()`: the skill's own `sound`, else its projectile's
  (`ProjectileDef.sound`: bow, throw, gun, cast; monsters' shots `mob_shot`), else a swing for
  an attack or a cast for magic. Buffs sound through their effect.
- **Jingles**: level up (`TDWorldFx.LEVEL_UP_JINGLE`), fainting (`TDPlayer.FAINT_JINGLE`), and
  the server's `ev_jingle` for a quest done or a job advance (`ServerQuests.QUEST_JINGLE`,
  `ServerJobs.ADVANCE_JINGLE`).
- **Your hero**: getting hurt, entering a portal (`TDPlayer.*_SOUND`).
- **UI**: every `BaseButton` clicks by itself (`Sound.CLICK`, connected as buttons are added
  to the tree); `TDWindow` buttons click, and windows play `open` and `close`.

## How to add music

1. Make it: add the cue to `tools/audio/lyria_cues.json` (a zone's track follows its mood and
   instruments in [zone vibes](../zone-vibes.md)) and run
   `python3 tools/audio/lyria_pass.py OUT_DIR --only <cue>` (paid, Lyria has no batch mode:
   ask Cory first; `--dry-run` shows the cost). Each cue gets several takes.
2. Put the chosen take in: `python3 tools/audio/make_music.py OUT_DIR/<cue>_a.mp3 <id>`
   (cuts the fade-out and crossfades the end into the start so it loops), or `--jingle` for
   a one-shot (cut where it first falls silent).
3. Point data at it: a region's `town_music`/`field_music`, or a map's `music`.

## How to add a sound effect

1. `python3 tools/audio/make_sfx.py <id> SOURCE [SOURCE ...]` writes
   `assets/audio/sfx/<id>.ogg` (or variants), trimmed, mono and at one loudness
   (`--gain` to nudge it).
2. Name it from data (`EffectDef.sound`, `SkillDef.sound`, `ProjectileDef.sound`) or, for
   something only code knows about, a constant next to the code that plays it, added to
   `content_audio_test.gd`'s list.

## Where the sounds came from

- Music: Google Lyria (Gemini API, `lyria-3.5` tracks, `lyria-3-clip-preview` jingles), from
  the prompts in `tools/audio/lyria_cues.json`. Every Lyria file carries Google's inaudible
  SynthID watermark; the Steam page must declare AI-generated content.
- Sound effects: see `assets/audio/sfx/CREDITS.md`.
