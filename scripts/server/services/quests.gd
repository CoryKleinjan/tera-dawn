class_name ServerQuests
extends ServerPart
## Quests on the server: taking, handing in and giving up quests, and telling players how
## their quests are going as they kill monsters, pick things up, visit maps and climb to spots. The rules
## are QuestLog's.

## The jingle (a Sound.jingle id, sent as ev_jingle) for finishing a quest.
const QUEST_JINGLE := &"jingle_quest"

## A monster the player killed: it goes in their Monster Book and moves their quests on.
func record_kill(p: SimPlayer, monster: MonsterDef) -> void:
	p.character.book.record_kill(monster)
	if monster.boss:
		p.character.count(Counters.BOSSES)
	progress(p, p.character.quests.record_kill(monster))

## Shows how quests that collect `item` are going after picking one up.
func picked_up(p: SimPlayer, item: ItemDef) -> void:
	var c := p.character
	for id in c.quests.active:
		var q: QuestDef = Content.quests.get(id)
		for i in q.objectives.size():
			var o := q.objectives[i]
			if o.kind == QuestObjective.Kind.COLLECT and o.item == item:
				tell(p, "%s: %s %d/%d" % [q.title, o.item.display_name, c.quests.progress(q, i, c), o.count], Palette.CARD)

## Tells the player how the quests that just moved on are going.
func progress(p: SimPlayer, moved: Array[QuestDef]) -> void:
	for q in moved:
		p.dirty_character = true
		var c := p.character
		for i in q.objectives.size():
			var o := q.objectives[i]
			if o.kind != QuestObjective.Kind.COLLECT:
				tell(p, "%s: %s %d/%d" % [q.title, o.describe(), c.quests.progress(q, i, c), o.count], Palette.CARD)
		if c.quests.is_ready(q, c):
			tell(p, "%s is ready to hand in." % q.title, Palette.SUN)

func on_quest_accept(peer: int, npc_id: StringName, quest_id: StringName) -> void:
	var p := player_of(peer)
	var q: QuestDef = Content.quests.get(quest_id)
	if p == null or q == null or q.giver != npc_id or p.map.npc_near(p, npc_id) == null:
		return
	if p.character.quests.status(q, p.character) == QuestLog.Status.AVAILABLE:
		start(p, q)

## Gives the player quest `q` (already checked as theirs to take).
func start(p: SimPlayer, q: QuestDef) -> void:
	var c := p.character
	c.quests.accept(q)
	p.dirty_character = true
	tell(p, "New quest: %s" % q.title, Palette.SUN)
	progress(p, c.quests.record_visit(p.map.def.id))
	reached(p)
	if q.gift_on_accept:
		p.map.toss_to(p, q.gift_on_accept)
	server.scenes.play(p, q.start_scene)

## Counts the spot the player stands on toward quests asking them to reach it.
func reached(p: SimPlayer) -> void:
	var c := p.character
	if not c.quests.wants_reach(p.map.def.id):
		return
	var platforms := p.map.layout.platforms
	for i in platforms.size():
		if p.stands_on(platforms[i]):
			progress(p, c.quests.record_reach(p.map.def.id, i))

func on_quest_complete(peer: int, npc_id: StringName, quest_id: StringName) -> void:
	var p := player_of(peer)
	var q: QuestDef = Content.quests.get(quest_id)
	if p == null or q == null or q.turn_in_npc() != npc_id or p.map.npc_near(p, npc_id) == null:
		return
	var problem := p.character.quests.complete(q, p.character)
	p.dirty_character = true
	if problem != "":
		tell(p, problem)
		return
	tell(p, "Quest complete: %s" % q.title, Palette.SUN)
	Net.send(p.peer, &"ev_jingle", [QUEST_JINGLE])
	if q.reward_xp > 0:
		server.give_xp(p, q.reward_xp)
	server.scenes.play(p, q.finish_scene)
	var c := p.character
	# a job test: passing it makes you that job
	for job: JobDef in Content.jobs.values():
		if job.advance_quest == q and job.opens_from(c.job.id):
			server.jobs.advance(p, job)
	for next: QuestDef in Content.quests.values():
		if next.auto_start and next.requires.has(q.id) and c.quests.status(next, c) == QuestLog.Status.AVAILABLE:
			start(p, next)

func on_quest_forfeit(peer: int, quest_id: StringName) -> void:
	var p := player_of(peer)
	var q: QuestDef = Content.quests.get(quest_id)
	if p and q and p.character.quests.active.has(q.id):
		p.character.quests.forfeit(q)
		p.dirty_character = true
		tell(p, "Gave up on %s." % q.title, Palette.MIST)
