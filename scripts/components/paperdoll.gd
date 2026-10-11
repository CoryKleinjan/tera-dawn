class_name Paperdoll
extends RefCounted
## How a character looks, worked out from their look (Character.look(): appearance and the
## gear that shows). The hero is drawn as layers: a bare body, then hair, face and each piece
## of gear, each a strip that plays frame for frame with the body. PaperdollSprite shows it
## in the world and PaperdollView in menus.
##
## The body (hero.png) comes with a region map (hero_regions.png: which pixels are skin, the
## chest, the shorts and the feet) and a rig (hero_rig.json: where his head, face, neck, hand
## and shield are in every frame), both made with the layers by tools/art/paperdoll_layers.py.
## The skin tone recolours his skin. A worn top, bottom or shoes is a greyscale cut tinted with
## its colour (EquipDef.worn_style: a tunic, boots...) over the bare skin, or its own art
## (EquipDef.worn_frames); with neither it recolours the chest, shorts or feet. A bottom's cut
## also recolours the shorts, so no grey shows at its edges. Hair, irises, capes,
## shields and gloves are greyscale art tinted with the hair, eye or item colour. The weapon
## is a layer too, already placed in his fist on every frame by paperdoll_layers.py, with a
## hole where his fingers wrap the grip (see weapon_layers); a weapon kind is held its own way
## (a bow upright, a staff planted). A hat is a layer too, one per shape (EquipDef.look_shape),
## tinted with the hat's colour; the hair under it is the hairstyle's own _hat layer.

## The parts of the body, as hero_regions.png numbers them. Hair, eyes, cape, weapon, shield
## and gloves are layers now, so only skin, top, bottom and shoes are on the map.
enum Region { NONE, HAIR, SKIN, EYES, TOP, BOTTOM, SHOES, CAPE, WEAPON, SHIELD, GLOVES }
const REGIONS := 11
## Worn places that show on the hero, in drawing order (back to front) for layered art.
const SHOWN_PLACES: Array[StringName] = [&"cape", &"bottom", &"shoes", &"top", &"gloves", &"shield", &"hat", &"weapon"]
## The body region a worn piece without art of its own recolours.
const PLACE_REGIONS := {&"bottom": Region.BOTTOM, &"shoes": Region.SHOES, &"top": Region.TOP}
## How strongly it recolours it (a little of the body's shading shows through).
const PLACE_STRENGTH := 0.85
## The chest and feet are skin when nothing is worn there.
const BARE_SKIN: Array[StringName] = [&"top", &"shoes"]

const FRAMES := preload("res://assets/animations/hero.tres")
const STRIP := preload("res://assets/sprites/characters/hero.png")
const MASK := preload("res://assets/sprites/characters/hero_regions.png")
const RIG_PATH := "res://assets/sprites/characters/hero_rig.json"
## The art for worn places with no art of their own: tinted with the piece's colour.
const CAPE := preload("res://assets/animations/paperdoll/cape.tres")
## The cape's part in front of him: its collar and clasp, or all of it seen from behind (climbing).
const CAPE_FRONT := preload("res://assets/animations/paperdoll/cape_front.tres")
const SHIELD := preload("res://assets/animations/paperdoll/shield_round.tres")
## Gloves on both hands (climbing: bare hands).
const GLOVES := preload("res://assets/animations/paperdoll/gloves.tres")
## Weapon layers: weapon_<kind>.tres (greyscale, tinted) or weapon_item_<id>.tres (a weapon's
## own held picture, in colour), each with an optional _behind twin for frames where the
## weapon is behind his body (far hand, or carried on his back while sitting).
const WEAPON_DIR := "res://assets/animations/paperdoll/weapon_"
## The kind a weapon without one is drawn as.
const DEFAULT_WEAPON := &"sword"
## Tops worn open at the front (EquipDef.worn_style), with UNDERSHIRT under them so his
## chest isn't bare, in UNDERSHIRT_COLOR (a plain linen).
const OPEN_TOPS: Array[StringName] = [&"coat"]
const UNDERSHIRT := preload("res://assets/animations/paperdoll/top_undershirt.tres")
const UNDERSHIRT_COLOR := Color(0.86, 0.82, 0.72)
## Hat layers: hat_<shape>.tres (EquipDef.look_shape; a hat without one is a DEFAULT_HAT).
const HAT_DIR := "res://assets/animations/paperdoll/hat_"
const DEFAULT_HAT := &"cap"
## Shields by EquipDef.look_shape (any other: SHIELD).
const SHIELDS := {&"kite": preload("res://assets/animations/paperdoll/shield_kite.tres")}
## The hero's frame size in pixels; every frame of the strip is this big.
const FRAME_SIZE := Vector2(256, 207)
## How many strip pixels make one "hero pixel", the unit the game sizes him in (TDStage.TEXEL):
## the strip is cut at the full resolution of the painted sheet, twice as fine as the hero is sized.
const ART_SCALE := 2.0

