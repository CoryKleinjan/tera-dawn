class_name SlotGrid
extends RefCounted
## A grid of square item slots in a window (the bag, a shop's bag, storage, a trade side, the
## quickslots): where slot `i` is, and which slot is under a point. Slots run left to right,
## `cols` to a row, `gap` pixels apart, starting at `origin`.

var origin: Vector2
var cols: int
var count: int
var slot: float
var gap: float

func _init(origin_: Vector2, cols_: int, count_: int, slot_: float, gap_: float) -> void:
	origin = origin_
	cols = cols_
	count = count_
	slot = slot_
	gap = gap_

## How many rows the slots take.
func rows() -> int:
	return ceili(count / float(cols))

## The size of the whole grid, from the first slot's top left to the last row's far corner.
func size() -> Vector2:
	return Vector2(cols, rows()) * (slot + gap) - Vector2(gap, gap)

## The rect around every slot.
func bounds() -> Rect2:
	return Rect2(origin, size())

## Where slot `i` is.
func rect(i: int) -> Rect2:
	return cell_rect(Vector2i(i % cols, i / cols))

## Where the slot in column `cell.x` and row `cell.y` is.
func cell_rect(cell: Vector2i) -> Rect2:
	return Rect2(origin + Vector2(cell) * (slot + gap), Vector2(slot, slot))

## The slot under `at`, or -1.
func at(pos: Vector2) -> int:
	for i in count:
		if rect(i).has_point(pos):
			return i
	return -1
