class_name LookDef
extends Resource
## One appearance option picked when a character is made: a skin tone, a face, an eye
## colour, a hairstyle or a hair colour. Add one by saving a LookDef in data/looks/; the
## character creator lists every LookDef with `creator` set, in `order`.
##
## Colours recolour the hero's skin, or tint his irises or hair. Faces and hairstyles are
## layers of art (Paperdoll), frame for frame like the hero's SpriteFrames, made by
## tools/art/paperdoll_layers.py.

enum Kind { SKIN, FACE, EYES, HAIR, HAIR_COLOR }
## The Appearance field each kind fills, in the order the creator lists them.
const FIELDS: Array[StringName] = [&"skin", &"face", &"eyes", &"hair", &"hair_color"]
const KIND_NAMES := ["Skin", "Face", "Eyes", "Hair", "Hair colour"]

@export var id: StringName
@export var display_name := ""
@export var kind: Kind = Kind.SKIN
## Skin tone, eye colour or hair colour. Fully transparent keeps the hero's own colour.
@export var color := Color(0, 0, 0, 0)
## The face or hairstyle, drawn over the hero (hair art is greyscale, tinted with the hair
## colour).
@export var frames: SpriteFrames
## Hair: the part that hangs behind him (long hair, tails), drawn under the body.
@export var back_frames: SpriteFrames
## Hair: what shows under a hat, drawn instead of `frames` and `back_frames`.
@export var hat_frames: SpriteFrames
## Face: the irises, tinted with the eye colour.
@export var detail_frames: SpriteFrames
## Offered in the character creator.
@export var creator := true
## Lower comes first in the creator; the first of each kind is the default look.
@export var order := 0

func field() -> StringName:
	return FIELDS[kind]

## Whether this recolours the hero (false keeps his own colour).
func recolors() -> bool:
	return color.a > 0.0
