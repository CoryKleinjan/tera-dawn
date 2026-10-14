class_name NewCharacter
extends RefCounted
## The choices made in the character creator: the starting outfit. The client sends it with
## its first join (`to_dict`), and the server checks every choice against what the creator
## offers before making the character (`Character.create`).
##
## Outfit choices come from the starting job's `creator_gear`: one piece per kind of gear
## (top, bottom, shoes...). Kinds not chosen keep the job's `starting_gear`.

## Gear kind (EquipDef.Slot) -> the EquipDef picked for it.
var outfit := {}

## Starts with the job's own starting gear picked where the creator offers it.
func _init(job_id := Character.START_JOB) -> void:
	var job := Content.job(job_id)
	for kind in outfit_kinds(job):
		var options := outfit_options(job, kind)
		outfit[kind] = options[0]
		for e in job.starting_gear:
			if e.slot == kind and e in options:
				outfit[kind] = e

## The kinds of gear the creator lets a new character of `job` pick, in EquipDef.Slot order.
static func outfit_kinds(job: JobDef) -> Array[EquipDef.Slot]:
	var out: Array[EquipDef.Slot] = []
	for e in job.creator_gear:
		if not e.slot in out:
			out.append(e.slot)
	out.sort()
	return out

## The pieces of one kind the creator offers.
static func outfit_options(job: JobDef, kind: EquipDef.Slot) -> Array[EquipDef]:
	var out: Array[EquipDef] = []
	for e in job.creator_gear:
		if e.slot == kind:
			out.append(e)
	return out

## Picks the next or previous piece of one kind.
func cycle_outfit(job: JobDef, kind: EquipDef.Slot, step: int) -> void:
	var options := outfit_options(job, kind)
	if not options.is_empty():
		outfit[kind] = options[posmod(options.find(outfit.get(kind)) + step, options.size())]

## Every choice made at random.
func roll(job: JobDef, rng: RandomNumberGenerator = null) -> void:
	for kind in outfit_kinds(job):
		var options := outfit_options(job, kind)
		outfit[kind] = options[rng.randi_range(0, options.size() - 1) if rng else randi() % options.size()]

## What a new character of `job` starts wearing: the job's starting gear with the outfit
## swapped in.
func starting_gear(job: JobDef) -> Array[EquipDef]:
	var out: Array[EquipDef] = []
	for e in job.starting_gear:
		if not outfit.has(e.slot):
			out.append(e)
	for kind in outfit:
		out.append(outfit[kind])
	return out

func to_dict() -> Dictionary:
	var gear := []
	for kind in outfit:
		gear.append(String(outfit[kind].id))
	return {"outfit": gear}

## The choices a client sent, keeping only what the creator offers a new `job` character.
## Anything missing or not on offer stays as the default (an older client's "look" is left
## out).
static func from_dict(data: Dictionary, job_id := Character.START_JOB) -> NewCharacter:
	var n := NewCharacter.new(job_id)
	var job := Content.job(job_id)
	var gear: Variant = data.get("outfit")
	if gear is Array:
		for id in gear:
			var e := Content.items.get(StringName(str(id))) as EquipDef
			if e and e in job.creator_gear:
				n.outfit[e.slot] = e
	return n
