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
5. Optional behavior (`SimMob` runs it): `jumps` hops now and then; `stationary` never walks;
   `shot` (a ProjectileDef) with `shot_range` and `shot_cooldown` shoots whoever hit it, or
   anyone in range when `aggressive`. A shot flies to where the player stood (`ev_mob_shot`)
   and only hurts them if they're still there when it lands. `splits_into` with `split_count`
   bursts into smaller monsters when defeated.
6. Put it on a map: add a **SpawnDef** to the map's `spawns` with the monster, a platform index
   and a count.

`Content` finds every `.tres` in `data/monsters/` on its own; there's no list to update.
