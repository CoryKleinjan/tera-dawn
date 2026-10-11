class_name DragPayload
extends RefCounted
## What's being dragged between the windows and the quickslots: a bag slot, a worn item, a
## skill or a quickslot. Make one with the constructors below and return it from
## `_get_drag_data`; a window it's dropped on reads it back with `of`.

enum From { INVENTORY, EQUIPMENT, SKILLS, QUICKSLOT }

var from: From
## INVENTORY: the bag tab and slot. QUICKSLOT: the slot (tab stays -1).
var tab := -1
var index := -1
## EQUIPMENT: the place it's worn.
var place: StringName = &""
## SKILLS: the skill.
var id: StringName = &""

func _init(from_: From) -> void:
	from = from_

## Slot `index` of bag tab `tab`.
static func bag_item(tab_: int, index_: int) -> DragPayload:
	var d := DragPayload.new(From.INVENTORY)
	d.tab = tab_
	d.index = index_
	return d

## What's worn at `place`.
static func worn(place_: StringName) -> DragPayload:
	var d := DragPayload.new(From.EQUIPMENT)
	d.place = place_
	return d

## A skill from the skill book.
static func skill(id_: StringName) -> DragPayload:
	var d := DragPayload.new(From.SKILLS)
	d.id = id_
	return d

## Quickslot `index`.
static func quickslot(index_: int) -> DragPayload:
	var d := DragPayload.new(From.QUICKSLOT)
	d.index = index_
	return d

## `data` (a drag's data) as a payload, or null when it's something else.
static func of(data: Variant) -> DragPayload:
	return data as DragPayload if data is DragPayload else null

## What `c`'s viewport is dragging right now, or null.
static func dragging(c: Control) -> DragPayload:
	if not c.get_viewport().gui_is_dragging():
		return null
	return of(c.get_viewport().gui_get_drag_data())

## Whether `data` is a bag item from tab `tab_` (any tab when -1).
static func is_bag_item(data: Variant, tab_ := -1) -> bool:
	var d := of(data)
	return d != null and d.from == From.INVENTORY and (tab_ < 0 or d.tab == tab_)

## Keeps the drag a control started until NOTIFICATION_DRAG_END, when the viewport has
## already forgotten it, so the control can tell where it ended (the bag drops an item
## dragged out of every window; a quickslot dragged off is cleared).
class Tracker:
	var _pending: DragPayload

	## Starts dragging `payload` from `c` with `preview` under the mouse; returns the payload
	## for `_get_drag_data`.
	func start(c: Control, payload: DragPayload, preview: Control) -> DragPayload:
		c.set_drag_preview(preview)
		_pending = payload
		return payload

	## Call on NOTIFICATION_DRAG_END: the drag this tracker started, if it was dropped
	## nowhere that took it, or null.
	func ended_unplaced(c: Control) -> DragPayload:
		var d := _pending
		_pending = null
		if d != null and not c.get_viewport().gui_is_drag_successful():
			return d
		return null
