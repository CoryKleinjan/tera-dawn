class_name SocialShops
extends SocialPart
## Player shops in the free market: a player puts things from their bag up for sale and
## stands still while others browse and buy.

## Opens a shop: `entries` is [[tab, slot, count, price], ...] from the bag.
func on_open(peer: int, title: String, entries: Array) -> void:
	var p := server.player_of(peer)
	if p == null or social.shops.has(peer) or social.trades.has(peer):
		return
	if not p.map.def.market:
		tell(p, "Shops can only be opened in the Free Market.", MapInstance.BAD)
		return
	if entries.is_empty() or entries.size() > TDSocial.SHOP_SLOTS:
		tell(p, "Put up 1 to %d things for sale." % TDSocial.SHOP_SLOTS, MapInstance.BAD)
		return
	for other: TDSocial.Shop in social.shops.values():
		var o := server.player_of(other.owner)
		if o and o.map == p.map and absf(o.position.x - p.position.x) < 90:
			tell(p, "You're too close to %s's shop." % o.character.name, MapInstance.BAD)
			return
	var shop := TDSocial.Shop.new()
	shop.owner = peer
	shop.title = title.strip_edges().substr(0, 24) if title.strip_edges() != "" else "%s's Shop" % p.character.name
	var inv := p.character.inventory
	# check everything first so nothing moves if one entry is bad
	var used := {}
	for e in entries:
		if not e is Array or e.size() != 4:
			return
		var tab := int(e[0])
		var slot := int(e[1])
		if not Inventory.valid_slot(tab, slot) or used.has([tab, slot]):
			return
		used[[tab, slot]] = true
		var held := inv.at(tab, slot)
		if held == null or held.item.quest_item or int(e[3]) <= 0:
			tell(p, "Something on your list can't be sold.", MapInstance.BAD)
			return
	for e in entries:
		var held := inv.at(int(e[0]), int(e[1]))
		var n := clampi(int(e[2]), 1, held.count)
		shop.items.append([inv.take(int(e[0]), int(e[1]), n), clampi(int(e[3]), 1, 999999999)])
	social.shops[peer] = shop
	p.dirty_character = true
	tell(p, "Your shop is open. Others can click you to browse.", Palette.GOOD)
	shop.viewers[peer] = true
	_send(shop)

func _send(shop: TDSocial.Shop) -> void:
	var o := server.player_of(shop.owner)
	var items := shop.items.map(func(e: Array) -> Array: return [(e[0] as ItemStack).to_dict(), e[1]])
	for v in shop.viewers.keys():
		Net.send(v, &"ev_player_shop", [shop.owner, o.character.name if o else "", shop.title, items])

func on_view(peer: int, owner: int) -> void:
	var shop: TDSocial.Shop = social.shops.get(owner)
	var p := server.player_of(peer)
	var o := server.player_of(owner)
	if shop == null or p == null or o == null or o.map != p.map:
		return
	shop.viewers[peer] = true
	_send(shop)

## Buys entry `index` of `owner`'s shop. `item_id` must still match (the list may have moved).
func on_buy(peer: int, owner: int, index: int, item_id: StringName) -> void:
	var shop: TDSocial.Shop = social.shops.get(owner)
	var p := server.player_of(peer)
	var o := server.player_of(owner)
	if shop == null or p == null or o == null or peer == owner or o.map != p.map or index < 0 or index >= shop.items.size():
		return
	var entry: Array = shop.items[index]
	var stack: ItemStack = entry[0]
	if stack.item.id != item_id:
		return
	var price: int = entry[1]
	if p.character.shards < price:
		tell(p, "You need %d Dawnshards." % price, MapInstance.BAD)
		return
	if not p.character.inventory.room_for([stack]):
		tell(p, "Your %s inventory is full." % ItemDef.TAB_NAMES[stack.item.tab()], MapInstance.BAD)
		return
	p.character.shards -= price
	o.character.shards += price
	p.character.inventory.add_stack(stack)
	shop.items.remove_at(index)
	p.dirty_character = true
	o.dirty_character = true
	p.character.count("deals")
	o.character.count("deals")
	tell(p, "You bought %s." % MapInstance.amount_name(stack.item, stack.count), Palette.GOOD)
	tell(o, "%s bought %s for %d Dawnshards." % [p.character.name, MapInstance.amount_name(stack.item, stack.count), price], Palette.GOOD)
	if shop.items.is_empty():
		close(owner)
	else:
		_send(shop)

func on_leave(peer: int, owner: int) -> void:
	if peer == owner:
		close(owner)
	elif social.shops.has(owner):
		(social.shops[owner] as TDSocial.Shop).viewers.erase(peer)

## Closes a shop: unsold things go back to the owner.
func close(owner: int) -> void:
	var shop: TDSocial.Shop = social.shops.get(owner)
	if shop == null:
		return
	social.shops.erase(owner)
	var o := server.player_of(owner)
	if o:
		for e in shop.items:
			if not o.character.inventory.add_stack(e[0]):
				o.character.storage.add_stack(e[0])
		o.dirty_character = true
		tell(o, "Your shop is closed.")
	for v in shop.viewers.keys():
		Net.send(v, &"ev_player_shop", [owner, "", "", []])
