class_name Platform
extends RefCounted
## A walkable surface at runtime. Platform 0 of every map is the solid floor; the rest are
## one-way platforms you can jump up through and drop down from.

var x: float
var y: float
var w: float
var solid: bool

func _init(px: float, py: float, pw: float, is_solid := false) -> void:
	x = px
	y = py
	w = pw
	solid = is_solid

static func floor_of(map: MapDef) -> Platform:
	return Platform.new(0, map.ground_y, map.width, true)

static func from_def(d: PlatformDef) -> Platform:
	return Platform.new(d.x, d.y, d.width)

func contains_x(px: float) -> bool:
	return px >= x and px <= x + w
