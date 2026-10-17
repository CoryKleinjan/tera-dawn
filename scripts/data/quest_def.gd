class_name QuestDef
extends Resource
## A quest: who gives it, who it's handed in to, what it asks for and what it pays.
## Add one by saving a QuestDef in data/quests/; the NPCs offer it on their own.

@export var id: StringName
@export var title := ""
## Who offers it, and who it's handed in to (the giver if left empty).
@export var giver: StringName
@export var turn_in: StringName

@export_group("Who can take it")
## Job ids that may take it; empty for anyone.
@export var jobs: Array[StringName] = []
## Quests that must be finished first.
@export var requires: Array[StringName] = []
## Can be done again after handing it in.
@export var repeatable := false

@export_group("What they say")
@export_multiline var offer_text := ""
@export_multiline var progress_text := ""
@export_multiline var complete_text := ""
## The offer and progress pages also list every job a Beginner can advance into and what
## each takes, built from the JobDefs so it never drifts from them.
@export var lists_job_paths := false
## Cutscenes that play when the quest is taken and when it's handed in (see CutsceneDef).
@export var start_scene: CutsceneDef
@export var finish_scene: CutsceneDef
## Key hints for a tutorial, shown at the bottom of the screen: `offer_hint` while the quest
## can be taken or handed in and its NPC is on your map, `hint` while it's in progress. Write
## keys as {action} (e.g. {jump}); they show the player's own key (TDHud.quest_hint).
@export var offer_hint := ""
@export var hint := ""
## An item the giver tosses to your feet when you take the quest (picked up for a COLLECT
## objective). Empty: none.
@export var gift_on_accept: ItemDef
## Taken by itself, without asking, the moment the quest it requires is handed in: the next
## step of a tutorial. Its start_scene usually says the offer.
@export var auto_start := false

@export_group("Objectives")
@export var objectives: Array[QuestObjective] = []

@export_group("Rewards")
## Pays this much Dawn Essence and as much EXP.
@export var reward_essence := 0
@export var reward_shards := 0
## Each entry gives its item, `min_amount` of it.
@export var reward_items: Array[DropEntry] = []

## Who to hand it in to.
func turn_in_npc() -> StringName:
	return turn_in if turn_in != &"" else giver

## "120 EXP · 120 Dawn Essence · 50 Dawnshards · 3 Red Potion"
func describe_rewards() -> String:
	var parts := []
	if reward_essence > 0:
		parts.append("%d EXP" % reward_essence)
		parts.append("%d Dawn Essence" % reward_essence)
	if reward_shards > 0:
		parts.append("%d Dawnshards" % reward_shards)
	for r in reward_items:
		if r.item:
			parts.append(("%d %s" % [r.min_amount, r.item.display_name]) if r.min_amount > 1 else r.item.display_name)
	return " · ".join(parts)
