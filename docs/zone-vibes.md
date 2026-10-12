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
- **Music**: each zone has one town track and one field track; the field track must suit every
  field in the zone. Boss maps play `boss`, dungeon maps play `dungeon` (shared world-wide).
- **New content**: a new sub-zone, building or track starts from its zone's "Keep" lines plus its
  own row. A new zone gets an entry here before any art or music is made for it.
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
- Roles below: **border** fields cross to a neighbouring zone, **training** fields lead deeper,
  the **boss** map ends the branch.

---

## Dawnrise Isle (start island)

Lv 1-12 · town Dawnrise Village · `meadow` biome · ship to Dawnharbor. The sunny, gentle island
where every adventurer wakes; the softest, most innocent zone.

**Keep (art):** sunrise palette: plum sky top `#2b2152`, peach horizon `#ffd3a0`, warm gold light
`#ffe2b0`, rose-pink haze `#e8a49a`; golden motes, light shafts. Rolling grass, wildflowers,
ropes, small rocks and trees. Round, soft, friendly shapes; small cute monsters.

**Keep (music):** innocent and carefree. Town: music box, ocarina, acoustic guitar, soft strings,
gentle bouncy tempo. Field: strings, flute, light percussion, bright skipping melody.

**Town: Dawnrise Village.** Small and cosy, humbler than Dawnharbor: cottages, gardens, a warm
welcome *(inferred)*.

| Sub-zone | Role | Lv | What changes | Monsters |
| --- | --- | --- | --- | --- |
| Dawnrise Meadow | First field | 1-6 | Nothing: the zone look as painted, open sunrise meadow | Dewling, Mossling, Petal Bat, Sproutcap, Boulderkin |
| Sunny Slope | Easy field | 2-3 | Brighter: clear blue sky, golden horizon, more saturated | Tide Dewling, Mossling, Petal Bat |
| Mushroom Dell | Training | 4-6 | Cooler shade under giant mushrooms, lilac sky, misty, green spores | Sporecap, Sproutcap, Sea Gull |
| Tidal Flats | Training, boss | 3-12 | Island shore: sea-blue sky, peach low sky, pale washed backdrop | Shell Crab, Sea Gull, Tide Dewling; boss Old Clawbeard |
| Fern Hollow | Training, boss | 4-12 | Shaded mossy hollow, deep green light, light shafts, green motes | Sproutcap, Fern Boar, Shell Crab, Boulderkin; boss Fern Boar Chief |

## Dawnharbor Coast

Lv 10-22 · towns Dawnharbor and the Free Market · `harbor` biome · neighbours Driftcove and
Greenbough. The busy port at the heart of the mainland; open, breezy and prosperous.

**Keep (art):** warm early morning over the sea: navy sky top `#1c2e5c`, peach-cream horizon
`#ffdfb0`, soft cream light `#fff0d0`, cool blue sea haze `#9dc3e7`; cream clouds with peach
undersides, sun sparkles on water, gulls. White and cream plaster, blue roof tiles, weathered
wood, rope, sails, stone harbour walls.

**Keep (music):** breezy, travelling, sea wind. Field: acoustic guitar, strings, flute, light
snare, steady travelling tempo. Town: the same instruments plus accordion touches, busier and
warmer, a cheerful harbour-market tune. Free Market: plucked guitar, light strings, flute, hand
claps and light snare, a friendly bargaining shuffle (its own track).

**Town: Dawnharbor (the template city).** Three levels: a long quay with a walkable wooden pier
and Marlo's ship, a stone-walled terrace above, and a cliff top with the lighthouse and chapel.
Every building its own model (tavern, sail loft, harbormaster's office, shipwright, row houses,
lighthouse, chapel). One 4K warm-morning harbour panorama fills the background; clouds drift.
Layout: `/mnt/project-files/plans/dawnharbor-city-layout.md`.

**Free Market:** the trading hall off the quay, harbour palette indoors *(inferred)*.

