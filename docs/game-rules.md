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

- The hero is a chibi boy (`art/reference/hero.png`) painted in layers, MapleStory style: one
  body sheet (bald, blank face, mitten fists), and his face, hair and each piece of gear painted
  over a flat green silhouette of it so they land in place on every frame.
- Gear is painted whole on every frame: no holes, gaps, notches or bites where an arm, hand or
  leg crosses it, nothing cut off flat, and both shoes or boots on every pose (sitting and lying
  down too). On climbing and back frames he faces away, so gear shows its BACK: no buttons,
  buckles, clasps, collar stars, flies, knee patches or toe caps. Every gear prompt says both
  rules in plain words, names the cells seen from behind, and every result is checked frame by
  frame on a flat colour before it goes in; a hole is fixed by repainting that piece alone on
  plain magenta. A helmet, hat, shield or tome
  is one painting pinned to his head or hand on every frame (separate paints only where his head
  turns). The weapon is one painting held in his near fist; the shield or tome is in his far
  hand and only shows while the weapon does. Where each sits, its turn and its layer on every
  frame are set by hand in the pose editor.
- Draw order, back to front: off-hand (shield), cape, body, trousers, shoes, tome, top, gloves,
  face, hair (hidden under helmets), hat, weapon, then his fists over its grip. In the pose editor
  any piece (his body, face, hair, fists, each piece of gear) can be moved, turned, resized and
  moved up or down the stack on any frame; nothing is repainted or cut for it. Prefer shrinking
  to growing: a piece drawn bigger than painted looks softer.
- Every piece of gear has frames for every pose in the game, whatever its job: every job's
  attack (swing, bow, pistol, throw, cast) and every skill pose added later. A new body pose
  means new frames for all gear.
- His arms, fists and held weapons never cover his face, in any pose; both fists show. Blink
  has no pose of its own: he just vanishes and reappears.
- Animations are shared across similar actions (one swing for all melee, one cast for all
  spells); his walk is 4 steps, slow. Melee attacks play one 2-frame swing (swing2, swing3) with the weapon
  only turning in the picture, never edge-on.
- Male only for now.

## Movement and combat feel

- A bit metroidvania, like Hollow Knight: the hero starts and stops at once, steers freely in the
  air, hops short when jump is let go early and falls faster than he rises. A full jump keeps its
  height, so every map stays reachable.
- He walks, never runs, and walks 15% faster after about 0.4 s of moving. No jump sound.
- No dash for the hero: each job has its own movement skill instead. Warrior Charge (a lunge
  that only shoves monsters aside, no damage; once per jump in the air too), Thief Flash Jump (a
  second jump in mid-air), Magician Blink (a teleport the held way, up and down too), Archer
  Backstep Leap (springs back still facing ahead), Pirate Rolling Dash (a low roll on the ground
  nothing can hit). Beginners have none. Their effects are code-drawn stand-ins until painted
  ones are made with Gemini in the same look as every other skill effect.
- Attacks and most attack skills aim: up hits overhead, down (in the air only) hits below. Buffs
  don't aim. A downward melee blow that meets a monster bounces him off it (pogo).
- He can move while swinging and keeps facing the swing until it ends. Buffs and spells make no
  swing: he carries on with what he was doing.
- Holding attack keeps swinging, and a press made just before he can swing again goes off
  when he can (no lost presses). A hit flashes the monster white once.
- Melee hits feel heavy: longer hit-stop (he and the monster both hold still), a small push back on him, a harder knockback on the
  monster, a camera kick on crits and kills. Ranged hits (arrows, stars, bullets, spells) stay
  light.
- Getting hit freezes him a beat, flashes the screen and knocks him away without steering.
- No chairs: the Sit key sits him on the ground, where he regains HP and MP twice as fast (the
  base part). Moving, the Sit key again or any monster hit gets him up.
- An aimed attack turns its swing effect up or down.
- Job skills will be flashy and grand, like MapleStory.

## Jobs, stats and skills

