extends Node
## The entry scene: starts the game.

func _ready() -> void:
	add_child(load("res://scenes/world.tscn").instantiate())
