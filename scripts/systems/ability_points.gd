class_name AbilityPoints
extends CharacterPart
## Buying base stats (StatBlock.BASE) with Dawn Essence: each point in a stat costs more than
## the last one bought in it (CharacterStats.stat_price), and the Auto button (Character.ap).

## Points bought in `stat`: how far it is above where the character started.
func bought(stat: StringName) -> int:
	return maxi(0, character.base.value(stat) - _starting_stat(stat))

## Dawn Essence for the next point of `stat`.
func price(stat: StringName) -> int:
	return CharacterStats.stat_price(bought(stat))

## Buys up to `amount` points of a base stat, as many as the character's essence pays for.
## Returns how many were bought.
func buy(stat: StringName, amount := 1) -> int:
	if amount <= 0 or not stat in StatBlock.BASE:
		return 0
	var c := character
	var n := 0
	while n < amount and c.essence >= price(stat):
		c.essence -= price(stat)
		c.base.set(stat, c.base.value(stat) + 1)
		n += 1
	if n > 0:
		c.recalc()
	return n

## The Auto button: spends essence on the job's damage stats (a blend's two take turns, the
## cheaper first) until the next point costs more than is left. Returns how many were bought.
func auto() -> int:
	var stats := character.job.damage_stats()
	var n := 0
	while true:
		var next: StringName = stats[0]
		for stat in stats:
			if price(stat) < price(next):
				next = stat
		if buy(next) == 0:
			return n
		n += 1
	return n

## Points bought so far, in every stat.
func spent() -> int:
	var out := 0
	for stat in StatBlock.BASE:
		out += bought(stat)
	return out

## The Dawn Essence the points bought so far cost.
func essence_spent() -> int:
	var out := 0
	for stat in StatBlock.BASE:
		for n in bought(stat):
			out += CharacterStats.stat_price(n)
	return out

## What a stat started at: the starting stats of the job the character's line began with.
func _starting_stat(stat: StringName) -> int:
	var line := character.job_path()
	var first := Content.job(line[-1]) if not line.is_empty() else character.job
	return first.starting_stats.value(stat) if first and first.starting_stats else 0

## Hands back the essence of every point bought, with the base stats back where the
## character started: the free reset saved characters get when the stat rules change (see
## CharacterCodec).
func refund_all() -> void:
	var c := character
	c.essence += essence_spent()
	for stat in StatBlock.BASE:
		c.base.set(stat, mini(c.base.value(stat), _starting_stat(stat)))
	c.recalc()
