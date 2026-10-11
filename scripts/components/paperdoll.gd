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
## a weapon, a shield and a hat keep their shape, so each is a Piece: one picture per view that
## goes in his fist, on his arm or on his head on every frame, where the rig says, with his
## fingers drawn over a weapon's grip (fist masks); a weapon kind is held its own way (a bow
## upright, a staff planted). The hair under a hat is the hairstyle's own _hat layer, cut where the hat
## hides it (Piece.hair_cut) so none pokes out of its top or sides.

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
## Pieces (Piece): gear that keeps its shape, one picture per view placed on him each frame.
## weapon_<kind> (greyscale, tinted) or weapon_item_<id> (from its icon), shield_item_<id>,
## hat_<shape> (greyscale, tinted) or hat_item_<id>; fist_<kind>.png cuts his fingers out of a
## weapon over its grip.
const PIECE_DIR := "res://assets/sprites/characters/pieces/"
## The kind a weapon without one is drawn as.
const DEFAULT_WEAPON := &"sword"
## Tops worn open at the front (EquipDef.worn_style), with UNDERSHIRT under them so his
## chest isn't bare, in UNDERSHIRT_COLOR (a plain linen).
const OPEN_TOPS: Array[StringName] = [&"coat"]
const UNDERSHIRT := preload("res://assets/animations/paperdoll/top_undershirt.tres")
const UNDERSHIRT_COLOR := Color(0.86, 0.82, 0.72)
## A piece's own art, drawn from its icon in its own colours (tools/art/paperdoll/items.py):
## worn_item_<id>.tres over him, and for a cape worn_item_<id>_behind.tres under his body
## (the part hanging behind him).
const OWN_DIR := "res://assets/animations/paperdoll/worn_item_"
## The hat shape (EquipDef.look_shape, piece hat_<shape>) of a hat with none.
const DEFAULT_HAT := &"cap"
## Shields by EquipDef.look_shape (any other: SHIELD).
const SHIELDS := {&"kite": preload("res://assets/animations/paperdoll/shield_kite.tres")}
## The hero's frame size in pixels; every frame of the strip is this big.
const FRAME_SIZE := Vector2(256, 208)
## How many strip pixels make one "hero pixel", the unit the game sizes him in (TDStage.TEXEL):
## the strip is cut at the full resolution of the painted sheet, twice as fine as the hero is sized.
const ART_SCALE := 2.0

## A layer of art, played in step with the hero and multiplied by `tint`, or with `gear`
## (greyscale gear art) shaded in it, its light and dark greys turning light and deep shades
## of the colour (gear_tint.gdshaderinc).
class Layer:
	var frames: SpriteFrames
	## Or a piece, placed on each frame (then `behind` is per frame: Piece.pose).
	var piece: Piece
	var behind := false
	var tint := Color.WHITE
	var gear := false
	## Hair under a hat: the hat's hair cut strip (Piece.hair_cut), or null.
	var hair_cut: Texture2D

	func _init(f: SpriteFrames, back: bool, t := Color.WHITE, g := false) -> void:
		frames = f
		behind = back
		tint = t
		gear = g

	## Sets a layer material's uniforms (paperdoll_layer or paperdoll_ui_layer shader).
	func apply(mat: ShaderMaterial) -> void:
		mat.set_shader_parameter(&"tint", tint)
		mat.set_shader_parameter(&"gear", gear)
		mat.set_shader_parameter(&"has_hair_cut", hair_cut != null)
		if hair_cut:
			mat.set_shader_parameter(&"hair_cut", hair_cut)
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

