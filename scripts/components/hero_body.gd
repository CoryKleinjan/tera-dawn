class_name HeroBody
extends RefCounted
## How a hero shows in the world, yours (TDPlayer) or another player's (TDAvatar): his painted
## layers stacked frame by frame (HeroLookDef: body, his face and hairstyle (HeroStyleDef), then
## each piece of gear's EquipDef.worn) and the pet trotting after him (TDCompanion). Both kinds
## of hero draw the same way.
##
##   body = HeroBody.new(self, world, z)               # in _ready: adds the companion
##   body.draw(face, pet, animation, worn)             # every frame (the layers are set up
##                                                      # again only when the frame, facing, gear or looks change)

const LOOK: HeroLookDef = preload("res://data/hero/look.tres")
## Where each held piece's shots start (MuzzleSetDef).
const MUZZLES: MuzzleSetDef = preload("res://data/hero/muzzles.tres")
## How far in front of the one below it each layer sits (3D units), so the layers stack in
## order without fighting over depth.
const LAYER_STEP := 0.002
## Worn places drawn behind his body, and over it under and over his top (a held weapon or
## off-hand goes where its pin says, HeldDef.Layer). Any piece can be moved, turned and
## restacked per frame (Layer).
const BACK := [&"cape"]
const UNDER := [&"bottom", &"shoes"]
const OVER := [&"top", &"gloves"]

## The pet trotting after them.
var companion: TDCompanion
## His face and hairstyle (HeroStyleDef), LOOK's first of each unless set.
var face_style: HeroStyleDef = LOOK.faces[0]
var hair_style: HeroStyleDef = LOOK.hairs[0]
var visible := true:
	set(v):
		visible = v
		for s in _layers:
			s.visible = v and s.texture != null
var _owner: Node2D
var _world: TDWorld
var _z: float
## One sprite per layer, back to front, made as needed.
var _layers: Array[Sprite3D] = []
## What the layers were last set up for (frame, facing, gear and looks): while it stays the
## same, only where he stands changes, so the stack isn't built again.
var _shown: Array = []
## Each layer's place relative to his feet, in game pixels, as last set up.
var _offsets: Array[Vector2] = []
## The animation showing and the physics tick it started on, so frames run from its start in
## game time (a slow frame doesn't skip or hold a step).
var _anim := &""
var _since := 0
## What he wore when last drawn (place -> EquipDef), for muzzle().
var _worn: Dictionary = {}

## Holds the animation where it is for `ticks` physics ticks (hit-stop, TDPlayer.hit_stop):
## the frame clock starts that much later.
func hold(ticks: int) -> void:
	_since += ticks

## Adds the companion to `owner`, drawn at depth `z` (TDStage.Z_*).
func _init(owner: Node2D, world: TDWorld, z: float) -> void:
	_owner = owner
	_world = world
	_z = z
	companion = TDCompanion.new()
	owner.add_child(companion)

## Draws the hero this frame, between his last two ticks (TDWorld.drawn), facing `face`, doing
## `anim` (TDPlayer._animation) and wearing `worn` (place -> EquipDef). His pet (an item id,
## or empty) follows him.
func draw(face: int, pet: StringName, anim: StringName, worn: Dictionary) -> void:
	var at := _world.drawn(_owner)
	companion.set_pet(pet, _owner.position)
	companion.follow(at, face, _z, _world.layout.ground_below(_owner.position))
	if anim != _anim:
		_anim = anim
		_since = Engine.get_physics_frames()
	_worn = worn
	var weapon: EquipDef = worn.get(&"weapon")
	var frame := LOOK.frame_at(anim, weapon.weapon_kind if weapon else &"", float(Engine.get_physics_frames() - _since) / Engine.physics_ticks_per_second)
	var shown := [frame, face, face_style, hair_style, worn.values()]
	if shown != _shown:
		_shown = shown
		_set_up(worn, frame, face)
	for i in _layers.size():
		var s := _layers[i]
		if s.texture:
			s.position = TDStage.to3d(at + _offsets[i], _z + i * LAYER_STEP)

## Where a shot of `anim` (SkillDef.animation) leaves from, from his feet in game pixels
## facing `face`: the muzzle (MUZZLES) of the held piece showing on the frame the shot leaves
## on (MuzzleSetDef.frames, else the move's first), the off-hand first (a pistol or star
## beside a sword), else his shooting fist there (MuzzleSetDef.hands), or null for neither.
func muzzle(anim: StringName, face: int) -> Variant:
	return muzzle_of(_worn, anim, face)

