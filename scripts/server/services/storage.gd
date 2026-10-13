class_name ServerStorage
extends ServerPart
## The storage keeper (NpcDef.storage): putting bag items in storage and taking them back.
## The fee and the rules are Character.store / Character.retrieve.

## Stores bag slot `slot` of `tab` with the storage keeper `npc_id`.
func on_store(peer: int, npc_id: StringName, tab: int, slot: int) -> void:
	_at_storage(peer, npc_id, tab, slot, func(c: Character) -> String: return c.store(tab, slot))

## Takes storage slot `slot` of `tab` back from the storage keeper `npc_id`.
func on_retrieve(peer: int, npc_id: StringName, tab: int, slot: int) -> void:
	_at_storage(peer, npc_id, tab, slot, func(c: Character) -> String: return c.retrieve(tab, slot))

func _at_storage(peer: int, npc_id: StringName, tab: int, slot: int, change_: Callable) -> void:
	var p := player_of(peer)
	var npc := p.map.npc_near(p, npc_id) if p else null
	if npc == null or not npc.storage or not Inventory.valid_slot(tab, slot):
		return
	var problem: String = change_.call(p.character)
	if problem != "":
		tell(p, problem)
	p.dirty_character = true
	p.dirty_vitals = true
	server.save(p)
