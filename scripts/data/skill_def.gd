class_name SkillDef
extends Resource
## An attack the player can use. The basic attack is a skill too.
## Add a skill by saving a SkillDef in data/skills/ and binding it in GameState.SKILL_BINDINGS.

@export var id: StringName
@export var display_name := ""
@export var icon: Texture2D
@export var mp_cost := 0
## Ticks before any attack can be used again.
@export var cooldown := 24
## Ticks the player is rooted in the attack pose.
@export var action_ticks := 16
## How far in front of the player it reaches, and how tall the hit area is.
@export var reach := 78.0
@export var height := 100.0
@export var max_targets := 1
## Damage lines per target (each rolls its own damage and critical).
@export var hits := 1
@export var damage_multiplier := 1.0
## Player animation to play (see assets/animations/hero.tres).
@export var animation := &"attack"
## Played in front of the player, flipped with their facing.
@export var effect: EffectDef
## Played on each monster hit.
@export var hit_effect: EffectDef
