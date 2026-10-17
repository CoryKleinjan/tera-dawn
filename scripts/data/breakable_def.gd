class_name BreakableDef
extends Resource
## Something on a map that breaks open when the player hits it: a chest, whose loot spills
## out, a wall or cracked floor, which opens the shortcut behind it (a PortalDef whose
## `shortcut` is this id), or a lever, which swings over (its broken picture) and lifts the
## gate on the doors whose `gate` is this id. A fake wall (`walk_through`) opens the same way when the player walks
## into it. Each character breaks their own once, for good (Character.secrets); it stands
## whole for everyone who hasn't, whoever else broke theirs.

## Its id in Character.secrets, unique across the game. A wall's is the shortcut it opens, a
## lever's the gate it lifts.
@export var id: StringName
@export var x := 0.0
## Index of the platform it stands on (0 is the floor).
@export var platform := 0
## Blows it takes to break.
@export var hits := 1
## A fake wall: blows pass through it, and so do you. It fades the first time you step into
## it and opens the way behind it for good, as if broken (`hits` doesn't count).
@export var walk_through := false
## A cracked floor: blows only shake it, and a Slam (RelicDef.Move.SLAM) landing on it breaks
## it at once. Like a wall, it opens the shortcut whose `shortcut` is its id (a way down).
@export var slam_only := false
## Its picture standing whole, and once broken (an opened chest, a wall with a hole in it);
## with no broken picture it is gone once broken.
@export var whole: Texture2D
@export var broken: Texture2D
## How tall it stands, in game pixels: its pictures are scaled to this. A blow lands when an
## attack's area meets the whole picture.
@export var height := 60.0
## What spills out when it breaks, for the player who broke it.
@export var loot: Array[DropEntry] = []
## A Monster Book card of this monster spills out too, unless their page for it is complete.
@export var card: MonsterDef

## Game pixels per texel its pictures are drawn at.
func texel() -> float:
	return height / whole.get_height() if whole else 1.0

## Its size on the map, in game pixels.
func size() -> Vector2:
	return whole.get_size() * texel() if whole else Vector2(40.0, height)

## The area a blow must reach to land, standing with its feet at `foot`.
func rect(foot: Vector2) -> Rect2:
	var s := size()
	return Rect2(foot.x - s.x / 2.0, foot.y - s.y, s.x, s.y)