- There are no levels anywhere. Monsters drop Dawn Essence when they die and it flies to the hero
  (quests pay it too). It is spent anywhere, in the stats window on stat points and in the skill
  window on skill levels; each point in a stat costs more than the last one in that stat, and
  each skill level more than the last skill level bought. Every stat point bought also adds a
  little Max HP and MP. Fainting loses 10% of the unspent essence, with no way to win it back.
  The HUD and menus call it "Dawn Essence".
- Each first job has one stat that drives its damage, and no other stat adds to it: Warrior STR,
  Magician INT, Thief LUK, Archer DEX, Pirate CHA (Charisma). Gear asks only for the job's own
  stat; Auto spends essence on that stat.
- What each stat also gives as it grows: STR Max HP, INT Max MP, DEX Accuracy, LUK Avoidability,
  CHA slightly lower shop prices (capped) and more Dawnshards found.
- A first job has seven skills: a movement skill, a quick single-target attack, a crowd attack, a
  self buff, a party buff (reaches party members nearby), a passive and a monster-control skill.
  Skill levels get dear quickly, so players choose what to leave unmaxed.
- Monster control, one per job, made to combo: Warrior Skyward Cleave throws monsters in front
  into the air; Magician Gravity Well pulls airborne monsters down, then hits every grounded one
  around; Thief Shadow Ambush blinks into the biggest group ahead (ground or air) and stuns it;
  Archer Pinning Shot pins one monster in place, even in mid-air; Pirate Anchor Haul drags
  monsters in a line back to the hero. Thrown or stunned monsters can't move, attack or hurt by
  touch. Every one deals damage. Bosses take the damage but are never thrown, dragged or stunned.
- First-job tutors open when the hero reaches their town, with no stat requirement and no stat
  reset; each job is taken by passing its Job Test once, and switching back to a job already
  passed is free (its gifts come only the first time). Switching jobs at any tutor
  that offers one drops the old job's skills and refunds the essence spent on them; stats stay.
- Second tier: every first job picks one of two blends of itself and another first job:
  Spellblade (Warrior + Magician), Hexcaster (Magician + Thief), Swashbuckler (Thief + Pirate),
  Sharpshooter (Pirate + Archer), Wildhunter (Archer + Warrior). A blend is the same job from
  either side. It keeps its own first-job skills and opens all of the other job's first-job
  skills; it has no skills of its own (its draw is combining the two jobs). Both stats add
  together for damage (no averaging); Auto buys both, the cheaper first. It wields every weapon and off-hand of both jobs.
  Second- and third-tier jobs open when the hero beats a set boss, found through the tears,
  while one of the parent jobs. Which tutor teaches them and which boss opens each wait on
  the story.
- Every job is built to attack and be fun solo: no tank or healer jobs.
- No job is shown or named to the player until they can choose it: no menu, list, tooltip,
  quest or NPC line hints at a later job before then. The one exception: Beginners hear the
  five first jobs named.
- Third tier (planned): each blend splits into two jobs, each leaning into one of its
  two parents: Spellblade into Bladecaller (Warrior) or Runeblade (Magician), Hexcaster into
  Warlock (Magician) or Nightweaver (Thief), Swashbuckler into Cutthroat (Thief) or Dread
  Pirate (Pirate), Sharpshooter into Gunslinger (Pirate) or Hawkeye (Archer), Wildhunter into
  Stalker (Archer) or Berserker (Warrior). It joins no new job: it keeps both parents' skills
  and weapons (no two-handed weapons), both stats still add evenly, and it adds four skills of
  its own that differ by lean: three skills and one ultimate that hits a very large area.
- There is no Harbinger job: the harbinger is only a story reveal.
- Off-hand slot (once the Shield slot): Warriors and Beginners wear a shield, a Thief throwing
  stars (with a dagger in hand), a Magician a book, an Archer a quiver worn on the back, a Pirate a pistol (with a scimitar). Stars
  and pistols never run out. A Thief's dagger hits one monster and the stars hit a crowd; a
  Pirate's scimitar hits one and the pistol a crowd.

## Gear

