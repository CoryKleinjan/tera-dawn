class_name ServerTravel
extends ServerPart
## Getting from map to map: walking through a portal, and the trips NPCs offer (ships and
## coaches, NpcDef.travel).

func on_portal(peer: int) -> void:
	var p := player_of(peer)
	if p == null or p.fainted():
		return
	var portal := p.map.layout.portal_at(p.position)
	if portal == null or not Content.maps.has(portal.target_map):
		return
	if portal.shows_to(p.character) and portal.gated_for(p.character):
		_shut_gate(p, portal)
		return
	if not portal.open_to(p.character):
		return
	# the near end of a shortcut: its far end opens for good
	var found := portal.opens_shortcut != &"" and p.character.find_secret(portal.opens_shortcut)
	if found:
		p.dirty_character = true
	server.enter_map(p, portal.target_map, portal.target_x, portal.target_platform)
	if found:
		tell(p, "You found a shortcut.", Palette.SUN)

## `p` tried a gated door whose gate stands shut for them: its key, if they carry it, is used
## up and opens it for good (and the other end of the way, which shares its id); a lever's
## gate stays shut.
func _shut_gate(p: SimPlayer, portal: PortalDef) -> void:
	if portal.key == null:
		tell(p, "The gate is shut. A lever opens it.")
		return
	if p.character.inventory.remove(portal.key, 1) < 1:
		tell(p, "It's locked. It takes the %s." % portal.key.display_name)
		return
	p.character.find_secret(portal.gate)
	p.dirty_character = true
	tell(p, "You unlocked the gate with the %s." % portal.key.display_name, Palette.SUN)

## Takes the player on trip `index` of the NPC `npc_id` they stand by, if they can pay its
## fare (TravelRoute.price).
func on_travel(peer: int, npc_id: StringName, index: int) -> void:
	var p := player_of(peer)
	var npc := p.map.npc_near(p, npc_id) if p and not p.fainted() else null
	if npc == null or index < 0 or index >= npc.travel.size():
		return
	var route := npc.travel[index]
	if not Content.maps.has(route.target_map) or not route.open_to(p.character):
		return
	if p.character.shards < route.price:
		tell(p, ServerNpcShop.NOT_ENOUGH_SHARDS)
		return
	p.character.shards -= route.price
	p.dirty_vitals = true
	server.enter_map(p, route.target_map, route.target_x)
	tell(p, "%s to %s." % [route.by, Content.map(route.target_map).display_name], Palette.SUN)
