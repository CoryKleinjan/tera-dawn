# Zone vibes

The style and music guide for every major zone, its town(s) and its sub-zones. Read the zone's
entry before making art (`tools/art/gemini_pass.json`), music (`tools/audio/lyria_cues.json`) or
a map look (`MapDef.variant`) for it, and update the entry when the zone changes.

## How a zone stays consistent

- **One zone, one style.** Everything in a major zone (town, fields, boss map, backdrops,
  buildings, props, monsters, music) shares the zone's palette, light, materials and
  instruments listed under "Keep".
- **Sub-zones vary, they don't break.** A sub-zone changes only what its row says (time of day,
  light, fog, colour grade, setting). It keeps the zone's palette family, brushwork and materials.
- **Music**: each zone has one town track and one field track in the town's tone; the field
  track plays in every field of the zone, dark caves and woods included. Each zone's boss map
  has its own `boss_<zone>` track: the town's tone, but more upbeat and dangerous. Bosses that
  live in a training map (Dawnrise) play the field track.
- **Cities**: Dawnharbor is the gold standard. Every other city matches its attention to detail
  and polish in its own zone's tone, never copying Dawnharbor's look. Change Dawnharbor only with
  great care.
- **New content**: a new sub-zone, building or track starts from its zone's "Keep" lines plus its
  own row. A new zone gets an entry here before any art or music is made for it.
- **Town cards**: each town's own materials (its signature) are in `tools/art/towns/<town>.json`;
  no other town uses them. A new town's card is filled from its zone's entry here (see
  `docs/game-rules.md`, "Making a town").
- Text marked *(inferred)* is not settled yet; confirm it with Cory before building on it.

## World-wide (every zone)

- **Art**: painted NPC style only (`/mnt/project-files/art-sheets/flat-buildings/npc_style_ref.png`):
  rich warm colours, strong light and shadow with bright highlights, chunky visible brushwork
  (cloth folds, wood grain, worn patches), dark outline. Buildings straight from the front, flat
  bottom. MapleStory sets scale, layout and spacing; the look is the game's own.
- **Light**: a world of endless dawn: warm, hopeful, golden light, even in the darkest zones.
  Shadows lean plum-violet, never pure black.
- **Music**: each prompt leads with its zone's own mood, lead instruments and tempo (the
  "Keep (music)" line), then ends with a short neutral line only: instrumental, no vocals,
  video game background music, loop-friendly, steady tempo, no long intro or fade-out. A long
  shared mood line on every prompt made all zones sound alike, so mood lives in each zone's line.
- Towns have no monsters. Each sub-zone should be recognisable at a glance from its light and
  palette alone.
- **Monsters**: each kind of monster belongs to one zone; zones don't share kinds unless Cory
  says so. A map has at most three kinds (a boss counts as one).
- **Levels**: border fields are the walk between towns and stay at Lv 10 or below; a zone's
  training branch climbs from about Lv 10 to its boss map. `tests/content/content_zones_test.gd`
  checks these monster and level rules.
- Roles below: **border** fields cross to a neighbouring zone, **training** fields lead deeper,
  the **boss** map ends the branch.
- Each job town also has a **Trial Ground** (Lv 10-11) for its job test, where a tear opens and
  the tear boss waits; it keeps its zone's look.

---

## Dawnrise Isle (start island)

Lv 1-12 · town Dawnrise Village · `meadow` biome · ship to Dawnharbor. The sunny, gentle island
where every adventurer wakes; the softest, most innocent zone.

**Keep (art):** sunrise palette: plum sky top `#2b2152`, peach horizon `#ffd3a0`, warm gold light
`#ffe2b0`, rose-pink haze `#e8a49a`; golden motes, light shafts. Rolling grass, wildflowers,
ropes, small rocks and trees. Round, soft, friendly shapes; small cute monsters.

**Keep (music):** innocent and carefree. Town: music box, ocarina, acoustic guitar, soft strings,
gentle bouncy tempo. Field: strings, flute, light percussion, bright skipping melody.

