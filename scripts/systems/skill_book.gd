class_name SkillBook
extends CharacterPart
## A character's attacks (Character.skills): the weapon's own attack, the skills they have and
## the buffs running. Job skills and buying skill levels are gone (Cory Oct 19); the innate
## attacks are always known.

## Skill id -> level known.
var learned := {}
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
	var o := c.gear.offhand()
	if not skill.offhand.is_empty() and (o == null or not o.offhand_kind in skill.offhand):
		return "%s needs %s in your off-hand slot." % [skill.display_name, " or ".join(skill.offhand.map(EquipDef.offhand_name))]
	if c.mp < skill.mp_at(level(skill)):
		return "Not enough Mana for %s." % skill.display_name
	return ""

## Starts (or refreshes) a buff from `skill`, at the character's own level of it or, for a
## party member's buff, at `lvl` (the caster's). A buff with no duration (just a heal) adds
## nothing.
func add_buff(skill: SkillDef, lvl := -1) -> void:
	if lvl < 0:
		lvl = level(skill)
	if skill.duration_ticks(lvl) <= 0:
		return
	buffs[skill.id] = [lvl, skill.duration_ticks(lvl)]
	character.recalc()

## Running buffs that keep monster hits from knocking the player back.
func steady() -> bool:
	return _any_buff(func(s: SkillDef) -> bool: return s.steady)

## Running buffs that hide the player from monsters.
func hidden() -> bool:
	return _any_buff(func(s: SkillDef) -> bool: return s.hide)

## Ends every hiding buff (attacking gives the player away). True if one was running.
func end_hiding() -> bool:
	var ended := false
	for id in buffs.keys():
		var s: SkillDef = Content.skills.get(id)
		if s and s.hide:
			buffs.erase(id)
			ended = true
	if ended:
		character.recalc()
	return ended

## The share of damage taken that comes out of MP (the strongest running guard).
func mp_guard() -> float:
	var out := 0.0
	for id in buffs:
		var s: SkillDef = Content.skills.get(id)
		if s:
			out = maxf(out, s.mp_guard_at(buffs[id][0]))
	return out

func _any_buff(test: Callable) -> bool:
	for id in buffs:
		var s: SkillDef = Content.skills.get(id)
		if s and test.call(s):
			return true
	return false

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

## Extra HP and MP restored each time HP and MP regenerate, from passives and running buffs.
func regen_bonus() -> Vector2i:
	var out := Vector2i.ZERO
	for id in learned:
		var s: SkillDef = Content.skills.get(id)
		if s and s.kind == SkillDef.Kind.PASSIVE:
			out += Vector2i(s.regen_hp_at(learned[id]), s.regen_mp_at(learned[id]))
	for id in buffs:
		var s: SkillDef = Content.skills.get(id)
		if s:
			out += Vector2i(s.regen_hp_at(buffs[id][0]), s.regen_mp_at(buffs[id][0]))
	return out
