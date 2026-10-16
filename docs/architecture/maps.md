# Maps, buildings and towns

Part of the [architecture docs](../../ARCHITECTURE.md).

## How to add a map

1. Create `data/maps/<id>.tres` as a **MapDef**. Give it an `id`, a display name, a size and
   a `biome` (`data/biomes/meadow.tres` or `harbor.tres`, or a new BiomeDef).
2. Lay it out: `platforms` (one-way, numbered from 1; the floor is 0), `climbables` (x, top,
   bottom and a climb style: rope, vine, ladder or rope ladder) and `portals`.
3. Fill it: `spawns`, `npcs` (an **NpcPlacement** with an NpcDef and an x) and hand-placed
   `props` on top of the biome's random decoration. Anything that looks like ground (a
   tall ledge) is a platform with that picture as its `look`, never a prop, so everything
   that looks walkable is. Land art stands on the floor: no floating rock islands or
   arches; a floating platform uses the biome's plain platform front. Every platform, rope,
   portal, NPC and spawn must be reachable with the hero's own jump from where players arrive, and no
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
   `zone_rect`), `level_text` (a hidden tuning tier, never shown), and either `town = true` or the
   `return_map` where fainting and Return Scrolls send you.
6. Optionally give it an `intro_scene`, a cutscene played the first time a character arrives
   (see [cutscenes](cutscenes.md)).

A portal with `opens_after` set to a quest is hidden, and goes nowhere, until the player has
handed that quest in, one with `while_on` only while that quest is under way, and one with
`after_boss` once the player has beaten that boss (`PortalDef.open_to`; `TDStage.locked_portals`;
everyone on the map when a boss falls gets the kill); `one_way` means no portal
leads back (the content tests let it). A boss stands alone in a small arena map (about 1.3
screens wide, a floor and three low ledges, no lanterns) past the zone's top map, with a portal
back and a `one_way`, `after_boss` portal home to the zone's town. `tears` hangs faint white glows out over the water,
drawn in code (`TDStage._build_tears`); nothing in the game mentions them.

A `solo` map gives each player a copy of their own, started fresh every time they come in
(`TDServer.map_instance` keys it by peer; `_off_map` drops it). It isn't on the world map: you
show in its `return_map` town (`MapDef.outside`). With `tear_platform` set, its tear stays
hidden until a player first stands on that platform (`MapInstance.check_tear`, `ev_tear`): then
it shows, closer and bigger, `tear_scene` plays, and the spawns marked `from_tear` (asleep until
then) step out of the first tear when the scene ends (`wake_tear`) and stay down once beaten.

The job tests use both: each job town's hall has a trial gate (`while_on` its Job Test) to its
`trial_<town>` Trial Ground, a short course with the tutor at the start and an arena at the far
end where the tear boss steps out.

New characters start on `Character.NEW_MAP`, the tutorial beach Daybreak Shore. It's off the
world map (`world_pos` zero), wakes you on the beach if you faint there, and its one-way
portal to Dawnrise Village (`Character.START_MAP`, the first town) opens when the girl's last
quest is handed in. Characters made before it never see it.

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
Inventory saved with the character; `ServerStorage.on_store` / `on_retrieve`, `TDStorageWindow`).
The same NpcDef can stand in several maps (Brin is in every town).

Travel NPCs (ships, wagons) list **TravelRoute**s in `NpcDef.travel` (destination, arrival x,
fare, "Ship"/"Wagon"); their dialogue offers "Travel" and `ServerTravel.on_travel` moves the
player, charging `TravelRoute.price` (everyone pays the same fare). Each trip's label shows the
destination and fare ("Wagon to Fern Hollow (150 Dawnshards)", `TDDialogueWindow.travel_label`). A **UseDef** with `teleport` set to a map id, or to `town`, is a return scroll.

The content tests (`tests/content/`) check that every portal points at a real map and every
spawn at a real platform, so a typo fails a test instead of the game.

