class_name MonsterDef
extends Resource
## Everything that makes one kind of monster: stats, looks and loot.
## Add a monster by saving a new MonsterDef in data/monsters/ (see docs/architecture/monsters.md).
## Distances are in game pixels, speeds in pixels per physics tick (60 Hz).

@export var id: StringName
@export var display_name := ""
@export var level := 1
@export var max_hp := 10
## Damage dealt to the player on contact, before the player's defence.
@export var attack := 5
## Dawn Essence it gives the player who beats it (and a share to their party there).
@export var essence := 1
@export var speed := 1.0
## The hurtbox: width and height in game pixels, standing on the feet.
@export var size := Vector2(36, 30)
## Shown with a "Boss" badge and a wider HP bar.
@export var boss := false
## Ground monsters patrol their platform; flying ones do the same in the air above it.
@export var flying := false
@export var hover_height := 50.0

@export_group("Behavior")
## Hops around its platform now and then (a pixel speed straight up).
@export var jumps := false
@export var jump_power := 7.0
## Never walks (a plant, a cannon); it still turns to attack.
@export var stationary := false
## How far away it notices a player (horizontally) and starts attacking them. Hitting it
## makes it notice you from anywhere.
@export var sight := 260.0
## Its attacks (see MonsterMove and data/monster_moves/). None: it only hurts by touch.
@export var moves: Array[MonsterMove] = []
## Keeps about this far from its target when it has no close move ready (shooters).
@export var keep_distance := 0.0
## Defeated, it bursts into `split_count` of these. They don't come back on their own:
## they wait for the next time this one is defeated.
@export var splits_into: MonsterDef
@export var split_count := 2
## Bosses: ticks it stands roaring (its "intro" animation) when it first sees a player, and
## (its "phase" animation) when it gets its second wind at half HP. 0 skips the roar.
@export var intro_ticks := 0
@export var rage_ticks := 0

@export_group("Looks")
## Animated monsters: SpriteFrames with idle, move, attack, hurt and die (missing ones fall back to idle).
@export var sprite_frames: SpriteFrames
## Single-image monsters: animated procedurally with bobbing and squash.
@export var texture: Texture2D
## Multiplies the sprite's size in the world.
@export var sprite_scale := 1.0
## Multiplies the sprite's colours (lets one sprite stand in for several monsters).
@export var tint := Color.WHITE
## A light carried by the monster (Ember Boar's mane). Alpha 0 means no light.
@export var light_color := Color(0, 0, 0, 0)
@export var light_energy := 1.4
## Glowing particles drifting up off the monster (embers). Alpha 0 means none.
@export var aura_color := Color(0, 0, 0, 0)

@export_group("Loot")
@export var drops: Array[DropEntry] = []
## Ticks before a slain monster returns, picked between x and y.
@export var respawn_ticks := Vector2i(360, 540)

## What its shot moves fire (empty when it has none).
func projectiles() -> Array[ProjectileDef]:
	var out: Array[ProjectileDef] = []
	for mv in moves:
		if mv and mv.kind == MonsterMove.Kind.SHOT and mv.projectile:
			out.append(mv.projectile)
	return out
