class_name BiomeVariantDef
extends Resource
## A sub zone's own take on its region's look (Cory, 2026-10-11: each major zone has one
## style; its sub zones differ within it). A map keeps its region's BiomeDef as `biome` and
## sets a variant (MapDef.variant) that changes only what this sub zone does differently:
## time of day, light, fog, colour grade, the backdrop's tint and extra scenery. Anything
## left at its "keep" value (a fully transparent colour, -1, KEEP) stays the biome's own.
## MapDef.look() is the biome with the variant applied.

enum Toggle { KEEP, ON, OFF }

const KEEP_COLOR := Color(0, 0, 0, 0)

@export_group("Sky and light")
@export var sky_top := KEEP_COLOR
@export var sky_mid := KEEP_COLOR
@export var sky_low := KEEP_COLOR
@export var sky_horizon := KEEP_COLOR
@export var sun_color := KEEP_COLOR
@export var light_color := KEEP_COLOR
@export var light_energy := -1.0
@export var ambient_color := KEEP_COLOR
@export var ambient_energy := -1.0
@export var fog_color := KEEP_COLOR
@export var mote_color := KEEP_COLOR
@export var motes_rise := Toggle.KEEP

@export_group("Atmosphere")
@export var grade_tint := KEEP_COLOR
@export var grade_lift := KEEP_COLOR
@export var grade_lift_amount := -1.0
@export var grade_saturation := -1.0
@export var light_shafts := Toggle.KEEP
@export var light_shaft_color := KEEP_COLOR

@export_group("Scenery")
## Multiplies every backdrop layer's tint: a misty, dusky or sunlit take on the same painting.
@export var backdrop_tint := Color.WHITE
## Backdrop layers (indexes into BiomeDef.backdrop) this sub zone leaves out.
@export var hide_layers: PackedInt32Array = []
## Backdrop layers of its own, added after the biome's (e.g. one painted picture for a town
## that hides the biome's strips).
@export var more_backdrop: Array[BackdropLayerDef] = []
## Floor scenery rules (indexes into BiomeDef.ground_decor) this sub zone leaves out, e.g. the
## little scattered houses in a town that has real buildings.
@export var hide_ground_decor: PackedInt32Array = []
## Extra scenery scattered along its floor, on top of the biome's ground_decor.
@export var more_ground_decor: Array[DecorDef] = []

@export_group("Land")
## The sub zone's own land pieces (BiomeDef's platform, terrace and ground pictures), e.g. a
## town's paved stone terraces in a forest zone. Any left empty stay the biome's own.
@export var platform_left: Texture2D
@export var platform_middle: Texture2D
@export var platform_middle_alt: Texture2D
@export var platform_right: Texture2D
@export var terrace_left: Texture2D
@export var terrace_right: Texture2D
@export var terrace_corner_left: Texture2D
@export var terrace_corner_right: Texture2D
@export var ground_side: Texture2D

const COLORS := ["sky_top", "sky_mid", "sky_low", "sky_horizon", "sun_color", "light_color", "ambient_color",
	"fog_color", "mote_color", "grade_tint", "grade_lift", "light_shaft_color"]
const NUMBERS := ["light_energy", "ambient_energy", "grade_lift_amount", "grade_saturation"]
const TOGGLES := ["motes_rise", "light_shafts"]
const LAND := ["platform_left", "platform_middle", "platform_middle_alt", "platform_right", "terrace_left",
	"terrace_right", "terrace_corner_left", "terrace_corner_right", "ground_side"]

## `base` with this variant applied: a copy, so the shared biome is never changed.
func apply(base: BiomeDef) -> BiomeDef:
	var b: BiomeDef = base.duplicate()
	for key in COLORS:
		if get(key) != KEEP_COLOR:
			b.set(key, get(key))
	for key in NUMBERS:
		if get(key) >= 0.0:
			b.set(key, get(key))
	for key in TOGGLES:
		if get(key) != Toggle.KEEP:
			b.set(key, get(key) == Toggle.ON)
	if backdrop_tint != Color.WHITE or not hide_layers.is_empty() or not more_backdrop.is_empty():
		var layers: Array[BackdropLayerDef] = []
		for i in base.backdrop.size():
			if i in hide_layers:
				continue
			var layer: BackdropLayerDef = base.backdrop[i].duplicate()
			layer.tint *= backdrop_tint
			layers.append(layer)
		for extra in more_backdrop:
			var layer: BackdropLayerDef = extra.duplicate()
			layer.tint *= backdrop_tint
			layers.append(layer)
		b.backdrop = layers
	if not more_ground_decor.is_empty() or not hide_ground_decor.is_empty():
		var decor: Array[DecorDef] = []
		for i in base.ground_decor.size():
			if i not in hide_ground_decor:
				decor.append(base.ground_decor[i])
		decor.append_array(more_ground_decor)
		b.ground_decor = decor
	for key in LAND:
		if get(key) != null:
			b.set(key, get(key))
	return b
