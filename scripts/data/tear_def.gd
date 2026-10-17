class_name TearDef
extends Resource
## A hidden tear: a small zone of its own past a secret room that only a boss move from
## another zone reaches (plans: the tears). It stays sealed until the story first takes the
## hero through a tear (`seal_quest`). Finishing what waits inside (`finish_quest`, the last
## of its quests) turns the zone it opens from (`region`) for that character: darker light
## and fog (`dark_look`) and the more dangerous painted versions of its monsters
## (`dangerous`), stronger by TearState.STRENGTH. Towns never change.
## Add one by saving a TearDef in data/tears/ (see docs/architecture/tears.md).

@export var id: StringName
## The zone (RegionDef id) the tear opens from, and the one its finish darkens.
@export var region: StringName
## Done, it unseals the tear (the story quest where the hero first goes through one).
@export var seal_quest: StringName = &"story_a_closer_look"
## Done, the tear is finished and its zone turns. Empty: it can't be finished yet.
@export var finish_quest: StringName
## The zone's darker light and fog, set on top of each map's own look. Only light and fog:
## art is never recoloured in code (TearState.LIGHT_AND_FOG lists what it may set).
@export var dark_look: BiomeVariantDef
## Monster id -> the more dangerous version of it that takes its place in the zone once the
## tear is finished: its own MonsterDef with its own painted sheets. Kinds left out stay as
## they are (only stronger).
@export var dangerous: Dictionary[StringName, MonsterDef] = {}
