class_name ServerJobs
extends ServerPart
## Becoming or switching jobs at a job instructor (NpcDef.instructs). The rules are
## Character's.

## The jingle (a Sound.jingle id, sent as ev_jingle) for a job advance.
const ADVANCE_JINGLE := &"jingle_jobadvance"

## Advances the player to `job_id` through the instructor `npc_id` they stand by.
func on_advance(peer: int, npc_id: StringName, job_id: StringName) -> void:
	var p := player_of(peer)
	var next := _instructed(p, npc_id, job_id)
	if next != null:
		advance(p, next)

## Makes the player a `next` (telling them why not, if they can't be one yet).
func advance(p: SimPlayer, next: JobDef) -> void:
	var c := p.character
	var first_time := not c.has_passed(next)
	var problem := c.advance(next)
	if problem != "":
		tell(p, problem)
		return
	p.dirty_character = true
	p.dirty_vitals = true
	p.map.broadcast(&"ev_effect", [EffectDef.CELEBRATE, p.position.x, p.position.y, 1, p.peer])
	tell(p, ("You are now %s!" if first_time else "You are %s again!") % with_article(next.display_name), Palette.SUN)
	Net.send(p.peer, &"ev_jingle", [ADVANCE_JINGLE])
	if first_time and not next.advance_gifts.is_empty():
		tell(p, "Your instructor hands you: %s." % next.gifts_text(), Palette.SUN)
	server.save(p)

## The job `job_id` if the player stands by the instructor `npc_id` and it teaches that
## job, else null.
func _instructed(p: SimPlayer, npc_id: StringName, job_id: StringName) -> JobDef:
	var npc := p.map.npc_near(p, npc_id) if p else null
	var next: JobDef = Content.jobs.get(job_id)
	if npc == null or next == null or not job_id in npc.instructs:
		return null
	return next

## "a Warrior", "an Archer".
static func with_article(noun: String) -> String:
	return ("an " if noun.substr(0, 1).to_lower() in ["a", "e", "i", "o", "u"] else "a ") + noun