| Sub-zone | Role | Lv | What changes | Monsters |
| --- | --- | --- | --- | --- |
| Harbor Beach | Border to Driftcove | 3-11 | Sunrise beach: peach low sky, warmer golden light | Sand Crab, Sea Gull, Tide Dewling |
| Harbor Road | Border to Greenbough | 6-14 | Bright, airy coast road, pale blue sky, light haze; first green from Greenbough | Thornling, Bramble Boar, Sea Gull |
| Windmill Downs | Training | 13-15 | Grassy downs with windmills, sunny and breezy *(inferred; plain harbour look today)* | Bramble Boar, Reef Gull, Tide Slime |
| Gull Bluffs | Training | 15-20 | Windy sea cliffs crowded with gulls *(inferred; plain harbour look today)* | Reef Gull, Coral Turret, Kelp Lurker |
| Smugglers' Grotto | Boss | 20-22 | Dim sea cave lit by smugglers' lanterns *(inferred; plain harbour look today)* | Kelp Lurker, Barnacle Boar; boss Grotto Tusker |

## Greenbough Wilds

Lv 10-30 · town Greenbough Village (Archers) · `greenwood` biome · neighbours Dawnharbor and
Lumewood. Towering trees and rope bridges; lively, airy, hunter's forest.

**Keep (art):** fresh daylight through leaves: deep green sky top `#173a29`, pale yellow horizon
`#fff1b0`, yellow-green light `#f4ffd0`, leaf-green mist `#a7d499`; light shafts, green motes.
Giant oak trunks, broad leaf canopies, planks, rope bridges and ladders, moss and bark. Monsters
are plant and woodland creatures.

**Keep (music):** adventurous and verdant. Town: wooden flutes, harp, plucked strings,
birdsong-like woodwinds, light skipping rhythm. Field: wooden flutes, strings, hand drums,
swinging hunting rhythm.

**Town: Greenbough Village.** Treehouses built into giant oaks, reached by ladders and linked by
rope bridges; life happens up in the branches *(inferred)*.

| Sub-zone | Role | Lv | What changes | Monsters |
| --- | --- | --- | --- | --- |
| Bough Trail | Border to Dawnharbor | 11-14 | Forest edge, warm golden daylight | Thornling, Leafwing, Bramble Boar |
| Whispering Grove | Border to Lumewood | 13-18 | Cool mint-teal mist, rising motes; quiet, a little magical, hinting at Lumewood | Barkcap, Leafwing, Acorn Sentry |
| Mossy Glade | Training | 11-13 | Brightest Greenbough map, sunlit glade, strong light shafts | Thornling, Leafwing |
| Thornwood | Training | 13-16 | Dim and tangled: olive fog, muted colour, darker shadows, thorns | Bramble Boar, Leafwing, Acorn Sentry |
| Deep Canopy | Training | 16-20 | Dark green under a closed canopy, warm shafts piercing through | Barkcap, Grove Wisp, Acorn Sentry |
| Elder's Root | Boss | 18-28 | Golden late-afternoon glow around an ancient tree, gold motes; reverent | Grove Wisp, Barkcap; boss Elder Treant |

## Lumewood

Lv 10-30 · town Lumewood Sanctum (Magicians) · `lumewood` biome · neighbours Greenbough and
Emberreach. A glowing, dreaming forest; mystical, serene, wondrous.

**Keep (art):** twilight glow: indigo sky top `#120e33`, lavender horizon `#c8a7ff`, soft violet
light `#d8c7ff`, violet fog `#7961c7`; blue-white motes drifting upward, light shafts. Glowing
mushrooms and plants, blue crystals, pale stone, glass domes. Monsters are wisps, crystals and
spell creatures.

**Keep (music):** mystical and sparkling. Town: celesta, glass harmonica, harp arpeggios, wordless
choir pads, floating. Field: celesta, harp, strings, gentle bells, dreamy but moving forward.

**Town: Lumewood Sanctum.** Round pale-stone towers with blue glass and crystal domes, round
windows; calm and scholarly, lit by crystals and glowing plants *(inferred beyond the buildings)*.

