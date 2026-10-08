class_name Plat
extends RefCounted
## A one-way platform: the player and monsters stand on its top edge.

var x: float
var y: float
var w: float
var solid: bool

func _init(px: float, py: float, pw: float, is_solid := false) -> void:
	x = px
	y = py
	w = pw
	solid = is_solid

func contains_x(px: float) -> bool:
	return px >= x and px <= x + w
