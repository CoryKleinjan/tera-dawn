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

# ---------- players (SimPlayer.snapshot, read by TDAvatar) ----------
const PLAYER_FAINTED := 1
const PLAYER_BLINK := 2
const PLAYER_CLIMBING := 4