- Gear is drawn on the hero (see Hero) but has no icons yet: a slot shows an item's name in
  place of its icon. Each first job has a
  starter armor set (hat, top, trousers, shoes; that job and its blends only), sold in its
  town's shop: Warrior Squire set (Emberforge), Magician Novice set (Lumewood), Thief Footpad set
  (Lanternfall), Archer Hunter's set (Greenbough), Pirate Deckhand set (Driftcove). Tests still
  bring their own plain gear (`tests/fixtures/gear`) for what the game doesn't have yet.

## Weapons

- No ammo for any weapon. Claws were dropped; thieves use a dagger and throwing stars.
- Shops sell only basic weapons; better weapons come from monster drops.

## Maps and scenery

- Map names show only at the top of the screen; nothing labels a map in the world.
- Every piece of land is walkable: no arches or floating rock islands, nothing that looks like
  ground but isn't. No two exits of a map lead to the same map. Maps can be wide and multi-level.
- A zone's fields are a web you can loop through, stacked like Hollow Knight's (canopy above,
  roots below), each with 2 to 4 exits; Greenbough is the pilot. Shortcuts open one way until
  you find them, then work both ways; a breakable wall opens one.
- Every field has two secret ledges only a job's movement skill reaches: a high one (Flash Jump,
  Blink) and a far one across a gap (every movement skill). Each holds a chest a character opens
  once (shards, potions, a 60% scroll, a local Monster Book card). Secret ledges and shortcuts
  stay off the minimap and world map.
