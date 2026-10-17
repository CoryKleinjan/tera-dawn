extends TestCase
## Every tear (data/tears) opens from a real zone, darkens it only with light and fog (art is
## never recoloured in code), and swaps in dangerous versions only for that zone's own
## monsters, each a monster of its own.

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
		check(t.seal_quest != &"", "%s is sealed by a story quest" % t.id)

func test_tears_darken_only_with_light_and_fog() -> void:
	for t: TearDef in Content.tears.values():
		if t.dark_look == null:
			continue
		for key in _set_keys(t.dark_look):
			check(key in TearState.LIGHT_AND_FOG, "%s's dark look only sets light and fog, not %s" % [t.id, key])

func test_dangerous_versions_replace_the_zones_own_monsters() -> void:
	for t: TearDef in Content.tears.values():
		var here := {}
		for m: MapDef in Content.maps.values():
			if m.region == t.region:
				for s in m.spawns:
					here[s.monster.id] = true
		for id: StringName in t.dangerous:
			var d: MonsterDef = t.dangerous[id]
			check(here.has(id), "%s: %s lives in its zone" % [t.id, id])
			check(d != null and d.id != id, "%s: %s's dangerous version is a monster of its own" % [t.id, id])
