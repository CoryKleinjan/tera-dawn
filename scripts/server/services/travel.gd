class_name ServerTravel
extends ServerPart
## Getting from map to map: walking through a portal, and the trips NPCs offer (ships and
## coaches, NpcDef.travel).

func on_portal(peer: int) -> void:
	var p := player_of(peer)
	if p == null or p.fainted():
		return
	var portal := p.map.layout.portal_at(p.position)
	if portal and Content.maps.has(portal.target_map):
		server.enter_map(p, portal.target_map, portal.target_x)

## Takes the player on trip `index` of the NPC `npc_id` they stand by, if they can pay its
## fare (TravelRoute.fare_for: free coaches for Beginners ready for a job).
func on_travel(peer: int, npc_id: StringName, index: int) -> void:
	var p := player_of(peer)
	var npc := p.map.npc_near(p, npc_id) if p and not p.fainted() else null
	if npc == null or index < 0 or index >= npc.travel.size():
		return
	var route := npc.travel[index]
	if not Content.maps.has(route.target_map):
		return
	var fare := route.fare_for(p.character)
	if p.character.shards < fare:
		tell(p, ServerNpcShop.NOT_ENOUGH_SHARDS)
		return
	p.character.shards -= fare
	p.dirty_vitals = true
	server.enter_map(p, route.target_map, route.target_x)
	tell(p, "%s to %s." % [route.by, Content.map(route.target_map).display_name], Palette.SUN)