## A layer of art, played in step with the hero and multiplied by `tint`, or with `gear`
## (greyscale gear art) shaded in it, its light and dark greys turning light and deep shades
## of the colour (gear_tint.gdshaderinc).
class Layer:
	var frames: SpriteFrames
	var behind := false
	var tint := Color.WHITE
	var gear := false

	func _init(f: SpriteFrames, back: bool, t := Color.WHITE, g := false) -> void:
		frames = f
		behind = back
		tint = t
		gear = g

	## Sets a layer material's uniforms (paperdoll_layer or paperdoll_ui_layer shader).
	func apply(mat: ShaderMaterial) -> void:
		mat.set_shader_parameter(&"tint", tint)
		mat.set_shader_parameter(&"gear", gear)

## Per region: colour to recolour it with (alpha: how much, 0 keeps the art's own).
var tints := PackedColorArray()
## Per region: 1 hides it.
var hidden := PackedFloat32Array()
## Back to front: the ones `behind` go under the body, the rest over it.
var layers: Array[Layer] = []
## The kind of weapon in his hand (&"" bare-handed) and its colour (its streak when swung).
var weapon_kind := &""
var weapon_tint := Color.WHITE

static var _rig: Dictionary
static var _refs: PackedVector3Array

func _init() -> void:
	tints.resize(REGIONS)
	tints.fill(Color(0, 0, 0, 0))
	hidden.resize(REGIONS)
	hidden.fill(0.0)

