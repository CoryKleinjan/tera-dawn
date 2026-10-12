class_name WeaponStyle
extends RefCounted
## How each kind of weapon fights: which of the hero's animations (assets/animations/hero.tres)
## a skill plays with it. A skill names a motion (SkillDef.animation): "attack" is the
## weapon's own basic blow, "slash" its big one; any other name ("throw") is played as it
## is, whatever the weapon, except "cast" (SPELL), which plays nothing. Your own game and
## everyone watching you work it out the same way from the weapon you wear, so they all see
## the same motion.
##
## Add a weapon kind with a row here, its holds in art/sheets/paperdoll_rig.json and its
## picture on the paperdoll weapons sheet (see docs/architecture/items.md "How to add a weapon").

## weapon kind -> {motion: animation}
const MOTIONS := {
	&"sword": {&"attack": &"attack", &"slash": &"slash"},
	&"wand": {&"attack": &"attack", &"slash": &"cast"},
	&"staff": {&"attack": &"heavy", &"slash": &"cast"},
	&"bow": {&"attack": &"shoot", &"slash": &"shoot"},
	&"gun": {&"attack": &"gun", &"slash": &"gun"},
	&"star": {&"attack": &"throw", &"slash": &"throw"},
	&"knuckle": {&"attack": &"punch", &"slash": &"slash"},
}
## With nothing in hand.
const UNARMED := {&"attack": &"punch", &"slash": &"slash"}
## The motion of buffs and spells: it plays no animation at all. The hero flashes the skill's
## colour (SkillDef.flash) and carries on with whatever he was doing.
const SPELL := &"cast"
## Every animation a skill can play (each restarts when the skill is used again).
const ACTIONS: Array[StringName] = [&"attack", &"slash", &"punch", &"throw", &"shoot", &"gun", &"heavy"]
## The frame each throwing or shooting animation lets go on: the shot leaves his hand there.
const RELEASES := {&"throw": 1, &"shoot": 1, &"gun": 1}
## Weapon kinds that leave his hand when thrown: gone from his fist from the release frame
## until the throw ends.
const THROWN: Array[StringName] = [&"star"]
## Weapon kinds that show their shot on the weapon while he draws (the arrow on the string).
const NOCKED: Array[StringName] = [&"bow"]

## The animation a motion plays with a weapon kind (&"" for bare hands).
static func animation(kind: StringName, motion: StringName) -> StringName:
	var row: Dictionary = MOTIONS.get(kind, MOTIONS[Paperdoll.DEFAULT_WEAPON]) if kind != &"" else UNARMED
	return row.get(motion, motion)

## Whether an animation is a skill being used (not moving about).
static func is_action(anim: StringName) -> bool:
	return anim in ACTIONS

## Whether an animation is a buff or spell going off (no motion, a flash instead).
static func is_spell(anim: StringName) -> bool:
	return anim == SPELL

## The kind of weapon a look (Character.look()) holds, or &"" for bare hands.
static func kind_in(look: Dictionary) -> StringName:
	var gear: Variant = look.get("gear")
	if not gear is Dictionary or not gear.has("weapon"):
		return &""
	return Paperdoll.kind_of(Content.items.get(StringName(str(gear["weapon"]))) as EquipDef)

## What someone wearing `look` plays for a motion.
static func animation_for(look: Dictionary, motion: StringName) -> StringName:
	return animation(kind_in(look), motion)