## Gear that keeps its shape (a weapon, shield or hat): a picture per view (held, on his back,
## from the side, from behind...), which goes on him at the place, angle and size its pose for
## each frame says, over him or under his body (tools/art/paperdoll/pieces.py writes them).
class Piece:
	var name := ""
	## view -> {"picture": Texture2D, "anchor": Vector2 (the picture point "at" names)}
	var views := {}
	## Per body frame: null (not shown) or {"view": String, "at": Vector2 (frame pixels),
	## "angle": radians clockwise, "scale": float, "behind": bool, "fist": bool}.
	var frames: Array = []
	## Greyscale art, shaded in the item's colour.
	var tinted := false
	## The fist mask strip cutting his fingers out over its grip (fist_<kind>.png), or null.
	var fist: Texture2D
	## A hat's strip of where his hair is hidden under it (haircut_<name>.png), or null.
	var hair_cut: Texture2D

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
			if data.get("hair_cut") is String and ResourceLoader.exists(data["hair_cut"]):
				p.hair_cut = load(data["hair_cut"])
		_cache[id] = p
		return p

	## How it sits on body frame `frame` (see `frames`), or null when it doesn't show.
	func pose(frame: int) -> Variant:
		return frames[frame] if frame >= 0 and frame < frames.size() else null

	## A pose's picture.
	func picture(p: Dictionary) -> Texture2D:
		return views[p["view"]]["picture"]

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
	var own := {}  # place -> own_art() of the piece worn there
	for place in gear:
		var art := own_art(gear[place])
		if not art.is_empty():
			own[place] = art
	for place in PLACE_REGIONS:
		var e: EquipDef = gear.get(place)
		if e == null or e.worn_frames or own.has(place):
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
		if own.has(&"cape"):
			d._add(own[&"cape"].get("behind"), true)
		elif cape.worn_frames:
			d._add(cape.worn_frames, true)
		else:
			d._add(CAPE, true, cape.worn_color(), true)
	if hair and not gear.has(&"hat"):
		d._add(hair.back_frames, true, hair_tone)
	var weapon: EquipDef = gear.get(&"weapon")
	if weapon:
		d.weapon_kind = kind_of(weapon)
		d.weapon_tint = weapon.worn_color()

	# over him
	for place in [&"bottom", &"shoes", &"top", &"gloves"]:
		var e: EquipDef = gear.get(place)
		var mittens: Array[Piece] = glove_pieces(e) if place == &"gloves" else ([] as Array[Piece])
		if not mittens.is_empty():  # a mitten on each hand (Piece)
			for p: Piece in mittens:
				d._add_piece(p)
		elif own.has(place):
			d._add(own[place]["front"], false)
			if PLACE_REGIONS.has(place):
				d.hidden[PLACE_REGIONS[place]] = 1.0
		elif e and e.worn_frames:
			d._add(e.worn_frames, false)
			if PLACE_REGIONS.has(place):
				d.hidden[PLACE_REGIONS[place]] = 1.0
		elif cuts.has(place):
			if place == &"top" and e.worn_style in OPEN_TOPS:
				d._add(UNDERSHIRT, false, UNDERSHIRT_COLOR, true)
			d._add(cuts[place], false, e.worn_color(), true)
		elif e and place == &"gloves":
			d._add(GLOVES, false, e.worn_color(), true)
	if own.has(&"cape"):
		d._add(own[&"cape"]["front"], false)
	elif cape and cape.worn_frames == null:
		d._add(CAPE_FRONT, false, cape.worn_color(), true)
	var face := a.part(LookDef.Kind.FACE)
	if face:
		d._add(face.frames, false)
		d._add(face.detail_frames, false, _look_color(a.part(LookDef.Kind.EYES), Region.EYES))
	var hat: EquipDef = gear.get(&"hat")
	var own_hat := Piece.named("hat_item_" + String(hat.id)) if hat else null
	var hat_on: Piece = own_hat if own_hat or hat == null or hat.worn_frames else hat_piece(hat)
	if hair:
		var before := d.layers.size()
		d._add(hair.hat_frames if hat and hair.hat_frames else hair.frames, false, hair_tone)
		if hat_on and d.layers.size() > before:  # none of it pokes out of the hat's top or sides
			d.layers[-1].hair_cut = hat_on.hair_cut
	var shield: EquipDef = gear.get(&"shield")
	if shield:
		var own_shield := Piece.named("shield_item_" + String(shield.id))
		if own_shield:  # its back on his far arm, behind him; its face on his back as he climbs
			d._add_piece(own_shield)
		elif shield.worn_frames:
			d._add(shield.worn_frames, false)
		else:
			d._add(SHIELDS.get(shield.look_shape, SHIELD), false, shield.worn_color(), true)
	if hat:
		if own_hat:
			d._add_piece(own_hat)
		elif hat.worn_frames:
			d._add(hat.worn_frames, false)
		else:
			d._add_piece(hat_on, hat.worn_color())
	if weapon and weapon.worn_frames: # over the hat: a sword raised over his head
		d._add(weapon.worn_frames, false)
	elif weapon:
		var held := weapon_piece(weapon)
		d._add_piece(held, Color.WHITE if held.name.begins_with("weapon_item_") else weapon.worn_color())
	return d

