# Maps, buildings and towns

Part of the [architecture docs](../../ARCHITECTURE.md).

## How to add a map

1. Create `data/maps/<id>.tres` as a **MapDef**. Give it an `id`, a display name, a size and
   a `biome` (`data/biomes/meadow.tres` or `ember.tres`, or a new BiomeDef).
2. Lay it out: `platforms` (one-way, numbered from 1; the floor is 0), `climbables` (x, top,
   bottom and a climb style: rope, vine, ladder or rope ladder) and `portals`.
3. Fill it: `spawns`, `npcs` (an **NpcPlacement** with an NpcDef and an x) and hand-placed
   `props` on top of the biome's random decoration. Anything that looks like ground (a
   tall ledge) is a platform with that picture as its `look`, never a prop, so everything
   that looks walkable is. Land art stands on the floor: no floating rock islands or
   arches (Cory removed them); a floating platform uses the biome's plain platform front. Every platform, rope, portal, NPC
   and spawn must be reachable with the hero's own jump from where players arrive, and no
   two portals on a map may lead to the same map (`tests/content/content_reach_test.gd`).
   A platform more than about 90 px above the one below needs a rope or ladder. A map can
   be taller than 700 (more floors, more exits); keep `ground_y` 80 above `height`.
4. Connect it: add a **PortalDef** on an existing map whose `target_map` is the new id, and a
   portal back. Players arriving (a portal's or travel route's `target_x`) and NPCs stay at
   least the quickslot panel's width plus a hero from the map's right edge, so the panel never
   covers them (`tests/content/content_world_test.gd`). The map's name shows only at the top
   of the screen (`display_name`); nothing labels a map out in the world.
5. Place it in the world: its `region` (a **RegionDef** in `data/regions/`), `world_pos` on
   the world map (pixels of the painting, `TDWorldMapWindow.WORLD`, inside its region's
   `zone_rect`), `level_text`, and either `town = true` or the
   `return_map` where fainting and Return Scrolls send you.

## The shape of the world

Each **region** is a major zone with one main city (`RegionDef.capital`) in the middle: a
border field on each side leads to a neighbouring region, and a training branch goes deeper in.
Two neighbouring regions share exactly **one** crossing on foot; a region you can't walk to
(the start island) is reached by ship. `WorldRoutes` works the routes out from the portals and
travel NPCs (coaches between walkable regions are shortcuts, not routes), and
`tests/content/content_routes_test.gd` keeps the shape: every map can be walked to from its
city inside its region. The world map (W) draws the major routes city to city; clicking a
region opens its zone view (its `zone_rect` of the painting, zoomed in) with every map and path,
and where each exit leads. A new region needs a `capital`, `label_pos` and `zone_rect`.

An NpcDef with `storage = true` keeps the player's storage (`Character.storage`, an
Inventory saved with the character; `TDServer.on_store` / `on_retrieve`, `TDStorageWindow`).
The same NpcDef can stand in several maps (Brin is in every town).

Travel NPCs (ships, wagons) list **TravelRoute**s in `NpcDef.travel` (destination, arrival x,
fare, "Ship"/"Wagon"); their dialogue offers "Travel" and `TDServer.on_travel` moves the
player. A route with `free_for_beginners` costs nothing for a Beginner who has reached
the first job level (`JobDef.first_advance_level`); Rook's coaches from Dawnharbor to the
job towns are free this way. `TravelRoute.fare_for(character)` is the one place that
decides the fare, for the server and for the dialogue. Each trip's label also shows the
destination's `MapDef.level_text` unless it's a town ("Wagon to Ember Hollow (Lv. 6-12,
150 Dawnshards)", `TDDialogueWindow.travel_label`). A **UseDef** with `teleport` set to a map id, or to `town`, is a return scroll.

The smoke test checks that every portal points at a real map and every spawn at a real
platform, so a typo fails the test instead of the game.

A **BiomeDef** is the look shared by many maps: sky and light colours, ground and platform
textures, parallax backdrop layers (`BackdropLayerDef`: a tiled strip or scattered pieces at a
depth), random decoration (`DecorDef`), lantern and portal art. A new region of the
world is usually a new biome plus a few maps that use it.

## How to add a building

Towns are a street of buildings in the MapleStory way: each stands at full size right behind
the walking line (a house about 2.5 heroes tall, a shop or hall 3 to 3.5), and some have a
door you walk through by pressing Up, into a small room that is its own map.

1. **The picture**: a **BuildingDef** in `data/buildings/<id>.tres`: its `texture` (cut from a
   building sheet into `assets/sprites/buildings/<town>/`), the `height` it stands on screen,
   `door_x` (the middle of its doorway, 0 at the picture's left edge to 1 at its right) and
   an optional `chimney` that smokes when the biome has `chimney_smoke`.
2. **On the street**: add a **BuildingPlacement** to the town's `buildings`. Its `x` is where
   its door is, so NPCs and doors line up with the doorway; `platform`, `flip`, `scale` and a
   `tint` let one picture stand in for several houses. It stands at `depth` -2 (behind the
   lanterns and the people) and is sized to keep its `height` there.
3. **Making it enterable**: create the room, a **MapDef** in `data/maps/rooms/<id>.tres` with
   `interior = true`, `return_map` set to the town (so return scrolls and the world map treat
   it as the town), its town's `region`, no `world_pos` or `level_text`, a biome from
   `data/biomes/rooms/`, NPCs and furniture `props`, and one **PortalDef** with `door = true`
   leading back out beside the building. Then add a door portal (`door = true`) to the town
   at the building's `x` and platform, leading into the room.
   Doors draw no swirl: the building's picture is the door and a warm light stands in it (in a
   room, the biome's `door` picture on the back wall). The overlay says "↑ Enter …" or
   "↑ Out to …", and the minimap shows a little lit doorway.

A room's biome (`data/biomes/rooms/<town>_room.tres`) has a `wall` strip as its only backdrop
layer, a plank floor, warm low light and a `door`. Its painted pieces are cut from the
`room_<town>` sheets over stand-in art from `tools/art/make_room_placeholders.py`, on the same
file names, at the shared pixel size. `tests/content/content_world_test.gd` checks every door is
in a building and every room has one door back to the town that leads into it.

### Town layout

A town is one street on the floor, laid out left to right: the west exit and the
taxi, then the buildings with about 160 px of open ground between them (an NPC can stand in
a gap, an exit gets a wider gap of its own), then the east exit. The map is only as wide as
that row needs. Towns have **no monsters**: hunting happens in the fields next door (the
start town, Dawnrise Village, leads east into Dawnrise Meadow).

The biome's `town_decor` (small houses far behind the street) don't scatter randomly in a
town with buildings: `SceneryBuilder.back_house_slots` stands them in one row,
`BACK_HOUSE_GAP` apart and never straight behind a building.
`tests/content/content_town_test.gd` checks all of this against the real picture sizes, so
when new building art comes in wider or narrower, the test names the buildings that now sit
too close and you nudge their `x` (and the doors, NPCs and the portals that lead in).
