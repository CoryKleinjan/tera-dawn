# Draw order and the HD-2D stage

Part of the [architecture docs](../../ARCHITECTURE.md).

## Draw order

The world is a 3D diorama, so what covers what depends on depth (3D z, bigger is nearer the
camera). The layers are constants at the top of `scripts/world/stage.gd`, back to front:

| Layer | Depth | What |
| --- | --- | --- |
| Backdrop | far behind | Sky, mountains, distant trees (`BackdropLayerDef.depth`) |
| Land | `-SCENERY_LAYER` to `LAND_FRONT` | The floor and platforms (flat painted front skins), and just behind them buildings, decoration, props, lanterns, signs |
| `Z_PORTAL` | 0.17 | Portals, in front of all the land and scenery (NPCs are never placed over one) |
| `Z_CLIMBABLE` | 0.2 | Ropes, vines and ladders |
| `Z_NPC` | 0.3 | NPCs |
| `Z_MONSTER` | 0.38 to 0.52 | Monsters, each at a slightly different depth so overlapping ones don't flicker |
| `Z_DROP` | 0.56 | Dawnshards and other drops |
| `Z_OTHER_PLAYER` | 0.6 | Other players |
| `Z_PLAYER` | 0.64 | Your hero |
| `Z_EFFECT` | 0.8 | Skill and hit effects |

Skill, hit and projectile effects are soft glowing sprites, but `TDStage.effect_sprite` makes their
solid parts record depth like the characters do. Without that, the depth of field would take the
depth of whatever is behind an effect and blur it into the scenery, so it read as behind things.
Use `effect_sprite` for anything that plays on the characters' plane, and keep `glow_sprite`
for glows that belong to the scenery (lanterns, drops).

Everything you can touch stands in front of all the land, so a platform, bush or prop never
hides a character, NPC, rope or ladder. Decoration and prop depths in data (0 down to
`-SCENERY_DEEP`) go through `TDStage.land_depth()`, which squeezes them into the thin
`SCENERY_LAYER` behind the land's front in the same order, so a `DecorDef` or `PropPlacement`
can't be set in front of the actors by mistake. Something new that the player interacts with should use one of the `Z_`
layers (or add one here) rather than a raw number.

Land is flat, like a 2D game: no ground runs back into the scene. Each floating platform is
just its painted front skin at `LAND_FRONT`, and the floor is the same kind of picture: the
biome's platform middles repeated along its walking line (`TerrainBuilder.floor_edge`), with
its rock and soil textures filling below. Things standing on land go through
`TDStage.stand_on_land()`: at their `land_depth`, scaled to show as big as at their data depth,
and sunk (`land_sink`) so their base tucks behind the grass edge at any camera height. The skin is one picture per platform width
(`PlatformSkin`): the biome's left cap, middles and right cap, overlapped and joined where they
match best, so a long platform never reads as small ones pasted together.

All environment art (tiles, platform pieces, ground textures, buildings, ropes and ladders,
lanterns, portals, backdrop layers and room interiors) is cut at two texels per art pixel and drawn at
`TDStage.TEXEL` game pixels per art pixel (`TDStage.art_density`, `art_size`), so the whole
screen shows one pixel size. Backdrop layers are cut to the size they show at, so depth
doesn't change it; a building's art is cut to its `height`. Data sizes it only within a narrow band (a
manifest's `grow`, a decor or prop `scale`); `tools/art/land_pixels.py --check` and the tests
keep it there. Edge grass on the floor and platforms stands just behind the skin and peeks
over its top edge.

Text that belongs to a spot in the world (name tags, hints, damage numbers)
is never put in the 3D stage: `TDOverlay` projects the spot to the screen and draws it there,
so depth of field never blurs it and nothing in the world covers it.