- Characters, NPCs, ropes and ladders draw in front of land; characters cast no shadows. Portals draw in front of land and
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
- Sizes next to the hero (he stands about 88 game px): every door is about 1.2 heroes (Dawnharbor's
  tavern), grown-up townsfolk about 1 hero and kids a little less, a barrel about 0.6 and a lamp
  post 1.5 to 1.9. A building that misses is recut whole from its painting at the right size
  (its manifest's `art_px` and its `height`), never stretched.
- No houses in monster maps unless a quest needs one or Cory asks. Shops are proper full-size
  buildings.
- Backdrops: one high-quality, sharp picture for the whole background, not strips. Dawnharbor's 4K
  panorama is the template. Clouds drift in front of it.
- Fields look clean, like Hollow Knight's (Greenbough is the pilot): land with one clean grassy edge
  over plain earth, no tufts or plants strewn along it, few floor plants, and dark leaves framing
  the screen's top corners. A breakable wall is gone once smashed.
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
- **In game**: the content tests check the town has its buildings, shop and storage keeper, its
  building pictures are its own, its NPCs have their own names and stand mid-platform, and its
  ladders stay clear of platform ends.

## Monsters

- Two or three monster kinds per map (a boss counts as one). Each kind belongs to one zone unless
  Cory says otherwise. A monster taken out of a zone stays in the files.
- No levels are shown anywhere: no "Lv." on monsters, bosses, maps, regions, the Monster Book,
  quests, gear or trips. Monsters, maps and quests keep a hidden tuning tier (MonsterDef.level,
  the "Lv. a-b" level_text) only so content tests keep the zones in order.
- Monster strength: each kind's own HP, attack and Dawn Essence are what it is on the map nearest
  a town that it lives on; on each map farther from the nearest town than that it is 15% stronger
  (HP, attack and essence). Shortcuts don't count toward that distance. Bosses keep their own
  numbers.
- The paths players walk between towns stay gentle (tuning tier 10 or below) the whole way, so new
  players can reach every job town. Dead-end training branches climb in smooth steps to a boss
  past the top map.
- A boss fights alone in an arena: a small map about 1.3 screens wide past its zone's top map, no
  other monsters. Beating it opens a one-way portal there home to the zone's town.
- Monsters target a player who comes in sight (the first fields' monsters only up close) or hits them, and
  give up a few seconds after losing sight. Every monster has one or two moves and every boss
  three different ones; each move winds up with a glow first so it can be dodged. Moves reuse
  the monster's own frames (the attack pose plus motion).
- Bosses are about 1.5x a normal monster of their kind, not bigger. They fight smarter: the move
  that fits the distance, in a set order players can learn, aim where the player is heading,
  leap to the player's platform, chain a charge or pounce into a slam, and get a second wind at
  half HP (faster, each move followed straight away by the next). In co-op they go for whoever has hurt them most lately.
- Bosses look and move a step above normal monsters: each move has a two-frame wind-up, a
  two-frame strike and a recovery pose; they roar an intro when they first see a player and
  roar again at their second wind; their defeat is a painted fall (hit pause, collapse, embers
  fading) rather than a quick poof. Molten King has this first; the others follow as painted.
- Monster HP is 40% lower than first tuned, so fights stay quick.

## UI

- Painted travel leather and parchment. No fake stitching; the close X fits the style; the minimap
  frame matches the bottom bar.
- Monster HP bars have no dragon emblem. Quest marks are a painted "!", "?" and three dots.
- The equipment window lays its slots out like a person (hat on top, shoes at the bottom), with
  what the gear adds beside them.
- No clouds on the title screen.
- The world map shows towns always and a field only once visited (as "???" before).
- Playing solo, the chat box shows only the last few lines, briefly; achievements are solo goals.
- No controls box on screen, in towns or fields: the tutorial teaches the keys (its step hints
  show at the bottom), and the full list is in Settings > Controls.
- Everything works on a gamepad (the Steam Deck). Holding the left trigger turns to quickslots
  4-8 (Y, RB, LB, RT, B), Back opens a window menu, and with a window open a pad cursor stands
  in for the mouse (A click and drag, X right-click, Y double-click, B closes). Key hints name
  the pad's buttons while it's in use.
- Skill icons are painted NPC-style badges: one bold subject (no people for Shoulder Bash or
  Rolling Dash) in a thick rounded frame of the job's colour: Beginner warm brown, Warrior
  crimson, Magician blue, Thief charcoal black with silver trim, Archer green, Pirate gold.

## Audio and travel

- Every town, field and boss map plays its zone's music: one town track, one field track and one
  cinematic, dangerous boss track per zone. Lanternfall sounds like a thieves' den.
- Music feels grown-up, never childish (Hollow Knight's spirit): towns, fields and the title are
  ambient; bosses are cinematic. Each zone keeps its own tone (`docs/zone-vibes.md`).
- Kenney CC0 sound effects; the jingles stay.
- Captain Marlo's ship carries players from the start island to Dawnharbor; coachman Rook takes them
  to the job towns (400-500 Dawnshards, the same for everyone), but coaches only go to towns the
  player has already been to; the towns are also joined by a ring
  of portals. Developer test characters start in their job's town.
- Not an MMO: no accounts, usernames or passwords. Play leads to Solo or Co-op; Co-op leads to Host
  (UDP 7350, shows the LAN address with Copy) or Join (`address:port`). Up to 4 players counting the
  host; each brings a character saved on their own computer, and their progress saves there.

## Story

- The world is Morrowmere. The main story (Tera and the Dawn curse) stays hidden until well past
  today's content: no in-game text names Tera's Dawn, the curse or the other dawns before
  the story reveals them, and nobody knows what Dawnshards really are at first. The tears are
  only called that (a tear or rip in the air) from the first Job Test on.
- Most quests and NPCs have nothing to do with the story. Cory reviews every story character,
  quest, cutscene and line before it goes in the game.
- New characters wake on Daybreak Shore, the tutorial beach before Dawnrise Village. A girl
  (labelled "Girl on the Beach", no title) teaches the keys as games she plays with you; a key
  hint shows at the bottom of the screen for each step. Her last quest opens a one-way portal
  to the village, where she stands by Elder Rowan as "Rowan's Granddaughter". Her name is never
  shown. A faint white glow sits out on the water; nobody mentions it.
- Each first-job tutor gives a Job Test before advancing: a short course on the town's Trial
  Ground, fought alone (every player gets their own copy, even in co-op). At the far end a tear
  opens and one boss, the same for all five jobs (a hulking beast of pale starlit stone), steps
  out. Beating it and handing the test in makes you that job; the tutor sends you to Archmage
  Celest in Lumewood (Magicians are already with her).
