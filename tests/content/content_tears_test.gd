extends TestCase
## Every tear (data/tears) opens from a real zone and is sealed by a story quest; every decline
## step (data/declines) is a step of its own, darkens only with light and fog (art is never
## recoloured in code) and swaps in dangerous versions that are monsters of their own.

func _set_keys(v: BiomeVariantDef) -> Array[String]:
	var out: Array[String] = []
	var blank := BiomeVariantDef.new()
	for prop in v.get_property_list():
		if not prop.usage & PROPERTY_USAGE_STORAGE or prop.name in ["resource_name", "resource_path",
				"resource_local_to_scene", "script", "metadata/_custom_type_script"]:
			continue
		if v.get(prop.name) != blank.get(prop.name):
			out.append(prop.name)
	return out

func test_every_tear_opens_from_a_real_zone() -> void:
	for t: TearDef in Content.tears.values():
		check(Content.regions.has(t.region), "%s opens from a zone that exists" % t.id)
		check(t.inside != &"" and t.inside != t.region, "%s has its own zone" % t.id)
		check(t.seal_quest != &"", "%s is sealed by a story quest" % t.id)

func test_each_decline_step_is_its_own() -> void:
	var seen := {}
	for d: DeclineDef in Content.declines.values():
		check(d.step >= 1, "%s is a step of the decline" % d.id)
		check(not seen.has(d.step), "%s: one DeclineDef per step" % d.id)
		seen[d.step] = true

func test_declines_darken_only_with_light_and_fog() -> void:
	for d: DeclineDef in Content.declines.values():
		if d.look == null:
			continue
		for key in _set_keys(d.look):
			check(key in TearState.LIGHT_AND_FOG, "%s only sets light and fog, not %s" % [d.id, key])

func test_dangerous_versions_are_monsters_of_their_own() -> void:
	for d: DeclineDef in Content.declines.values():
		for id: StringName in d.dangerous:
			var m: MonsterDef = d.dangerous[id]
			check(m != null and m.id != id, "%s: %s's dangerous version is a monster of its own" % [d.id, id])

## The way in to `t`: its scene spots (SceneSpot.tear), with the map each stands on.
func _ways_in(t: TearDef) -> Array:
	var out := []
	for m: MapDef in Content.maps.values():
		for s in m.scene_spots:
			if s.tear == t:
				out.append([m, s])
	return out

func _inside(t: TearDef) -> Array[MapDef]:
	var out: Array[MapDef] = []
	for m: MapDef in Content.maps.values():
		if m.region == t.inside:
			out.append(m)
	return out

func test_every_tear_has_maps_and_quests() -> void:
	for t: TearDef in Content.tears.values():
		check(not _inside(t).is_empty(), "%s: no map is inside it (MapDef.region %s)" % [t.id, t.inside])
		check(not Content.regions.has(t.inside), "%s: its own zone is off the world map, not a RegionDef" % t.id)
		check(Content.quests.has(t.seal_quest), "%s: seal_quest %s is not a quest" % [t.id, t.seal_quest])
		if t.finish_quest != &"":
			check(Content.quests.has(t.finish_quest), "%s: finish_quest %s is not a quest" % [t.id, t.finish_quest])

## Its way in is a scene spot on a secret ledge of its zone (a boss relic's move reaches it),
## sealed with the tear, that sends you to one of its maps; one of its maps leads back out.
func test_every_tear_has_a_secret_way_in_and_a_way_out() -> void:
	for t: TearDef in Content.tears.values():
		var ways := _ways_in(t)
		check(not ways.is_empty(), "%s: no scene spot leads in (SceneSpot.tear)" % t.id)
		for w: Array in ways:
			var m: MapDef = w[0]
			var s: SceneSpot = w[1]
			check(m.region == t.region, "%s: its way in on %s isn't in %s" % [t.id, m.id, t.region])
			check(s.platform >= 1 and s.platform <= m.platforms.size() and m.platforms[s.platform - 1].secret,
					"%s: its way in on %s isn't on a secret ledge" % [t.id, m.id])
			var to: MapDef = Content.maps.get(s.then_map)
			check(to != null and to.region == t.inside, "%s: its way in on %s doesn't lead inside" % [t.id, m.id])
			check(s.glow != Vector2.ZERO, "%s: its way in on %s shows no tear" % [t.id, m.id])
		var out := false
		for m in _inside(t):
			for p in m.portals:
				var to: MapDef = Content.maps.get(p.target_map)
				out = out or (to != null and to.region != t.inside)
		check(out, "%s: none of its maps leads back out" % t.id)

## Its last quest is its guardian: a boss that lives inside it.
func test_every_tear_ends_with_its_guardian() -> void:
	for t: TearDef in Content.tears.values():
		var q: QuestDef = Content.quests.get(t.finish_quest)
		if q == null:
			continue
		var guardian: MonsterDef = null
		for o in q.objectives:
			if o.kind == QuestObjective.Kind.KILL and o.monster and o.monster.boss:
				guardian = o.monster
		if not check(guardian != null, "%s: %s doesn't defeat a boss" % [t.id, q.id]):
			continue
		var lives := _inside(t).any(func(m: MapDef) -> bool: return m.spawns.any(func(s: SpawnDef) -> bool: return s.monster == guardian))
		check(lives, "%s: its guardian %s doesn't live inside it" % [t.id, guardian.id])
