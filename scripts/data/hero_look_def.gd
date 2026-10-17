class_name HeroLookDef
extends Resource
## One look the hero can have, picked in the character creator (data/hero/looks/): every frame
## of him painted whole, one animation per thing he does (art/sheets/hero_look_<id>_*.json).
## HeroBody plays them. Older saves, and any id the game doesn't know, get the first look.

@export var id: StringName
## Its name in the creator ("Boy").
@export var display_name := ""
## Where it comes in the creator's list (lowest first).
@export var order := 0
## His animations, named for what TDPlayer._animation() says he is doing ("walk", "dash"),
## with "attack" for every attack and skill motion.
@export var frames: SpriteFrames
## His punching fist on the last frame of "attack", in that frame's pixels from its top left:
## shots leave from it until the job sets put a weapon in his hand.
@export var fist := Vector2.ZERO

## Every look, in the creator's order.
static func all() -> Array[HeroLookDef]:
	var out: Array[HeroLookDef] = []
	for l: HeroLookDef in Content.looks.values():
		out.append(l)
	out.sort_custom(func(a: HeroLookDef, b: HeroLookDef) -> bool: return a.order < b.order or (a.order == b.order and a.id < b.id))
	return out

## The look called `look_id`, or the first one when there is none by that name.
static func of(look_id: StringName) -> HeroLookDef:
	var l: HeroLookDef = Content.looks.get(look_id)
	return l if l else all()[0]
