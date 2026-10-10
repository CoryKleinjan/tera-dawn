class_name BuildingDef
extends Resource
## A building's painted front: its picture, how tall it stands next to the hero and where
## its door is. Maps stand buildings in a row with BuildingPlacement; a building you can
## walk into also gets a door portal at its placement (see ARCHITECTURE.md, "How to add a
## building").

@export var id: StringName
@export var texture: Texture2D
## How tall it stands on screen, in game pixels (the hero is about 105). A house is about
## 2.5 heroes, a shop or hall 3 to 3.5.
@export var height := 280.0
## The middle of the doorway across the picture: 0 is its left edge, 1 its right (as drawn,
## before a placement flips it).
@export_range(0.0, 1.0) var door_x := 0.5
## Where chimney smoke rises from (share across and up the picture). x below 0 means none.
@export var chimney := Vector2(-1.0, 0.0)

## Game pixels per art pixel of the picture (TDStage.art_density). The building art is cut
## so this is TDStage.TEXEL, like all the land around it.
func texel() -> float:
	return height / texture.get_height() * TDStage.art_density(texture) if texture else 1.0

## Its width in game pixels.
func width() -> float:
	return texture.get_width() * height / texture.get_height() if texture else 0.0

## How far the doorway's middle is from the picture's middle, in game pixels (flipped or not).
func door_offset(flip: bool) -> float:
	var off := (door_x - 0.5) * width()
	return -off if flip else off
