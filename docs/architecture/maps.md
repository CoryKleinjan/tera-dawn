# Maps, buildings and towns

Part of the [architecture docs](../../ARCHITECTURE.md).

## How to add a map

1. Create `data/maps/<id>.tres` as a **MapDef**. Give it an `id`, a display name, a size and
   a `biome` (`data/biomes/meadow.tres` or `harbor.tres`, or a new BiomeDef).
2. Lay it out: `platforms` (one-way, numbered from 1; the floor is 0) and `portals`. There
   are no ropes or ladders: every place is reached by jumping.
3. Fill it: `spawns`, `npcs` (an **NpcPlacement** with an NpcDef and an x) and hand-placed
   `props` on top of the biome's random decoration. Anything that looks like ground (a
   tall ledge) is a platform with that picture as its `look`, never a prop, so everything
   that looks walkable is. A deck or ledge already painted into a building or a
   `look` (a treehouse deck, a crow's nest, a terrace's railed wing) gets a platform with
   `in_scenery` set, which draws nothing, so it can be stood on; a painted ladder gets narrow
   `in_scenery` steps up its rungs. Land art stands on the floor: no floating rock islands or
   arches; a floating platform uses the biome's plain platform front. Every platform,
   portal, NPC and spawn must be reachable with the hero's own jump from where players arrive
   (secret ledges aside, below), and no two portals on a map may lead to the same map
   (`tests/content/content_reach_test.gd`). A plain jump rises about 90 px, so a platform
   higher than that above the one below needs steps up to it (keep each rise about 70). A map can be taller than 700 (more floors, more exits); keep
   `ground_y` 80 above `height`. On a tall map the backdrop strips sit lower
   (`BackdropBuilder.strip_center`), so climbing up shows more sky.
4. Connect it: add a **PortalDef** on an existing map whose `target_map` is the new id, and a
   portal back. A portal lands players on the floor, or on the platform its `target_platform`
   names (its `target_x` on that platform). Players arriving (a portal's or travel route's `target_x`) and NPCs stay at
   least the quickslot panel's width plus a hero from the map's right edge, so the panel never
   covers them (`tests/content/content_world_test.gd`). The map's name shows only at the top
   of the screen (`display_name`); nothing labels a map out in the world.
5. Place it in the world: its `region` (a **RegionDef** in `data/regions/`), `world_pos` on
   the world map (pixels of the painting, `TDWorldMapWindow.WORLD`, inside its region's
   `zone_rect`), and either `town = true` or the `return_map` where fainting and Return Scrolls
   send you. In a region drawn to shape (`RegionDef.shaped_zone`) also give it a `zone_pos`:
   where its top-left corner sits on the zone map, in game pixels, touching each map its
   portals lead to (below).
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

### Secrets and shortcuts

A **secret ledge** (`PlatformDef.secret`) is reached only with a move from a boss relic
(Dash, Double Jump, Surge; see `RelicDef`), never a plain jump or a fall, and the minimap
leaves it out. Nothing a player needs stands on one (a chest may); `content_reach_test` checks
both ways with `map_reach.gd`'s relic moves. A field has two: a high one about 130 px over the
ledge you jump from, with nothing over it (Double Jump), and a far one about 220 px out from a
ledge's end and 50 px lower, at least 100 px over anything below and too far out to drift onto
in a fall from anything above (Dash or Surge). A Dash goes 180 px (`TDPlayer.DASH_SPEED` x
`DASH_TICKS`), farther sideways than a Double Jump (about 137 px), so a far ledge across a wide
gap can need a Dash alone.

A **shortcut** is a pair of portals: its far end (`PortalDef.shortcut`, an id) is hidden and shut
until the character has found it; its near end (`opens_shortcut`, the same id) is always open
and going through finds it. Found ids live in `Character.secrets`. `WorldRoutes` leaves
shortcuts off the world map.

A **breakable** (`MapDef.breakables`, a **BreakableDef**) is a chest or wall that breaks open
after `hits` blows. Each character breaks their own, once for good (`Character.secrets`); only
they see it shake and break (`ev_struck`). A chest's `loot` and Monster Book `card` spill for
whoever broke it. A wall's id is the shortcut it opens: both its ends are `shortcut` portals,
so breaking it opens the way on both maps. With no `broken` picture it is gone once broken.
A **fake wall** (`walk_through`) takes no blows: it fades the first time a player steps into it
(`MapInstance.check_secrets` after each move report) and opens the `shortcut` portal behind it
the same way, so put it where the main way never crosses, at the end of a side ledge or a nook,
looking like the room's wall. A **cracked floor** (`slam_only`) is a wall lying on a platform:
blows only shake it, and a Slam landing on it (`MapInstance.slam`) breaks it and opens its
`shortcut` portal, a way down. Standing on a secret ledge finds it too (`MapDef.ledge_secret`),
so the zone map can show it.

