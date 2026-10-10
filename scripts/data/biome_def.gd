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
@export var light_shaft_color := Color(1.0, 0.85, 0.6, 0.18)
## Slow cloud shadows drifting across the floor.
@export var cloud_shadows := true

@export_group("Ground")
## Seamless textures for the solid floor block (the only land with 3D depth).
@export var ground_top: Texture2D
@export var ground_side: Texture2D
@export var ground_soil: Texture2D
## The painted front of a floating platform: left end, repeating middle, right end. Floating
## platforms are only this skin, with no 3D block behind it.
@export var platform_left: Texture2D
@export var platform_middle: Texture2D
@export var platform_right: Texture2D
@export var platform_texel := 1.0
## Grass blades: a short fringe along the floor's front edge, and tufts behind platform skins.
@export var edge_grass: Array[Texture2D] = []

@export_group("Scenery")
@export var backdrop: Array[BackdropLayerDef] = []
## Scattered along the floor of every map in this biome.
@export var ground_decor: Array[DecorDef] = []
## Scattered along every floating platform, just behind its skin (keep `depth` near 0, like -0.6 to -0.2).
@export var platform_decor: Array[DecorDef] = []
@export var lantern: Texture2D
@export var signpost: Texture2D
@export var portal_frames: Array[Texture2D] = []
