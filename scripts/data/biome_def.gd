class_name BiomeDef
extends Resource
## The look of a region: sky, light, ground textures, platform art, backdrop and the
## scenery scattered over every map that uses it. Maps share biomes.

@export var id: StringName

@export_group("Sky and light")
@export var sky_top := Color("2b2152")
@export var sky_mid := Color("6a4688")
@export var sky_low := Color("e8917e")
@export var sky_horizon := Color("ffd3a0")
@export var sun_color := Color("ffe7a8")
@export var light_color := Color("ffe2b0")
@export var light_energy := 1.9
@export var ambient_color := Color("7a6ab8")
@export var ambient_energy := 0.35
@export var fog_color := Color("e8a49a")
## HDR colour of the floating motes; rising makes them drift up like embers.
@export var mote_color := Color(1.8, 1.5, 0.9)
@export var motes_rise := false
@export var lantern_light := Color("ffc070")

@export_group("Atmosphere")
## Colour grade of the finished picture (post.gdshader): a multiply tint, a colour the
## shadows lean toward and how much, and saturation (1 = unchanged).
@export var grade_tint := Color(1.0, 0.98, 0.95)
@export var grade_lift := Color("4a3a78")
@export_range(0.0, 1.0) var grade_lift_amount := 0.25
@export_range(0.0, 2.0) var grade_saturation := 1.05
## Soft beams of sunlight slanting through the scene (dawn meadows, forests).
@export var light_shafts := false
@export var light_shaft_color := Color(1.0, 0.85, 0.6, 0.12)

@export_group("Ground")
## Seamless textures for the floor's painted front: rock (side) in a band under its grass
## edge, then soil below.
@export var ground_side: Texture2D
@export var ground_soil: Texture2D
## The painted front of a floating platform (art/sheets/platform_pieces_<area>.json): its
## left end, the middle and a second middle mixed in, and its right end. PlatformSkin sets
## them edge to edge for each platform's width. Floating platforms are only this skin, with
## no 3D block behind it, and the floor's top edge is its middles repeated.
@export var platform_left: Texture2D
@export var platform_middle: Texture2D
## Optional: middles alternate between this and platform_middle so long platforms don't repeat.
@export var platform_middle_alt: Texture2D
@export var platform_right: Texture2D
## Optional, for raised terraces (`PlatformDef.solid`; art/sheets/terrace_pieces_<area>.json):
## square ends that replace the rounded platform ends on a terrace's top edge, and columns of
## corner stones that run down the two ends of its wall, repeating top to bottom.
@export var terrace_left: Texture2D
@export var terrace_right: Texture2D
@export var terrace_corner_left: Texture2D
@export var terrace_corner_right: Texture2D
## Grass blades: tufts peeking over the top edge of the floor and platforms, from behind.
@export var edge_grass: Array[Texture2D] = []

@export_group("Scenery")
@export var backdrop: Array[BackdropLayerDef] = []
## Scattered along the floor of every map in this biome.
@export var ground_decor: Array[DecorDef] = []
## Scattered along every floating platform, just behind its skin (keep `depth` near 0, like -0.6 to -0.2).
@export var platform_decor: Array[DecorDef] = []
## Scattered along the floor of town maps only, on top of ground_decor: the props
## that make a town feel lived in (never a building picture: houses are BuildingPlacements).
@export var town_decor: Array[DecorDef] = []
@export var lantern: Texture2D
## Where the lit lamp sits on the lantern post, as shares of the post picture's width
## (from its middle, right is positive) and height (up from its base): the glow and light go there.
@export var lantern_lamp := Vector2(0.22, 0.62)
@export var portal_frames: Array[Texture2D] = []
## Rooms inside buildings: the doorway out, drawn on the back wall at every door portal.
@export var door: Texture2D

@export_group("Ambient life")
## Birds or other small creatures crossing the sky behind the scene (their "move" or
## "idle" animation), and how many.
@export var flyers: SpriteFrames
@export var flyer_count := 0
## Smoke curling up from the town's houses (town_decor, and buildings with a chimney).
@export var chimney_smoke := false
@export var smoke_color := Color(0.85, 0.82, 0.8, 0.35)