**Town: Dawnrise Village.** Small and cosy, humbler than Dawnharbor: a village green with a low
grassy rise (ladder up) where the windmill stands. Round honey-stone and timber cottages under fat
golden thatch, rose and peach heart shutters, flower boxes, climbing roses; no blue tiles or cream
plaster. Buildings: Elder Rowan's house, Mira's shop (striped awning), a family cottage, the
windmill. Rose-wound lamp posts. One 4K sunrise meadow panorama (hills, village, windmill, sea).

| Sub-zone | Role | Lv | What changes | Monsters |
| --- | --- | --- | --- | --- |
| Daybreak Shore | Tutorial | 1-2 | The zone look on a sunrise beach *(inferred)* | Dewling |
| Dawnrise Meadow | First field | 1-3 | Nothing: the zone look as painted, open sunrise meadow | Dewling, Mossling, Petal Bat |
| Sunny Slope | Easy field | 2-6 | Brighter: clear blue sky, golden horizon, more saturated | Tide Dewling, Mossling, Petal Bat |
| Mushroom Dell | Training | 4-8 | Cooler shade under giant mushrooms, lilac sky, misty, green spores | Sporecap, Sproutcap, Sea Gull |
| Tidal Flats | Training, boss | 7-12 | Island shore: sea-blue sky, peach low sky, pale washed backdrop | Shell Crab, Sea Gull; boss Old Clawbeard |
| Fern Hollow | Training, boss | 6-12 | Shaded mossy hollow, deep green light, light shafts, green motes | Fern Boar, Boulderkin; boss Fern Boar Chief |

## Dawnharbor Coast

Lv 3-22 · town Dawnharbor · `harbor` biome · neighbours Driftcove and
Greenbough. The busy port at the heart of the mainland; open, breezy and prosperous.

**Keep (art):** warm early morning over the sea: navy sky top `#1c2e5c`, peach-cream horizon
`#ffdfb0`, soft cream light `#fff0d0`, cool blue sea haze `#9dc3e7`; cream clouds with peach
undersides, sun sparkles on water, gulls. White and cream plaster, blue roof tiles, weathered
wood, rope, sails, stone harbour walls.

**Keep (music):** breezy, travelling, sea wind. Field: acoustic guitar, strings, flute, light
snare, steady travelling tempo. Town: the same instruments plus accordion touches, busier and
warmer, a cheerful harbour-market tune.

