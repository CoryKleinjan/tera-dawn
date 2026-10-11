class_name ServerJobs
extends ServerPart
## How a character grows: job advances and the free Ability Point reset at a job
## instructor (NpcDef.instructs), spending Ability Points and Skill Points. The rules are
## Character's.

## The jingle (a Sound.jingle id, sent as ev_jingle) for a job advance.
const ADVANCE_JINGLE := &"jingle_jobadvance"

## Advances the player to `job_id` through the instructor `npc_id` they stand by.
func on_advance(peer: int, npc_id: StringName, job_id: StringName) -> void:
	var p := player_of(peer)
	var next := _instructed(p, npc_id, job_id)
	if next == null:
		return
	var problem := p.character.advance(next)
	if problem != "":
		tell(p, problem)
		return
	p.dirty_character = true
	p.dirty_vitals = true
	p.map.broadcast(&"ev_effect", [&"celebrate", p.position.x, p.position.y, 1, p.peer])
	tell(p, "You are now a %s!" % next.display_name, Palette.SUN)
	Net.send(p.peer, &"ev_jingle", [ADVANCE_JINGLE])
	if not next.advance_gifts.is_empty():
		tell(p, "Your instructor hands you: %s." % next.gifts_text(), Palette.SUN)
	server.store.save(p.character)

## The free Ability Point reset from the instructor `npc_id` of `job_id` the player stands by.
func on_reset_ap(peer: int, npc_id: StringName, job_id: StringName) -> void:
	var p := player_of(peer)
	var next := _instructed(p, npc_id, job_id)
	if next == null:
		return
	var problem := p.character.reset_ap(next)
	if problem != "":
		tell(p, problem)
		return
	p.dirty_character = true
	p.dirty_vitals = true
	tell(p, "Your Ability Points are back: %d to spend." % p.character.ap, Palette.SUN)
	server.store.save(p.character)

## The job `job_id` if the player stands by the instructor `npc_id` and it teaches that
## job, else null.
func _instructed(p: SimPlayer, npc_id: StringName, job_id: StringName) -> JobDef:
	var npc := p.map.npc_near(p, npc_id) if p else null
	var next: JobDef = Content.jobs.get(job_id)
	if npc == null or next == null or not job_id in npc.instructs:
		return null
	return next

## Spends `amount` Ability Points on one base stat (the "+" buttons spend one, Auto more).
## Character.add_ap refuses other stats and never spends more points than there are.
func on_add_ap(peer: int, stat: StringName, amount := 1) -> void:
	change(peer, func(c: Character) -> String:
		c.add_ap(stat, amount)
		return "")

## Spends a Skill Point on `skill_id`.
func on_learn_skill(peer: int, skill_id: StringName) -> void:
	var p := player_of(peer)
	var skill: SkillDef = Content.skills.get(skill_id)
	if p == null or skill == null:
		return
	var problem := p.character.learn(skill)
	if problem != "":
		tell(p, problem)
		return
	p.dirty_character = true
	p.dirty_vitals = true
