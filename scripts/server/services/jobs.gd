class_name ServerJobs
extends ServerPart
## How a character grows: becoming or switching jobs at a job instructor (NpcDef.instructs),
## and buying stats and skills with Dawn Essence. The rules are Character's.

## The jingle (a Sound.jingle id, sent as ev_jingle) for a job advance.
const ADVANCE_JINGLE := &"jingle_jobadvance"

## Advances the player to `job_id` through the instructor `npc_id` they stand by.
func on_advance(peer: int, npc_id: StringName, job_id: StringName) -> void:
	var p := player_of(peer)
	var next := _instructed(p, npc_id, job_id)
	if next != null:
		advance(p, next)

## Makes the player a `next` (telling them why not, if they can't be one yet). Switching
## from another job hands back the essence of the skills that go.
func advance(p: SimPlayer, next: JobDef) -> void:
	var c := p.character
	var first_time := not c.has_passed(next)
	var lost := c.skills_lost_by(next)
	var before := c.essence
	var problem := c.advance(next)
	if problem != "":
		tell(p, problem)
		return
	p.dirty_character = true
	p.dirty_vitals = true
	p.map.broadcast(&"ev_effect", [EffectDef.CELEBRATE, p.position.x, p.position.y, 1, p.peer])
	tell(p, ("You are now %s!" if first_time else "You are %s again!") % with_article(next.display_name), Palette.SUN)
	Net.send(p.peer, &"ev_jingle", [ADVANCE_JINGLE])
	if not lost.is_empty():
		tell(p, "You forget %s, and %d Dawn Essence comes back to you." % [skill_names(lost), c.essence - before], Palette.SUN)
	if first_time and not next.advance_gifts.is_empty():
		tell(p, "Your instructor hands you: %s." % next.gifts_text(), Palette.SUN)
	server.save(p)

## "Power Strike, Iron Body and Rage": the skills' names, for messages.
static func skill_names(skills: Array[SkillDef]) -> String:
	var names: Array = skills.map(func(s: SkillDef) -> String: return s.display_name)
	if names.size() == 1:
		return names[0]
	return ", ".join(names.slice(0, -1)) + " and " + names[-1]

## The job `job_id` if the player stands by the instructor `npc_id` and it teaches that
## job, else null.
func _instructed(p: SimPlayer, npc_id: StringName, job_id: StringName) -> JobDef:
	var npc := p.map.npc_near(p, npc_id) if p else null
	var next: JobDef = Content.jobs.get(job_id)
	if npc == null or next == null or not job_id in npc.instructs:
		return null
	return next

## Buys one point of a base stat with Dawn Essence (the "+" buttons). AbilityPoints.buy
## refuses other stats and never spends more essence than there is.
func on_buy_stat(peer: int, stat: StringName) -> void:
	change(peer, func(c: Character) -> String:
		if c.ap.buy(stat) == 0 and stat in StatBlock.BASE:
			return "You need %d Dawn Essence for that." % c.ap.price(stat)
		return "")

## The Auto button: buys the job's damage stats while the essence lasts.
func on_auto_stats(peer: int) -> void:
	change(peer, func(c: Character) -> String:
		c.ap.auto()
		return "")

## Buys a level of `skill_id` with Dawn Essence.
func on_learn_skill(peer: int, skill_id: StringName) -> void:
	var p := player_of(peer)
	var skill: SkillDef = Content.skills.get(skill_id)
	if p == null or skill == null:
		return
	var problem := p.character.skills.learn(skill)
	if problem != "":
		tell(p, problem)
		return
	p.dirty_character = true
	p.dirty_vitals = true

## "a Warrior", "an Archer".
static func with_article(noun: String) -> String:
	return ("an " if noun.substr(0, 1).to_lower() in ["a", "e", "i", "o", "u"] else "a ") + noun
