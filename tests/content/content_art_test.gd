extends TestCase
## Every texture and SpriteFrames content points at is there: monster, NPC, item, skill,
## effect, projectile, biome, climb style and prop art, and the frames animated actors play.

const Scan := preload("res://tests/content/content_scan.gd")

## True when `tex` is a real, non-empty texture (reports `what` otherwise).
func _texture(tex: Texture2D, what: String) -> bool:
	if not check(tex != null, "%s is empty" % what):
		return false
	return check(tex.get_width() > 0 and tex.get_height() > 0, "%s (%s) has no pixels" % [what, tex.resource_path])

func _frames(frames: SpriteFrames, what: String, needed: Array) -> void:
	for anim in needed:
		check(frames.has_animation(anim), "%s has no %s animation" % [what, anim])
	for anim in frames.get_animation_names():
		var n := frames.get_frame_count(anim)
		check(n > 0, "%s: animation %s has no frames" % [what, anim])
		for i in n:
			_texture(frames.get_frame_texture(anim, i), "%s: animation %s frame %d" % [what, anim, i])

func test_monsters_have_art() -> void:
	for m: MonsterDef in Content.monsters.values():
		var w := Scan.where(m)
		check(m.texture != null or m.sprite_frames != null, "%s: has neither texture nor sprite_frames" % w)
		if m.texture:
			_texture(m.texture, w + ": texture")
		if m.sprite_frames:
			_frames(m.sprite_frames, w + ": sprite_frames", [&"idle"])
		check(TDCollectionWindow.monster_icon(m) != null, "%s: the Monster Book can't find an icon" % w)

func test_npcs_have_art() -> void:
	for n: NpcDef in Content.npcs.values():
		var w := Scan.where(n)
		check(n.texture != null or n.sprite_frames != null, "%s: has neither texture nor sprite_frames" % w)
		if n.texture:
			_texture(n.texture, w + ": texture")
		if n.sprite_frames:
			_frames(n.sprite_frames, w + ": sprite_frames", [&"idle"])

func test_items_have_icons() -> void:
	for i: ItemDef in Content.items.values():
		var w := Scan.where(i)
		_texture(i.icon, w + ": icon")
		for k in i.world_frames.size():
			_texture(i.world_frames[k], "%s: world_frames[%d]" % [w, k])
		if i.pile_texture:
			_texture(i.pile_texture, w + ": pile_texture")

func test_skills_have_icons() -> void:
	for s: SkillDef in Content.skills.values():
		_texture(s.icon, Scan.where(s) + ": icon")

func test_effects_have_frames() -> void:
	for e: EffectDef in Content.effects.values():
		var w := Scan.where(e)
		check(not e.frames.is_empty(), "%s: frames is empty" % w)
		for k in e.frames.size():
			_texture(e.frames[k], "%s: frames[%d]" % [w, k])
		check(e.fps > 0 and e.duration() > 0, "%s: fps %s gives no duration" % [w, e.fps])

func test_projectiles_have_textures() -> void:
	for path in Scan.files(Scan.DATA.path_join("projectiles")):
		var p := load(path) as ProjectileDef
		if p:
			_texture(p.texture, path + ": texture")
			check(p.speed > 0 and p.max_range > 0, "%s: speed %s / max_range %s must be positive" % [path, p.speed, p.max_range])

func test_climb_styles_have_textures() -> void:
	for path in Scan.files(Scan.DATA.path_join("climb_styles")):
		var c := load(path) as ClimbStyleDef
		if c:
			_texture(c.middle, path + ": middle")
			check(c.climb_animation in [&"rope", &"ladder"], "%s: climb_animation %s is not rope or ladder" % [path, c.climb_animation])
			check(HeroBody.FRAMES.has_animation(c.climb_animation), "%s: hero has no %s animation" % [path, c.climb_animation])

func test_biomes_have_their_art() -> void:
	for path in Scan.files(Scan.DATA.path_join("biomes")):
		var b := load(path) as BiomeDef
		if b == null:
			continue
		# a room inside a building has a door out instead of platforms, lanterns and portals
		var room := b.door != null
		var needs := ["ground_top", "ground_side", "ground_soil"]
		if not room:
			needs += ["platform_left", "platform_middle", "platform_right", "lantern"]
		for f in needs:
			_texture(b.get(f), "%s: %s" % [path, f])
		check(room or not b.portal_frames.is_empty(), "%s: portal_frames is empty" % path)
		for k in b.portal_frames.size():
			_texture(b.portal_frames[k], "%s: portal_frames[%d]" % [path, k])
		for k in b.edge_grass.size():
			_texture(b.edge_grass[k], "%s: edge_grass[%d]" % [path, k])
		check(not b.backdrop.is_empty(), "%s: backdrop is empty" % path)
		for k in b.backdrop.size():
			var layer := b.backdrop[k]
			if check(layer != null and not layer.textures.is_empty(), "%s: backdrop[%d] has no textures" % [path, k]):
				for t in layer.textures.size():
					_texture(layer.textures[t], "%s: backdrop[%d].textures[%d]" % [path, k, t])
		for group in ["ground_decor", "platform_decor"]:
			var list: Array = b.get(group)
			for k in list.size():
				var d: DecorDef = list[k]
				if check(d != null and not d.textures.is_empty(), "%s: %s[%d] has no textures" % [path, group, k]):
					check(d.spacing.x > 0 and d.spacing.x <= d.spacing.y, "%s: %s[%d].spacing %s must be positive and low to high" % [path, group, k, d.spacing])
					check(d.chance >= 0 and d.chance <= 1, "%s: %s[%d].chance is %s" % [path, group, k, d.chance])
					for t in d.textures.size():
						_texture(d.textures[t], "%s: %s[%d].textures[%d]" % [path, group, k, t])

## Biomes kept for later that no map uses yet: Ember Hollow's volcanic look, kept with its
## fire monsters (content_world_test KNOWN_UNSPAWNED) for wherever Cory places them.
const KNOWN_UNUSED_BIOMES := ["res://data/biomes/ember.tres"]

func test_every_biome_is_used() -> void:
	var used := {}
	for m: MapDef in Content.maps.values():
		if m.biome:
			used[m.biome.resource_path] = true
	for path in Scan.files(Scan.DATA.path_join("biomes")):
		if path in KNOWN_UNUSED_BIOMES:
			check(not used.has(path), "%s is used now: take it off KNOWN_UNUSED_BIOMES" % path)
			continue
		check(used.has(path), "%s: no map uses this biome" % path)

func test_map_props_have_textures() -> void:
	for m: MapDef in Content.maps.values():
		for k in m.props.size():
			var p := m.props[k]
			if check(p != null, "%s: props[%d] is empty" % [Scan.where(m), k]):
				_texture(p.texture, "%s: props[%d].texture" % [Scan.where(m), k])
				check_between(p.x, 0, m.width, "%s: props[%d].x" % [Scan.where(m), k])
				check(p.scale > 0, "%s: props[%d].scale is %s" % [Scan.where(m), k, p.scale])

func test_hero_has_every_animation_the_game_plays() -> void:
	_frames(HeroBody.FRAMES, "assets/animations/hero.tres", [&"idle", &"rope", &"ladder"])
