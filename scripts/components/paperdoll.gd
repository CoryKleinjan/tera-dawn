class_name Paperdoll
extends RefCounted
## How a character looks, worked out from their look (Character.look(): appearance and the
## gear that shows). The hero is a boy or a girl body (the hairstyle's LookDef.body), drawn as
## layers that play frame for frame with it: a bald body with its painted face, then each
## piece of gear and the hair, each a strip laid out like the body strip
## (tools/art/hero_build.py makes them all from the painted sheets in art/source/hero/).
## PaperdollSprite shows it in the world and PaperdollView in menus.
##
## The body (hero.png, both bodies side by side) comes with a region map (hero_regions.png:
## which pixels are skin, so the skin tone recolours them) and a rig (hero_rig.json: each
## frame's pose and where his head is). Hair is greyscale, tinted with the hair colour.
## Worn gear is its own art in its own colours (layers/worn_item_<id>.png). A hat is drawn
## in one of the hat shapes of the hat/hair templates (EquipDef.look_shape): under it shows
## that shape's hair for his hairstyle (hair_<style>_<shape>.png) instead of his own, and his
## body is cut away where the hat hides it (pieces/headcut_<shape>.png: his ear under a helm).
## A weapon or shield keeps its shape, so it is a Piece: one picture per view placed in his
## fist or on his arm on every frame, where the rig says.

## The parts of the body, as hero_regions.png numbers them. Only skin is on the map now;
## the rest are kept so the numbers stay put.
enum Region { NONE, HAIR, SKIN, EYES, TOP, BOTTOM, SHOES, CAPE, WEAPON, SHIELD, GLOVES }
const REGIONS := 11
## Worn places with art of their own, in drawing order (back to front) over his body. The hat
## and weapon go over the hair, after these.
const WORN_PLACES: Array[StringName] = [&"cape", &"bottom", &"shoes", &"top", &"gloves"]
## Every worn place that shows on him (Character.look sends these).
const SHOWN_PLACES: Array[StringName] = [&"cape", &"bottom", &"shoes", &"top", &"gloves", &"shield", &"hat", &"weapon"]

## Each body's animations over the strip, by LookDef.body.
const BODIES := {
	&"boy": preload("res://assets/animations/hero.tres"),
	&"girl": preload("res://assets/animations/hero_girl.tres"),
}
const DEFAULT_BODY := &"boy"
## Any body's animations (every body has the same ones, with the same timings).
const FRAMES: SpriteFrames = BODIES[DEFAULT_BODY]
const STRIP := preload("res://assets/sprites/characters/hero.png")
const MASK := preload("res://assets/sprites/characters/hero_regions.png")
const RIG_PATH := "res://assets/sprites/characters/hero_rig.json"
## Layer strips: hair_<style>.png, hair_<style>_<hat shape>.png, worn_item_<id>.png.
const LAYER_DIR := "res://assets/sprites/characters/layers/"
## Pieces (Piece): weapon_item_<id> and shield_item_<id>, one picture per view placed on him
## each frame; fist_<kind>.png cuts his fingers out of a weapon over its grip. Also each hat
## shape's head cut (headcut_<shape>.png).
const PIECE_DIR := "res://assets/sprites/characters/pieces/"
## The kind a weapon without one is held as.
const DEFAULT_WEAPON := &"sword"
## The hero's frame size in pixels; every frame of the strip is this big.
const FRAME_SIZE := Vector2(256, 208)
## How many strip pixels make one "hero pixel", the unit the game sizes him in (TDStage.TEXEL):
## the strip is cut at twice the size he is drawn.
const ART_SCALE := 2.0
## A layer of art, played in step with the hero: a strip laid out like the body strip, or a
## piece placed on each frame. Multiplied by `tint`, or with `gear` (greyscale gear art) shaded
## in it (gear_tint.gdshaderinc).
class Layer:
	var strip: Texture2D
	## Or a piece, placed on each frame (then `behind` is per frame: Piece.pose).
	var piece: Piece
	var behind := false
	var tint := Color.WHITE
	var gear := false

	func _init(s: Texture2D, back: bool, t := Color.WHITE, g := false) -> void:
		strip = s
		behind = back
		tint = t
		gear = g

	## Sets a layer material's uniforms (the paperdoll_layer shader).
	func apply(mat: ShaderMaterial) -> void:
		mat.set_shader_parameter(&"tint", tint)
		mat.set_shader_parameter(&"gear", gear)
		mat.set_shader_parameter(&"has_hair_cut", false)
		mat.set_shader_parameter(&"has_fist", piece != null and piece.fist != null)
		if piece and piece.fist:
			mat.set_shader_parameter(&"fist", piece.fist)
			mat.set_shader_parameter(&"frame_size", FRAME_SIZE)

	## Sets the uniforms that place a piece's fist cut (paperdoll_piece.gdshaderinc) for
	## frame `frame` in pose `p` (Piece.pose).
	func apply_pose(mat: ShaderMaterial, frame: int, p: Dictionary) -> void:
		if piece.fist == null:
			return
		var v: Dictionary = piece.views[p["view"]]
		mat.set_shader_parameter(&"fist_on", p["fist"])
		mat.set_shader_parameter(&"frame", float(frame))
		mat.set_shader_parameter(&"at", p["at"])
		mat.set_shader_parameter(&"anchor", v["anchor"])
		mat.set_shader_parameter(&"turn", p["angle"])
		mat.set_shader_parameter(&"grow", p["scale"])
		mat.set_shader_parameter(&"picture_size", (v["picture"] as Texture2D).get_size())