## muzzle() for a hero wearing `worn` (place -> EquipDef).
static func muzzle_of(worn: Dictionary, anim: StringName, face: int) -> Variant:
	var weapon: EquipDef = worn.get(&"weapon")
	var move := LOOK.resolve(anim, weapon.weapon_kind if weapon else &"")
	var frame: StringName = MUZZLES.frames.get(move, LOOK.frame_at(move, &"", 0.0))
	if not LOOK.body.has_animation(frame):
		return null
	var at: Variant = MUZZLES.hands.get(frame)
	for e: EquipDef in [worn.get(&"shield"), weapon]:
		if e and e.held and e.held.shows(frame) and MUZZLES.points.has(e.id):
			var pin: Vector4 = e.held.pins[frame]
			var k := float(e.held.sizes.get(frame, 1.0))
			var off := (MUZZLES.points[e.id] as Vector2) - e.held.anchor
			if e.held.flipped(frame):
				off.x = -off.x
			# flipped, turned and sized the way the piece is drawn (_place), in his frame's pixels
			at = Vector2(pin.x, pin.y) + off.rotated(deg_to_rad(pin.z)) * k
			break
	if at == null:
		return null
	var size := LOOK.body.get_frame_texture(frame, 0).get_size()
	var texel := TDStage.TEXEL / TDStage.frames_density(LOOK.body)
	return Vector2(((at as Vector2).x - size.x / 2.0) * face, (at as Vector2).y - size.y) * texel

## Sets every layer up for `frame` facing `face` in `worn`: which picture it shows, flipped,
## turned, sized and mirrored, and where it sits from his feet (_offsets).
func _set_up(worn: Dictionary, frame: StringName, face: int) -> void:
	var stack := layers(worn, frame, face_style, hair_style)
	while _layers.size() < stack.size():
		_layers.append(_new_layer())
		_offsets.append(Vector2.ZERO)
	var size := LOOK.body.get_frame_texture(frame, 0).get_size() if LOOK.body.has_animation(frame) else Vector2.ZERO
	for i in _layers.size():
		var s := _layers[i]
		var layer: Layer = stack[i] if i < stack.size() else null
		s.texture = null
		s.rotation = Vector3.ZERO
		s.scale = Vector3.ONE
		var tex := layer.texture(frame) if layer else null
		if tex and size != Vector2.ZERO:
			var pin := layer.pin(frame)
			_offsets[i] = _place(s, tex, layer.anchor(frame), Vector2(pin.x, pin.y), pin.z, layer.size(frame), layer.flipped(frame), size, face)
		s.visible = visible and s.texture != null

## Puts `s` showing `tex` with its point `anchor` (its own pixels) on `pin` (the pixels of his
## frames, `size`, whose bottom middle is at his feet), mirrored around `anchor` when `flip`,
## turned `deg` clockwise and drawn `k` times as big around it, and all of that mirrored when
## he faces left. Returns where it sits from his feet, in game pixels.
func _place(s: Sprite3D, tex: Texture2D, anchor: Vector2, pin: Vector2, deg: float, k: float, flip: bool, size: Vector2, face: int) -> Vector2:
	var texel := TDStage.TEXEL / TDStage.frames_density(LOOK.body)
	var facing := -face if flip else face  # which way its painting faces on screen
	s.texture = tex
	s.flip_h = facing < 0
	s.offset = Vector2((tex.get_width() / 2.0 - anchor.x) * facing, anchor.y - tex.get_height() / 2.0)
	s.rotation.z = -deg_to_rad(deg) * face
	s.scale = Vector3(k, k, 1.0)
	return Vector2((pin.x - size.x / 2.0) * face, pin.y - size.y) * texel