## A piece's own art (OWN_DIR): {"front": SpriteFrames, "behind": SpriteFrames (if any)},
## or {} when it has none and is drawn with its kind's tinted greyscale art.
static func own_art(e: EquipDef) -> Dictionary:
	if e == null or e.slot in [EquipDef.Slot.WEAPON, EquipDef.Slot.SHIELD, EquipDef.Slot.HAT]:
		return {}  # (those keep their shape: pieces, see Piece)
	var base := OWN_DIR + String(e.id)
	if not ResourceLoader.exists(base + ".tres"):
		return {}
	var out := {"front": load(base + ".tres")}
	if ResourceLoader.exists(base + "_behind.tres"):
		out["behind"] = load(base + "_behind.tres")
	return out

## The piece a hat without art of its own is drawn as: its shape's (EquipDef.look_shape),
## greyscale, tinted with the hat's colour.
static func hat_piece(e: EquipDef) -> Piece:
	var shape := Piece.named("hat_" + String(e.look_shape)) if e.look_shape != &"" else null
	return shape if shape else Piece.named("hat_" + String(DEFAULT_HAT))

## Gloves' own mittens, one piece per hand (glove_item_<id>_1 and _2), or [] if they have none.
static func glove_pieces(e: EquipDef) -> Array[Piece]:
	var out: Array[Piece] = []
	if e:
		for h in [1, 2]:
			var p := Piece.named("glove_item_%s_%d" % [e.id, h])
			if p:
				out.append(p)
	return out

## The piece a weapon is held as: its own picture (weapon_item_<id>, from its icon, in its
## own colours) if it has one, else its kind's greyscale picture, tinted with its colour.
static func weapon_piece(e: EquipDef) -> Piece:
	var own := Piece.named("weapon_item_" + String(e.id))
	if own:
		return own
	var kind := Piece.named("weapon_" + String(kind_of(e)))
	return kind if kind else Piece.named("weapon_" + String(DEFAULT_WEAPON))

## The greyscale layer a top, bottom or shoes is worn as (EquipDef.worn_style), or null.
static func worn_cut(e: EquipDef) -> SpriteFrames:
	var path := e.worn_style_path()
	return load(path) if path != "" and ResourceLoader.exists(path) else null

## The kind of weapon an item is held as (a weapon without a kind is a sword).
static func kind_of(e: EquipDef) -> StringName:
	return e.weapon_kind if e and e.weapon_kind != &"" else DEFAULT_WEAPON

func _add(frames: SpriteFrames, behind: bool, tint := Color.WHITE, gear := false) -> void:
	if frames:
		layers.append(Layer.new(frames, behind, tint, gear))

## A piece as a layer: untinted, or greyscale art (Piece.tinted) shaded in `tint`.
func _add_piece(p: Piece, tint := Color.WHITE) -> void:
	if p:
		var l := Layer.new(null, false, tint if p.tinted else Color.WHITE, p.tinted)
		l.piece = p
		layers.append(l)

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
