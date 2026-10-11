class_name SkillBook
extends CharacterPart
## A character's skills: the levels learned, unspent Skill Points, the buffs running, and
## the rules for learning and using skills (Character.skills).

## Skill id -> level learned.
var learned := {}
## Unspent Skill Points.
var points := 0
## Buffs running: skill id -> [level, ticks left].
var buffs := {}

## The level the character has in a skill (innate skills are always at least 1).
func level(skill: SkillDef) -> int:
	if skill == null:
		return 0
	var n: int = learned.get(skill.id, 0)
	return maxi(n, 1) if skill.innate else n

## What the attack key does: the weapon's own attack (a bow shoots) or the plain swing.
func basic_attack() -> SkillDef:
	var w := character.gear.weapon()
	if w and w.basic_attack:
		return w.basic_attack
	return Content.skill(Character.BASIC_ATTACK)

## Why one more level of `skill` can't be learned now, or "".
func learn_problem(skill: SkillDef) -> String:
	if skill.innate or not skill.job in character.job_line():
		return "You can't learn %s." % skill.display_name
	if level(skill) >= skill.max_level:
		return "%s is already at its highest level." % skill.display_name
	if points <= 0:
		return "You have no Skill Points left."
	if skill.requires != &"":
		var need: SkillDef = Content.skills.get(skill.requires)
		if need and level(need) < skill.requires_level:
			return "Learn %s to level %d first." % [need.display_name, skill.requires_level]
	return ""

## Spends a Skill Point on `skill`. A newly learned skill goes on the first free quickslot.
## Returns why not, or "".
func learn(skill: SkillDef) -> String:
	var problem := learn_problem(skill)
	if problem != "":
		return problem
	var c := character
	points -= 1
	learned[skill.id] = level(skill) + 1
	if learned[skill.id] == 1 and skill.is_active() and c.quickslot_of(&"skill", skill.id) < 0:
		var free := c.quickslots.find([])
		if free >= 0:
			c.set_quickslot(free, &"skill", skill.id)
	c.recalc()
	return ""

## Why `skill` can't be used right now, or "".
func use_problem(skill: SkillDef) -> String:
	var c := character
	if skill == null or not skill.is_active() or level(skill) <= 0:
		return "You don't know that skill."
	if skill.innate and skill != basic_attack():
		return "You can't attack like that with this weapon."
	var w := c.gear.weapon()
	if not skill.weapons.is_empty() and (w == null or not w.weapon_kind in skill.weapons):
		return "%s needs a %s." % [skill.display_name, " or ".join(skill.weapons)]
	if skill.uses_ammo and c.gear.ammo_count() < skill.hits:
		return "You're out of %ss." % (w.ammo if w and w.ammo != &"" else &"arrow")
	if c.mp < skill.mp_at(level(skill)):
		return "Not enough MP for %s." % skill.display_name
	return ""

## Starts (or refreshes) a buff from `skill`.
func add_buff(skill: SkillDef) -> void:
	var lvl := level(skill)
	buffs[skill.id] = [lvl, skill.duration_ticks(lvl)]
	character.recalc()

## Counts buffs down by `ticks`. Returns the skills whose buffs just ran out.
func tick_buffs(ticks := 1) -> Array[SkillDef]:
	var ended: Array[SkillDef] = []
	for id in buffs.keys():
		buffs[id][1] -= ticks
		if buffs[id][1] <= 0:
			buffs.erase(id)
			var s: SkillDef = Content.skills.get(id)
			if s:
				ended.append(s)
	if not ended.is_empty():
		character.recalc()
	return ended

## What passives and running buffs add to the stats.
func bonus() -> StatBlock:
	var out := StatBlock.new()
	for id in learned:
		var s: SkillDef = Content.skills.get(id)
		if s and s.kind == SkillDef.Kind.PASSIVE:
			out.add(s.stats_at(learned[id]))
	for id in buffs:
		var s: SkillDef = Content.skills.get(id)
		if s:
			out.add(s.stats_at(buffs[id][0]))
	return out

## Extra HP and MP restored each time HP and MP regenerate, from passives.
func regen_bonus() -> Vector2i:
	var out := Vector2i.ZERO
	for id in learned:
		var s: SkillDef = Content.skills.get(id)
		if s and s.kind == SkillDef.Kind.PASSIVE:
			out += Vector2i(s.regen_hp_at(learned[id]), s.regen_mp_at(learned[id]))
	return out
