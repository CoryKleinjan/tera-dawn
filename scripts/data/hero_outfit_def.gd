class_name HeroOutfitDef
extends Resource
## One look painted wearing a job set's pieces (data/hero/outfits/): every frame of that look
## with `armor` on and `weapon` in hand, painted whole like the plain look (HeroLookDef), one
## painting per pair, as a set's armor shows whenever it is worn and its weapon shows with it.
## Either piece may be missing: the armor with an empty hand, or plain clothes with the weapon.
## HeroLookDef.frames_for picks the one a hero is wearing.

## Its file name: the look and the set, "boy_vanguard" or "boy_vanguard_armor".
@export var id: StringName
## The HeroLookDef it is a painting of.
@export var look: StringName
## The armor worn in it (EquipDef id), or empty for plain clothes.
@export var armor: StringName
## The weapon held in it (EquipDef id), or empty for an empty hand.
@export var weapon: StringName
## Its animations, named as the plain look's are.
@export var frames: SpriteFrames

## The painting of `look_id` wearing exactly `armor_id` and `weapon_id`, or null.
static func find(look_id: StringName, armor_id: StringName, weapon_id: StringName) -> HeroOutfitDef:
	for o: HeroOutfitDef in Content.outfits.values():
		if o.look == look_id and o.armor == armor_id and o.weapon == weapon_id:
			return o
	return null
