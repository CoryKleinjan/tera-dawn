class_name EquipDef
extends ItemDef
## A piece of gear: where it's worn, what it takes to wear it and the stats it gives.
## Each one that drops rolls its own stats around `stats` (see `variance`).

## Kinds of gear. A slot kind can have several places on the body (two rings). A job set is
## one Armor piece (hat to shoes, cape and off-hand all in one) and one weapon; earrings,
## pendants and rings only give stats. The numbers are what the data files hold.
enum Slot { WEAPON = 0, ARMOR = 1, EARRINGS = 7, PENDANT = 8, RING = 9 }
const SLOT_NAMES := {Slot.WEAPON: "Weapon", Slot.ARMOR: "Armor", Slot.EARRINGS: "Earrings",
	Slot.PENDANT: "Pendant", Slot.RING: "Ring"}

@export var slot: Slot = Slot.WEAPON

@export_group("Weapon")
## "sword", "dagger", "bow", "wand", "staff", "knuckle"... Skills can require one.
@export var weapon_kind: StringName
## Replaces the plain attack while wielded (a bow's shot). Null keeps the basic attack.
@export var basic_attack: SkillDef

@export_group("Held look")
## A weapon or off-hand's painting held in the old hero's hand (HeldDef). The hero is now
## painted whole (HeroLookDef) and no longer shows gear, so it is only where the icon comes
## from until the job sets replace it.
@export var held: HeldDef:
	set(v):
		held = v
		_icon_from_look()

@export_group("Requirements")
## Job lines that can wear it (JobDef.family); empty for anyone.
@export var jobs: Array[StringName] = []
## The tuning tier it's made for, like MonsterDef.level: never checked or shown (nothing
## needs a level). Balance and the test characters pick gear by it.
@export var required_level := 0

@export_group("Stats")
@export var stats: StatBlock
## Each nonzero stat on a dropped copy moves up or down by up to this much.
@export var variance := 1

func tab() -> Tab:
	return Tab.EQUIP

## Gear with no icon of its own shows its held painting, with the empty space around it dropped.
func _icon_from_look() -> void:
	if icon:
		return
	var tex: Texture2D = held.texture() if held else null
	if tex == null:
		return
	var used := TextureBounds.used_rect(tex)
	if used.size == Vector2i.ZERO:
		return
	var a := AtlasTexture.new()
	if tex is AtlasTexture:
		a.atlas = (tex as AtlasTexture).atlas
		a.region = Rect2((tex as AtlasTexture).region.position + Vector2(used.position), used.size)
	else:
		a.atlas = tex
		a.region = Rect2(used)
	icon = a

func stack_size() -> int:
	return 1

## "Warriors and Pirates" for a list of job lines.
static func families_text(families: Array[StringName]) -> String:
	var names := []
	for f in families:
		names.append(String(f).capitalize() + "s")
	if names.size() <= 1:
		return "".join(names)
	return ", ".join(names.slice(0, -1)) + " and " + names[-1]

func slot_name() -> String:
	return SLOT_NAMES[slot]
