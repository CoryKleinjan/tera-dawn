class_name Character
extends RefCounted
## One character: name, level, EXP, Dawn Essence, job, stats, quickslots, inventory, storage, quests,
## Dawnshards, HP, MP, the map they're on and what they've done. Formulas live in
## CharacterStats; this only holds and changes state. Two parts keep their own state and
## rules: `skills` (SkillBook: skills bought and buffs) and `gear` (Gear: wearing gear; what's
## worn is `equipment`).
##
## The server owns the real Character of every player. Each client keeps a copy of its own
## (Game.me) that the server refreshes, so the UI can read it but never changes it directly.

## Level, gear or skills changed: anything showing stats should refresh.
signal stats_changed

## The first town: where the way out of the tutorial leads, and where you wake after fainting
## with no town nearer.
const START_MAP := &"dawnrise_village"
## Where a brand-new character starts: the tutorial beach (START_MAP if there is none).
const NEW_MAP := &"daybreak_shore"
const START_JOB := &"beginner"
## Quickslots on the HUD, each bound to a key (quick_1 ... quick_8).
const QUICKSLOTS := 8
## The innate attack bound to the attack key.
const BASIC_ATTACK := &"basic_attack"
## What a storage keeper charges to store one stack.
const STORE_FEE := 10
## The level cap: EXP stops here.
const MAX_LEVEL := 100

var name := ""
## Levels come from EXP (monsters and quests give it); each one raises power, Max HP and MP by
## the job's growth (CharacterStats).
var level := 1
var xp := 0
## Unspent Dawn Essence: monsters and quests give it, skill levels cost it.
var essence := 0
var shards := 0
var mp := 0
var map_id: StringName = START_MAP
var health := Health.new()
var job: JobDef
## The job this character advanced into `job` from (for a blend, which of its two parents),
## or empty for a job reached the usual way.
var came_from: StringName = &""
## Ids of every job this character has passed (its Job Test taken and its gifts handed over),
## so switching back to one is free.
var jobs_passed: Array[String] = []
var inventory := Inventory.new()
## Kept by storage keepers in town.
var storage := Inventory.new()
## What's worn.
var equipment := Equipment.new()
## Putting gear on and off.
var gear := Gear.new(self)
var quests := QuestLog.new()
## Skills learned and buffs running.
var skills := SkillBook.new(self)
## One per quickslot: [] (empty), ["skill", id] or ["item", id].
var quickslots: Array = []
## Everything worn plus skill bonuses. Kept up to date by recalc().
var stats := StatBlock.new()
## Names of this character's buddies (the server keeps them both ways).
var buddies: Array[String] = []
## Fame other players gave (or took). `fame_day` is the day (days since 1970) this
## character last gave fame, and `fame_given` the day they last gave each name fame.
var fame := 0
var fame_day := -1
var fame_given := {}
## The guild's name, or "". The server's guild list is the real record.
var guild := ""
## Kills and cards of every monster met.
var book := MonsterBook.new()
## The pet that's out (a PetDef id, or empty) and how full it is (0 to 100).
var pet: StringName = &""
var pet_full := PetDef.FULL
## Every map visited, for the world map and achievements.
var visited: Array[String] = []
## Achievement ids reached (see Achievements).
var achievements: Array[String] = []
## Tallies achievements count that aren't kept anywhere else, by Counters name.
var counters := {}
## Cutscene ids already watched (or skipped), so none plays twice.
var scenes_seen: Array[String] = []
## Secrets found, for good: shortcuts opened, walls broken and chests opened (their ids).
var secrets: Array[String] = []
## Boss relics picked up (RelicDef ids): each one's move is unlocked for good.
var relics: Array[String] = []

func _init() -> void:
	equipment.changed.connect(recalc)
	quickslots.resize(QUICKSLOTS)
	quickslots.fill([])

## A fresh character of `job_id` with the job's starting gear and items, and
## the outfit picked in the character creator (`made`, null for the defaults).
static func create(char_name: String, job_id := START_JOB, made: NewCharacter = null) -> Character:
	var c := Character.new()
	c.name = char_name
	c.job = Content.job(job_id)
	if made == null:
		made = NewCharacter.new(job_id)
	for e in made.starting_gear(c.job):
		c.equipment.put(c.equipment.place_for(e), ItemStack.exact(e))
	for entry in c.job.starting_items:
		var n := entry.roll()
		if n > 0:
			c.inventory.add(entry.item, n)
	c.put_starting_quickslots()
	c.recalc()
	c.refill()
	c.map_id = NEW_MAP if Content.maps.has(NEW_MAP) else START_MAP
	return c

## Works out the total stats again after the level, gear or skills change.
func recalc() -> void:
	if job == null:
		return
	stats = equipment.bonus()
	stats.add(skills.bonus())
	health.set_max(max_hearts())
	mp = mini(mp, max_mp())
	stats_changed.emit()

## Full hearts and MP.
func refill() -> void:
	health.reset(max_hearts())
	mp = max_mp()

## How many hearts this character has (their health counts hearts, see CharacterStats).
func max_hearts() -> int:
	return CharacterStats.max_hearts(job, level, stats)