| Sub-zone | Role | Lv | What changes | Monsters |
| --- | --- | --- | --- | --- |
| Glimmer Path | Border to Greenbough | 15-20 | Brightest Lumewood map: strong light, pale lilac horizon, rich colour | Crystal Golem, Star Bat, Grove Wisp |
| Starfall Ridge | Border to Emberreach | 22-27 | Night ridge under a starry navy sky, starlight motes | Starfall Golem, Spell Imp |
| Glowcap Hollow | Training | 11-13 | Blue-teal mushroom glow, cyan motes | Glowcap, Lume Wisp |
| Crystal Caves | Training (dungeon music) | 13-17 | Deep indigo cave lit by violet crystals | Lume Wisp, Star Bat, Prism Slime |
| Prism Lake | Training | 17-22 | Pink-violet sky over a lake, most saturated map in the zone | Prism Slime, Crystal Golem, Spell Imp |
| Arcane Spire | Boss | 20-30 | Purple magic fog, magenta motes, heavy violet grade | Spell Imp, Crystal Golem; boss Arcane Sentinel |

## Emberreach

Lv 10-32 · town Emberforge (Warriors) · `forge` biome · neighbours Lumewood and Lanternfall.
Cinder hills and forges; proud, hot, hardworking, heroic.

**Keep (art):** ember glow: dark ember-brown sky top `#24120c`, orange horizon `#ffb060`, amber
light `#ffd0a0`, orange-red haze `#bf592f`; rising embers. Grey stone, terracotta shingles, big
chimneys, iron straps and rivets, forge-lit windows, cinder slopes, slag and lava. Monsters are
fire, stone and metal creatures.

**Keep (music):** proud and driving. Town: warm brass, low strings, anvil-like metal percussion,
taiko, a strong friendly march. Field: low brass, string ostinato, war drums, energetic but not
dark.

**Town: Emberforge.** Stone forge halls with terracotta roofs and tall chimneys, glowing windows
and iron-bound doors; smoke and forge glow *(inferred beyond the buildings)*.

| Sub-zone | Role | Lv | What changes | Monsters |
| --- | --- | --- | --- | --- |
| Cinder Pass | Border to Lumewood | 23-29 | Dusty mountain pass, brown-orange haze, muted colour | Cinder Hog, Starfall Golem, Forge Golem |
| Ashen Wastes | Border to Lanternfall | 20-31 | Grey ash plain, washed-out colour, white ash drifting | Ash Wraith, Cinder Hog, Magma Shell |
| Slag Fields | Training | 11-13 | Brightest Emberreach map, open slag heaps, warm orange horizon | Slag Slime, Cinder Pup |
| Smoke Pits | Training (dungeon music) | 13-17 | Smoky grey-brown pits, dim and choking | Cinder Pup, Ash Bat, Fire Imp Archer |
| Magma Falls | Training | 17-23 | Red-orange glow of falling lava, bright ember motes | Fire Imp Archer, Magma Shell, Forge Golem |
| Molten Throne | Boss | 20-30 | Near-black red sky, deep red lift; hottest, darkest map | Forge Golem, Magma Shell; boss Molten King |

## Lanternfall

Lv 10-35 · town Lanternfall (Thieves) · `lantern` biome · neighbours Emberreach and Driftcove.
A city of lanterns at dusk; sly, playful, mysterious but charming, never horror.

**Keep (art):** dusk: near-black navy sky top `#090e24`, amber horizon `#dfa060`, cool lavender
light `#c7bfff` against warm lantern glow, deep blue fog `#3a3a6f`; golden motes rising.
Tall, narrow half-timbered houses, cream plaster, dark beams, wall lanterns, narrow alleys,
cobbles. Monsters are shades, wisps, moths and crypt creatures.

**Keep (music):** sly and mysterious. Town: pizzicato strings, muted clarinet, soft jazz brushes,
celesta, sneaky tiptoe melody. Field: low strings, clarinet, harp, soft timpani, eerie yet playful.

