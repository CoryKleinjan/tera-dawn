class_name JobDef
extends Resource
## A job (class): what a new character of this job starts with, the gear it wears and how a
## character advances into it. Add a job by saving a
## JobDef in data/jobs/.
##
## Everyone starts as a Beginner (`advances_from` empty). A job instructor (an NpcDef that
## `instructs` this job) advances a character from `advances_from`.
##
## A second-tier job is a blend of two first jobs: `advances_from` and `partner`. Either one can
## advance into it, and it wears both their gear.

@export var id: StringName
@export var display_name := ""
@export_multiline var description := ""
## The job line it belongs to (warrior, archer, mage, thief, pirate, beginner). Gear that
## names a line can be worn by every job in it.
@export var family: StringName

@export_group("Advancement")
## The job you advance from (empty: you start as this job).
@export var advances_from: StringName
## For a blend, the other first job that can advance into it too. Its gear fits.
@export var partner: StringName
## A quest to hand in the first time (the job tutor's Job Test). Handing it in advances you
## right away when nothing else stands in the way (ServerQuests.on_quest_complete); a job
## passed once is free to switch back to.
@export var advance_quest: QuestDef
## Items handed over when advancing (each gives `min_amount`). A weapon listed here
## would be worn right away (see Character.advance); gear comes from vendors and secrets.
@export var advance_gifts: Array[DropEntry] = []

@export_group("New character")
## Worn from the start.
@export var starting_gear: Array[EquipDef] = []
## Put in the inventory at the start; each entry is rolled once (use chance 1).
@export var starting_items: Array[DropEntry] = []
## Items put on the last quickslots, in order, so a new player has them on a key.
@export var starting_quickslots: Array[ItemDef] = []
## The outfit pieces the character creator offers a new character of this job, any kinds of
## gear; the creator lets them pick one of each kind (see NewCharacter).
@export var creator_gear: Array[EquipDef] = []

## "Apprentice Wand, 3 Return Scroll": the advance gifts, for the message on advancing.
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
