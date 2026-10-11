extends SmokeArea
## Playing with others: chat, parties, buddies, trading, fame, guilds and player shops.

## Chat, parties, buddies, trading, guilds, fame and player shops, with a second
## character played straight on the server (it has no game of its own).
func check() -> void:
	var social := Net.server.social
	var ch := _me().character
	var ally := SimPlayer.new(4242, Character.create("Ally"))
	Net.server.sessions[ally.peer] = ally
	social.joined(ally)
	Net.server._enter_map(_me(), &"meadow", 400)
	Net.server._enter_map(ally, &"meadow", 470)
	await _ticks(5)
	_check(world.avatars.has(ally.peer) and world.avatars[ally.peer].char_name == "Ally", "the other character shows up on the map")
	# chat
	Net.ask(&"req_chat", ["Hello, meadow!"])
	await _ticks(2)
	var chat := world.hud.chat
	_check(chat.lines.size() > 0 and str(chat.lines[-1]["text"]).ends_with("Hello, meadow!") and world.player.speech_t > 0, "map chat shows in the box and over your head")
	Net.ask(&"req_chat", ["/w Ally psst"])
	await _ticks(2)
	_check(str(chat.lines[-1]["text"]) == "To Ally: psst", "/w whispers to someone")
	chat.open()
	_check(world.input_blocked(), "typing in chat stops the player moving")
	chat.close()
	# the player menu
	world.click_avatar(world.avatars[ally.peer])
	var menu: TDPlayerMenuWindow = world.hud.windows["player"]
	var labels: Array = menu.actions().map(func(a: Array) -> String: return a[0])
	_check(menu.visible and labels.has("Invite to party") and labels.has("Trade") and labels.has("Add buddy"), "clicking a player opens what you can do with them")
	menu.visible = false
	# a party, shared EXP
	Net.ask(&"req_social", [&"party", "Ally"])
	await _ticks(1)
	var id: int = social.invites.keys().filter(func(k: int) -> bool: return social.invites[k]["to"] == ally.peer)[0]
	social.on_answer(ally.peer, id, true)
	await _ticks(35)
	var party: Dictionary = Game.social.get("party", {})
	_check(party.get("leader") == ch.name and party.get("members", []).size() == 2, "a party forms when the invite is accepted")
	var xp := ally.character.xp
	var mob: SimMob = _me().map.mobs.filter(func(m: SimMob) -> bool: return not m.dead)[0]
	_me().map.kill_mob(mob, _me())
	_check(ally.character.xp > xp or ally.character.level > 1, "party members on the map share the EXP")
	Net.ask(&"req_chat", ["/p go team"])
	await _ticks(2)
	_check(str(chat.lines[-1]["text"]) == "[Party] %s: go team" % ch.name, "/p talks to the party")
	# buddies
	social.invite(ally, "buddy", ch.name)
	await _ticks(2)
	_check(world.hud.invites.visible and world.hud.invites.pending[0][1] == "buddy", "an invitation card pops up")
	world.hud.invites.answer(true)
	await _ticks(35)
	_check(ch.buddies.has("Ally") and ally.character.buddies.has(ch.name), "accepting makes you buddies both ways")
	var buddies: Array = Game.social.get("buddies", [])
	_check(buddies.size() == 1 and buddies[0][1], "the buddy list shows them online")
	# trading: an item for Dawnshards
	ch.inventory.remove(Content.item(&"moss_tuft"), 1000)
	ch.inventory.add(Content.item(&"moss_tuft"), 5)
	ally.character.shards = 1000
	_me().dirty_character = true
	await _ticks(2)
	var shards := ch.shards
	social.invite(ally, "trade", ch.name)
	await _ticks(2)
	world.hud.invites.answer(true)
	await _ticks(2)
	var trade: TDTradeWindow = world.hud.windows["trade"]
	_check(trade.visible and trade.state.get("partner") == "Ally", "accepting a trade opens the trade window")
	trade.offer(ItemDef.Tab.ETC, Game.me.inventory.find(Content.item(&"moss_tuft")))
	social.on_trade_shards(ally.peer, 300)
	await _ticks(2)
	_check(Game.me.inventory.count_of(Content.item(&"moss_tuft")) == 0 and trade.state["theirs"]["shards"] == 300, "both offers show in the window")
	Net.ask(&"req_trade_ready")
	await _ticks(1)
	_check(not trade.state.is_empty(), "nothing changes hands until both press Trade")
	social.on_trade_ready(ally.peer)
	await _ticks(3)
	_check(not trade.visible and ch.shards == shards + 300 and ally.character.inventory.count_of(Content.item(&"moss_tuft")) == 5, "then the items and Dawnshards swap")
	# a cancelled trade gives everything back
	social.invite(ally, "trade", ch.name)
	await _ticks(2)
	world.hud.invites.answer(true)
	await _ticks(2)
	social.on_trade_shards(ally.peer, 200)
	trade.cancel()
	await _ticks(2)
	_check(ally.character.shards == 700 and not trade.visible, "cancelling gives back what was offered")
	# fame
	ch.level = maxi(ch.level, TDSocial.FAME_LEVEL)
	ch.fame_day = -1
	Net.ask(&"req_fame", [ally.peer, true])
	Net.ask(&"req_fame", [ally.peer, true])
	_check(ally.character.fame == 1, "fame goes up by one, once a day")
	# a guild
	Net.server._enter_map(_me(), &"dawnharbor", 300)
	Net.server._enter_map(ally, &"dawnharbor", 400)
	await _ticks(3)
	ch.shards = TDSocial.GUILD_COST + 100
	ch.level = maxi(ch.level, TDSocial.GUILD_LEVEL)
	# Hollis keeps the guild register in Dawnharbor's Guild Hall
	Net.server._enter_map(_me(), &"dawnharbor_guild", 240)
	Net.server._enter_map(ally, &"dawnharbor_guild", 400)
	await _ticks(3)
	var clerk: TDNpc = world.npcs().filter(func(n: TDNpc) -> bool: return n.def.id == &"guild_clerk")[0]
	_teleport(Vector2(clerk.position.x - 30, clerk.position.y))
	await _ticks(2)
	Net.ask(&"req_guild_create", [&"guild_clerk", "Dawnbreakers"])
	await _ticks(2)
	_check(Game.me.guild == "Dawnbreakers" and ch.shards == 100, "the guild clerk founds a guild for its fee")
	Net.ask(&"req_social", [&"guild", "Ally"])
	id = social.invites.keys().filter(func(k: int) -> bool: return social.invites[k]["kind"] == "guild")[0]
	social.on_answer(ally.peer, id, true)
	await _ticks(5)
	_check(ally.character.guild == "Dawnbreakers" and world.avatars[ally.peer].guild == "Dawnbreakers", "guild members show the guild under their name")
	var reloaded := TDSocial.new(Net.server, save_dir)
	_check(reloaded.guild_of("Ally").get("name") == "Dawnbreakers", "guilds are saved")
	Net.ask(&"req_chat", ["/g hi guild"])
	await _ticks(2)
	_check(str(chat.lines[-1]["text"]) == "[Guild] %s: hi guild" % ch.name, "/g talks to the guild")
	# a player shop in the free market
	Net.server._enter_map(_me(), &"dawnharbor", 300)
	await _ticks(3)
	var market: PortalDef = Content.map(&"dawnharbor").portals.filter(func(p: PortalDef) -> bool: return p.target_map == &"free_market")[0]
	_teleport(Vector2(market.x, 620))
	await _ticks(2)
	await _tap("move_up")
	await _ticks(4)
	_check(world.map.id == &"free_market", "Dawnharbor's portal leads to the Free Market")
	Net.server._enter_map(ally, &"free_market", 900)
	ch.inventory.add(Content.item(&"petal_wing"), 4)
	_me().dirty_character = true
	await _ticks(3)
	var stall: TDPlayerShopWindow = world.hud.windows["player_shop"]
	stall.setup()
	stall.add_entry(ItemDef.Tab.ETC, Game.me.inventory.find(Content.item(&"petal_wing")), 120)
	stall.open_shop()
	await _ticks(3)
	_check(social.shops.has(_me().peer) and world.hud.selling() and Game.me.inventory.count_of(Content.item(&"petal_wing")) == 0, "opening a shop puts your goods on display")
	await _ticks(TDServer.SNAPSHOT_EVERY)
	_check(world.player_infos.get(_me().peer, [""])[-1] == stall.shop_title, "others see the shop sign")
	var before := ch.shards
	social.on_shop_view(ally.peer, _me().peer)
	social.on_shop_buy(ally.peer, _me().peer, 0, &"petal_wing")
	await _ticks(3)
	_check(ally.character.inventory.count_of(Content.item(&"petal_wing")) == 4 and ch.shards == before + 120, "buying pays the owner")
	_check(not social.shops.has(_me().peer) and not world.hud.selling(), "a sold-out shop closes")
	# leaving takes them out of the party
	social.left(ally)
	Net.server.sessions.erase(ally.peer)
	ally.map.remove_player(ally)
	await _ticks(35)
	_check(Game.social.get("party", {}).is_empty(), "a party of one breaks up")
	Net.server._enter_map(_me(), &"meadow", 300)
	await _ticks(3)
