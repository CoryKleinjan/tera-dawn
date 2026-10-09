class_name LookDef
extends Resource
## One appearance option picked when a character is made: a skin tone, a face, an eye
## colour, a hairstyle or a hair colour. Add one by saving a LookDef in data/looks/; the
## character creator lists every LookDef with `creator` set, in `order`.
##
## Until the hero is drawn in layers, a look is shown on the painted hero: colours recolour
## his skin, eyes or hair, and `shape` names a stand-in drawn in code (LookShapes). Once
## layered art exists, `frames` holds it and replaces the stand-in.

enum Kind { SKIN, FACE, EYES, HAIR, HAIR_COLOR }
## The Appearance field each kind fills, in the order the creator lists them.
const FIELDS: Array[StringName] = [&"skin", &"face", &"eyes", &"hair", &"hair_color"]
const KIND_NAMES := ["Skin", "Face", "Eyes", "Hair", "Hair colour"]

@export var id: StringName
@export var display_name := ""
@export var kind: Kind = Kind.SKIN
## Skin tone, eye colour or hair colour. Fully transparent keeps the hero's own colour.
@export var color := Color(0, 0, 0, 0)
## The stand-in drawn in code for a face or hairstyle (LookShapes), empty for none.
@export var shape: StringName
## Layered art for this face or hairstyle, frame for frame like the hero's SpriteFrames.
@export var frames: SpriteFrames
## Offered in the character creator.
@export var creator := true
## Lower comes first in the creator; the first of each kind is the default look.
@export var order := 0

func field() -> StringName:
	return FIELDS[kind]

## Whether this recolours the hero (false keeps his own colour).
func recolors() -> bool:
	return color.a > 0.0
