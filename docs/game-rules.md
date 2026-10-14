# Game rules

How the game should look and play. These are Cory's decisions; follow them in every change and
update this page when one changes. Each zone's own look and music are in
[zone vibes](zone-vibes.md); how the code works is in [ARCHITECTURE.md](../ARCHITECTURE.md).

## Art

- Painted look only, never pixel art. The NPC sprites are the style reference: rich warm colours,
  strong light and shadow with bright highlights, visible painted texture at a fairly chunky brush
  scale, dark outline. The chibi boy hero (`art/reference/hero.png`) sets character proportions.
- MapleStory sets scale, feel, UI, layout and animation; the look and names are the game's own.
- Nothing is recoloured in code (no tint, modulate or palette swap). Another skin tone, hair colour
  or armour colour is its own painted sheet, put together as painted.
- High resolution everywhere, UI included: art is made and cut at about twice its on-screen size,
  never stretched or upscaled, never blurry.
- Clean edges: soft anti-aliased cut edges, never on/off pixels, never thicker outlines, no stray
  pixels or magenta fringe.
- Prefer a proper repaint over a crude cut in code. Only make or repaint art the game uses. Music
  and art the game no longer uses is dropped (git history keeps it), including the sheets of
  dropped features. Never reuse the old ChatGPT sheets.

## Hero

- The hero is a paperdoll in the NPC style, a boy or a girl (the hairstyle picks the body), hands
  with fingers. `art/reference/hero_look.png` (boy and girl in every pose, tunic, trousers and
  each hat type) is the approved look to match. Each body has one painted face; the creator
  picks the hairstyle (and so the body).
- Chibi proportions, drawn about 13% larger than the first cut.
- Looks exactly the same in menus (equipment, creator, character select) as in game: one renderer.
- Animation: walk only, 15% faster after about 0.4 s of moving; run frames never play. No walk bob;
  the walk is four painted steps. Standing, he breathes and blinks. Poses show as painted.
  No jump sound. No character shadows.
- Buffs and spells have no pose, just a flash in the skill's colour. Skill effects draw on the
  hero's layer.

## Movement and combat feel

- A bit metroidvania, like Hollow Knight: the hero starts and stops at once, steers freely in the
  air, hops short when jump is let go early and falls faster than he rises. A full jump keeps its
  height, so every map stays reachable.
- No dash for the hero: each job has its own movement skill instead. Warrior Charge (a lunge
  that only shoves monsters aside, no damage; once per jump in the air too), Thief Flash Jump (a
  second jump in mid-air), Magician Blink (a teleport the held way, up and down too), Archer
  Backstep Leap (springs back still facing ahead), Pirate Rolling Dash (a low roll on the ground
  nothing can hit). Beginners have none. Their effects are code-drawn stand-ins until painted
  ones are made with Gemini in the same look as every other skill effect.
- Attacks and most attack skills aim: up hits overhead, down (in the air only) hits below. Buffs
  don't aim. A downward melee blow that meets a monster bounces him off it (pogo).
- He can move while swinging and keeps facing the swing until it ends.
- Melee hits feel heavy: longer hit-stop, a small push back on him, a harder knockback on the
  monster, a camera kick on crits and kills. Ranged hits (arrows, stars, bullets, spells) stay
  light.
- Getting hit freezes him a beat, flashes the screen and knocks him away without steering.
- New poses (up and down slashes) wait for the rebuilt paperdoll hero; until then the attack
  pose plays with the swing effect turned up or down.
- Job skills will be flashy and grand, like MapleStory.

## Jobs, stats and skills

- Each first job has one stat that drives its damage, and no other stat adds to it: Warrior STR,
  Magician INT, Thief LUK, Archer DEX, Pirate CHA (Charisma). Gear asks only for the job's own
  stat; Auto puts every Ability Point there.
- What each stat also gives as it grows: STR Max HP, INT Max MP, DEX Accuracy, LUK Avoidability,
  CHA slightly lower shop prices (capped) and more Dawnshards found.
- A first job has six skills: a movement skill, a quick single-target attack, a crowd attack, a self
  buff, a party buff (reaches party members nearby) and a passive. Their max levels add up to the
  SP earned from Lv 10 to 30, so all are maxed by the second tier at Lv 30. No finishers in the
  first job; later tiers get them.
- Second tier (Lv 30): every first job picks one of two blends of itself and another first job:
  Spellblade (Warrior + Magician), Hexcaster (Magician + Thief), Swashbuckler (Thief + Pirate),
  Sharpshooter (Pirate + Archer), Wildhunter (Archer + Warrior). A blend is the same job from
  either side. It keeps its own first-job skills, opens all of the other job's first-job skills,
  and adds its own finisher and signature skill (max 10 each); 4 Skill Points a level, so
  everything is maxed by the third tier at Lv 50. Both stats add together for damage (no
  averaging); Auto splits points evenly. It wields every weapon and off-hand of both jobs.
  No Ability Point reset on advancing. A later tutor offers the blends; the first-job tutors
  never do.
