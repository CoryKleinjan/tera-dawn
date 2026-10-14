class_name LookDef
extends Resource
## One appearance option picked when a character is made: for now only the hairstyle, which
## picks the body too. Add one by saving a LookDef in data/looks/; the character creator lists
## every LookDef with `creator` set, in `order`.
##
## A hairstyle is a layer of art (Paperdoll: layers/<id>.png, and layers/<id>_<hat shape>.png
## under each hat shape) on its own body, made by tools/art/hero_build.py. Everything is drawn
## in its painted colours: a skin tone or hair colour would be its own painted art, never a
## recolour. The other kinds have no options (they stay so saved looks keep their numbers).

enum Kind { SKIN, FACE, EYES, HAIR, HAIR_COLOR }
## The Appearance field each kind fills, in the order the creator lists them.
const FIELDS: Array[StringName] = [&"skin", &"face", &"eyes", &"hair", &"hair_color"]
const KIND_NAMES := ["Skin", "Face", "Eyes", "Hair", "Hair colour"]

@export var id: StringName
@export var display_name := ""
@export var kind: Kind = Kind.SKIN
## A hairstyle's body: "boy" or "girl" (Paperdoll.BODIES).
@export var body: StringName = &"boy"
## Offered in the character creator.
@export var creator := true
## Lower comes first in the creator; the first of each kind is the default look.
@export var order := 0

func field() -> StringName:
	return FIELDS[kind]
