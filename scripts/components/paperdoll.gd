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
## The skin tone recolours his skin; a worn top, bottom or shoes recolour the chest, shorts
## or feet until the piece has its own art (EquipDef.worn_frames). Hair, irises, capes,
## shields and gloves are greyscale art tinted with the hair, eye or item colour. The weapon
## is a layer too, already placed in his fist on every frame by paperdoll_layers.py, with a
## hole where his fingers wrap the grip (see weapon_layers); a weapon kind is held its own way
## (a bow upright, a staff planted). Hats are drawn on top at a rig point (LookShapes):
## code-drawn stand-ins for now.

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
## The cape seen from behind (climbing), over his back.
const CAPE_BACK_VIEW := preload("res://assets/animations/paperdoll/cape_back_view.tres")
const SHIELD := preload("res://assets/animations/paperdoll/shield_round.tres")
## Gloves on both hands (climbing: bare hands).
const GLOVES := preload("res://assets/animations/paperdoll/gloves.tres")
## Weapon layers: weapon_<kind>.tres (greyscale, tinted) or weapon_item_<id>.tres (a weapon's
## own held picture, in colour), each with an optional _behind twin for frames where the
## weapon is behind his body (far hand, or carried on his back while sitting).
const WEAPON_DIR := "res://assets/animations/paperdoll/weapon_"
## The kind a weapon without one is drawn as.
const DEFAULT_WEAPON := &"sword"
## Shields by EquipDef.look_shape (any other: SHIELD).
const SHIELDS := {&"kite": preload("res://assets/animations/paperdoll/shield_kite.tres")}
## The hero's frame size in pixels; every frame of the strip is this big.
const FRAME_SIZE := Vector2(256, 207)
## How many strip pixels make one "hero pixel", the unit the game sizes him in (TDStage.TEXEL)
## and hat stand-ins are drawn in: the strip is cut at the full resolution of the painted
## sheet, twice as fine as the hero is sized.
const ART_SCALE := 2.0
## Heads bigger or smaller than this (strip pixels) scale hat stand-ins with them.
const HEAD_WIDTH := 40.0 * ART_SCALE

## A stand-in drawn on the hero.
class Overlay:
	var shape: StringName
	var color: Color

	func _init(s: StringName, c: Color) -> void:
		shape = s
		color = c

## A layer of art, played in step with the hero and multiplied by `tint`.
class Layer:
	var frames: SpriteFrames
	var behind := false
	var tint := Color.WHITE

	func _init(f: SpriteFrames, back: bool, t := Color.WHITE) -> void:
		frames = f
		behind = back
		tint = t

## Per region: colour to recolour it with (alpha: how much, 0 keeps the art's own).
var tints := PackedColorArray()
## Per region: 1 hides it.
var hidden := PackedFloat32Array()
var overlays: Array[Overlay] = []
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
	for place in PLACE_REGIONS:
		var e: EquipDef = gear.get(place)
		if e and e.worn_frames == null:
			var c := e.worn_color()
			c.a = PLACE_STRENGTH
			d.tints[PLACE_REGIONS[place]] = c

	# behind him
	var hair := a.part(LookDef.Kind.HAIR)
	var hair_tone := _look_color(a.part(LookDef.Kind.HAIR_COLOR), Region.HAIR)
	var cape: EquipDef = gear.get(&"cape")
	if cape:
		d._add(cape.worn_frames if cape.worn_frames else CAPE, true, Color.WHITE if cape.worn_frames else cape.worn_color())
	if hair and not gear.has(&"hat"):
		d._add(hair.back_frames, true, hair_tone)
	var weapon: EquipDef = gear.get(&"weapon")
	var held := weapon_layers(weapon) if weapon and weapon.worn_frames == null else {}
	if weapon:
		d.weapon_kind = kind_of(weapon)
		d.weapon_tint = weapon.worn_color()
	if held.has("behind"):
		d._add(held["behind"], true, held["tint"])

	# over him
	for place in [&"bottom", &"shoes", &"top", &"gloves"]:
		var e: EquipDef = gear.get(place)
		if e and e.worn_frames:
			d._add(e.worn_frames, false)
			if PLACE_REGIONS.has(place):
				d.hidden[PLACE_REGIONS[place]] = 1.0
		elif e and place == &"gloves":
			d._add(GLOVES, false, e.worn_color())
	if cape and cape.worn_frames == null:
		d._add(CAPE_BACK_VIEW, false, cape.worn_color())
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
			d._add(SHIELDS.get(shield.look_shape, SHIELD), false, shield.worn_color())
	if weapon and weapon.worn_frames:
		d._add(weapon.worn_frames, false)
	elif held.has("front"):
		d._add(held["front"], false, held["tint"])
	var hat: EquipDef = gear.get(&"hat")
	if hat:
		if hat.worn_frames:
			d._add(hat.worn_frames, false)
		elif LookShapes.has(hat.worn_shape()):
			d.overlays.append(Overlay.new(hat.worn_shape(), hat.worn_color()))
	return d

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

## The kind of weapon an item is held as (a weapon without a kind is a sword).
static func kind_of(e: EquipDef) -> StringName:
	return e.weapon_kind if e and e.weapon_kind != &"" else DEFAULT_WEAPON

static func _weapon_frames(base: String, tint: Color) -> Dictionary:
	var out := {"front": load(base + ".tres"), "tint": tint}
	if ResourceLoader.exists(base + "_behind.tres"):
		out["behind"] = load(base + "_behind.tres")
	return out

func _add(frames: SpriteFrames, behind: bool, tint := Color.WHITE) -> void:
	if frames:
		layers.append(Layer.new(frames, behind, tint))

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
	return float(w["size"][0]) - float(w["grip"][0]) if w is Dictionary else 0.0

## How far the head is turned on a frame (degrees clockwise, 0 upright); hats turn with it.
static func head_angle(frame: int) -> float:
	var frames: Array = rig().get("frames", [])
	return float(frames[frame].get("head_angle", 0.0)) if frame >= 0 and frame < frames.size() else 0.0

## Where a stand-in goes on a frame: its centre in frame pixels, its angle (radians, y
## down) and its scale, for a hero facing right; null if the frame has nowhere to put it.
## `mirror` turns it into the hero facing left (flip the picture and use these values).
static func place_overlay(shape: StringName, frame: int, mirror := false) -> Variant:
	var at: Variant = anchor(frame, LookShapes.anchor(shape))
	if at == null:
		return null
	var angle := 0.0
	var scale := 1.0
	if LookShapes.turns(shape):
		var tip: Variant = anchor(frame, &"tip")
		if tip == null:
			return null
		angle = (tip - at).angle()
	elif LookShapes.anchor(shape) != &"grip":
		var head: Variant = anchor(frame, &"head_size")
		if head != null:
			scale = clampf(head.x / HEAD_WIDTH, 0.85, 1.2)
		scale *= ART_SCALE
		angle = deg_to_rad(head_angle(frame))
	var size := LookShapes.texture(shape, Color.WHITE).get_size()
	var centre: Vector2 = at + ((size / 2.0 - LookShapes.pivot(shape)) * scale).rotated(angle)
	if mirror:
		centre.x = FRAME_SIZE.x - centre.x
		angle = -angle
	return {"centre": centre, "angle": angle, "scale": scale}
