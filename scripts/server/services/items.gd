class_name ServerItems
extends ServerPart
## The player's own things: using items (potions, pet food, return scrolls), the Setup tab
## (pets), wearing gear, and moving or dropping bag items.

# ---------- Use tab ----------

## Uses the item in Use slot `slot`. Each kind of effect is its own step below; one item
## can do several (a potion that heals and shows a sparkle, a scroll that heals and
## teleports).
func on_use_item(peer: int, slot: int) -> void:
	var p := player_of(peer)
	if p == null:
		return
	var stack := p.character.inventory.at(ItemDef.Tab.USE, slot)
	if stack == null or not stack.item is UseDef:
		return
	if p.fainted():
		tell(p, "You can't do that right now.")
		return
	if p.item_cd > 0:
		tell(p, "You can't use another item yet.")
		return
	var u := stack.item as UseDef
	if u.pet_food > 0:
		_feed_pet(p, u, slot)
		return
	var dest := &""
	if u.teleport != &"":
		dest = _teleport_target(p, u)
		if dest == &"":
			return
	_restore(p, u)
	_used(p, u, slot)
	if u.use_effect:
		p.map.broadcast(&"ev_effect", [u.use_effect.id, p.position.x, p.position.y - 40, p.face, peer])
	if dest != &"":
		server.enter_map(p, dest, Content.map(dest).start_x)

## Pet food: fills up the pet the player has out.
func _feed_pet(p: SimPlayer, u: UseDef, slot: int) -> void:
	var c := p.character
	var pet := c.pet_def()
	if pet == null:
		tell(p, "You have no pet out to feed.")
		return
	if c.pet_full >= PetDef.FULL:
		tell(p, "%s isn't hungry." % pet.display_name)
		return
	c.pet_full = mini(PetDef.FULL, c.pet_full + u.pet_food)
	_used(p, u, slot)
	tell(p, "%s munches happily. (Fullness %d)" % [pet.display_name, c.pet_full], Palette.GOOD)

## Where a teleporting item takes the player, or &"" when it can't (no such map, or already
## in the town it goes to; the item isn't used up then).
func _teleport_target(p: SimPlayer, u: UseDef) -> StringName:
	var dest := p.map.def.return_town() if u.teleport == UseDef.TELEPORT_TOWN else u.teleport
	if not Content.maps.has(dest):
		return &""
	if dest == p.map.def.id and p.map.def.town:
		tell(p, "You're already in town.")
		return &""
	return dest

## Potions: HP and MP back.
func _restore(p: SimPlayer, u: UseDef) -> void:
	var c := p.character
	c.health.heal(u.hp_for(c.max_hp()))
	c.restore_mp(u.mp_for(c.max_mp()))

## Takes one of the item from its slot and starts the item cooldown.
func _used(p: SimPlayer, u: UseDef, slot: int) -> void:
	p.item_cd = u.cooldown
	p.character.inventory.take(ItemDef.Tab.USE, slot, 1)
	p.dirty_character = true

# ---------- Setup tab ----------

## Uses what's in Setup slot `slot`: brings out a pet (or sends it home).
func on_setup(peer: int, slot: int) -> void:
	var p := player_of(peer)
	if p == null or not Inventory.valid_slot(ItemDef.Tab.SETUP, slot):
		return
	var stack := p.character.inventory.at(ItemDef.Tab.SETUP, slot)
	if stack == null:
		return
	if stack.item is PetDef:
		_call_pet(p, stack.item as PetDef)

func _call_pet(p: SimPlayer, pet: PetDef) -> void:
	var c := p.character
	if c.pet == pet.id:
		c.pet = &""
		tell(p, "%s went home." % pet.display_name, Palette.MIST)
	else:
		c.pet = pet.id
		c.pet_full = maxi(c.pet_full, PetDef.OUT_MIN)
		c.count(Counters.PETS)
		tell(p, "%s came out to play! It picks up things near you." % pet.display_name, Palette.GOOD)
		if not pet.chatter.is_empty():
			p.map.broadcast(&"ev_chat", ["pet", pet.display_name, pet.chatter.pick_random(), p.peer])
	p.dirty_character = true

# ---------- gear ----------

func on_equip(peer: int, slot: int, place: StringName) -> void:
	change(peer, func(c: Character) -> String: return c.gear.equip(slot, place))

func on_unequip(peer: int, place: StringName, slot: int) -> void:
	change(peer, func(c: Character) -> String: return c.gear.unequip(place, slot))

# ---------- the bag ----------

func on_move_item(peer: int, tab: int, from: int, to: int) -> void:
	if Inventory.valid_slot(tab, from) and Inventory.valid_slot(tab, to):
		change(peer, func(c: Character) -> String:
			c.inventory.move(tab, from, to)
			return "")

func on_drop_item(peer: int, tab: int, slot: int) -> void:
	var p := player_of(peer)
	if p == null or p.fainted() or not Inventory.valid_slot(tab, slot):
		return
	var held := p.character.inventory.at(tab, slot)
	if held and held.item.quest_item:
		tell(p, "Quest items can't be dropped.")
		return
	var stack := p.character.inventory.take(tab, slot)
	if stack:
		p.dirty_character = true
		p.map.drop_from_player(p, stack)
