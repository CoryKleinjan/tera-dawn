class_name HeroBody
extends RefCounted
## How a hero looks in the world, yours (TDPlayer) or another player's (TDAvatar): the
## paperdoll rig with its light, and the companion (chair and pet) that comes along. Each
## hero works out its own pose (from your keys, or from what the server passed on); this
## puts it on screen the same way for both.
##
##   body = HeroBody.new(self, world, z)       # in _ready: adds the rig and companion
##   var anim := body.use_skill(look, skill)  # a skill's weapon motion, or a flash
##   body.draw(anim, speed, face, ...)        # every frame

const FRAMES := preload("res://assets/animations/hero.tres")
## The hero's size against everyone else's art (TDStage.TEXEL). MapleStory proportions: he
## stands about a tenth of the screen tall, a little shorter than the townsfolk (TDNpc.SCALE),
## so heroes read as young adventurers among grown-ups, and most monsters come up to him.
## Raised from 0.62 (Cory 2026-10-12: drawn slightly larger), then set so the new paperdoll
## stands as tall as the old hero (TDPlayer.HEIGHT); his art is cut at twice this size, so he
## still shrinks on screen up to 1440p rather than stretching.
const SCALE := 0.735
## A soft warm light that travels with every player, so heroes stand out from the scenery.
const LIGHT := Color(1.0, 0.86, 0.68)
const LIGHT_ENERGY := 0.55
## Where his light sits above his feet (game pixels).
const LIGHT_HEIGHT := 33.0
## The walk and run cycles play at their drawn speed at this ground speed (game pixels a
## tick), faster or slower in step with him, so his feet don't slide.
const STRIDE_SPEED := 3.7
## Poses turned toward upright in game, per animation: {"angle": degrees, "pivot": frame
## pixels}. None: every pose shows as painted (art/reference/hero_look.png).
const UPRIGHT := {}
## Ticks in one blink while he can't be hurt after a hit: hidden for the first half of each.
const BLINK_TICKS := 8

var rig: SpriteRig
## The chair they sit on and the pet trotting after them.
var companion: TDCompanion
var _owner: Node2D
var _world: TDWorld
var _z: float
var _swing := false   # restart the animation on the next draw

## Adds the rig and companion to `owner`, drawn at depth `z` (TDStage.Z_*).
func _init(owner: Node2D, world: TDWorld, z: float) -> void:
	_owner = owner
	_world = world
	_z = z
	rig = make_rig(TDStage.PRIORITY_PLAYER if z >= TDStage.Z_PLAYER else TDStage.PRIORITY_OTHER_PLAYER)
	owner.add_child(rig)
	companion = TDCompanion.new()
	owner.add_child(companion)

## A hero's rig, sized and lit as in the world: in game, and in the menus (PaperdollView),
## so he looks the same in both. Dress it with SpriteRig.dress. `priority`: see
## PaperdollSprite.priority.
static func make_rig(priority: int) -> SpriteRig:
	var r := SpriteRig.new()
	r.setup(FRAMES, null, TDStage.TEXEL * SCALE / Paperdoll.ART_SCALE)
	r.upright = UPRIGHT
	r.breathes = true
	r.hero_priority = priority
	r.add_light(LIGHT, LIGHT_ENERGY, LIGHT_HEIGHT)
	return r

## Plays the next animation from its first frame, even if it's the one already playing (a
## new swing).
func restart() -> void:
	_swing = true

## The motion `skill` makes as the weapon in `look` does it (WeaponStyle), which starts from
## its first frame on the next draw. Buffs and spells make no motion: he flashes the skill's
## colour instead, and this returns &"".
func use_skill(look: Dictionary, skill: SkillDef) -> StringName:
	var anim := WeaponStyle.animation_for(look, skill.animation)
	if WeaponStyle.is_spell(anim):
		rig.pulse(skill.flash_color())
		return &""
	_swing = true
	return anim

## How see-through he is drawn: below 1 while hidden by a buff (Dark Sight, HIDDEN_VEIL).
var veil := 1.0
## Opacity of a hidden hero: your own, and someone else's faint outline.
const HIDDEN_VEIL := 0.45
const HIDDEN_VEIL_OTHERS := 0.2

## Draws the hero this frame: between his last two ticks (TDWorld.drawn), raised onto his
## chair, playing `anim` at `speed` (see stride_speed) and facing `face` (always the same way
## on a rope or ladder, while `climbing`). `blinking` hides him every other few ticks of
## `clock`. Then his chair and pet (item ids, or empty) follow him.
func draw(anim: StringName, speed: float, face: int, climbing: bool, blinking: bool, clock: int, chair: StringName, pet: StringName) -> void:
	var at := _world.drawn(_owner)
	rig.place(at + Vector2(0, -companion.seat_lift()), _z)
	rig.play(anim, _swing)
	rig.set_speed(speed)
	_swing = false
	rig.face(1 if climbing else face)
	rig.set_opacity((0.0 if blinking and clock % BLINK_TICKS < BLINK_TICKS / 2 else 1.0) * veil)
	companion.set_chair(chair)
	companion.set_pet(pet, _owner.position)
	companion.follow(at, face, _z, _world.layout.ground_below(_owner.position))

## How fast an animation plays for a ground speed: walking and running keep step with him.
static func stride_speed(anim: StringName, speed_x: float) -> float:
	if anim in [&"walk", &"run"]:
		return clampf(absf(speed_x) / STRIDE_SPEED, 0.55, 1.4)
	return 1.0
