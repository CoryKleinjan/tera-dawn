class_name JumpGrace
extends RefCounted
## When a press of the jump key turns into a jump. Besides standing on something, you
## can still jump for a few ticks after walking off a ledge ("coyote time"), and a press
## a few ticks before you land goes off as you land ("jump buffering"). Leaving the
## ground by jumping, being knocked back or grabbing a rope gives no coyote time.
##
##   if _tapped("jump"): grace.press()
##   if grace.can_jump(on_ground): grace.cancel(); jump
##   ...move...
##   grace.step(on_ground)

## Ticks after walking off a ledge that a jump still works.
const COYOTE_TICKS := 5
## Ticks before landing that a jump press is kept for.
const BUFFER_TICKS := 5

var since_ground := COYOTE_TICKS + 1   # ticks since last standing on something
var since_press := BUFFER_TICKS + 1    # ticks since the jump key went down

## The jump key went down this tick.
func press() -> void:
	since_press = 0

## Whether a wanted jump may happen now. `on_ground` is whether you stand on something.
func can_jump(on_ground: bool) -> bool:
	return since_press <= BUFFER_TICKS and (on_ground or since_ground <= COYOTE_TICKS)

## The jump happened, or you left the ground some other way than walking off (knockback,
## a rope, a portal): the press is spent and there's no coyote time until you land.
func cancel() -> void:
	since_press = BUFFER_TICKS + 1
	since_ground = COYOTE_TICKS + 1

## Call once a tick, after moving.
func step(on_ground: bool) -> void:
	since_ground = 0 if on_ground else mini(since_ground + 1, COYOTE_TICKS + 1)
	since_press = mini(since_press + 1, BUFFER_TICKS + 1)
