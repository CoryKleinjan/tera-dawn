class_name ScrollList
extends RefCounted
## A list in a window that shows `rows` rows at a time and scrolls one row per mouse wheel
## step (a shop's lines, the quest log, a player shop). Rows are counted from the top of the
## whole list: `row_rect(i)` is where row `i` is drawn while it's scrolled into view.

## The "scroll for more" line sits this far under the last row.
const MORE_GAP := 8.0
const MORE_SIZE := 10
const MORE_ALPHA := 0.6

## Where the first row shown starts.
var origin: Vector2
var width: float
## The step from one row to the next; each row is `row_gap` shorter, leaving a gap.
var row_h: float
var row_gap: float
## How many rows show at once.
var rows: int
## The first row shown.
var scroll := 0

func _init(origin_: Vector2, width_: float, row_h_: float, row_gap_: float, rows_: int) -> void:
	origin = origin_
	width = width_
	row_h = row_h_
	row_gap = row_gap_
	rows = rows_

## Where row `i` of the list is drawn.
func row_rect(i: int) -> Rect2:
	return Rect2(origin.x, origin.y + (i - scroll) * row_h, width, row_h - row_gap)

## The rows of a list of `count` that show now, top to bottom.
func shown(count: int) -> Array:
	return range(scroll, mini(scroll + rows, count))

## The shown row under `at` in a list of `count`, or -1.
func row_at(at: Vector2, count: int) -> int:
	for i in shown(count):
		if row_rect(i).has_point(at):
			return i
	return -1

## The furthest the list can scroll with `count` rows in it.
func most(count: int) -> int:
	return maxi(0, count - rows)

## Keeps the scroll inside a list of `count` (one that has shrunk since).
func clamp_to(count: int) -> void:
	scroll = clampi(scroll, 0, most(count))

## Scrolls one row for a mouse wheel `button`; true when it was a wheel button.
func wheel(button: int, count: int) -> bool:
	if button == MOUSE_BUTTON_WHEEL_DOWN:
		scroll = clampi(scroll + 1, 0, most(count))
	elif button == MOUSE_BUTTON_WHEEL_UP:
		scroll = maxi(0, scroll - 1)
	else:
		return false
	return true

## "scroll for more (2/5)" under the list's right end, when `count` rows don't all fit.
func draw_more(ci: CanvasItem, count: int) -> void:
	if count > rows:
		DrawUtil.text(ci, Game.ui_font, Vector2(origin.x + width, origin.y + rows * row_h + MORE_GAP),
			"scroll for more (%d/%d)" % [scroll + 1, count - rows + 1], MORE_SIZE, Color(Palette.MIST, MORE_ALPHA), -1)