## Gear that keeps its shape (a weapon or shield): a picture per view (held, on his back...),
## which goes on him at the place, angle and size its pose for each frame says, over him or
## under his body.
class Piece:
	var name := ""
	## view -> {"picture": Texture2D, "anchor": Vector2 (the picture point "at" names)}
	var views := {}
	## Per strip frame: null (not shown) or {"view": String, "at": Vector2 (frame pixels),
	## "angle": radians clockwise, "scale": float, "behind": bool, "fist": bool}.
	var frames: Array = []
	## Greyscale art, shaded in the item's colour.
	var tinted := false
	## The fist mask strip cutting his fingers out over its grip (fist_<kind>.png), or null.
	var fist: Texture2D

	static var _cache := {}

	## The piece called `id` (PIECE_DIR<id>.json), or null if there's none.
	static func named(id: String) -> Piece:
		if _cache.has(id):
			return _cache[id]
		var p: Piece = null
		var f := FileAccess.open(PIECE_DIR + id + ".json", FileAccess.READ)
		var data: Variant = JSON.parse_string(f.get_as_text()) if f else null
		if data is Dictionary:
			p = Piece.new()
			p.name = id
			p.tinted = data.get("tinted", false)
			for view in data["views"]:
				var v: Dictionary = data["views"][view]
				p.views[view] = {"picture": load(v["picture"]), "anchor": Vector2(v["anchor"][0], v["anchor"][1])}
			for e: Variant in data["frames"]:
				p.frames.append(null if e == null else {"view": e["view"], "at": Vector2(e["at"][0], e["at"][1]),
					"angle": deg_to_rad(e["angle"]), "scale": float(e["scale"]), "behind": e["behind"], "fist": e["fist"]})
			if data.get("fist") is String and ResourceLoader.exists(PIECE_DIR + "fist_" + data["fist"] + ".png"):
				p.fist = load(PIECE_DIR + "fist_" + data["fist"] + ".png")
		_cache[id] = p
		return p

	## How it sits on strip frame `frame` (see `frames`), or null when it doesn't show.
	func pose(frame: int) -> Variant:
		return frames[frame] if frame >= 0 and frame < frames.size() else null

	## A pose's picture.
	func picture(p: Dictionary) -> Texture2D:
		return views[p["view"]]["picture"]

