class_name DeclineDef
extends Resource
## One step of the world's decline: how the world looks and which monsters roam it once a
## character has finished `step` tears (TearState.decline). Every step up to the character's
## applies, in order, so a later step only says what changes again.
## Add one by saving a DeclineDef in data/declines/ (see docs/architecture/tears.md).

@export var id: StringName
## Finished tears it takes (1 is the first tear).
@export var step := 1
## The world's light and fog at this step, set on top of each map's own look. Only light and
## fog: art is never recoloured in code (TearState.LIGHT_AND_FOG lists what it may set). The
## dreary new scenery is painted as its own art.
@export var look: BiomeVariantDef
## Monster id -> what takes its place from this step on: its own MonsterDef with its own
## painted sheets. Kinds left out stay as they are (only stronger).
@export var dangerous: Dictionary[StringName, MonsterDef] = {}
