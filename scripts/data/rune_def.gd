class_name RuneDef
extends ItemDef
## An enchant rune. An enchanter (NpcDef.enchants) sets it in one of a gear piece's rune slots
## (ItemStack.runes), where it adds `stats` for as long as it stays there. Setting one always
## works; setting one over another loses the old one. Monsters in a zone's fields drop its
## runes (RegionDef.drops), and each zone boss drops a stronger one of its own
## (MonsterDef.drops) that no shop sells. Runes stack in the Etc tab.

## What it adds to the gear it's set in.
@export var stats: StatBlock
## Dawnshards an enchanter asks to set it.
@export var fee := 200
## A boss's own rune: drop-only and stronger. The tooltip says so.
@export var boss := false

## Its bonuses as players read them: "Weapon Attack +1, Heart Pieces +1".
func bonus_text() -> String:
	var parts := PackedStringArray()
	if stats:
		for f in stats.nonzero():
			parts.append("%s %s" % [StatBlock.LABELS[f], StatBlock.format(f, stats.value(f))])
	return ", ".join(parts)
