class_name TearState
extends RefCounted
## The rules for the tears (TearDef) and the world's decline (DeclineDef): when a tear is open
## to a character, how many they have finished, and what that does to the world. The first
## finished tear turns the whole world (every map but the tears' own) and each one after
## takes it a step further. The server's MapInstance asks which monsters spawn and how strong;
## the stage asks for the light. In co-op a map follows the host's character, so everyone on
## it sees and fights the same thing.

## How much stronger (HP, attack and Dawn Essence) monsters get with each step of the decline.
const STRENGTH_PER_STEP := 0.5
## The only parts of a look a decline step may set: light and fog, never colours of the art.
const LIGHT_AND_FOG := ["light_color", "light_energy", "ambient_color", "ambient_energy", "fog_color",
	"fog_begin", "fog_end", "fog_density", "mote_color", "light_shafts"]
## The peer whose character a shared map follows: the one running the game (solo or host).
const HOST_PEER := 1

## `c` can go through tear `t`: the story has taken them through one.
static func open(t: TearDef, c: Character) -> bool:
	return t != null and c != null and (t.seal_quest == &"" or c.quests.done.has(t.seal_quest))

## `c` has finished tear `t`.
static func finished(t: TearDef, c: Character) -> bool:
	return t != null and c != null and t.finish_quest != &"" and c.quests.done.has(t.finish_quest)

## How far the world has declined for `c`: the tears they have finished.
static func decline(c: Character) -> int:
	var n := 0
	for t: TearDef in Content.tears.values():
		if finished(t, c):
			n += 1
	return n

## Whether `region` is a tear's own zone (TearDef.inside). It isn't a RegionDef: a tear is
## off the world map, has no town and no routes, and its maps never decline.
static func inside_tear(region: StringName) -> bool:
	if region == &"":
		return false
	for t: TearDef in Content.tears.values():
		if t.inside == region:
			return true
	return false

## How far map `map` has declined for `c`: the world's step, except inside a tear.
static func decline_of(map: MapDef, c: Character) -> int:
	if map == null or inside_tear(map.region):
		return 0
	return decline(c)

## The character a shared map on `server` follows: the host's, or anyone's when the host
## isn't playing (tests, a host at the character select).
static func host(server: TDServer) -> Character:
	var p: SimPlayer = server.sessions.get(HOST_PEER)
	if p == null and not server.sessions.is_empty():
		p = server.sessions.values()[0]
	return p.character if p else null

## The decline steps that apply at step `step`, in order.
static func steps(step: int) -> Array[DeclineDef]:
	var out: Array[DeclineDef] = []
	for d: DeclineDef in Content.declines.values():
		if d.step <= step:
			out.append(d)
	out.sort_custom(func(a: DeclineDef, b: DeclineDef) -> bool: return a.step < b.step)
	return out

## The kind that spawns in place of `m` at step `step`.
static func kind(m: MonsterDef, step: int) -> MonsterDef:
	if m == null:
		return m
	for d in steps(step):
		m = d.dangerous.get(m.id, m)
	return m

## How much stronger monsters are at step `step`.
static func strength(step: int) -> float:
	return 1.0 + STRENGTH_PER_STEP * maxi(0, step)

## How `map` looks at step `step`: its own look, with each step's light and fog on top.
static func look(map: MapDef, step: int) -> BiomeDef:
	var b := map.look()
	if b == null:
		return b
	for d in steps(step):
		if d.look:
			b = d.look.apply(b)
	return b
