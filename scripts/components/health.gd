class_name Health
extends RefCounted
## Hit points for anything that can be hurt: the player and every monster.

signal changed
signal died

var max_hp := 1
var hp := 1

func _init(maximum := 1) -> void:
	reset(maximum)

## Back to full health, optionally with a new maximum.
func reset(maximum := -1) -> void:
	if maximum > 0:
		max_hp = maximum
	hp = max_hp
	changed.emit()

## Takes damage and returns how much was actually lost. Emits `died` when it reaches 0.
func damage(amount: int) -> int:
	if hp <= 0:
		return 0
	var lost := mini(amount, hp)
	hp -= lost
	changed.emit()
	if hp <= 0:
		died.emit()
	return lost

func heal(amount: int) -> void:
	if hp <= 0:
		return
	hp = mini(max_hp, hp + amount)
	changed.emit()

## Sets hp directly (loading, reviving), kept within 0..max_hp.
func set_hp(value: int) -> void:
	hp = clampi(value, 0, max_hp)
	changed.emit()

func is_dead() -> bool:
	return hp <= 0

func fraction() -> float:
	return float(hp) / float(max_hp) if max_hp > 0 else 0.0
