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