## Works out how a look is drawn.
static func dress(look: Dictionary) -> Paperdoll:
	var d := Paperdoll.new()
	var a := Appearance.new()
	if look.get("appearance") is Dictionary:
		a.load_dict(look["appearance"])
	var gear := {}
	if look.get("gear") is Dictionary:
		for place in look["gear"]:
			var e := Content.items.get(StringName(str(look["gear"][place]))) as EquipDef
			if e:
				gear[StringName(place)] = e

	# the body
	var skin := a.part(LookDef.Kind.SKIN)
	if skin and skin.recolors():
		d.tints[Region.SKIN] = skin.color
	for place in BARE_SKIN:
		if not gear.has(place):
			d.tints[PLACE_REGIONS[place]] = d.tints[Region.SKIN]
	var cuts := {}  # place -> the worn_style layer it's drawn with
	for place in PLACE_REGIONS:
		var e: EquipDef = gear.get(place)
		if e == null or e.worn_frames:
			continue
		var cut := worn_cut(e)
		if cut:
			cuts[place] = cut
		if cut and place in BARE_SKIN:  # the cut covers what it covers; skin shows around it
			d.tints[PLACE_REGIONS[place]] = d.tints[Region.SKIN]
		else:
			var c := e.worn_color()
			c.a = PLACE_STRENGTH
			d.tints[PLACE_REGIONS[place]] = c

	# behind him
	var hair := a.part(LookDef.Kind.HAIR)
	var hair_tone := _look_color(a.part(LookDef.Kind.HAIR_COLOR), Region.HAIR)
	var cape: EquipDef = gear.get(&"cape")
	if cape:
		if cape.worn_frames:
			d._add(cape.worn_frames, true)
		else:
			d._add(CAPE, true, cape.worn_color(), true)
	if hair and not gear.has(&"hat"):
		d._add(hair.back_frames, true, hair_tone)
	var weapon: EquipDef = gear.get(&"weapon")
	var held := weapon_layers(weapon) if weapon and weapon.worn_frames == null else {}
	if weapon:
		d.weapon_kind = kind_of(weapon)
		d.weapon_tint = weapon.worn_color()
	if held.has("behind"):
		d._add(held["behind"], true, held["tint"], held["tint"] != Color.WHITE)

	# over him
	for place in [&"bottom", &"shoes", &"top", &"gloves"]:
		var e: EquipDef = gear.get(place)
		if e and e.worn_frames:
			d._add(e.worn_frames, false)
			if PLACE_REGIONS.has(place):
				d.hidden[PLACE_REGIONS[place]] = 1.0
		elif cuts.has(place):
			if place == &"top" and e.worn_style in OPEN_TOPS:
				d._add(UNDERSHIRT, false, UNDERSHIRT_COLOR, true)
			d._add(cuts[place], false, e.worn_color(), true)
		elif e and place == &"gloves":
			d._add(GLOVES, false, e.worn_color(), true)
	if cape and cape.worn_frames == null:
		d._add(CAPE_FRONT, false, cape.worn_color(), true)
	var face := a.part(LookDef.Kind.FACE)
	if face:
		d._add(face.frames, false)
		d._add(face.detail_frames, false, _look_color(a.part(LookDef.Kind.EYES), Region.EYES))
	if hair:
		d._add(hair.hat_frames if gear.has(&"hat") and hair.hat_frames else hair.frames, false, hair_tone)
	var shield: EquipDef = gear.get(&"shield")
	if shield:
		if shield.worn_frames:
			d._add(shield.worn_frames, false)
		else:
			d._add(SHIELDS.get(shield.look_shape, SHIELD), false, shield.worn_color(), true)
	var hat: EquipDef = gear.get(&"hat")
	if hat:
		if hat.worn_frames:
			d._add(hat.worn_frames, false)
		else:
			d._add(hat_frames(hat), false, hat.worn_color(), true)
	if weapon and weapon.worn_frames: # over the hat: a sword raised over his head
		d._add(weapon.worn_frames, false)
	elif held.has("front"):
		d._add(held["front"], false, held["tint"], held["tint"] != Color.WHITE)
	return d

## The layer a hat without art of its own is drawn with: its shape's (EquipDef.look_shape).
static func hat_frames(e: EquipDef) -> SpriteFrames:
	var path := HAT_DIR + String(e.look_shape) + ".tres"
	return load(path if e.look_shape != &"" and ResourceLoader.exists(path) else HAT_DIR + String(DEFAULT_HAT) + ".tres")

## How a weapon is drawn in his hand: {"front": SpriteFrames, "behind": SpriteFrames (if any),
## "tint": Color}. Its own held picture (weapon_item_<id>) if one was drawn, in its own colours;
## else its kind's greyscale picture in the item's colour.
static func weapon_layers(e: EquipDef) -> Dictionary:
	var own := WEAPON_DIR + "item_" + String(e.id)
	if ResourceLoader.exists(own + ".tres"):
		return _weapon_frames(own, Color.WHITE)
	var kind := kind_of(e)
	if not ResourceLoader.exists(WEAPON_DIR + String(kind) + ".tres"):
		kind = DEFAULT_WEAPON
	return _weapon_frames(WEAPON_DIR + String(kind), e.worn_color())

## The greyscale layer a top, bottom or shoes is worn as (EquipDef.worn_style), or null.
static func worn_cut(e: EquipDef) -> SpriteFrames:
	var path := e.worn_style_path()
	return load(path) if path != "" and ResourceLoader.exists(path) else null

