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

- The hero is being rebuilt as a new paperdoll from the reference (`art/reference/hero.png`) in
  the NPC style: white tee and grey shorts as the base, the reference face, hands with fingers.
  The old hero stays in game until the new one is approved.
- Chibi proportions, drawn about 13% larger than the first cut.
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
- Third tier (Lv 50, planned): five jobs, each joining two blends that share no first job, so
  each cares about four stats. It uses every weapon of its four first jobs plus its own
  two-handed weapon, opens every skill of those four jobs and both blends, and adds one
  ultimate skill that hits a very large area and a huge number of monsters.
- Max level is 100.
- Off-hand slot (once the Shield slot): Warriors and Beginners wear a shield, a Thief throwing
  stars (with a dagger in hand), a Magician a book, an Archer a quiver worn on the back, a Pirate a pistol (with knuckles). Stars
  and pistols never run out. A Thief's dagger hits one monster and the stars hit a crowd; a
  Pirate's fists hit one and the pistol a crowd.

## Gear

- The game has no equipment for now: every item, icon and worn picture was removed to be redrawn
  for the new hero (2026-10-13). The equipment system (slots, the equip window, stats) stays, and
  the tests bring their own plain gear (`tests/fixtures/gear`).
- An item's icon and its worn or held look are the same object: shape, colours and details. Worn
  gear is cut the same way the icons are, keeps their detail, uses the hero's near-black outline,
  and is never cut off.
- Every piece of gear is its own layer on the paperdoll.

## Hats and hair

- Hats fit the MapleStory way: sized to the whole head and hair, face open, lined up with the eyes.
  Helmets have a low dome and the nose guard reaches down between the eyes. No part of the head
  pokes out the side.
- Hats and hoods end at the neck: no cape or cloth over the back (cloaks are their own item).
- Hoods have an open face. Bandanas sit low on the brow and stay small.
- Two hairstyles for now: tousled (boy) and ponytail (girl).
- Hair is slightly wider than the head. Keep the forehead bangs; trim floating bits and tufts that
  hang past the front of the face; no hair near the mouth.
- Hair under hats follows Cory's template sheets, one per hairstyle with a cell for every hat type
  (`boy_tousled.png`, `girl_ponytail.png` in the project's `references/hat-hair-templates/`):
  the painted hair in each cell is how that hairstyle looks under that hat. The girl's short tail hangs below each hat behind her neck (none
  under the hood); under a helmet her hair hangs down behind her shoulders and never sticks up or
  out. A new hairstyle needs a template with every hat type; a new hat type needs a cell for every
  hairstyle. No seam between hat and hair.
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
  picture. There is no Free Market and no player shops.
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
