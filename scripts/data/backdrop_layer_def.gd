class_name BackdropLayerDef
extends Resource
## One layer of the parallax backdrop: a strip of mountains or trees that repeats across
## the map, or a few loose pieces (clouds, the sun) scattered in the sky.

enum Mode { STRIP, SCATTER }

@export var textures: Array[Texture2D] = []
@export var mode := Mode.STRIP
## Distance behind the play area in 3D units; further layers scroll slower.
@export var depth := 60.0
## Where the top of the layer sits on screen (0 top, 1 bottom) when the camera is mid-map.
## Scattered pieces are placed between x and y.
@export var screen_top := Vector2(0.35, 0.35)
## On-screen size of one texel in game pixels.
@export var texel := 2.0
@export var tint := Color.WHITE
## Glowing layers (the sun, embers) ignore lighting and fog and can bloom.
@export var glow := false
## Scatter: how many pieces, and how fast they drift (3D units per second).
@export var count := 1
@export var drift := 0.0