- Every job is built to attack and be fun solo: no tank or healer jobs.
- No job is shown or named to the player until they can choose it: no menu, list, tooltip,
  quest or NPC line hints at a later job before then. The one exception: Beginners see the
  five first jobs and what each needs, so they can plan their stats.
- Third tier (Lv 50, planned): five jobs, each joining two blends that share no first job, so
  all four of their stats add together for damage. It uses every weapon of its four first
  jobs plus its own two-handed weapon, opens every skill of those four jobs and both blends,
  and adds one ultimate skill that hits a very large area and a huge number of monsters.
- Fourth tier (planned): one job, Harbinger. It has every skill and weapon in the game, and
  all five stats add together for its damage. It unlocks only after the story reveals the hero
  is the harbinger; until then nothing in the game names it.
- Max level is 100.
- Off-hand slot (once the Shield slot): Warriors and Beginners wear a shield, a Thief throwing
  stars (with a dagger in hand), a Magician a book, an Archer a quiver worn on the back, a Pirate a pistol (with knuckles). Stars
  and pistols never run out. A Thief's dagger hits one monster and the stars hit a crowd; a
  Pirate's fists hit one and the pistol a crowd.

## Gear

- Gear is being redrawn for the new hero: the old items, icons and worn pictures were removed
  (2026-10-13) and are never used again. Each first job has a starter armor set (hat, top,
  trousers, shoes; Lv 10, that job and its blends only), sold in its town's shop: Warrior
  Squire set (Emberforge), Magician Novice set (Lumewood), Thief Footpad set (Lanternfall),
  Archer Hunter's set (Greenbough), Pirate Deckhand set (Driftcove). Tests still bring their own
  plain gear (`tests/fixtures/gear`) for what the game doesn't have yet.
- Each piece of gear is painted once, worn on the hero, plus one icon that the boy and the girl
  share. (The starter sets were also painted on the girl.)
- An item's icon and its worn or held look are the same object: shape, colours and details. Worn
  gear is cut the same way the icons are, keeps their detail, uses the hero's near-black outline,
  and is never cut off.
- Every piece of gear is its own layer on the paperdoll.

## Hats and hair

- Hats fit the MapleStory way: sized to the whole head and hair, face open, lined up with the eyes.
  Helmets have a low dome and the nose guard reaches down between the eyes. No part of the head
  pokes out the side.
- Hats and hoods end at the neck: no cape or cloth over the back (cloaks are their own item), and
  hoods have no collar, scarf, capelet, clasp or shoulder pieces; the bare neck shows below. Every
  hairstyle wears the same hood.
- Hoods have an open face. Bandanas sit low on the brow and stay small.
- Two hairstyles for now: tousled (boy) and ponytail (girl).
- Hair is slightly wider than the head. Keep the forehead bangs; trim floating bits and tufts that
  hang past the front of the face; no hair near the mouth.
- Hair under hats follows Cory's template sheets, one per hairstyle with a cell for every hat type
  (`boy_tousled.png`, `girl_ponytail.png` in the project's `references/hat-hair-templates/`):
  the painted hair in each cell is how that hairstyle looks under that hat. The girl's short tail hangs below each hat behind her neck (none
  under the hood); under a helmet her hair hangs down behind her shoulders and never sticks up or
  out. A new hairstyle needs a template with every hat type; a new hat type needs a cell for every
  hairstyle. Every hat is drawn in one of the template hat types. No seam between hat and hair.
- The old hero (until it is replaced) shows only its own hair under a hat, cut along the hat's
  lower edge, with the ponytail's tail cut away.

## Weapons

- Always in the front hand (nearest the viewer), on every frame: on the walk that is walk1 a,
  walk2 b, walk3 a, walk4 b. Never moved to the back hand, not even to smooth an animation.
- In hand on every pose except climbing, when it goes on his back.
- Fingers over the grip; the same spot in the hand and the same angle to the forearm every frame;
  smooth changes between frames. Never upside down, never over the face, none on level-up.
- Drawn in front of everything except the hands; when the palm shows (the fall), in front of all.
- The staff's holds are the model for every kind, but each kind has its own grip point. Wands are
  gripped halfway along the shaft. Bows sit level when sitting and at their true angle when
  crouching, with the arm drawn over the string. Guns point and shoot with the barrel along the
  forearm. Throwing stars sit in the front fist behind the hand, points sticking out. Knuckles are a
  big glove centred over the front fist.
