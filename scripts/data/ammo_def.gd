class_name AmmoDef
extends ItemDef
## Arrows, throwing stars and bullets. They sit in the Use tab and are spent by ranged
## weapons whose EquipDef.ammo names the same `kind`; the first stack in the bag goes first.

## "arrow", "star" or "bullet".
@export var kind: StringName
## Added to Weapon Attack while this ammo is fired (stars and bullets hit harder).
@export var attack := 0

func tab() -> Tab:
	return Tab.USE
