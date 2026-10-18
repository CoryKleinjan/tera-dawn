class_name GearTierDef
extends Resource
## One tier of gear (ItemStack.tier). Every piece starts at tier 1 and an enchanter can raise
## it one tier at a time, for good, for the next tier's `fee` (Gear.upgrade). Its look never
## changes; only its stats grow. Tiers aren't tied to zones or levels.

@export var id: StringName
## Its place in the order, from 1. Content.gear_tier(rank) finds it.
@export var rank := 1
## What players read: "Tier III".
@export var display_name := ""
## Each of the piece's own stats (not its runes') is this many times as big.
@export var stat_scale := 1.0
## Dawnshards an enchanter asks to raise a piece from the tier below to this one.
@export var fee := 0
