class_name SnapshotSync
extends RefCounted
## Keeps TDWorld's views of the map in step with the server: the monsters and other players
## in each snapshot (SnapshotCodec), other players' info (name, job...) and the drops
## on the ground. Net hands these to TDWorld, which passes them on here.

var world: TDWorld
## drop id -> TDDrop
var drops := {}
## peer id -> TDAvatar
var avatars := {}
## peer id -> another player's info (name, job...; see MapInstance.send_player_info),
## kept so an avatar made after it arrived still gets it.
var player_infos := {}

func _init(w: TDWorld) -> void:
	world = w

## Forgets everything on the map (a new map; the world frees the views with their layers).
func clear() -> void:
	drops.clear()
	avatars.clear()
	player_infos.clear()

## Takes every other player off the map (back to the title screen).
func clear_avatars() -> void:
	for a in avatars.values():
		a.queue_free()
	avatars.clear()
	player_infos.clear()

## Where the monsters and other players are now (SnapshotCodec.decode). Monsters left out
## of it haven't changed.
func apply_snapshot(snap: Dictionary) -> void:
	var views := world.mobs()
	for row: Array in snap.get("mobs", []):
		if row[0] < views.size():
			views[row[0]].apply(row[1])
	var me := world.multiplayer.get_unique_id()
	var seen := {}
	for state in snap.get("players", []):
		var peer: int = state[0]
		if peer == me:
			continue
		seen[peer] = true
		if not avatars.has(peer):
			avatars[peer] = TDAvatar.create(world, peer)
			world.avatar_layer.add_child(avatars[peer])
			if player_infos.has(peer):
				avatars[peer].apply_info(player_infos[peer])
		avatars[peer].apply(state)
	for peer in avatars.keys():
		if not seen.has(peer):
			remove_avatar(peer)

## Another player's name, job and the like changed.
func set_player_info(peer: int, info: Array) -> void:
	player_infos[peer] = info
	if avatars.has(peer):
		avatars[peer].apply_info(info)

func remove_avatar(peer: int) -> void:
	var a: TDAvatar = avatars.get(peer)
	player_infos.erase(peer)
	if a:
		avatars.erase(peer)
		a.queue_free()

func add_drop(snap: Array) -> void:
	var d := TDDrop.create(world, snap)
	if d.item == null or drops.has(d.id):
		return
	drops[d.id] = d
	world.drop_layer.add_child(d)

## A drop was picked up (by peer `by`) or vanished (by 0).
func remove_drop(id: int, by: int) -> void:
	var d: TDDrop = drops.get(id)
	if d == null:
		return
	drops.erase(id)
	var taker := world.actor(by) if by != 0 else null
	if taker:
		d.collect(taker)  # it flies to them, then sparkles
	elif by != 0:
		world.add_effect(d.item.pickup_effect, d.position + Vector2(0, -16), 1)
		d.queue_free()
	else:
		d.queue_free()
