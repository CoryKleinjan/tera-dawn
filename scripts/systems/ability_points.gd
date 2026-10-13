class_name AbilityPoints
extends CharacterPart
## A character's Ability Points: the ones left to spend on the base stats (StatBlock.BASE),
## the Auto button's plan, and the one free reset a job instructor gives a Beginner
## (Character.ap).

## Unspent Ability Points.
var points := 0
## Whether the one free reset a job instructor gives a Beginner is used up.
var reset_used := false

## Spends `amount` points (at most what's left) on a base stat.
func spend(stat: StringName, amount := 1) -> bool:
	if points <= 0 or amount <= 0 or not stat in StatBlock.BASE:
		return false
	var c := character
	amount = mini(amount, points)
	points -= amount
	c.base.set(stat, c.base.value(stat) + amount)
	c.recalc()
	return true

## How the Auto button spends the unspent points, as {stat: amount}: all of them in the
## job's one stat (gear only ever asks for that one).
func auto_plan() -> Dictionary:
	if points <= 0:
		return {}
	return {StringName(character.job.primary_stat): points}

## Points spent so far: how far the base stats are above the job's starting stats.
func spent() -> int:
	var out := 0
	for stat in StatBlock.BASE:
		out += maxi(0, character.base.value(stat) - _starting_stat(stat))
	return out

## What a stat started at: the starting stats of the job the character's line began with.
func _starting_stat(stat: StringName) -> int:
	var line := character.job_line()
	var first := Content.job(line[-1]) if not line.is_empty() else character.job
	return first.starting_stats.value(stat) if first and first.starting_stats else 0

## Hands back every point spent, with the base stats back where the character started (the
## free reset saved characters get when the stat rules change, see CharacterCodec).
func refund_all() -> void:
	var c := character
	for stat in StatBlock.BASE:
		var extra := c.base.value(stat) - _starting_stat(stat)
		if extra > 0:
			points += extra
			c.base.set(stat, _starting_stat(stat))
	c.recalc()

## Why a `next` instructor can't hand out the free reset, or "" if they can: once per
## character, for a Beginner who has spent points but lacks the stats `next` asks for.
func reset_problem(next: JobDef) -> String:
	var c := character
	if not c.job.is_starting_job():
		return "Only a %s can have their Ability Points reset." % c.job.display_name
	if reset_used:
		return "You've already had your free reset."
	if c.stats_short_of(next).is_empty():
		return "You already have the stats a %s needs." % next.display_name
	if spent() == 0:
		return "You haven't spent any Ability Points yet."
	return ""

## The free reset (see reset_problem): base stats go back to the job's starting stats and
## every point spent comes back to spend again. Returns why not, or "".
func reset(next: JobDef) -> String:
	var problem := reset_problem(next)
	if problem != "":
		return problem
	var c := character
	for stat in StatBlock.BASE:
		var extra := c.base.value(stat) - _starting_stat(stat)
		if extra > 0:
			points += extra
			c.base.set(stat, _starting_stat(stat))
	reset_used = true
	c.recalc()
	return ""
