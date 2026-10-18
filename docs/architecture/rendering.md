# Draw order and the stage

Part of the [architecture docs](../../ARCHITECTURE.md).

## Draw order

The world is a 3D diorama, so what covers what depends on depth (3D z, bigger is nearer the
camera). The layers are constants at the top of `scripts/world/stage.gd`, back to front:

| Layer | Depth | What |
| --- | --- | --- |
| Backdrop | far behind | Sky, mountains, distant trees (`BackdropLayerDef.depth`) |
| Land | `-SCENERY_LAYER` to `LAND_FRONT` | The floor and platforms (flat painted front skins), and just behind them buildings, decoration, props, lanterns, signs |
| `Z_PORTAL` | 0.17 | Portals, in front of all the land and scenery (NPCs are never placed over one) |
| `Z_GATE` | 0.2 | A locked door's shut gate, just in front of its portal |
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
hides a character or NPC. Decoration and prop depths in data (0 down to
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

All art in the world (land, buildings, lanterns, portals, backdrop layers,
room interiors, NPCs, monsters, pets, drops, effects and projectiles)
is cut at two texels per art pixel with its smooth painted edge and drawn at `TDStage.TEXEL` game
pixels per art pixel (`TDStage.art_density`, `art_size`; `TDStage.ART_DENSITY` lists the
folders), so the whole screen shows one pixel size and outlines stay clean.
`TDStage.style_sprite` blends that soft edge in (`ALPHA_CUT_OPAQUE_PREPASS`) rather than cutting
it at half alpha, which would step it. Backdrop layers are cut to the size they show at, so depth
doesn't change it; a building's art is cut to its `height`. Data sizes it only within a narrow band (a
manifest's `grow`, a decor or prop `scale`); `tools/art/land_pixels.py --check` and the tests
keep it there. Edge grass on the floor and platforms stands just behind the skin and peeks
over its top edge.

The backdrop haze (`BiomeDef.fog_begin`, `fog_end`, `fog_density`) starts behind the play line,
so it never fades the play area: bright maps use more of it to push the backdrop back so the
hero and monsters stand out, and a gloomier sub-zone dims a borrowed backdrop with a dark
`fog_color`, never a tint. Ambient occlusion keeps a small radius, so it shades creases in the
land and never draws a halo round a character standing in front of it.

The costly effects are video settings (`VideoSettings`, applied by `TDStage.apply_video` and
`VideoSettings.apply`): bloom, ambient occlusion, fog, depth of field, sun shadows, a render
scale (the 3D scene drawn at 85% or 70% and sharpened back up with FSR; the HUD stays sharp)
and MSAA. MSAA stays at 4x by default because it gives the land's edges their soft line
(alpha to coverage in `TerrainBuilder._strip`). A Steam Deck starts at 85% scale, 2x MSAA, no
ambient occlusion or depth of field. The game is made for Vulkan (Forward+); a computer
without it falls back to the compatibility renderer, which has no ambient occlusion or depth
of field, and the video page says so. Store pages should list Vulkan as recommended.

Text that belongs to a spot in the world (name tags, hints, "Miss")
is never put in the 3D stage: `TDOverlay` projects the spot to the screen and draws it there,
so depth of field never blurs it and nothing in the world covers it.
