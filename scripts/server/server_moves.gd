class_name ServerMoves
extends RefCounted
## The server's side of a job's movement skill (SkillDef.move): the hero moves on his own
## machine, so here a Blink puts him where it lands, a Charge shoves the monsters in its
## path aside (no damage) and a roll keeps him from being hit while it lasts.

## How tall the strip a Charge shoves monsters out of is, standing on the feet.
const SHOVE_HEIGHT := 90.0

## `p` used movement skill `skill` aimed `aim` (already paid for). Tells everyone on the map.
static func use(p: SimPlayer, skill: SkillDef, aim: Hitbox.Aim) -> void:
	var move := skill.move
	var level := p.character.skills.level(skill)
	var from := p.position
	if move.style == MoveDef.Style.BLINK:
		p.position = move.blink_to(from, p.face, aim, level, float(p.map.def.width), float(p.map.def.ground_y))
	if move.untouchable:
		p.dodge_t = maxi(p.dodge_t, move.ticks)
	if move.shoves > 0:
		shove(p, Hitbox.attack_area(from, p.face, move.distance_at(level), SHOVE_HEIGHT), move.shoves, move.shove_force)
	p.map.broadcast(&"ev_skill", [p.peer, skill.id, from.x, from.y, p.face, [], aim])

## Knocks up to `count` monsters inside `area` away the way `p` faces, nearest first.
static func shove(p: SimPlayer, area: Rect2, count: int, force: float) -> void:
	var hit: Array[SimMob] = []
	for m in p.map.mobs:
		if not m.dead and area.intersects(m.hurtbox.rect_at(m.body_position())):
			hit.append(m)
	hit.sort_custom(func(a: SimMob, b: SimMob) -> bool:
		return absf(a.position.x - p.position.x) < absf(b.position.x - p.position.x))
	for m in hit.slice(0, count):
		m.hurt(p.face, p.peer, force)