func max_mp() -> int:
	return CharacterStats.max_mp(job, level, stats)

## What damage grows from: the job's power at this level plus the Monster Book's rank.
func power() -> int:
	return CharacterStats.power(job, level) + book.power_bonus()

func damage_range() -> Vector2i:
	return CharacterStats.damage_range(job, power(), stats)

func magic_range() -> Vector2i:
	return CharacterStats.magic_range(job, power(), stats)

func magic_attack() -> int:
	return CharacterStats.magic_attack(stats, power())

func avoid() -> int:
	return CharacterStats.avoid(job, level, stats)

## EXP needed to go from level `lvl` (this character's own by default) to the next.
func xp_need(lvl := -1) -> int:
	return CharacterStats.xp_need(level if lvl < 0 else lvl)

## Whether the character is at MAX_LEVEL, where EXP stops.
func at_max_level() -> bool:
	return level >= MAX_LEVEL

## Adds EXP and returns how many levels were gained; each level up refills HP and MP. At
## MAX_LEVEL EXP stops (kept at 0).
func gain_xp(n: int) -> int:
	if at_max_level():
		xp = 0
		return 0
	xp += maxi(0, n)
	var gained := 0
	while not at_max_level() and xp >= xp_need():
		xp -= xp_need()
		level += 1
		gained += 1
	if at_max_level():
		xp = 0
	if gained > 0:
		recalc()
		refill()
	return gained

## Adds Dawn Essence (from a monster or a quest).
func gain_essence(n: int) -> void:
	essence += maxi(0, n)

func spend_mp(n: int) -> bool:
	if mp < n:
		return false
	mp -= n
	return true

func restore_mp(n: int) -> void:
	mp = clampi(mp + n, 0, max_mp())

# ---------- what they've done ----------

## Adds to one of the achievement tallies (a Counters name).
func count(kind: String, n := 1) -> void:
	counters[kind] = int(counters.get(kind, 0)) + n

## Notes a map as visited. True the first time.
func visit(id: StringName) -> bool:
	if visited.has(String(id)):
		return false
	visited.append(String(id))
	return true

## Whether this character has already watched (or skipped) cutscene `id`.
func has_seen(id: StringName) -> bool:
	return scenes_seen.has(String(id))

## Notes cutscene `id` as watched.
func saw(id: StringName) -> void:
	if not has_seen(id):
		scenes_seen.append(String(id))

## Whether this character has found secret `id` (a shortcut, a wall or a chest).
func found_secret(id: StringName) -> bool:
	return secrets.has(String(id))

## Notes secret `id` as found. True the first time.
func find_secret(id: StringName) -> bool:
	if found_secret(id):
		return false
	secrets.append(String(id))
	return true

## The relic that unlocked move `m` (RelicDef.Move), or null while it's still locked.
func relic_for(m: RelicDef.Move) -> RelicDef:
	for id in relics:
		var r := Content.items.get(StringName(id)) as RelicDef
		if r and r.move == m:
			return r
	return null

func has_move(m: RelicDef.Move) -> bool:
	return relic_for(m) != null

func has_relic(r: RelicDef) -> bool:
	return relics.has(String(r.id))

## Picks up relic `r`, unlocking its move. True the first time.
func learn_relic(r: RelicDef) -> bool:
	if has_relic(r):
		return false
	relics.append(String(r.id))
	return true

## The pet that's out, or null.
func pet_def() -> PetDef:
	return Content.items.get(pet) as PetDef

# ---------- quickslots ----------

## Puts a skill or an item (`kind` "skill" or "item") on quickslot `i`, or clears it with
## an empty kind. A skill or item already on another slot swaps with what's here.
func set_quickslot(i: int, kind: StringName, id: StringName) -> void:
	if i < 0 or i >= QUICKSLOTS:
		return
	if kind == &"":
		quickslots[i] = []
		return
	var before := quickslot_of(kind, id)
	if before >= 0:
		quickslots[before] = quickslots[i]
	quickslots[i] = [kind, id]

## The quickslot holding this skill or item, or -1.
func quickslot_of(kind: StringName, id: StringName) -> int:
	for i in QUICKSLOTS:
		var q: Array = quickslots[i]
		if q.size() == 2 and StringName(q[0]) == kind and StringName(q[1]) == id:
			return i
	return -1

## Puts the job's starting items (JobDef.starting_quickslots) on the last quickslots.
func put_starting_quickslots() -> void:
	var items := job.starting_quickslots
	for i in items.size():
		set_quickslot(QUICKSLOTS - items.size() + i, &"item", items[i].id)

# ---------- storage ----------

## Puts bag slot `i` of `tab` into storage. Returns why not, or "".
func store(tab: int, i: int) -> String:
	var stack := inventory.at(tab, i)
	if stack == null:
		return ""
	if stack.item.quest_item:
		return "Quest items can't be stored."
	if shards < STORE_FEE:
		return "Storing costs %d Dawnshards." % STORE_FEE
	if not storage.has_room(stack.item, stack.count):
		return "Your storage is full."
	shards -= STORE_FEE
	inventory.take(tab, i)
	storage.add_stack(stack)
	return ""

