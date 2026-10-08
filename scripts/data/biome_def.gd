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

@export_group("Ground")
## Seamless textures for the solid floor and platform blocks.
@export var ground_top: Texture2D
@export var ground_side: Texture2D
@export var ground_soil: Texture2D
## The painted front of a floating platform: left end, repeating middle, right end.
@export var platform_left: Texture2D
@export var platform_middle: Texture2D
@export var platform_right: Texture2D
@export var platform_texel := 1.0
## Grass blades along the front edge of the floor and platforms.
@export var edge_grass: Array[Texture2D] = []

@export_group("Scenery")
@export var backdrop: Array[BackdropLayerDef] = []
## Scattered along the floor of every map in this biome.
@export var ground_decor: Array[DecorDef] = []
## Scattered along the back of every floating platform.
@export var platform_decor: Array[DecorDef] = []
@export var lantern: Texture2D
@export var signpost: Texture2D
@export var portal_frames: Array[Texture2D] = []