A **gated door** (`PortalDef.gate`, an id) shows from the start behind its shut gate
(`gate_picture`, drawn just in front of the portal at `TDStage.Z_GATE`) and takes nobody
through until the character has opened that gate, once for good (`Character.secrets`). A
**lever** is a breakable whose id is the gate's (one blow; `whole` is the lever up, `broken`
swung over): hitting it opens every door with that `gate`, so both ends of a gated way share
the id. A door with a `key` (an Etc item that is a `quest_item`, so it can't be sold or
dropped) is a lock instead: Up at it uses the key up and opens it (`ServerTravel._shut_gate`);
keys come from chests. A gated door counts as a shortcut (`is_shortcut`): it brings no map
nearer a town and the zone map draws it once it's open. `content_world_test` checks every gate
has a lever or a key that can be found. Gates guard side rooms and shortcuts, never the main
way.

A `solo` map gives each player a copy of their own, started fresh every time they come in
(`TDServer.map_instance` keys it by peer; `_off_map` drops it). It isn't on the world map: you
show in its `return_map` town (`MapDef.outside`). With `tear_platform` set, its tear stays
hidden until a player first stands on that platform (`MapInstance.check_tear`, `ev_tear`): then
it shows, closer and bigger, `tear_scene` plays, and the spawns marked `from_tear` (asleep until
then) step out of the first tear when the scene ends (`wake_tear`) and stay down once beaten.

`scene_spots` (SceneSpot) are spots that do something for the player standing on them
(`MapInstance.check_spots`): play a cutscene once, then optionally send them to `then_map`
with a `then_scene` there (a spot that sends you on keeps doing so after its scene is seen).
`while_on` opens a spot only during those quests (`until_ready`: until they're ready to hand
in), and `glow` draws a tear there for whoever it's open to (`TDStage.show_spot_glows`). The
home-world tear uses them: the light over Starfall Ridge pulls the hero into the `silent`,
solo `home_world` during "A Closer Look", thoughts play along it, and its far end leads back.

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

A region with `shaped_zone` (Greenbough first, then Dawnharbor Coast, Lumewood, Emberreach and Lanternfall) is drawn the Hollow Knight way instead: every map
is a room of its own width and height placed at its `zone_pos` (game pixels on one zone map), so
the canopy sits above the town and the roots below. Rooms never overlap; two rooms a portal joins
touch, and the portal stands by the edge they share: within 300 px of a side edge, or along a top
or bottom edge over the stretch they share (`content_routes_test`). The zone map draws each as a
gap in the shared edge.

In those zones a field's portals are **ways** out of the room, Hollow Knight style
(`RoomExits`, worked out once per map in `MapLayout.ways`): no data marks them. A portal
leads through the side its two rooms touch along (a town's, or a path into the next zone's, by
the side edge it stands within `SIDE_REACH` of). Through a side way you walk or jump off the
edge, within `OPENING` above the portal's platform, and come out `ARRIVE_IN` in from the facing
edge of the next room on its way back's platform, walking in (`TDPlayer.arrive`); no pillar
stands there. A bottom way is a spot where Down + Jump drops you through the ground (or ledge)
into the room below, dropping in over its top way; at a top way you jump up from its ledge and
hop up out of the room above's bottom way. The client says when (`TDPlayer._ways`, `req_way`)
and the server checks where they stand (`MapLayout.way_at`, `ServerTravel.on_way`). Building
doors, docks, `opens_after`/`while_on` portals and a boss arena's way home stay portals you press
Up at. Every way needs a way back through the facing side, a side way's platform runs to the
room's edge, and its two ends stand at the same height on the zone map (`content_ways_test`). A boss arena's way home
isn't a door. `TDWorldMapWindow` shows rooms once visited, secret ledges and the doors behind
shortcuts and fake or breakable walls once found, and the player where they stand.

