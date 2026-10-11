class_name TDNameTags
extends RefCounted
## The name tags drawn under people and monsters, gathered for one frame so tags that would
## overlap can be nudged apart before any is drawn. Your own tag is placed first, so it never
## moves, and drawn last, so nothing covers it. The overlay fills one each frame.

## Space left between two tags nudged apart.
const GAP := 2.0
## A tag in a crowd moves down at most this many times (then it overlaps rather than wander off).
const MAX_NUDGES := 8
## How far under a name tag its second tag (a guild) sits.
const SUB_TAG_Y := 22.0

## Each tag: {"rect": Rect2 it covers on screen, "draw": Callable(ci, offset), "mine": bool,
## "offset": Vector2 it was nudged by}.
var tags: Array[Dictionary] = []

## Adds a tag covering `rect` on screen; `draw(ci, offset)` draws it moved by `offset`.
## `mine` is the local player's own.
func add(rect: Rect2, draw: Callable, mine := false) -> void:
	tags.append({"rect": rect, "draw": draw, "mine": mine, "offset": Vector2.ZERO})

## A name tag with an optional guild plaque under it, as UiSkin draws them.
func add_name(top_center: Vector2, label: String, col: Color, guild := "", mine := false) -> void:
	var rect := WorldSkin.name_tag_rect(top_center, label)
	if guild != "":
		rect = rect.merge(WorldSkin.guild_tag_rect(top_center + Vector2(0, SUB_TAG_Y), guild))
	var draw_it := func(ci: CanvasItem, offset: Vector2) -> void:
		WorldSkin.draw_name_tag(ci, top_center + offset, label, col)
		if guild != "":
			WorldSkin.draw_guild_tag(ci, top_center + offset + Vector2(0, SUB_TAG_Y), guild)
	add(rect, draw_it, mine)

## Moves tags that overlap one already placed down below it. Your own tag is placed first
## and stays put; the rest keep the order they were added in.
func arrange() -> void:
	var placed: Array[Rect2] = []
	for t in _in_order():
		var r: Rect2 = t["rect"]
		for n in MAX_NUDGES:
			var hit := _overlapping(r, placed)
			if hit < 0:
				break
			r.position.y = placed[hit].end.y + GAP
		t["offset"] = r.position - (t["rect"] as Rect2).position
		placed.append(r)

## Arranges the tags and draws them, your own last.
func draw(ci: CanvasItem) -> void:
	arrange()
	for t in tags:
		if not t["mine"]:
			(t["draw"] as Callable).call(ci, t["offset"])
	for t in tags:
		if t["mine"]:
			(t["draw"] as Callable).call(ci, t["offset"])

## Where each tag ended up (after `arrange`), in the order they were added.
func rects() -> Array[Rect2]:
	var out: Array[Rect2] = []
	for t in tags:
		var r: Rect2 = t["rect"]
		out.append(Rect2(r.position + t["offset"], r.size))
	return out

func _in_order() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for t in tags:
		if t["mine"]:
			out.append(t)
	for t in tags:
		if not t["mine"]:
			out.append(t)
	return out

## The index in `placed` of the first rect `r` overlaps, or -1.
static func _overlapping(r: Rect2, placed: Array[Rect2]) -> int:
	for i in placed.size():
		if placed[i].grow(GAP / 2.0).intersects(r.grow(GAP / 2.0)):
			return i
	return -1
