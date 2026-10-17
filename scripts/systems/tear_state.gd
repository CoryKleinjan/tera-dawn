class_name TearState
extends RefCounted
## The rules for the tears (TearDef): when one is open to a character, when it's finished,
## and what a finished one does to its zone. The server's MapInstance asks which monsters
## spawn and how strong; the stage asks for the light. In co-op a map follows the host's
## character, so everyone on it sees and fights the same thing.

## How much stronger (HP, attack and Dawn Essence) a finished tear's zone's monsters are.
const STRENGTH := 1.5
## The only parts of a look a tear's dark_look may set: light and fog, never colours of the art.
const LIGHT_AND_FOG := ["light_color", "light_energy", "ambient_color", "ambient_energy", "fog_color",
	"fog_begin", "fog_end", "fog_density", "mote_color", "light_shafts"]
## The peer whose character a shared map follows: the one running the game (solo or host).
const HOST_PEER := 1

## The tear that opens from region `region`, or null.
static func of_region(region: StringName) -> TearDef:
	for t: TearDef in Content.tears.values():
		if t.region == region:
			return t
	return null

## `c` can go through tear `t`: the story has taken them through one.
static func open(t: TearDef, c: Character) -> bool:
	return t != null and c != null and (t.seal_quest == &"" or c.quests.done.has(t.seal_quest))

## `c` has finished tear `t`.
static func finished(t: TearDef, c: Character) -> bool:
	return t != null and c != null and t.finish_quest != &"" and c.quests.done.has(t.finish_quest)

## Map `map` has turned for `c`: a field (not a town) in a zone whose tear `c` has finished.
static func dark(map: MapDef, c: Character) -> bool:
	return map != null and not map.town and finished(of_region(map.region), c)

## The character a shared map on `server` follows: the host's, or anyone's when the host
## isn't playing (tests, a host at the character select).
static func host(server: TDServer) -> Character:
	var p: SimPlayer = server.sessions.get(HOST_PEER)
	if p == null and not server.sessions.is_empty():
		p = server.sessions.values()[0]
	return p.character if p else null

## The kind that spawns in place of `m` on `map`: its dangerous version once turned.
static func kind(m: MonsterDef, map: MapDef, is_dark: bool) -> MonsterDef:
	if not is_dark or m == null:
		return m
	var t := of_region(map.region)
	return t.dangerous.get(m.id, m) if t else m

## How much stronger monsters are on a map that has (or hasn't) turned.
static func strength(is_dark: bool) -> float:
	return STRENGTH if is_dark else 1.0

## How `map` looks: its own look, with its zone's darker light and fog once turned.
static func look(map: MapDef, is_dark: bool) -> BiomeDef:
	var t := of_region(map.region) if is_dark else null
	if t == null or t.dark_look == null or map.look() == null:
		return map.look()
	return t.dark_look.apply(map.look())
