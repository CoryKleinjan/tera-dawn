class_name TestGear
## The game has only the job starter sets (with no icons yet), but the tests wear, trade and
## compare much more gear. This loads their own plain gear (tests/fixtures/gear, the old items with a test
## icon) and hands it out the way the jobs did, in memory only: the game's data stays as it is.

const FOLDER := "res://tests/fixtures/gear"
## What a new Beginner wears, and the outfit the character creator offers.
const STARTING_GEAR := [&"training_sword", &"linen_tunic", &"trail_pants"]
const CREATOR_GEAR := [&"linen_tunic", &"meadow_shirt", &"berry_smock", &"trail_pants", &"rolled_shorts",
	&"field_trousers", &"canvas_shoes", &"clay_clogs", &"reed_sandals"]
## Gear the village shop sells, as it used to.
const SHOP := &"meadow_general"
const SHOP_GEAR := [&"training_sword", &"leaf_cap", &"linen_tunic", &"trail_pants", &"leather_boots"]
## Each job's basic weapons, handed over when advancing (the first is worn at once).
const ADVANCE_WEAPONS := {
	&"warrior": [&"bronze_sword"], &"mage": [&"apprentice_wand"], &"archer": [&"willow_bow"],
	&"thief": [&"rusty_dagger", &"iron_star"], &"pirate": [&"brass_knuckle", &"driftwood_pistol"],
}

static func install() -> void:
	if not Content.extra_items.is_empty():
		return
	Content.add_items_from(FOLDER)
	var beginner := Content.job(&"beginner")
	beginner.starting_gear.assign(STARTING_GEAR.map(Content.item))
	beginner.creator_gear.assign(CREATOR_GEAR.map(Content.item))
	for id: StringName in SHOP_GEAR:
		var line := ShopEntry.new()
		line.item = Content.item(id)
		Content.shop(SHOP).items.append(line)
	for job: StringName in ADVANCE_WEAPONS:
		var gifts: Array[DropEntry] = []
		for id: StringName in ADVANCE_WEAPONS[job]:
			var gift := DropEntry.new()
			gift.item = Content.item(id)
			gifts.append(gift)
		var j := Content.job(job)
		gifts.append_array(j.advance_gifts)
		j.advance_gifts = gifts