## His layers back to front on `frame` for what he wears (place -> EquipDef), with his face and
## hairstyle (HeroStyleDef, LOOK's first of each when null): a held piece set
## behind him, what hangs behind him, his body, his trousers and shoes, held pieces under his top,
## his top, his face, his hair (or under a hat that covers it, the bits of it sticking out), his hat, held pieces over
## his clothes, his fists over the grip (or resting, LOOK.resting_hand_frames), held pieces over
## his hands. Each held piece's pin says
## its layer on that frame; any other piece can be moved up or down the stack on a frame by its
## nudge (Vector4.w). The off-hand only shows while the weapon does. Under long sleeves the fists
## painted with bare forearms are left off.
static func layers(worn: Dictionary, frame: StringName, face: HeroStyleDef = null, hair_style: HeroStyleDef = null) -> Array[Layer]:
	var out: Array[Layer] = []
	var offhand: EquipDef = worn.get(&"shield")
	var hat: EquipDef = worn.get(&"hat")
	var weapon: EquipDef = worn.get(&"weapon")
	var top: EquipDef = worn.get(&"top")
	var shown := weapon != null and _shows(weapon, frame)
	if weapon and not shown:
		offhand = null  # put away with the weapon (sitting, lying down)
	var held := {}  # HeldDef.Layer -> [EquipDef]
	for e: EquipDef in [offhand, weapon]:
		if e and e.held and e.held.shows(frame):
			held.get_or_add(e.held.layer(frame), []).append(e)
	_add(out, held.get(HeldDef.Layer.BEHIND, []), true)
	_add(out, [offhand] + BACK.map(func(p): return worn.get(p)))
	out.append(Layer.new(LOOK, &"body"))
	_add(out, UNDER.map(func(p): return worn.get(p)))
	_add(out, held.get(HeldDef.Layer.UNDER_TOP, []), true)
	_add(out, OVER.map(func(p): return worn.get(p)))
	out.append(Layer.new(face if face else LOOK.faces[0], &"face"))
	var hs: HeroStyleDef = hair_style if hair_style else LOOK.hairs[0]
	var hair := Layer.new(hs, &"hair")
	if hair.added(frame) or not (hat and hat.hides_hair and Layer.new(hat).shows(frame)):
		out.append(hair)
	elif hs.under_hats.has(hat.id):
		out.append(Layer.new(hs.under_hats[hat.id], &"hair_under"))  # the bits sticking out
	_add(out, [hat, weapon])
	_add(out, held.get(HeldDef.Layer.OVER_CLOTHES, []), true)
	var hands := Layer.new(LOOK, &"hands")
	if hands.added(frame) or (shown or frame in LOOK.resting_hand_frames) and not (top and top.long_sleeves and frame in LOOK.bare_arm_frames):
		out.append(hands)
	_add(out, held.get(HeldDef.Layer.OVER_HANDS, []), true)
	out = out.filter(func(l: Layer): return l.shows(frame))
	# A piece moved up or down the stack goes just past the one it is moved over or under.
	var keys := {}
	for i in out.size():
		var w := out[i].steps(frame)
		keys[out[i]] = Vector2(i + w + signf(w) * 0.5, i)
	out.sort_custom(func(a: Layer, b: Layer): return keys[a] < keys[b])
	return out

static func _shows(e: EquipDef, frame: StringName) -> bool:
	return Layer.new(e).shows(frame)

## Adds each piece of `gear` worn as a layer (or, with `held`, its held painting); nulls are skipped.
static func _add(out: Array[Layer], gear: Array, held := false) -> void:
	for e in gear:
		if e and ((e as EquipDef).held if held else (e as EquipDef).worn):
			out.append(Layer.new(e))

func _new_layer() -> Sprite3D:
	var s := Sprite3D.new()
	TDStage.style_sprite(s, TDStage.TEXEL / TDStage.frames_density(LOOK.body))
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_owner.add_child(s)
	return s