## Per region: colour to recolour it with (alpha: how much, 0 keeps the art's own).
var tints := PackedColorArray()
## Per region: 1 hides it.
var hidden := PackedFloat32Array()
## The body's animations (BODIES).
var frames: SpriteFrames = FRAMES
## Where the body is cut away under the hat (headcut_<shape>.png), or null.
var head_cut: Texture2D
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
	var hair := a.part(LookDef.Kind.HAIR)
	d.frames = BODIES.get(hair.body if hair else DEFAULT_BODY, FRAMES)
	var skin := a.part(LookDef.Kind.SKIN)
	if skin and skin.recolors():
		d.tints[Region.SKIN] = skin.color
	var hat: EquipDef = gear.get(&"hat")
	if hat and ResourceLoader.exists(head_cut_path(hat.look_shape)):
		d.head_cut = load(head_cut_path(hat.look_shape))

	# behind him, then over him
	var shield: EquipDef = gear.get(&"shield")
	var own_shield := Piece.named("shield_item_" + String(shield.id)) if shield else null
	for place in WORN_PLACES:
		var e: EquipDef = gear.get(place)
		var art := worn_strip(e)
		if art:
			d._add(art, false)
	if own_shield:  # on his far arm, behind him; on his back as he climbs
		d._add_piece(own_shield)
	if hair:
		var hair_art := hair_strip(hair, hat.look_shape if hat else &"")
		if hair_art:
			d._add(hair_art, false, _look_color(a.part(LookDef.Kind.HAIR_COLOR), Region.HAIR))
	var hat_art := worn_strip(hat)
	if hat_art:
		d._add(hat_art, false)
	var weapon: EquipDef = gear.get(&"weapon")
	if weapon:
		d.weapon_kind = kind_of(weapon)
		d.weapon_tint = weapon.worn_color()
		d._add_piece(Piece.named("weapon_item_" + String(weapon.id)))
	return d

## A piece's own art over him (LAYER_DIR worn_item_<id>.png), or null when it has none.
static func worn_strip(e: EquipDef) -> Texture2D:
	if e == null:
		return null
	var path := LAYER_DIR + "worn_item_" + String(e.id) + ".png"
	return load(path) if ResourceLoader.exists(path) else null

## His hair: the hairstyle's own, or under a hat of shape `hat_shape` that shape's hair for
## the style (none if it has none drawn).
static func hair_strip(hair: LookDef, hat_shape: StringName) -> Texture2D:
	var path := LAYER_DIR + String(hair.id) + ("_" + String(hat_shape) if hat_shape != &"" else "") + ".png"
	return load(path) if ResourceLoader.exists(path) else null

## Where the body is cut away under a hat of shape `shape`.
static func head_cut_path(shape: StringName) -> String:
	return PIECE_DIR + "headcut_" + String(shape) + ".png"

## The kind of weapon an item is held as (how it fights: WeaponStyle). A weapon without a
## kind, or of a kind WeaponStyle doesn't know, is held as a sword.
static func kind_of(e: EquipDef) -> StringName:
	if e == null or e.weapon_kind == &"" or not WeaponStyle.MOTIONS.has(e.weapon_kind):
		return DEFAULT_WEAPON
	return e.weapon_kind

func _add(strip: Texture2D, behind: bool, tint := Color.WHITE, gear := false) -> void:
	if strip:
		layers.append(Layer.new(strip, behind, tint, gear))

## A piece as a layer: untinted, or greyscale art (Piece.tinted) shaded in `tint`.
func _add_piece(p: Piece, tint := Color.WHITE) -> void:
	if p:
		var l := Layer.new(null, false, tint if p.tinted else Color.WHITE, p.tinted)
		l.piece = p
		layers.append(l)

## A look's colour, or the art's own colour for the region when it keeps it.
static func _look_color(l: LookDef, region: Region) -> Color:
	return l.color if l and l.recolors() else ref_color(region)

## Sets a dressing material's uniforms (the paperdoll_sprite shader). The
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
	mat.set_shader_parameter(&"has_head_cut", head_cut != null)
	if head_cut:
		mat.set_shader_parameter(&"head_cut", head_cut)

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
