class_name AchievementDef
extends Resource
## A milestone a character can reach, unlocked on Steam too. Add one by saving an
## AchievementDef in data/achievements/; the collection window lists them in `order` and the
## server checks them (see Achievements). It is reached when what `kind` measures
## (Achievements.measure) is at least `goal`.
##
## `id` and `steam` never change once shipped: saved characters keep the id and Steamworks
## knows the Steam name. That's why level_50 keeps its name from when the level cap was 50,
## though its goal is now 35, the highest level.

@export var id: StringName
## The achievement's API name in the Steamworks app (upper case, like ACH_FIRST_HUNT).
@export var steam := ""
@export var title := ""
## What to do, shown when you point at it in the collection window.
@export var text := ""
## What it measures: one of the kinds Achievements.measure reads from the character, or a
## tally in Counters.
@export var kind := ""
@export var goal := 1
## Where it's listed (lowest first), and the order the server awards several at once.
@export var order := 0
