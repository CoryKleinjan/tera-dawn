class_name ServerNpcShop
extends ServerPart
## Buying from and selling to an NPC's shop (NpcDef.shop). The player must stand by the NPC.

const NOT_ENOUGH_SHARDS := "You don't have enough Dawnshards."

## The NPC `npc_id` if the player stands by it and it keeps a shop, else null.
func _shop_npc(p: SimPlayer, npc_id: StringName) -> NpcDef:
	var npc := p.map.npc_near(p, npc_id) if p else null
	return npc if npc and npc.shop else null

## Buys `count` of a shop's entry `index` from the NPC `npc_id` the player stands by.
func on_buy(peer: int, npc_id: StringName, index: int, count: int) -> void:
	var p := player_of(peer)
	var npc := _shop_npc(p, npc_id)
	if npc == null or index < 0 or index >= npc.shop.items.size():
		return
	var entry := npc.shop.items[index]
	count = clampi(count, 1, entry.item.stack_size())
	var c := p.character
	var total := entry.cost_for(c) * count
	if c.shards < total:
		tell(p, NOT_ENOUGH_SHARDS)
	elif not c.inventory.has_room(entry.item, count):
		tell(p, "Your %s inventory is full." % ItemDef.TAB_NAMES[entry.item.tab()])
	else:
		c.shards -= total
		c.inventory.add_stack(ItemStack.unrolled(entry.item, count))
		p.dirty_character = true
		tell(p, "Bought %s for %d Dawnshards." % [MapInstance.amount_name(entry.item, count), total], Palette.MIST)

## Sells up to `count` from a bag slot to the NPC `npc_id`'s shop.
func on_sell(peer: int, npc_id: StringName, tab: int, slot: int, count: int) -> void:
	var p := player_of(peer)
	if _shop_npc(p, npc_id) == null or not Inventory.valid_slot(tab, slot):
		return
	var stack := p.character.inventory.at(tab, slot)
	if stack == null:
		return
	if stack.item.quest_item:
		tell(p, "You can't sell quest items.")
		return
	var sold := p.character.inventory.take(tab, slot, clampi(count, 1, stack.count))
	var total := sold.item.sell_price * sold.count
	p.character.shards += total
	p.dirty_character = true
	tell(p, "Sold %s for %d Dawnshards." % [MapInstance.amount_name(sold.item, sold.count), total], Palette.MIST)

## Sells everything in the Etc tab to the NPC `npc_id`'s shop.
func on_sell_all_etc(peer: int, npc_id: StringName) -> void:
	var p := player_of(peer)
	if _shop_npc(p, npc_id) == null:
		return
	var total := 0
	for i in Inventory.SLOTS:
		var held := p.character.inventory.at(ItemDef.Tab.ETC, i)
		if held and not held.item.quest_item:
			var s := p.character.inventory.take(ItemDef.Tab.ETC, i)
			total += s.item.sell_price * s.count
	if total > 0:
		p.character.shards += total
		p.dirty_character = true
		tell(p, "Sold all your Etc items for %d Dawnshards." % total, Palette.MIST)
