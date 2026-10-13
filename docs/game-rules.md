# Game rules

How the game should look and play. These are Cory's decisions; follow them in every change and
update this page when one changes. Each zone's own look and music are in
[zone vibes](zone-vibes.md); how the code works is in [ARCHITECTURE.md](../ARCHITECTURE.md).

## Art

- Painted look only, never pixel art. The NPC sprites are the style reference: rich warm colours,
  strong light and shadow with bright highlights, visible painted texture at a fairly chunky brush
  scale, dark outline. The chibi boy hero (`art/reference/hero.png`) sets character proportions.
- MapleStory sets scale, feel, UI, layout and animation; the look and names are the game's own.
- High resolution everywhere, UI included: art is made and cut at about twice its on-screen size,
  never stretched or upscaled, never blurry.
- Clean edges: soft anti-aliased cut edges, never on/off pixels, never thicker outlines, no stray
  pixels or magenta fringe.
- Prefer a proper repaint over a crude cut in code. Only make or repaint art the game uses. Music
  and art the game no longer uses is dropped (git history keeps it), including the sheets of
  dropped features. Never reuse the old ChatGPT sheets.

## Hero

- Chibi proportions, drawn about 13% larger than the first cut. Hands are mittens (NPC hands still
  have fingers).
- Looks exactly the same in menus (equipment, creator, character select) as in game: one renderer.
- Animation: walk only, 15% faster after about 0.4 s of moving; run frames never play. No walk bob;
  the walk has a stride shift. Standing, he breathes and blinks. Only a slight tilt when falling.
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

## Gear

- The game has no equipment for now: every item, icon and worn picture was removed to be redrawn
  for the new hero (2026-10-13). The equipment system (slots, the equip window, stats) stays, and
  the tests bring their own plain gear (`tests/fixtures/gear`).
- An item's icon and its worn or held look are the same object: shape, colours and details. Worn
  gear is cut the same way the icons are, keeps their detail, uses the hero's near-black outline,
  and is never cut off.
- Every piece of gear is its own layer on the paperdoll.
- Shields: the back side on the off hand, about a third visible.
- Gloves: cuffless mittens in the glove's colours.

## Hats and hair

- Hats fit the MapleStory way: sized to the whole head and hair, face open, lined up with the eyes.
  The steel helm sits low so its visor slits are on his eyes, with no brown part under it. No part
  of the head pokes out the side.
- Hair below a hat's lower edge shows as is, never trimmed short, except the ponytail's tail, which
  is cut away.
- Hoods have an open face. Bandanas sit low on the brow and stay small.
- Two hairstyles for now: tousled (boy) and ponytail (girl).
- Hair is slightly wider than the head. Keep the forehead bangs; trim floating bits and tufts that
  hang past the front of the face; no hair near the mouth.
- Under a hat each pose shows only its own hair, cut along the hat's lower edge: nothing new is
  drawn, nothing reshaped, no hair copied between poses. The ponytail's tail never shows under a hat
  (the back of the head stays covered). No seam between hat and hair.

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
- No ammo for any weapon. Claws were dropped; thieves use throwing stars.
- Shops sell only basic weapons; better weapons come from monster drops.
- Future dual-wield is the one exception to the front-hand rule.

## Maps and scenery

- Map names show only at the top of the screen; nothing labels a map in the world.
- Every piece of land is walkable: no arches or floating rock islands, nothing that looks like
  ground but isn't. No two exits of a map lead to the same map. Maps can be wide and multi-level.
- Characters, NPCs, ropes and ladders draw in front of land. Portals draw in front of land and
  scenery, behind ropes, NPCs, monsters and players; no NPC stands on a portal.
- Portals are a blue-white light pillar on the ground, at exits and doorways.
- Platforms and land cast no shadows. Platform end caps line up with the platform. Terrace walls stop
  straight down from the bottom of the path's end stone, with the path's thin outline, standing
  straight up and down. Wall ivy hangs flush with the platform's bottom edge.
- Ladders, ropes and vines stand straight and line up at every joint.
- Buildings, props and decorations are flat 2D front views with a flat bottom, never a perspective
  picture cut flat. Every building is unique and at proper scale; windows, doors and props are in
  proportion across a map. Nothing (ropes, chains, cloth) ends in mid-air.
- No houses in monster maps unless a quest needs one or Cory asks. Shops are proper full-size
  buildings.
- Backdrops: one high-quality, sharp picture for the whole background, not strips. Dawnharbor's 4K
  panorama is the template. Clouds drift in front of it.
- Sparse ground scenery, each piece wholly on its platform; few lanterns, never overlapping buildings,
  NPCs or scenery.

## Towns

- Towns have no monsters and no grass tufts.
- NPCs stand still at idle.
- Dawnharbor is the gold standard for how a city looks. Other cities keep its attention to detail
  and polish but have their own tone; they never copy Dawnharbor's look. Change Dawnharbor only
  with great care: show Cory any change to it before it goes in.
- Dawnharbor's layout: a quay, a terrace and a cliff top, every building its own
  picture. The Free Market portal has a painted signboard beside it; the Free Market itself uses
  Dawnharbor's panorama and is empty for now.
- Dawnharbor's store door, stone paths and cliff top stay as they are. The pier was dropped.
- One city (Dawnharbor) and one monster zone are set exactly right before any world-wide art pass.
  Reference maps from other games are for layout and spacing only.

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
- Level cap Lv 35. Monster HP is 40% lower than first tuned and EXP needed per level is halved
  (monster and quest EXP unchanged), so early levels go fast; about 40 hours to the cap was only a
  starting reference.

## UI

- Painted travel leather and parchment. No fake stitching; the close X fits the style; the minimap
  frame matches the bottom bar.
- Monster HP bars have no dragon emblem. Quest marks are a painted "!", "?" and three dots.
- The equipment window shows the hero on a stencil with the slots around him.
- No clouds on the title screen.

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
  today's Lv 35 content: no in-game text names Tera's Dawn, the curse, the tears or the other
  dawns before the story reveals them, and nobody knows what Dawnshards really are at first.
- Most quests and NPCs have nothing to do with the story. Cory reviews every story character,
  quest, cutscene and line before it goes in the game.
- New characters wake on Daybreak Shore, the tutorial beach before Dawnrise Village. A girl
  (labelled "Girl on the Beach", no title) teaches the keys as games she plays with you; a key
  hint shows at the bottom of the screen for each step. Her last quest opens a one-way portal
  to the village, where she stands by Elder Rowan as "Rowan's Granddaughter". Her name is never
  shown. A faint white glow sits out on the water; nobody mentions it.