**Town: Lanternfall.** Narrow half-timbered houses packed along lantern-lit alleys, always at dusk
*(inferred beyond the buildings)*.

| Sub-zone | Role | Lv | What changes | Monsters |
| --- | --- | --- | --- | --- |
| Dusk Bridge | Border to Emberreach | 22-33 | Long bridge in an orange sunset, warm strong light | Dusk Stalker, Ash Wraith, Crypt Shell |
| Shadow Marsh | Border to Driftcove | 19-24 | Murky green marsh fog, green will-o'-wisp motes | Marsh Horror, Crypt Shell, Gloomcap |
| Lantern Alley | Training | 11-13 | Back alleys in warm lantern light, closest to the town look | Shade Imp, Lantern Wisp |
| Gloom Woods | Training (dungeon music) | 13-17 | Dark teal woods, dim and muted | Lantern Wisp, Dusk Moth, Night Boar |
| Wraith Moor | Training | 17-22 | Cold blue-grey moor fog, pale blue motes, low colour | Night Boar, Gloomcap, Crypt Shell |
| Forgotten Crypt | Boss | 19-30 | Near-black purple crypt, darkest map in the game | Crypt Shell, Gloomcap; boss Lantern Wraith |

## Driftcove

Lv 10-30 · town Driftcove (Pirates) · `coast` biome · neighbours Dawnharbor and Lanternfall.
Sea caves, wrecks and beaches; swashbuckling, jolly, watery.

**Keep (art):** tropical sea light: deep teal sky top `#132f4a`, cream horizon `#ffe2a7`, warm
cream light `#fff0c7`, turquoise haze `#8ed0d8`; cool sparkle. Sand, rock pools, coral, kelp,
wreck timber, portholes, masts and rigging, sea caves. Monsters are crabs, gulls, slimes, kelp
and reef creatures.

**Keep (music):** jolly and buoyant. Town: fiddle, accordion, concertina, stomping hand drums,
rollicking shanty feel without singing. Field: marimba, steel-string guitar, flowing strings,
light island percussion.

**Town: Driftcove.** A pirate hideout built from beached ship hulls and wreck timber in sea caves,
sails and rope everywhere *(inferred beyond the buildings)*.

| Sub-zone | Role | Lv | What changes | Monsters |
| --- | --- | --- | --- | --- |
| Sandy Shoals | Border to Dawnharbor | 11-15 | Bright tropical shallows, strong sun, saturated colour | Sand Crab, Tide Slime, Reef Gull |
| Saltwind Cliffs | Border to Lanternfall | 20-22 | Windy grey-blue overcast cliffs, pale and muted | Cliff Harpy, Barnacle Boar, Kelp Lurker |
| Tidepools | Training | 11-13 | Rock pools under a pink-coral dusk sky | Sand Crab, Tide Slime |
| Coral Reef | Training | 13-17 | Teal underwater-style light, cyan motes | Tide Slime, Reef Gull, Coral Turret |
| Wreck Cove | Training | 17-22 | Stormy dark blue cove full of wrecks, muted | Kelp Lurker, Barnacle Boar, Coral Turret |
| Titan Grotto | Boss | 20-30 | Deep blue sea cave, dim and cold | Kelp Lurker, Barnacle Boar; boss Reef Titan |

---

## Open questions

- Windmill Downs, Gull Bluffs and Smugglers' Grotto still use the plain harbour look; confirm
  their vibes before they get their own light settings.
- Town vibes beyond the current buildings and music are inferred; confirm them, and whether each
  town follows Dawnharbor's multi-level layout later.
- Lanternfall sits at permanent dusk while the world is endless dawn; keep it as the one dusk zone?
- Dawnrise Isle has two boss maps (Fern Hollow and Tidal Flats); keep both?
- Most border fields are among their zone's highest-level maps (Cinder Pass 23-29, Ashen Wastes
  20-31, Dusk Bridge 22-33); is that intended for crossings?