A **BiomeDef** is the look shared by many maps: sky and light colours, ground and platform
textures, parallax backdrop layers (`BackdropLayerDef`: a tiled strip, scattered pieces, or one
painted `PICTURE` stretched just wide enough to cover the view from either end of the map and
left out of the fog, all at a depth nearer than `TDStage.FAR`), random decoration (`DecorDef`), lantern and portal art. A new region of the
world is usually a new biome plus a few maps that use it.

Each region has **one** biome (its style); its fields differ within it. A field keeps its region's `biome` and sets a **BiomeVariantDef** as `MapDef.variant`: only
what this sub zone changes (sky, light, fog colour and haze, colour grade, hidden backdrop
layers, extra backdrop layers, hidden or extra ground scenery). `MapDef.look()` is the biome with the variant applied; the
world builders read `look()`, never `biome`. Towns usually use the plain biome; Dawnharbor's
variant swaps the harbour strips for one painted picture (the clouds stay). `tests/screenshot.gd`
with `subzones` renders every field for a side-by-side look.

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
   A door draws the biome's portal (the blue-white light pillar) standing in the doorway, so
   players can see the building can be entered, with a warm light behind it (in a room, the
   biome's `door` picture stands on the back wall). NPCs keep a portal's width clear of doors. The overlay says "↑ Enter …" or
   "↑ Out to …", and the minimap shows a little lit doorway.

A room's biome (`data/biomes/rooms/<town>_room.tres`) has a `wall` strip as its only backdrop
layer, a plank floor, warm low light and a `door`. Its painted pieces are cut from the
`room_<town>` sheets and the shared `room_props` sheet (crate, plant and soil), at the shared
pixel size. `tests/content/content_world_test.gd` checks every door is
in a building and every room has one door back to the town that leads into it.

### Town layout

A town is one street on the floor, laid out left to right: the west exit and the
taxi, then the buildings with about 160 px of open ground between them (an NPC can stand in
a gap, an exit gets a wider gap of its own), then the east exit. The map is only as wide as
that row needs. Towns have **no monsters**: hunting happens in the fields next door (the
start town, Dawnrise Village, leads east into Dawnrise Meadow).

A bigger town can have **levels**, like a classic MapleStory city: raised stone terraces
and a cliff top above the street, each a platform with `solid = true`. A solid platform's
front runs all the way down to the land it stands on (`MapDef.land_under`: the highest
platform under its middle, or the floor), so it reads as raised ground rather than a thin
ledge; you still walk in front of it along the street below. Ladders and ropes join the
levels (more than about 90 px needs one). Buildings, NPCs and portals stand on a level by
their `platform`; each level is its own row for the spacing checks, and nothing should
stand on the floor straight behind a terrace's wall (lanterns, scattered decor and
background houses keep clear of it by themselves). Lanterns stand only on open street by themselves; a level gets its own with `MapDef.level_lanterns` (x and platform), drawn in front of the land so the wall of the level above doesn't hide them; ivy and flower boxes hung on a level's wall are props with `on_wall` set. Doors stay on the floor for now, since
players arrive on a map's floor. In a town the backdrop is laid out for the camera on the
street (`TDStage.backdrop_center`), so climbing up just shows more sky. Dawnharbor is the
example: a quay street, a terrace 150 px up and a cliff top 320 px up.

The biome's `town_decor` (its signature prop far behind the street) doesn't scatter randomly in a
town with buildings: `SceneryBuilder.back_house_slots` stands them in one row,
`BACK_HOUSE_GAP` apart and never straight behind a building.
Houses stand only as placed buildings at full size, and only in towns: scattered scenery
never uses a building picture (far back at a random size it looks like a tiny house), and a
map that isn't a town has no buildings unless it sets `houses_allowed` (a quest needs the
house, or Cory asked for one). `tests/content/content_houses_test.gd` checks this.
`tests/content/content_town_test.gd` checks all of this (every level of a town) against the real picture sizes, so
when new building art comes in wider or narrower, the test names the buildings that now sit
too close and you nudge their `x` (and the doors, NPCs and the portals that lead in).
