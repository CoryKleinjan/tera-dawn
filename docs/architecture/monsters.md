# Monsters

Part of the [architecture docs](../../ARCHITECTURE.md).

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
   glowing monsters, a `tint` (one sprite can stand in for several monsters), and
   `respawn_ticks`.
5. Give it one or two `moves` (three, all different, for a boss) from `data/monster_moves/`
   (see below), and a `sight` (how far away it notices players; starters 120, shooters 340,
   bosses 700).
6. Optional behavior (`SimMob` runs it): `jumps` hops now and then; `stationary` never walks
   (it can only shoot or slam); `keep_distance` backs away from a player crowding it when no
   close move is ready; `splits_into` with `split_count` bursts into smaller monsters when
   defeated.
7. Put it on a map: add a **SpawnDef** to the map's `spawns` with the monster, a platform index
   and a count.

`Content` finds every `.tres` in `data/monsters/` on its own; there's no list to update.

## Aggro and moves

The server runs monsters (`SimMob`), so co-op players all see the same fight.

- **Targeting.** A monster notices the nearest player within its `sight` (and level with it),
  or anyone who hits it, and gives up `SimMob.SIGHT_TICKS` after losing sight (longer after a
  hit). It keeps after its target while it can see them; whoever else hit it meanwhile is next.
  Bosses go for whoever has done the most damage lately (`threat`, fading over time).
- **Moves** are `MonsterMove` presets in `data/monster_moves/` (`lunge`, `charge`, `pounce`,
  `slam`, `swoop`, `shot_*`, and `boss_*` versions with longer reach). `MobMoves` picks a ready
  move whose reach fits, winds up (`MOB_WINDUP`: clients glow and lean back), plays it out
  (`MOB_CASTING`: the attack pose) hurting each player once for `power` x attack, then rests.
  A hit doesn't knock a monster out of a move. Shots fly to the aimed spot (`ev_mob_shot`) and
  only hurt if the player is still there; slams miss players in the air. Slams, landings,
  blinks and a boss's second wind send `ev_mob_move` for dust, light and screen shake.
- **Bosses** go through their `moves` in order (the first ready one that fits after the last,
  a pattern players can learn), aim ahead of a moving player, chain a charge
  or pounce into a slam, leap to the player's platform after a moment unable to reach them,
  and at half HP get a second wind (`MOB_ENRAGED`): faster moves and walking, and each move
  followed at once by the next in the pattern. Order a boss's `moves` the way it should fight.
- To tune a family, change its preset; to give one monster a different move, make a new
  preset file.