**Town: Dawnharbor (the gold standard for every city's detail and polish).** Three levels: a long quay lined with barrels, crates,
nets and carts, a stone-walled terrace above with lamp posts, ivy and flower boxes, and a cliff top
with the lighthouse and chapel.
Every building its own model (tavern, sail loft, harbormaster's office, shipwright, row houses,
lighthouse, chapel). One 4K warm-morning harbour panorama fills the background; clouds drift.
Layout: `/mnt/project-files/plans/done/dawnharbor-city-layout.md`.


| Sub-zone | Role | Lv | What changes | Monsters |
| --- | --- | --- | --- | --- |
| Harbor Beach | Border to Driftcove | 3-9 | Sunrise beach: peach low sky, warmer golden light | Sand Crab, Sea Gull, Tide Dewling (borrowed until Dawnharbor has its own) |
| Harbor Road | Border to Greenbough | 6-9 | Bright, airy coast road, pale blue sky, light haze; first green from Greenbough | Thornling, Sea Gull (borrowed until Dawnharbor has its own) |
| Windmill Downs | Training | 10-17 | Grassy downs with windmills, sunny and breezy *(inferred; plain harbour look today)* | Bramble Boar, Reef Gull, Tide Slime (borrowed until Dawnharbor has its own) |
| Gull Bluffs | Training | 15-20 | Windy sea cliffs crowded with gulls *(inferred; plain harbour look today)* | Reef Gull, Coral Turret, Kelp Lurker (borrowed until Dawnharbor has its own) |
| Smugglers' Grotto | Boss | 20-22 | Dim sea cave lit by smugglers' lanterns *(inferred; plain harbour look today)* | Kelp Lurker, Barnacle Boar (borrowed until Dawnharbor has its own); boss Grotto Tusker |

## Greenbough Wilds

Lv 9-28 · town Greenbough Village (Archers) · `greenwood` biome · neighbours Dawnharbor and
Lumewood. Towering trees and rope bridges; lively, airy, hunter's forest.

**Keep (art):** fresh daylight through leaves: deep green sky top `#173a29`, pale yellow horizon
`#fff1b0`, yellow-green light `#f4ffd0`, leaf-green mist `#a7d499`; light shafts, green motes.
Giant oak trunks, broad leaf canopies, planks, rope bridges and ladders, moss and bark. Monsters
are plant and woodland creatures.

**Keep (music):** adventurous and verdant. Town: wooden flutes, harp, plucked strings,
birdsong-like woodwinds, light skipping rhythm. Field: wooden flutes, strings, hand drums,
swinging hunting rhythm.

**Town: Greenbough Village.** Treehouses built into giant oaks, reached by ladders and linked by
rope bridges; life happens up in the branches. Honey oak planks, log posts, straw-and-leaf
thatch and antler trim.

| Sub-zone | Role | Lv | What changes | Monsters |
| --- | --- | --- | --- | --- |
| Bough Trail | Border to Dawnharbor | 9-10 | Forest edge, warm golden daylight | Thornling, Leafwing |
| Whispering Grove | Border to Lumewood | 9-10 | Cool mint-teal mist, rising motes; quiet, a little magical, hinting at Lumewood | Thornling, Leafwing |
| Mossy Glade | Training | 10-14 | Brightest Greenbough map, sunlit glade, strong light shafts | Leafwing, Bramble Boar |
| Thornwood | Training | 14-16 | Dim and tangled: olive fog, muted colour, darker shadows, thorns | Bramble Boar, Acorn Sentry |
| Deep Canopy | Training | 16-18 | Dark green under a closed canopy, warm shafts piercing through | Acorn Sentry, Barkcap |
| Old Oak Heights | Training | 18-23 | High in the old oaks: warm afternoon light through the leaves, golden shafts, soft green haze | Barkcap, Grove Wisp |
| Elder's Root | Boss | 23-28 | Golden late-afternoon glow around an ancient tree, gold motes; reverent | Grove Wisp; boss Elder Treant |

## Lumewood

Lv 9-30 · town Lumewood Sanctum (Magicians) · `lumewood` biome · neighbours Greenbough and
Emberreach. A glowing, dreaming forest; mystical, serene, wondrous.

**Keep (art):** twilight glow: indigo sky top `#120e33`, lavender horizon `#c8a7ff`, soft violet
light `#d8c7ff`, violet fog `#7961c7`; blue-white motes drifting upward, light shafts. Glowing
mushrooms and plants, blue crystals, pale stone, glass domes. Monsters are wisps, crystals and
spell creatures.

**Keep (music):** mystical and sparkling. Town: celesta, glass harmonica, harp arpeggios, wordless
choir pads, floating. Field: celesta, harp, strings, gentle bells, dreamy but moving forward.

**Town: Lumewood Sanctum.** Pale lilac-grey stone with blue glass domes and silver-blue ribs,
round windows, violet banners and glowing blue crystals for light; calm and scholarly, under soft
violet twilight. A street and two stone terraces (the Magicians' Library and store below, the
dormitory and observatory above); crystal fountain, book cart, star globe and glowing-mushroom
planters.

| Sub-zone | Role | Lv | What changes | Monsters |
| --- | --- | --- | --- | --- |
| Glimmer Path | Border to Greenbough | 9-10 | Brightest Lumewood map: strong light, pale lilac horizon, rich colour | Glowcap, Lume Wisp |
| Starfall Ridge | Border to Emberreach | 9-10 | Night ridge under a starry navy sky, starlight motes | Glowcap, Lume Wisp |
| Glowcap Hollow | Training | 10-15 | Blue-teal mushroom glow, cyan motes | Lume Wisp, Star Bat |
| Crystal Caves | Training | 15-17 | Deep indigo cave lit by violet crystals | Star Bat, Prism Slime |
| Prism Lake | Training | 17-20 | Pink-violet sky over a lake, most saturated map in the zone | Prism Slime, Crystal Golem |
| Glass Dome Ruins | Training | 20-27 | Ruined glass domes under a cool blue-violet sky, pale blue motes | Crystal Golem, Spell Imp, Starfall Golem |
| Arcane Spire | Boss | 22-30 | Purple magic fog, magenta motes, heavy violet grade | Spell Imp, Starfall Golem; boss Arcane Sentinel |

## Emberreach

Lv 7-31 · town Emberforge (Warriors) · `forge` biome · neighbours Lumewood and Lanternfall.
Cinder hills and forges; proud, hot, hardworking, heroic.

**Keep (art):** ember glow: dark ember-brown sky top `#24120c`, orange horizon `#ffb060`, amber
light `#ffd0a0`, orange-red haze `#bf592f`; rising embers. Grey stone, terracotta shingles, big
chimneys, iron straps and rivets, forge-lit windows, cinder slopes, slag and lava. Monsters are
fire, stone and metal creatures.

**Keep (music):** proud and driving. Town: warm brass, low strings, anvil-like metal percussion,
taiko, a strong friendly march. Field: low brass, string ostinato, war drums, energetic but not
dark.

**Town: Emberforge.** Stone forge halls with terracotta roofs and tall chimneys, glowing windows
and iron-bound doors; smoke and forge glow. Grey forge stone, iron straps and rivets.

| Sub-zone | Role | Lv | What changes | Monsters |
| --- | --- | --- | --- | --- |
| Cinder Pass | Border to Lumewood | 7-8 | Dusty mountain pass, brown-orange haze, muted colour | Cinder Imp, Ember Boar |
| Ashen Wastes | Border to Lanternfall | 8-9 | Grey ash plain, washed-out colour, white ash drifting | Ember Boar, Ashshell |
| Slag Fields | Training | 11-13 | Brightest Emberreach map, open slag heaps, warm orange horizon | Slag Slime, Cinder Pup |
| Smoke Pits | Training | 13-17 | Smoky grey-brown pits, dim and choking | Cinder Pup, Ash Bat, Fire Imp Archer |
| Magma Falls | Training | 17-20 | Red-orange glow of falling lava, bright ember motes | Fire Imp Archer, Magma Shell |
| Ironworks Depths | Training | 20-29 | Dark old ironworks, near-black sky with a low forge-red glow, muted colour | Magma Shell, Forge Golem, Cinder Hog |
| Molten Throne | Boss | 23-31 | Near-black red sky, deep red lift; hottest, darkest map | Forge Golem, Ash Wraith; boss Molten King |

## Lanternfall

Lv 9-30 · town Lanternfall (Thieves) · `lantern` biome · neighbours Emberreach and Driftcove.
A city of lanterns at dusk; sly, playful, mysterious but charming, never horror.

**Keep (art):** dusk: near-black navy sky top `#090e24`, amber horizon `#dfa060`, cool lavender
light `#c7bfff` against warm lantern glow, deep blue fog `#3a3a6f`; golden motes rising.
Tall, narrow half-timbered houses, cream plaster, dark beams, wall lanterns, narrow alleys,
cobbles. Monsters are shades, wisps, moths and crypt creatures.

**Keep (music):** a den of thieves: sly, roguish heist-caper mischief, cozy and charming, never
dark. Walking upright bass, muted clarinet (and muted trumpet), pizzicato strings, brushed snare and
finger snaps, accordion and celesta touches. Town: relaxed swagger. Field: sneaky tiptoe caper.
Boss: a fast heist-gone-wrong chase.

**Town: Lanternfall.** Always at dusk, the one dusk town (Cory). Tall narrow half-timbered houses of
smoky ochre plaster and dark soot-stained beams over dark brick, slate-blue roofs, crooked chimneys,
iron wall lanterns, hanging signs on brackets, plum and teal awnings; no cream plaster (Dawnharbor's).
A cobbled street with a brick-pillared balcony walkway and a rooftop lane joined by ladders; a dusk
rooftop panorama behind.

| Sub-zone | Role | Lv | What changes | Monsters |
| --- | --- | --- | --- | --- |
| Dusk Bridge | Border to Emberreach | 9-10 | Long bridge in an orange sunset, warm strong light | Shade Imp, Lantern Wisp |
| Shadow Marsh | Border to Driftcove | 9-10 | Murky green marsh fog, green will-o'-wisp motes | Shade Imp, Lantern Wisp |
| Lantern Alley | Training | 10-15 | Back alleys in warm lantern light, closest to the town look | Lantern Wisp, Dusk Moth |
| Gloom Woods | Training | 15-17 | Dark teal woods, dim and muted | Dusk Moth, Night Boar |
| Wraith Moor | Training | 17-19 | Cold blue-grey moor fog, pale blue motes, low colour | Night Boar, Gloomcap |
| Sunken Graveyard | Training | 19-24 | Sunken graves under a dark slate sky, grey-blue fog, pale green motes | Gloomcap, Crypt Shell, Marsh Horror |
| Forgotten Crypt | Boss | 24-30 | Near-black purple crypt, darkest map in the game | Marsh Horror, Dusk Stalker; boss Lantern Wraith |

## Driftcove

Lv 9-30 · town Driftcove (Pirates) · `coast` biome · neighbours Dawnharbor and Lanternfall.
Sea caves, wrecks and beaches; swashbuckling, jolly, watery.

**Keep (art):** tropical sea light: deep teal sky top `#132f4a`, cream horizon `#ffe2a7`, warm
cream light `#fff0c7`, turquoise haze `#8ed0d8`; cool sparkle. Sand, rock pools, coral, kelp,
wreck timber, portholes, masts and rigging, sea caves. Monsters are crabs, gulls, slimes, kelp
and reef creatures.

**Keep (music):** jolly and buoyant. Town: fiddle, accordion, concertina, stomping hand drums,
rollicking shanty feel without singing. Field: marimba, steel-string guitar, flowing strings,
light island percussion.

**Town: Driftcove.** A jolly pirate hideout built from beached ship hulls and wreck timber in a
big sea cave, lit turquoise from the cave mouth with warm lantern glow. Dark and sun-bleached wreck
timber, patched canvas, rope, portholes, brass, barnacles and kelp, red-and-cream striped awnings
and anchor flags (no skulls, no plaster or blue tiles). Two levels: a sandy floor plus a beached
hull deck and a jetty reached by rope ladders. Every building its own picture (boat store, grog
shack, Pirates' Quarters, mast lookout, captain's cabin, net loft); one 4K sea-cave panorama looks
out on a sunrise cove with wrecks and a moored pirate ship.

| Sub-zone | Role | Lv | What changes | Monsters |
| --- | --- | --- | --- | --- |
| Sandy Shoals | Border to Dawnharbor | 9-10 | Bright tropical shallows, strong sun, saturated colour | Sand Crab, Tide Slime |
| Saltwind Cliffs | Border to Lanternfall | 9-10 | Windy grey-blue overcast cliffs, pale and muted | Sand Crab, Tide Slime |
| Tidepools | Training | 10-15 | Rock pools under a pink-coral dusk sky | Tide Slime, Reef Gull |
| Coral Reef | Training | 15-17 | Teal underwater-style light, cyan motes | Reef Gull, Coral Turret |
| Wreck Cove | Training | 17-20 | Stormy dark blue cove full of wrecks, muted | Coral Turret, Kelp Lurker |
| Drowned Docks | Training | 20-22 | Half-sunk old docks, grey-teal sky and sea mist | Kelp Lurker, Barnacle Boar |
| Titan Grotto | Boss | 22-30 | Deep blue sea cave, dim and cold | Barnacle Boar, Cliff Harpy; boss Reef Titan |

---

## Open questions

- Windmill Downs, Gull Bluffs and Smugglers' Grotto still use the plain harbour look; confirm
  their vibes before they get their own light settings.
- Dawnrise Isle has two boss maps (Fern Hollow and Tidal Flats); keep both?
- Dawnharbor's fields borrow neighbouring zones' monsters until it gets its own harbour monsters
  (agreed; their look is still to be asked).