## One layer of his stack: a piece of gear (its worn frames or held painting), his face or
## hairstyle (HeroStyleDef) or one of LOOK's parts (his body or fists), and where it sits on a
## frame. Moved by hand in its data file.
class Layer:
	## The EquipDef or HeroStyleDef, or LOOK for his body and fists.
	var owner: Resource
	## Which of his parts (&"body", &"face", &"hair", &"hair_under", &"hands"); empty for gear.
	var part: StringName
	## Texture -> the middle of its painted pixels, what a moved piece turns around.
	static var _middles := {}

	func _init(o: Resource, p := &"") -> void:
		owner = o
		part = p

	## The held painting, when this is a held piece.
	func held() -> HeldDef:
		return (owner as EquipDef).held if owner is EquipDef else null

	## Its frames, when this is a worn layer or one of his parts.
	func frames() -> SpriteFrames:
		if owner is EquipDef:
			return (owner as EquipDef).worn
		if owner is HeroStyleDef:
			return (owner as HeroStyleDef).frames
		return owner.get(part) as SpriteFrames

	## The resource holding its own nudges, sizes and frame art (gear or a face or hairstyle), or
	## null for LOOK's parts, kept per part in LOOK.
	func _own() -> Resource:
		return owner if owner is EquipDef or owner is HeroStyleDef else null

	## Frame -> Vector4(x, y, degrees clockwise, places up the stack) it is moved by. A held
	## piece is placed by its pins instead (HeldDef.pins).
	func nudges() -> Dictionary:
		if _own():
			return _own().get("nudges")
		return (owner as HeroLookDef).nudges.get(part, {})

	## Moves it by `n` on `frame` (see nudges); zero clears it.
	func set_nudge(frame: StringName, n: Vector4) -> void:
		var all: Dictionary = _own().get("nudges") if _own() else (owner as HeroLookDef).nudges.get_or_add(part, {})
		if n == Vector4.ZERO:
			all.erase(frame)
		else:
			all[frame] = n

	## Frame -> how big it is drawn there (1.0 as painted).
	func sizes() -> Dictionary:
		if held():
			return held().sizes
		if _own():
			return _own().get("sizes")
		return (owner as HeroLookDef).sizes.get(part, {})

	func size(frame: StringName) -> float:
		return float(sizes().get(frame, 1.0))

	## Draws it `k` times as big on `frame` (see sizes); 1.0 clears it.
	func set_size(frame: StringName, k: float) -> void:
		var all: Dictionary
		if held():
			all = held().sizes
		elif _own():
			all = _own().get("sizes")
		else:
			all = (owner as HeroLookDef).sizes.get_or_add(part, {})
		if is_equal_approx(k, 1.0):
			all.erase(frame)
		else:
			all[frame] = k

	## Frame -> true where it is drawn mirrored around the point it turns around, before it is
	## turned (Flip).
	func flips() -> Dictionary:
		if held():
			return held().flips
		if _own():
			return _own().get("flips")
		return (owner as HeroLookDef).flips.get(part, {})

	func flipped(frame: StringName) -> bool:
		return bool(flips().get(frame, false))

	## Draws it mirrored on `frame` (see flips), or as painted.
	func set_flipped(frame: StringName, on: bool) -> void:
		var all: Dictionary
		if held():
			all = held().flips
		elif _own():
			all = _own().get("flips")
		else:
			all = (owner as HeroLookDef).flips.get_or_add(part, {})
		if on:
			all[frame] = true
		else:
			all.erase(frame)

	## Frame -> the frame whose painting shows there, or &"" for none, set by hand
	## (EquipDef.frame_art); frames not listed show their own painting.
	func frame_art() -> Dictionary:
		if _own():
			return _own().get("frame_art")
		return (owner as HeroLookDef).frame_art.get(part, {})

	func set_frame_art(frame: StringName, art: Variant) -> void:
		var all: Dictionary = _own().get("frame_art") if _own() else (owner as HeroLookDef).frame_art.get_or_add(part, {})
		if art == null:
			all.erase(frame)
		else:
			all[frame] = art

	## The frame whose painting it shows on `frame` (&"" for none).
	func art(frame: StringName) -> StringName:
		return frame_art().get(frame, frame)

	## Added to `frame` by hand, so it shows there even where the stack would leave it off (hair
	## under a hat, fists with no weapon out).
	func added(frame: StringName) -> bool:
		return held() == null and frame_art().get(frame, &"") != &""

	func shows(frame: StringName) -> bool:
		var h := held()
		if h:
			return h.shows(frame)
		var f := frames()
		return f != null and f.has_animation(art(frame))

	func texture(frame: StringName) -> Texture2D:
		var h := held()
		return h.texture() if h else frames().get_frame_texture(art(frame), 0)

	## How many places up (negative: down) the stack it is moved on `frame`.
	func steps(frame: StringName) -> int:
		return 0 if held() else int((nudges().get(frame, Vector4.ZERO) as Vector4).w)

	## The point of its painting that sits on its pin and that it turns around.
	func anchor(frame: StringName) -> Vector2:
		var h := held()
		if h:
			return h.anchor
		var tex := texture(frame)
		if not _middles.has(tex):
			_middles[tex] = Rect2(TextureBounds.used_rect(tex)).get_center()
		return _middles[tex]

	## Vector3(x, y, degrees clockwise): where its anchor sits on `frame`, in his frame's pixels
	## (worn layers are painted the size of his frames and line up corner to corner).
	func pin(frame: StringName) -> Vector3:
		var h := held()
		if h:
			var p: Vector4 = h.pins[frame]
			return Vector3(p.x, p.y, p.z)
		var n: Vector4 = nudges().get(frame, Vector4.ZERO)
		var a := anchor(frame)
		return Vector3(a.x + n.x, a.y + n.y, n.z)