## The kind of weapon an item is held as (a weapon without a kind is a sword).
static func kind_of(e: EquipDef) -> StringName:
	return e.weapon_kind if e and e.weapon_kind != &"" else DEFAULT_WEAPON

static func _weapon_frames(base: String, tint: Color) -> Dictionary:
	var out := {"front": load(base + ".tres"), "tint": tint}
	if ResourceLoader.exists(base + "_behind.tres"):
		out["behind"] = load(base + "_behind.tres")
	return out

func _add(frames: SpriteFrames, behind: bool, tint := Color.WHITE, gear := false) -> void:
	if frames:
		layers.append(Layer.new(frames, behind, tint, gear))

## A look's colour, or the art's own colour for the region when it keeps it.
static func _look_color(l: LookDef, region: Region) -> Color:
	return l.color if l and l.recolors() else ref_color(region)

## Sets a dressing material's uniforms (paperdoll_sprite or paperdoll_ui shader). The
## per-region values go in a tiny texture, one column per region (see paperdoll.gdshaderinc).
func apply(mat: ShaderMaterial) -> void:
	var data := Image.create(REGIONS, 3, false, Image.FORMAT_RGBAF)
	var refs := ref_colors()
	for r in REGIONS:
		data.set_pixel(r, 0, tints[r])
		data.set_pixel(r, 1, Color(hidden[r], 0, 0, 1))
		data.set_pixel(r, 2, Color(refs[r].x, refs[r].y, refs[r].z, 1))
	mat.set_shader_parameter(&"regions", MASK)
	mat.set_shader_parameter(&"look_data", ImageTexture.create_from_image(data))

# ---------- the hero's rig (hero_rig.json) ----------

static func rig() -> Dictionary:
	if _rig.is_empty():
		var f := FileAccess.open(RIG_PATH, FileAccess.READ)
		var data: Variant = JSON.parse_string(f.get_as_text()) if f else null
		_rig = data if data is Dictionary else {"frames": [], "region_colors": []}
	return _rig

## Each region's typical colour in the art.
static func ref_colors() -> PackedVector3Array:
	if _refs.is_empty():
		var colors: Array = rig().get("region_colors", [])
		for i in REGIONS:
			var c: Array = colors[i] if i < colors.size() else [1, 1, 1]
			_refs.append(Vector3(c[0], c[1], c[2]))
	return _refs

static func ref_color(region: Region) -> Color:
	var v := ref_colors()[region]
	return Color(v.x, v.y, v.z)

## Which frame of the strip a hero frame texture is.
static func frame_index(tex: Texture2D) -> int:
	var at := tex as AtlasTexture
	return int(at.region.position.x / FRAME_SIZE.x) if at else 0

## A named point of a frame ("head_top", "head", "face", "grip", "tip"...) in frame pixels
## from its top-left corner, or null if the frame doesn't have it.
static func anchor(frame: int, name: StringName) -> Variant:
	var frames: Array = rig().get("frames", [])
	if frame < 0 or frame >= frames.size():
		return null
	var p: Variant = frames[frame].get(String(name))
	return Vector2(p[0], p[1]) if p is Array else null

## How a weapon kind is held on a frame: {"grip": fist point (frame pixels), "angle": radians,
## y down, the way it points, "behind": in his far hand}, or null when it isn't in his hand.
static func hold(frame: int, kind: StringName) -> Variant:
	var frames: Array = rig().get("frames", [])
	if frame < 0 or frame >= frames.size():
		return null
	var h: Variant = frames[frame].get("holds", {}).get(String(kind))
	if not h is Array:
		return null
	return {"grip": Vector2(h[0], h[1]), "angle": deg_to_rad(h[2]), "behind": frames[frame].get("weapon_behind", false)}

## How far a weapon kind reaches past the fist, in frame pixels.
static func weapon_reach(kind: StringName) -> float:
	var w: Variant = rig().get("weapons", {}).get(String(kind))
	if not w is Dictionary:
		return 0.0
	return float(w.get("reach", float(w["size"][0]) - float(w["grip"][0])))