## Takes storage slot `i` of `tab` back into the bag. Returns why not, or "".
func retrieve(tab: int, i: int) -> String:
	var stack := storage.at(tab, i)
	if stack == null:
		return ""
	if not inventory.has_room(stack.item, stack.count):
		return "Make room in your %s inventory first." % ItemDef.TAB_NAMES[tab]
	storage.take(tab, i)
	inventory.add_stack(stack)
	return ""

# ---------- jobs ----------

## The jobs this character has been, newest first: their job, the one they advanced from
## (`came_from` for a blend), and so on back to the Beginner.
func job_path() -> Array[StringName]:
	var out: Array[StringName] = []
	var j := job
	while j and not j.id in out:
		out.append(j.id)
		var back := came_from if j == job and j.opens_from(came_from) else j.advances_from
		j = Content.jobs.get(back)
	return out

## The jobs whose skills this character may learn: every job on their path, plus for a blend
## the other parent job (a Warrior who becomes a Spellblade learns Magician skills too).
func job_line() -> Array[StringName]:
	var out := job_path()
	for id in out.duplicate():
		var j: JobDef = Content.jobs.get(id)
		if j == null:
			continue
		for parent in j.parents():
			if not parent in out:
				out.append(parent)
	return out

## Whether this character has passed `j` before (see jobs_passed).
func has_passed(j: JobDef) -> bool:
	return jobs_passed.has(String(j.id))

## Whether a tutor teaching `next` would offer it: a first job to anyone past the Beginner
## (switching from another first job or a blend), a blend to one of its parents, and any job
## passed before.
func can_become(next: JobDef) -> bool:
	if next == job or next.is_starting_job():
		return false
	return next.tier() == 1 or next.opens_from(job.id) or has_passed(next)

## The skills this character would lose by becoming `next` (those outside its JobDef.line).
func skills_lost_by(next: JobDef) -> Array[SkillDef]:
	return skills.outside(next.line())

## Why the character can't become `next`, or "" if they can.
func advance_problem(next: JobDef) -> String:
	if next == job:
		var article := "an" if next.display_name.substr(0, 1).to_lower() in ["a", "e", "i", "o", "u"] else "a"
		return "You're already %s %s." % [article, next.display_name]
	if not can_become(next):
		return "A %s can't become a %s." % [job.display_name, next.display_name]
	if has_passed(next):
		return ""
	if next.advance_quest and not quests.done.has(next.advance_quest.id):
		return "Pass the %s first." % next.advance_quest.title
	var full := inventory.tab_without_room(next.advance_gifts.map(func(g: DropEntry) -> Array: return [g.item, 1 if g.item is EquipDef else g.min_amount]))
	if full >= 0:
		return "Make room in your %s inventory first." % ItemDef.TAB_NAMES[full]
	return ""

## Becomes `next` (see advance_problem). The skills of the old job that `next` can't use go,
## and the Dawn Essence paid for them comes back; stats stay. The first time, it receives the
## job's gifts. Returns why not, or "".
func advance(next: JobDef) -> String:
	var problem := advance_problem(next)
	if problem != "":
		return problem
	var first_time := not has_passed(next)
	came_from = job.id if next.partner != &"" and next.opens_from(job.id) else &""
	job = next
	skills.forget_outside(next.line())
	if first_time:
		jobs_passed.append(String(next.id))
		for g in next.advance_gifts:
			if g.item is EquipDef:
				inventory.add_stack(ItemStack.unrolled(g.item, 1))
			elif g.item:
				inventory.add(g.item, g.min_amount)
	recalc()
	_wear_advance_weapon(next)
	refill()
	return ""

## Wears the first weapon among `next`'s gifts when the one worn isn't made for the new job
## (the Beginner's Training Sword), so a new Magician casts with the wand just handed over.
## A weapon of the job's own line that the player found stays on. The same goes for an
## off-hand among the gifts (a Thief's stars, a Pirate's pistol) in the off-hand slot.
func _wear_advance_weapon(next: JobDef) -> void:
	for slot in [EquipDef.Slot.WEAPON, EquipDef.Slot.SHIELD]:
		var worn := gear.weapon() if slot == EquipDef.Slot.WEAPON else gear.offhand()
		if worn and next.wear_families().any(func(f: StringName) -> bool: return f in worn.jobs):
			continue
		for g in next.advance_gifts:
			var e := g.item as EquipDef
			if e and e.slot == slot and _wear_from_bag(e):
				break

## Wears `e` from the bag. False when it isn't there.
func _wear_from_bag(e: EquipDef) -> bool:
	for i in Inventory.SLOTS:
		var s := inventory.at(ItemDef.Tab.EQUIP, i)
		if s and s.item == e:
			gear.equip(i)
			return true
	return false

## Everything about the character, for the save file and for sending to its client (see
## CharacterCodec).
func to_dict() -> Dictionary:
	return CharacterCodec.to_dict(self)

## Loads what to_dict() wrote. Missing or bad values keep the current ones, so older saves
## still load.
func load_dict(data: Dictionary) -> void:
	CharacterCodec.load_dict(self, data)
