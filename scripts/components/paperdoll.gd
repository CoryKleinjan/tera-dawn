class_name Paperdoll
extends RefCounted
## How a character looks, worked out from their look (Character.look(): appearance and the
## gear that shows). The hero is drawn as layers: his body, then hair, face and each piece
## of gear. PaperdollSprite shows it in the world and PaperdollView in menus.
##
## The hero is still one painted sprite strip, so for now the layers are faked on it:
## tools/art/hero_regions.py maps which of his pixels are hair, skin, eyes, tunic, trousers,
## boots, cape, sword, shield and bracers (hero_regions.png) and where his head, face and
## hand are in every frame (hero_rig.json). The skin tone, eye and hair colour and the
## colour of each worn piece recolour those pixels, gear that isn't worn hides them, and
## hats, hairstyles, faces and weapons other than swords are stand-ins drawn on top
## (LookShapes). When a look or a piece has layered art (LookDef.frames,
## EquipDef.worn_frames), that layer is drawn instead of its stand-in.

## The parts of the painted hero, as hero_regions.png numbers them.
enum Region { NONE, HAIR, SKIN, EYES, TOP, BOTTOM, SHOES, CAPE, WEAPON, SHIELD, GLOVES }
const REGIONS := 11
## Worn places that show on the hero, in drawing order (back to front) for layered art.
const SHOWN_PLACES: Array[StringName] = [&"cape", &"bottom", &"shoes", &"top", &"gloves", &"shield", &"hat", &"weapon"]
## The region each shown place recolours.
const PLACE_REGIONS := {
	&"cape": Region.CAPE, &"bottom": Region.BOTTOM, &"shoes": Region.SHOES, &"top": Region.TOP,
	&"gloves": Region.GLOVES, &"shield": Region.SHIELD, &"weapon": Region.WEAPON,
}
## How strongly a worn piece recolours its region (a little of the painted detail shows).
const PLACE_STRENGTH := {
	&"cape": 0.9, &"bottom": 0.85, &"shoes": 0.85, &"top": 0.85, &"gloves": 0.8, &"shield": 0.65, &"weapon": 0.45,
}
## What shows where nothing is worn: plain undershirt and shorts; bare places are hidden
## (cape, shield, weapon) or keep the painted look (gloves are his bracers).
const BARE := {&"top": Color(0.93, 0.9, 0.82), &"bottom": Color(0.58, 0.56, 0.6)}
const BARE_HIDDEN: Array[StringName] = [&"cape", &"shield", &"weapon"]
## Hairstyle stand-ins on top of the head, which a hat covers.
const UNDER_HAT: Array[StringName] = [&"hair_bun", &"hair_crest"]

const FRAMES := preload("res://assets/animations/hero.tres")
const STRIP := preload("res://assets/sprites/characters/hero.png")
const MASK := preload("res://assets/sprites/characters/hero_regions.png")
const RIG_PATH := "res://assets/sprites/characters/hero_rig.json"
## The hero's frame size in pixels; every frame of the strip is this big.
const FRAME_SIZE := Vector2(132, 91)
## Hair bigger or smaller than this scales head stand-ins with it.
const HEAD_WIDTH := 40.0

## A stand-in drawn on the hero.
class Overlay:
	var shape: StringName
	var color: Color

	func _init(s: StringName, c: Color) -> void:
		shape = s
		color = c

## A layer of real art, played in step with the hero.
class Layer:
	var frames: SpriteFrames
	var behind := false

	func _init(f: SpriteFrames, back: bool) -> void:
		frames = f
		behind = back

## Per region: colour to recolour it with (alpha: how much, 0 keeps the art's own).
var tints := PackedColorArray()
## Per region: 1 hides it.
var hidden := PackedFloat32Array()
var overlays: Array[Overlay] = []
var layers: Array[Layer] = []

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

	# appearance
	var skin := a.part(LookDef.Kind.SKIN)
	if skin and skin.recolors():
		d.tints[Region.SKIN] = skin.color
	var eyes := a.part(LookDef.Kind.EYES)
	if eyes and eyes.recolors():
		d.tints[Region.EYES] = eyes.color
	var hair_color := a.part(LookDef.Kind.HAIR_COLOR)
	var hair_tone := ref_color(Region.HAIR)
	if hair_color and hair_color.recolors():
		d.tints[Region.HAIR] = hair_color.color
		hair_tone = hair_color.color
	for kind in [LookDef.Kind.HAIR, LookDef.Kind.FACE]:
		var l := a.part(kind)
		if l and l.frames:
			d.layers.append(Layer.new(l.frames, false))
		elif l and LookShapes.has(l.shape) and not (gear.has(&"hat") and l.shape in UNDER_HAT):
			d.overlays.append(Overlay.new(l.shape, hair_tone if kind == LookDef.Kind.HAIR else Color.WHITE))

	# gear
	for place in SHOWN_PLACES:
		var e: EquipDef = gear.get(place)
		var region: int = PLACE_REGIONS.get(place, Region.NONE)
		if e == null:
			if place in BARE_HIDDEN:
				d.hidden[region] = 1.0
			elif BARE.has(place):
				d.tints[region] = BARE[place]
			continue
		if e.worn_frames:
			d.layers.append(Layer.new(e.worn_frames, place == &"cape"))
			if region != Region.NONE:
				d.hidden[region] = 1.0
			continue
		var shape := e.worn_shape()
		if place == &"weapon" and shape != &"sword":
			d.hidden[region] = 1.0 # the painted sword makes way for the stand-in
		elif region != Region.NONE:
			var c := e.worn_color()
			c.a = PLACE_STRENGTH[place]
			d.tints[region] = c
			continue
		if LookShapes.has(shape):
			d.overlays.append(Overlay.new(shape, e.worn_color()))
	return d

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
	var size := LookShapes.texture(shape, Color.WHITE).get_size()
	var centre: Vector2 = at + ((size / 2.0 - LookShapes.pivot(shape)) * scale).rotated(angle)
	if mirror:
		centre.x = FRAME_SIZE.x - centre.x
		angle = -angle
	return {"centre": centre, "angle": angle, "scale": scale}
