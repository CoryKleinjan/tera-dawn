class_name Appearance
extends RefCounted
## What a character was made to look like: each the id of a LookDef. Only the hairstyle has
## options for now (it picks the body); skin tone, face, eye and hair colour are painted on
## the body. What they wear is on top of this (see Paperdoll).

var skin: StringName
var face: StringName
var eyes: StringName
var hair: StringName
var hair_color: StringName

func _init() -> void:
	for kind in LookDef.Kind.values():
		var options := Content.looks_of(kind)
		set(LookDef.FIELDS[kind], options[0].id if not options.is_empty() else &"")

## A look picked at random from the creator's options.
static func random(rng: RandomNumberGenerator = null) -> Appearance:
	var a := Appearance.new()
	for kind in LookDef.Kind.values():
		var options := Content.looks_of(kind)
		if not options.is_empty():
			var i := rng.randi_range(0, options.size() - 1) if rng else randi() % options.size()
			a.set(LookDef.FIELDS[kind], options[i].id)
	return a

## The LookDef chosen for a kind (null if none exists).
func part(kind: LookDef.Kind) -> LookDef:
	return Content.looks.get(get(LookDef.FIELDS[kind]))

## Picks the next (`step` 1) or previous (-1) creator option of a kind, wrapping around.
func cycle(kind: LookDef.Kind, step: int) -> void:
	var options := Content.looks_of(kind)
	if options.is_empty():
		return
	var i := options.find(part(kind))
	set(LookDef.FIELDS[kind], options[posmod(i + step, options.size())].id)

func copy() -> Appearance:
	var a := Appearance.new()
	a.load_dict(to_dict())
	return a

func to_dict() -> Dictionary:
	var out := {}
	for f in LookDef.FIELDS:
		out[String(f)] = String(get(f))
	return out

## Takes the looks in `data` that exist and are of the right kind; anything else stays.
func load_dict(data: Dictionary) -> void:
	for kind in LookDef.Kind.values():
		var f := LookDef.FIELDS[kind]
		var l: LookDef = Content.looks.get(StringName(str(data.get(String(f), ""))))
		if l and l.kind == kind:
			set(f, l.id)