An NpcDef with `storage = true` keeps the player's storage (`Character.storage`, an
Inventory saved with the character; `ServerStorage.on_store` / `on_retrieve`, `TDStorageWindow`).
The same NpcDef can stand in several maps.

Travel NPCs (ships, wagons) list **TravelRoute**s in `NpcDef.travel` (destination, arrival x,
fare, "Ship"/"Wagon"); their dialogue offers "Travel" and `ServerTravel.on_travel` moves the
player, charging `TravelRoute.price` (everyone pays the same fare). Each trip's label shows the
destination and fare ("Coach to Lumewood (400 Dawnshards)", `TDDialogueWindow.travel_label`). A **UseDef** with `teleport` set to a map id, or to `town`, is a return scroll.

The content tests (`tests/content/`) check that every portal points at a real map and every
spawn at a real platform, so a typo fails a test instead of the game.

A **BiomeDef** is the look shared by many maps: sky and light colours, ground and platform
textures, parallax backdrop layers (`BackdropLayerDef`: a tiled strip, scattered pieces, or one
painted `PICTURE` stretched just wide enough to cover the view from either end of the map (on a
tall map, raised and stretched so it covers the view from top to bottom too) and left out of
the fog, all at a depth nearer than `TDStage.FAR`), random decoration (`DecorDef`), lantern and portal art, and
optional leaves hanging into the screen's top corners (`frame_left` / `frame_right`, drawn by `CornerFrame` over the
world and under the HUD, like Hollow Knight's foreground plants; `frame_scale` sets their share of the screen's
height and `frame_fade` fades their bottom out at draw time, for a frame painted down to its bottom edge). A new region of the
world is usually a new biome plus a few maps that use it.

Each region has **one** biome (its style); its fields differ within it. A field keeps its region's `biome` and sets a **BiomeVariantDef** as `MapDef.variant`: only
what this sub zone changes (sky, light, fog colour and haze, colour grade, hidden backdrop
layers, extra backdrop layers, hidden or extra ground scenery, no edge tufts or platform plants for land painted with its
own grass, its own land pieces and corner leaves). `MapDef.look()` is the biome with the variant applied; the
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
   its door is, so NPCs and doors line up with the doorway; `platform`, `flip` and `scale` place it;
   every building is its own picture. It stands at `depth` -2 (behind the
   lanterns and the people) and is sized to keep its `height` there.
3. **Making it enterable**: create the room, a **MapDef** in `data/maps/rooms/<id>.tres` with
   `interior = true`, `return_map` set to the town (so return scrolls and the world map treat
   it as the town), its town's `region`, no `world_pos`, a biome from
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
ledge; you still walk in front of it along the street below. Steps join the
levels (more than about 90 px needs them). Buildings, NPCs and portals stand on a level by
their `platform`; each level is its own row for the spacing checks, and nothing should
stand on the floor straight behind a terrace's wall (lanterns, scattered decor and
background houses keep clear of it by themselves). Lanterns stand only on open street by themselves; a level gets its own with `MapDef.level_lanterns` (x and platform), drawn in front of the land so the wall of the level above doesn't hide them; ivy and flower boxes hung on a level's wall are props with `on_wall` set. Doors stay on the floor for now (a portal's
`target_platform` could land players on a level). In a town the backdrop is laid out for the camera on the
street (`TDStage.backdrop_center`), so climbing up just shows more sky. Dawnharbor is the
example: a quay street, a terrace 150 px up and a cliff top 320 px up.

The biome's `town_decor` (its signature prop far behind the street) doesn't scatter randomly in a
town with buildings: `SceneryBuilder.back_house_slots` stands them in one row,
`BACK_HOUSE_GAP` apart and never straight behind a building. The rest of a town's scattered
scenery (`DecorPlacement`) comes at half a field's density (`TOWN_DENSITY`) and, trees and
far props included, keeps clear of exits, props, townsfolk and every other scattered piece.
Houses stand only as placed buildings at full size, and only in towns: scattered scenery
never uses a building picture (far back at a random size it looks like a tiny house), and a
map that isn't a town has no buildings unless it sets `houses_allowed` (a quest needs the
house, or Cory asked for one). `tests/content/content_houses_test.gd` checks this.
`tests/content/content_town_test.gd` checks all of this (every level of a town) against the real picture sizes, so
when new building art comes in wider or narrower, the test names the buildings that now sit
too close and you nudge their `x` (and the doors, NPCs and the portals that lead in).
