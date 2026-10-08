class_name GameData
extends RefCounted
## Static content: monsters, maps and color themes.
## Distances are in pixels, speeds in pixels per physics tick (60 Hz).

const MOBS := {
	"dewling": {"name": "Dewling", "lvl": 1, "hp": 28, "atk": 6, "xp": 6, "shards": [2, 6], "speed": 0.7, "w": 36, "h": 30},
	"sproutcap": {"name": "Sproutcap", "lvl": 4, "hp": 85, "atk": 12, "xp": 18, "shards": [6, 14], "speed": 0.9, "w": 40, "h": 44},
	"emberboar": {"name": "Ember Boar", "lvl": 8, "hp": 230, "atk": 22, "xp": 46, "shards": [15, 32], "speed": 1.25, "w": 60, "h": 42},
}

# plats: [x, y, width] one-way platform tops. The ground is added as platform 0.
# ropes: [x, top, bottom, kind] hanging from a platform top to the surface below.
# spawns: [mob, platform index, count].
const MAPS := {
	"meadow": {
		"name": "Dawnrise Meadow", "theme": "dawn", "w": 2600, "h": 700, "ground": 620,
		"plats": [
			[180, 500, 320], [600, 420, 280], [980, 510, 300],
			[260, 340, 240], [900, 300, 260], [1380, 400, 340],
			[1800, 490, 320], [1600, 260, 260], [2150, 360, 260],
		],
		"ropes": [
			[240, 500, 620, "rope"], [440, 340, 500, "ladder"], [700, 420, 620, "rope"],
			[1040, 300, 510, "ladder"], [1500, 400, 620, "rope"], [1680, 260, 400, "rope"],
			[1960, 490, 620, "rope"], [2260, 360, 620, "ladder"],
		],
		"portals": [{"x": 2530, "plat": 0, "to": "hollow", "tx": 90}],
		"spawns": [
			["dewling", 0, 6], ["dewling", 1, 2], ["dewling", 3, 2], ["dewling", 6, 3],
			["sproutcap", 5, 2], ["sproutcap", 7, 2], ["sproutcap", 9, 2], ["dewling", 8, 2],
		],
		"sign": {"x": 120, "text": "Dawnrise Meadow"},
	},
	"hollow": {
		"name": "Ember Hollow", "theme": "ember", "w": 2800, "h": 700, "ground": 620,
		"plats": [
			[300, 480, 360], [780, 400, 300], [1200, 500, 380],
			[520, 300, 260], [1100, 250, 300], [1700, 380, 360],
			[2150, 480, 380], [2050, 270, 300],
		],
		"ropes": [
			[380, 480, 620, "rope"], [620, 300, 480, "ladder"], [900, 400, 620, "rope"],
			[1250, 250, 500, "rope"], [1820, 380, 620, "ladder"], [2200, 270, 480, "rope"],
			[2450, 480, 620, "rope"],
		],
		"portals": [{"x": 60, "plat": 0, "to": "meadow", "tx": 2460}],
		"spawns": [
			["sproutcap", 0, 4], ["emberboar", 0, 3], ["sproutcap", 1, 3], ["emberboar", 3, 2],
			["sproutcap", 4, 2], ["emberboar", 5, 2], ["emberboar", 6, 2], ["emberboar", 7, 3],
			["sproutcap", 8, 2],
		],
		"sign": {"x": 180, "text": "Ember Hollow · Lv. 6+"},
	},
}

const THEMES := {
	"dawn": {
		"sky": [Color("2b2152"), Color("6a4688"), Color("e8917e"), Color("ffd3a0")], "sun": Color("ffe7a8"),
		"far": Color("5b4682"), "mid": Color("7f5f93"), "near": Color("4f7a5a"),
		"grass": Color("8fd16a"), "grass_hi": Color("c3ef8e"), "dirt": Color("8a5a43"), "dirt_dark": Color("5e3a2e"),
		# HD-2D stage: sprite set, sunlight, ambient fill, distance haze and floating particles
		"art": "dawn", "light": Color("ffe2b0"), "light_energy": 1.9, "ambient": Color("7a6ab8"), "ambient_energy": 0.35,
		"fog": Color("e8a49a"), "motes": Color(1.8, 1.5, 0.9), "lantern": Color("ffc070"),
	},
	"ember": {
		"sky": [Color("1a0f2b"), Color("4d1b3e"), Color("b9423b"), Color("ff9b5c")], "sun": Color("ffb35c"),
		"far": Color("3c1c3e"), "mid": Color("5e2741"), "near": Color("3a2a33"),
		"grass": Color("d9774f"), "grass_hi": Color("ffa577"), "dirt": Color("5c3433"), "dirt_dark": Color("3a1f24"),
		"art": "ember", "light": Color("ffb07a"), "light_energy": 1.5, "ambient": Color("7a3a5a"), "ambient_energy": 0.45,
		"fog": Color("b9423b"), "motes": Color(3.0, 1.2, 0.4), "lantern": Color("ff8a4a"),
	},
}

# Shared palette for UI and effects.
const NIGHT := Color("1b1230")
const PLUM := Color("4b3570")
const SUN := Color("ffd166")
const EMBER := Color("ff7a59")
const MIST := Color("fff3e4")
const HP := Color("ff5d73")
const MP := Color("5aa9ff")
const XP := Color("ffd166")