- No throw or shot effects (no projectile leaving the hand, empty fist, arrow on the string, glint or
  punch burst).
- No ammo for any weapon. Claws were dropped; thieves use a dagger and throwing stars.
- Shops sell only basic weapons; better weapons come from monster drops.
- Future dual-wield is the one exception to the front-hand rule.

## Maps and scenery

- Map names show only at the top of the screen; nothing labels a map in the world.
- Every piece of land is walkable: no arches or floating rock islands, nothing that looks like
  ground but isn't. No two exits of a map lead to the same map. Maps can be wide and multi-level.
- Characters, NPCs, ropes and ladders draw in front of land. Portals draw in front of land and
  scenery, behind ropes, NPCs, monsters and players; no NPC stands on a portal.
- Portals are a blue-white light pillar on the ground, at exits and doorways, 70% opaque.
- Platforms and land cast no shadows. Platform end caps line up with the platform. Terrace walls stop
  straight down from the bottom of the path's end stone, with the path's thin outline, standing
  straight up and down. Wall ivy hangs flush with the platform's bottom edge.
- Ladders, ropes and vines stand straight and line up at every joint. Ladders sit on flat wall
  faces and never stick out past a corner.
- Buildings, props and decorations are flat 2D front views with a flat bottom, never a perspective
  picture cut flat. They sit flush on the ground with no gap under them (the stage sinks every base
  a few pixels; fix a leftover gap in the map's data). Every building is unique and at proper
  scale; windows, doors and props are in proportion across a map. Nothing (ropes, chains, cloth)
  ends in mid-air.
- No houses in monster maps unless a quest needs one or Cory asks. Shops are proper full-size
  buildings.
- Backdrops: one high-quality, sharp picture for the whole background, not strips. Dawnharbor's 4K
  panorama is the template. Clouds drift in front of it.
- Sparse ground scenery, each piece wholly on its platform; few lanterns, never overlapping buildings,
  NPCs or scenery.
- No on-screen controls or how-to-play text anywhere: the tutorial teaches new characters the keys.

## Towns

- Towns have no monsters and no grass tufts.
- NPCs stand still at idle; town villagers use the second idle frame. An NPC stands in the middle
  of a plank, jetty or platform, never at its edge, on a rope or on a portal.
- No duplicate NPCs anywhere in the game, names included: every town has its own shopkeepers,
  storage keeper and townsfolk. A character who travels (the ship's captain at both ends of the
  voyage, a job tutor in their hall and at their Trial Ground, the coachmen) is one person, not a
  copy, and may appear in more than one place. Check every branch before naming a new NPC
  (`python3 tools/art/town_kit.py names <name>`).
- Every building in a town is its own picture, painted in that town's tone, and used only there.
- Dawnharbor is the gold standard for how a city looks. Other cities keep its attention to detail
  and polish but have their own tone; they never copy Dawnharbor's look. Change Dawnharbor only
  with great care: show Cory any change to it before it goes in.
- Dawnharbor's layout: a quay, a terrace and a cliff top, every building its own
  picture. There is no Free Market and no player shops.
- Dawnharbor's store door, stone paths and cliff top stay as they are. The pier was dropped.
- Reference maps from other games are for layout and spacing only.

## Making a town

Every new town is made the same way, so it reaches Dawnharbor's level the first time. The tool is
`tools/art/town_kit.py`; how to use it is in [art/sheets/README.md](../art/sheets/README.md#town-kit).

- **What a town has**: 5 or 6 buildings (its store and its job hall among them), a 4K backdrop
  panorama, a lamp post, 6 or 12 props, three townsfolk and its own storage keeper, and its own
  store and hall room walls. Raised levels when the town has them.
- **The town card first**: `tools/art/towns/<town>.json` holds the town's look from
  [zone vibes](zone-vibes.md) (mood, light, palette, materials, painted texture), its signature
  materials, and its building, prop and townsfolk lists. Cory agrees the card before any paint.
- **Fixed canvases**: every piece is painted on one of the kit's canvases. Building canvases mark
  the doorway at the bottom centre at a door's size next to the hero; buildings are painted around
  that door and cut at one kit scale, so doors match in every town and a building's height comes
  from its painting.
- **Locked prompts**: the kit writes every Gemini entry from the card in the same words. One
  building, the lamp or the backdrop per paint; props six to a sheet; townsfolk four to a sheet.
  Buildings get only the NPC style picture and this town's approved buildings as references; the
  backdrop and props get none. Every prompt bans the other towns' signature materials.
- **Pilot, then the rest**: the first building and the backdrop are painted and shown to Cory
  first. Once he likes them, they become the references for the rest of the town.
- **Checks reject, never fix**: sheet_check runs the kit's checks on every result (door on its
  mark, base on the ground line, nothing cut off, stray bits, glow halos, a clear backdrop
  foreground). Results go in exactly as painted; one that fails goes to Cory as keep, repaint or
  leave out. Cleaning up a cut (background, ground line, stray bits) is fine; nothing is retouched.
- **In game**: the town content test checks the town has everything above, its buildings are its
  own, its NPCs stand mid-platform and its ladders sit on wall faces.

## Monsters and levels

- Two or three monster kinds per map (a boss counts as one). Each kind belongs to one zone unless
  Cory says otherwise. A monster taken out of a zone stays in the files.
- Every spawn is inside its map's level range; fix a mismatch by changing monster levels, not by
  removing monsters.
- The paths players walk between towns stay at Lv 10 or below the whole way, so new players can
  reach every job town. Dead-end training branches climb in smooth steps to a boss on the top map.
- Monsters target a player who comes in sight (Lv 1-5 starters only up close) or hits them, and
  give up a few seconds after losing sight. Every monster has one or two moves and every boss
  three different ones; each move winds up with a glow first so it can be dodged. Moves reuse
  the monster's own frames (the attack pose plus motion).
- Bosses are about 1.5x a normal monster of their kind, not bigger. They fight smarter: the move
  that fits the distance, never the same move twice in a row, aim where the player is heading,
  leap to the player's platform, chain a charge or pounce into a slam, and get a second wind at
  half HP. In co-op they go for whoever has hurt them most lately.
- Max level is 100; monsters and maps reach about Lv 30 so far. Monster HP is 40% lower than first
  tuned and EXP needed per level is halved (monster and quest EXP unchanged), so early levels go
  fast; about 40 hours to Lv 35 was only a starting reference.

## UI

- Painted travel leather and parchment. No fake stitching; the close X fits the style; the minimap
  frame matches the bottom bar.
- Monster HP bars have no dragon emblem. Quest marks are a painted "!", "?" and three dots.
- The equipment window shows the hero on a stencil with the slots around him.
- No clouds on the title screen.
- No controls box on screen, in towns or fields: the tutorial teaches the keys (its step hints
  show at the bottom), and the full list is in Settings > Controls.
- Skill icons are painted NPC-style badges: one bold subject (no people for Shoulder Bash or
  Rolling Dash) in a thick rounded frame of the job's colour: Beginner warm brown, Warrior
  crimson, Magician blue, Thief charcoal black with silver trim, Archer green, Pirate gold.

## Audio and travel

- Every town, field and boss map plays its zone's music: one town track, one field track and one
  more upbeat, dangerous boss track per zone. Lanternfall sounds like a thieves' den.
- Kenney CC0 sound effects; the title theme and jingles stay.
- Captain Marlo's ship carries players from the start island to Dawnharbor; coachman Rook takes them
  to the job towns (400-500 Dawnshards, the same for everyone); the towns are also joined by a ring
  of portals. Developer test characters start in their job's town.
- Not an MMO: no accounts, usernames or passwords. Play leads to Solo or Co-op; Co-op leads to Host
  (UDP 7350, shows the LAN address with Copy) or Join (`address:port`). Up to 4 players counting the
  host; each brings a character saved on their own computer, and their progress saves there.

## Story

- The world is Morrowmere. The main story (Tera and the Dawn curse) stays hidden until well past
  today's Lv 35 content: no in-game text names Tera's Dawn, the curse or the other dawns before
  the story reveals them, and nobody knows what Dawnshards really are at first. The tears are
  only called that (a tear or rip in the air) from the Lv 10 job test on.
- Most quests and NPCs have nothing to do with the story. Cory reviews every story character,
  quest, cutscene and line before it goes in the game.
- New characters wake on Daybreak Shore, the tutorial beach before Dawnrise Village. A girl
  (labelled "Girl on the Beach", no title) teaches the keys as games she plays with you; a key
  hint shows at the bottom of the screen for each step. Her last quest opens a one-way portal
  to the village, where she stands by Elder Rowan as "Rowan's Granddaughter". Her name is never
  shown. A faint white glow sits out on the water; nobody mentions it.
- At Lv 10 each job tutor gives a Job Test before advancing: a short course on the town's Trial
  Ground, fought alone (every player gets their own copy, even in co-op). At the far end a tear
  opens and one boss, the same for all five jobs (a hulking beast of pale starlit stone), steps
  out. Beating it and handing the test in makes you that job; the tutor sends you to Archmage
  Celest in Lumewood (Magicians are already with her).
