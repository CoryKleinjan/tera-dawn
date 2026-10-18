class_name ServerEnchanting
extends ServerPart
## The enchanter (NpcDef.enchants): setting a rune in a piece of gear, and raising a piece a
## tier. The rules and the fees are Gear.enchant and Gear.upgrade. The player must stand by
## the NPC.

## Sets the rune in Etc slot `rune_slot` in rune slot `socket` of the gear in Equip slot
## `gear_slot`, at the enchanter `npc_id`.
func on_enchant(peer: int, npc_id: StringName, gear_slot: int, rune_slot: int, socket: int) -> void:
	var p := player_of(peer)
	var npc := p.map.npc_near(p, npc_id) if p else null
	if npc == null or not npc.enchants:
		return
	var gear := p.character.inventory.at(ItemDef.Tab.EQUIP, gear_slot) if Inventory.valid_slot(ItemDef.Tab.EQUIP, gear_slot) else null
	var rune := p.character.inventory.at(ItemDef.Tab.ETC, rune_slot) if Inventory.valid_slot(ItemDef.Tab.ETC, rune_slot) else null
	var problem := p.character.gear.enchant(gear_slot, rune_slot, socket)
	if problem != "":
		tell(p, problem)
		return
	tell(p, "The %s is set in the %s." % [rune.item.display_name, gear.display_name()], Palette.GOOD)
	p.map.broadcast(&"ev_effect", [EffectDef.CELEBRATE, p.position.x, p.position.y, 1, peer])
	p.dirty_character = true
	server.save(p)

## Raises the gear in Equip slot `gear_slot` one tier, at the enchanter `npc_id`.
func on_upgrade(peer: int, npc_id: StringName, gear_slot: int) -> void:
	var p := player_of(peer)
	var npc := p.map.npc_near(p, npc_id) if p else null
	if npc == null or not npc.enchants:
		return
	var problem := p.character.gear.upgrade(gear_slot)
	if problem != "":
		tell(p, problem)
		return
	var gear := p.character.inventory.at(ItemDef.Tab.EQUIP, gear_slot)
	tell(p, "The %s is now %s." % [gear.display_name(), Content.gear_tier(gear.tier).display_name], Palette.GOOD)
	p.map.broadcast(&"ev_effect", [EffectDef.CELEBRATE, p.position.x, p.position.y, 1, peer])
	p.dirty_character = true
	server.save(p)
