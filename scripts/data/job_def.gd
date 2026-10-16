class_name JobDef
extends Resource
## A job (class): which stats drive its damage, how HP and MP grow, what a new character
## of this job starts with, and how a character advances into it. Add a job by saving a
## JobDef in data/jobs/.
##
## Everyone starts as a Beginner (`advances_from` empty). A job instructor (an NpcDef that
## `instructs` this job) advances a character from `advances_from`.
##
## A second-tier job is a blend of two first jobs: `advances_from` and `partner`. Either one can
## advance into it, both their skill books open to it, both their stats drive its damage and
## it wears both their gear.

@export var id: StringName
@export var display_name := ""
@export_multiline var description := ""
## The job line it belongs to (warrior, archer, mage, thief, pirate, beginner). Gear that
## names a line can be worn by every job in it.
@export var family: StringName
## The job's colour, for the places that show jobs (the hero now wears his job's gear instead).
@export var tint := Color.WHITE
## The one stat that drives the job's damage (STR for warriors). No other stat adds to it.
@export_enum("strength", "dexterity", "intelligence", "luck", "charisma") var primary_stat := "strength"
## A second stat that drives damage as much as `primary_stat` (a blend's partner stat): the
## two are added together. Empty: only `primary_stat`.
@export var secondary_stat: StringName
## Hit with whichever base stat is highest instead of `primary_stat`, so any build works
## (the Beginner, who hasn't picked a path yet).
@export var uses_best_stat := false
## The lowest hit as a fraction of the highest (MapleStory's mastery).
@export_range(0.1, 0.95) var mastery := 0.6

@export_group("Growth")
@export var base_hp := 50
## Max HP gained for every CharacterStats.GROWTH_POINTS stat points bought with Dawn Essence.
@export var hp_growth := 14
@export var base_mp := 20
## Max MP gained for every CharacterStats.GROWTH_POINTS stat points bought.
@export var mp_growth := 6

@export_group("Advancement")
## The job you advance from (empty: you start as this job).
@export var advances_from: StringName
## For a blend, the other first job that can advance into it too. Its skills open to this job
## and its gear fits.
@export var partner: StringName
## Base stats (STR, DEX, INT, LUK, before gear) needed to advance.
@export var advance_requirements: StatBlock
## A quest to hand in first (the job tutor's test). Handing it in advances you right away
## when nothing else stands in the way (ServerQuests.on_quest_complete).
@export var advance_quest: QuestDef
## Items handed over when advancing (each gives `min_amount`): the job's basic weapon (the
## first weapon here is worn right away, see Character.advance), and potions.
## Better weapons only drop.
@export var advance_gifts: Array[DropEntry] = []

@export_group("New character")
@export var starting_stats: StatBlock
## Worn from the start.
@export var starting_gear: Array[EquipDef] = []
## Put in the inventory at the start; each entry is rolled once (use chance 1).
@export var starting_items: Array[DropEntry] = []
## Items put on the last quickslots, in order, so a new player has potions on a key.
@export var starting_quickslots: Array[ItemDef] = []
## The outfit pieces the character creator offers a new character of this job, any kinds of
## gear; the creator lets them pick one of each kind (see NewCharacter).
@export var creator_gear: Array[EquipDef] = []

## The stat behind weapon damage for these `total` stats: `primary_stat`, or with
## `uses_best_stat` the highest base stat (`primary_stat` wins ties).
func damage_stat(total: StatBlock) -> StringName:
	var main := StringName(primary_stat)
	if uses_best_stat:
		for stat in StatBlock.BASE:
			if total.value(stat) > total.value(main):
				main = stat
	return main

## What advancing takes, as readable lines ("35 STR").
func requirement_lines() -> PackedStringArray:
	var out := PackedStringArray()
	if advance_requirements:
		for stat in StatBlock.BASE:
			var n := advance_requirements.value(stat)
			if n > 0:
				out.append("%d %s" % [n, StatBlock.LABELS[stat]])
	return out

## "Apprentice Wand, 30 Blue Potion": the advance gifts, for the message on advancing.
func gifts_text() -> String:
	var parts := PackedStringArray()
	for g in advance_gifts:
		if g.item:
			parts.append(g.item.display_name if g.item is EquipDef or g.min_amount <= 1 else "%d %s" % [g.min_amount, g.item.display_name])
	return ", ".join(parts)

## Whether this is a starting job (Beginner): one you don't advance into.
func is_starting_job() -> bool:
	return advances_from == &""

## 0 for the Beginner, 1 for a first job, 2 for a blend (a job with a `partner`).
func tier() -> int:
	if is_starting_job():
		return 0
	return 2 if partner != &"" else 1

## The jobs a character of job `from` can advance into, by tier and then name, so lists
## of them read the same everywhere.
static func paths_from(from: StringName) -> Array[JobDef]:
	var out: Array[JobDef] = []
	for j: JobDef in Content.jobs.values():
		if j.opens_from(from):
			out.append(j)
	out.sort_custom(func(a: JobDef, b: JobDef) -> bool:
		return a.display_name < b.display_name if a.tier() == b.tier() else a.tier() < b.tier())
	return out

## The stats that drive damage: `primary_stat`, and `secondary_stat` when it has one.
func damage_stats() -> Array[StringName]:
	var out: Array[StringName] = [StringName(primary_stat)]
	if secondary_stat != &"" and secondary_stat != StringName(primary_stat):
		out.append(secondary_stat)
	return out

## What damage is worked out from: `damage_stat` for one-stat jobs, or both stats added
## together for a blend, so a point in either is worth the same.
func damage_stat_value(total: StatBlock) -> int:
	if uses_best_stat:
		return total.value(damage_stat(total))
	var out := 0
	for stat in damage_stats():
		out += total.value(stat)
	return out

## The jobs that can advance into this one: `advances_from`, and `partner` for a blend.
func parents() -> Array[StringName]:
	var out: Array[StringName] = []
	if advances_from != &"":
		out.append(advances_from)
	if partner != &"" and partner != advances_from:
		out.append(partner)
	return out

## Whether a `from` character can advance into this job.
func opens_from(from: StringName) -> bool:
	return from != &"" and from in parents()

## The job lines whose gear this job can wear: its own, and for a blend its parents' too.
func wear_families() -> Array[StringName]:
	var out: Array[StringName] = [family]
	if partner != &"":
		for id in parents():
			var j: JobDef = Content.jobs.get(id)
			if j and not j.family in out:
				out.append(j.family)
	return out

## "Warrior: Level 10, 35 STR", for lists of the paths open to a Beginner.
func path_line() -> String:
	return "%s: %s" % [display_name, ", ".join(requirement_lines())]
