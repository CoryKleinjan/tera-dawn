class_name SocialTrade
extends SocialPart
## Trading between two players on the same map: each puts items and Dawnshards on the
## table, and once both press Trade everything changes hands.

func open(a: SimPlayer, b: SimPlayer) -> void:
	var t := TDSocial.Trade.new()
	t.peers = [a.peer, b.peer]
	for p in t.peers:
		t.items[p] = []
		t.shards[p] = 0
		t.ready[p] = false
		social.trades[p] = t
	_send(t)

func _send(t: TDSocial.Trade) -> void:
	for peer in t.peers:
		var other := t.other(peer)
		var o := server.player_of(other)
		Net.send(peer, &"ev_trade", [{
			"partner": o.character.name if o else "?",
			"mine": {"items": t.items[peer].map(func(s: ItemStack) -> Dictionary: return s.to_dict()), "shards": t.shards[peer], "ready": t.ready[peer]},
			"theirs": {"items": t.items[other].map(func(s: ItemStack) -> Dictionary: return s.to_dict()), "shards": t.shards[other], "ready": t.ready[other]},
		}])

## Puts `count` from bag slot `slot` of `tab` on the table.
func on_offer(peer: int, tab: int, slot: int, count: int) -> void:
	var t: TDSocial.Trade = social.trades.get(peer)
	var p := server.player_of(peer)
	if t == null or p == null or not Inventory.valid_slot(tab, slot):
		return
	var held := p.character.inventory.at(tab, slot)
	if held == null:
		return
	if held.item.quest_item:
		tell(p, "Quest items can't be traded.", MapInstance.BAD)
		return
	if (t.items[peer] as Array).size() >= TDSocial.TRADE_SLOTS:
		tell(p, "The trade window is full.", MapInstance.BAD)
		return
	var stack := p.character.inventory.take(tab, slot, clampi(count, 1, held.count) if count > 0 else -1)
	t.items[peer].append(stack)
	p.dirty_character = true
	_unready(t)

## Offers `amount` Dawnshards (replacing any offered before).
func on_shards(peer: int, amount: int) -> void:
	var t: TDSocial.Trade = social.trades.get(peer)
	var p := server.player_of(peer)
	if t == null or p == null:
		return
	p.character.shards += t.shards[peer]
	t.shards[peer] = clampi(amount, 0, p.character.shards)
	p.character.shards -= t.shards[peer]
	p.dirty_vitals = true
	_unready(t)

func _unready(t: TDSocial.Trade) -> void:
	for peer in t.peers:
		t.ready[peer] = false
	_send(t)

## Presses Trade. Once both have, everything changes hands (if both have room).
func on_ready(peer: int) -> void:
	var t: TDSocial.Trade = social.trades.get(peer)
	if t == null:
		return
	t.ready[peer] = true
	if not t.ready.values().all(func(r: bool) -> bool: return r):
		_send(t)
		return
	var a := server.player_of(t.peers[0])
	var b := server.player_of(t.peers[1])
	for pair in [[a, t.items[t.peers[1]]], [b, t.items[t.peers[0]]]]:
		if not pair[0].character.inventory.room_for(pair[1]):
			tell(a, "%s doesn't have room for that." % pair[0].character.name, MapInstance.BAD)
			tell(b, "%s doesn't have room for that." % pair[0].character.name, MapInstance.BAD)
			_unready(t)
			return
	for p: SimPlayer in [a, b]:
		var other := t.other(p.peer)
		for s: ItemStack in t.items[other]:
			p.character.inventory.add_stack(s)
		p.character.shards += t.shards[other]
		p.dirty_character = true
		p.character.count("deals")
		social.trades.erase(p.peer)
		Net.send(p.peer, &"ev_trade", [{}])
		tell(p, "The trade is done.", Palette.GOOD)

## Ends a trade: everything goes back to whoever offered it.
func cancel(peer: int, why: String) -> void:
	var t: TDSocial.Trade = social.trades.get(peer)
	if t == null:
		return
	for pp in t.peers:
		social.trades.erase(pp)
		var p := server.player_of(pp)
		if p == null:
			continue
		for s: ItemStack in t.items[pp]:
			if not p.character.inventory.add_stack(s):
				p.character.storage.add_stack(s)
		p.character.shards += t.shards[pp]
		p.dirty_character = true
		Net.send(pp, &"ev_trade", [{}])
		tell(p, why)
