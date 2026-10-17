class_name TearDef
extends Resource
## A hidden tear: a small zone of its own past a secret room that only a boss move from
## another zone reaches (plans: the tears). It stays sealed until the story first takes the
## hero through a tear (`seal_quest`). Finishing what waits inside (`finish_quest`, the last
## of its quests) moves the world one step further into its decline (DeclineDef): the first
## finished tear turns the whole world, and each one after takes it further.
## Add one by saving a TearDef in data/tears/ (see docs/architecture/tears.md).

@export var id: StringName
## The zone (RegionDef id) its way in is in.
@export var region: StringName
## The zone (RegionDef id) of its own maps, which never decline.
@export var inside: StringName
## Done, it unseals the tear (the story quest where the hero first goes through one).
@export var seal_quest: StringName = &"story_a_closer_look"
## Done, the tear is finished and the world declines a step. Empty: it can't be finished yet.
@export var finish_quest: StringName
