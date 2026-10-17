class_name SnapshotFlags
extends RefCounted
## Bits of the flags field in snapshots. The server sets them (SimMob / SimPlayer.snapshot)
## and clients read them (TDMob / TDAvatar), so both sides share these values.

# ---------- monsters (SimMob.snapshot, read by TDMob) ----------
const MOB_DEAD := 1
const MOB_HURT := 2
const MOB_AGGRO := 4
const MOB_SHOW_HP := 8
const MOB_CASTING := 16
## Winding up a move (see MonsterMove.windup): clients show a wind-up glow.
const MOB_WINDUP := 32
## Vanished mid-move (a blink): clients hide it.
const MOB_HIDDEN := 64
## A boss past its second wind (half HP): clients give it an angry glow.
const MOB_ENRAGED := 128
## Rooted (SkillDef.root): clients tint it green.
const MOB_ROOTED := 512
## Stunned (SkillDef.stun): clients freeze it and circle stars over its head.
const MOB_STUNNED := 2048
## A flier pulled down to the ground (SkillDef.slam): clients drop its hover.
const MOB_DOWNED := 4096
## In the air on its own (a hop or a leap): clients show its jump pose.
const MOB_AIRBORNE := 8192
## Thrown up by a skill (SkillDef.launch): clients show it knocked up.
const MOB_TOSSED := 16384
## Lying knocked down after a throw or a slam: clients show it knocked down.
const MOB_FLOORED := 32768
## A boss roaring on the spot (its intro, or its second wind): clients play the roar.
const MOB_ROARING := 65536

# ---------- players (SimPlayer.snapshot, read by TDAvatar) ----------
const PLAYER_FAINTED := 1
const PLAYER_BLINK := 2
## Hidden by a buff (Dark Sight): others see a faint outline.
const PLAYER_HIDDEN := 8
