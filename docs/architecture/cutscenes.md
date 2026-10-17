# Cutscenes

Part of the [architecture docs](../../ARCHITECTURE.md).

A cutscene is a short scene played in the game world: black bars slide in, the camera moves,
people walk, turn and talk, and the screen can fade. It only changes what that one player
sees; everyone else on the map keeps playing.

## How to add a cutscene

Create `data/cutscenes/<id>.tres` as a **CutsceneDef** (the file name is its `id`) with a list
of **CutsceneStep**s that run one after another. Each step has a `kind`:

- **WAIT** `ticks` (60 a second);
- **FADE** to black (`amount` 1) or back (`amount` 0) over `ticks`; **BARS** in (`amount` 1)
  or out (0) the same way. Both wait until done unless `wait` is off;
- **CAMERA** glides to the point `at` (map pixels) over `ticks`; **CAMERA_FOLLOW** keeps
  `who` in view; **CAMERA_BACK** returns to the hero;
- **SAY**: `speaker` (an NPC id, `hero`, or empty for a narrator) says `text`, shown in a
  speech box with their portrait until the player presses on (Jump, Up, Enter or a click).
  `speaker_name` overrides the name shown, e.g. "Girl on the Beach";
- **MOVE** walks `who` (an NPC on the map, or `hero`) to `x`, an NPC at `speed` pixels a tick
  and the hero at their own walking pace;
- **FACE** turns `who` left (-1) or right (1); **SHOW** hides or shows `who` (`shown`);
- **MUSIC** changes the track to `sound`; **SOUND** plays a sound effect;
- **POSE** holds `who` in the animation `pose` until another POSE for them or the end (the
  hero's `faint` lies them on the sand); an empty `pose` frees them;
- **PLACE** puts the NPCs where the player's quests now have them (see quest-chain NPCs in
  [NPCs and quests](npcs-quests-shops.md)), so someone a quest just moved shows up at their
  new spot mid-scene. Otherwise that happens when the cutscene ends.

Then hook it up: a map's `intro_scene` plays the first time a character arrives there, and a
quest's `start_scene` / `finish_scene` play when it's taken and handed in, and a map's scene
spot (`MapDef.scene_spots`, see [Maps](maps.md)) plays its `scene` for a player standing on
it. Each plays once per character. `tests/content/content_cutscenes_test.gd` checks every cutscene, and that a map's
intro only uses NPCs who stand on that map.

Anything in the main story (Tera, the Dawn curse, the tears, the other dawns, what Dawnshards
are) needs Cory's OK before it goes in, and nothing outside story cutscenes may mention them
(the same test checks every NPC, quest and item text).

## How it works

- The server decides when a cutscene plays (`ServerScenes`, `scripts/server/services/scenes.gd`)
  and sends `ev_scene`. While it plays, monsters don't touch the player (`SimPlayer.in_scene()`);
  attacking, changing maps or five minutes passing ends that.
- The client plays it (`TDCutscenePlayer`, `scripts/world/cutscene_player.gd`) once per physics
  tick: the camera through `WorldCamera.scene_center`, the hero through `TDPlayer.auto_walk`,
  NPC views directly. `TDCutsceneOverlay` draws the bars, fade, speech box (the dialogue
  window's frame) and the skip hint. The HUD hides and the player's keys are blocked.
- Holding the menu key skips it (unless `skippable` is off). At the end, or when skipped,
  every NPC it moved goes back to where they stood (the hero stays where they walked) and the
  client sends `req_scene_done`. Opening a cutscene closes the dialogue window, and its end
  shows and hides NPCs and locked portals for the player's quests (`TDWorld.show_for_me`); the server adds the id to `Character.scenes_seen`, which
  the save keeps. A cutscene that didn't end (the player left the map or the game) plays
  again next time.
