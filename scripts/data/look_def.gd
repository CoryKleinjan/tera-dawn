class_name LookDef
extends Resource
## One appearance option picked when a character is made: a skin tone, a face, an eye
## colour, a hairstyle or a hair colour. Add one by saving a LookDef in data/looks/; the
## character creator lists every LookDef with `creator` set, in `order`.
##
## Colours recolour the hero's skin or tint his hair. A hairstyle is a layer of art (Paperdoll:
## layers/<id>.png, and layers/<id>_<hat shape>.png under each hat shape) on its own body, made
## by tools/art/hero_build.py. Faces and eye colours are painted on the body, so there are
## none to pick (the kinds stay so saved looks keep their numbers).

enum Kind { SKIN, FACE, EYES, HAIR, HAIR_COLOR }
## The Appearance field each kind fills, in the order the creator lists them.
const FIELDS: Array[StringName] = [&"skin", &"face", &"eyes", &"hair", &"hair_color"]
const KIND_NAMES := ["Skin", "Face", "Eyes", "Hair", "Hair colour"]

@export var id: StringName
@export var display_name := ""
@export var kind: Kind = Kind.SKIN
## Skin tone, eye colour or hair colour. Fully transparent keeps the hero's own colour.
@export var color := Color(0, 0, 0, 0)
## A hairstyle's body: "boy" or "girl" (Paperdoll.BODIES).
@export var body: StringName = &"boy"
## Offered in the character creator.
@export var creator := true
## Lower comes first in the creator; the first of each kind is the default look.
@export var order := 0

func field() -> StringName:
	return FIELDS[kind]

## Whether this recolours the hero (false keeps his own colour).
func recolors() -> bool:
	return color.a > 0.0
