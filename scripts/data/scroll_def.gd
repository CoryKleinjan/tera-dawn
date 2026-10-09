class_name ScrollDef
extends ItemDef
## An upgrade scroll, like MapleStory's: used on a piece of gear in the bag that has
## upgrades left, it always spends one of them and, with `chance`, adds `stats` to it.
## Double-click it in the Use tab, then click the gear.

## Which kinds of gear it works on (EquipDef.Slot values).
@export var slots: Array[int] = []
@export_range(0.0, 1.0) var chance := 0.6
@export var stats: StatBlock

func tab() -> Tab:
	return Tab.USE

func fits(e: EquipDef) -> bool:
	return e != null and slots.has(e.slot)

## "Weapon", "Hat or Top"...
func slot_text() -> String:
	var names := PackedStringArray()
	for s in slots:
		names.append(EquipDef.SLOT_NAMES[s])
	return " or ".join(names)
