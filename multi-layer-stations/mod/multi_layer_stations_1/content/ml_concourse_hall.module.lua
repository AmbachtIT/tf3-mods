--- The concourse, hall variant: the same building as `ml_concourse_arch` with
--- no road through it, offered along the rest of the station frontage so that a
--- row of them reads as one continuous building.
---
--- Read `ml_concourse_arch.module.lua` for why a concourse exists at all and
--- why its numbers live on the desc rather than in the script. Everything there
--- applies here unchanged, and that is the point of the pair: **the two
--- variants differ in their art and in the ground they are offered on, and in
--- nothing else.** Same 40 x 6 m cell, same catchment, same capacity, same
--- share of the goods store, same stairs up to the elevated level.
---
--- Which is also why the numbers below are copied rather than scaled. A hall is
--- not a lesser concourse - it is the part of the concourse that does not have
--- to get out of the road's way - so pricing it differently would only tell a
--- player to build whichever one is cheaper and leave a hole in their frontage.
--- Where they differ is where they can go: an arch can only sit on an entrance,
--- a hall can only sit off one.
---
--- The slots come one per deck tile along the frontage, which means a hall is
--- always a platform's length and always lines up with the supports and with
--- the arch - see `addHallSlots` in `multi_layer_station.script.lua` for how
--- the row is bounded and why the tile the entrance road passes through is left
--- to the arch.
---
--- The art is a placeholder like everything else here: the arch's silhouette
--- with the span bricked up, drawn from the same stone as the supports so the
--- frontage lines up. What it wants to be is a facade - doors, glass, a
--- departure board - and `../PLAN.md` tracks that with the arch's portal.

function data()
return {
	availability = {
		yearFrom = 0,
		yearTo = 0,
	},
	description = {
		name = _("Concourse - Hall"),
		description = _("A concourse hall at grade, the length of one platform. Place these either side of the road arch to extend the station building along the frontage: each one adds the same passenger catchment, waiting capacity, goods store and stairs to the elevated level as the arch does. Cannot be placed where an entrance road passes through - that cell is the arch's."),
		icon = "multi_layer_stations_1::/ml_concourse_hall.tga",
		previewIcon = "multi_layer_stations_1::/ml_concourse_hall_preview.tga",
		attributes = {
			cost = { 30000, -1 },
			maintenanceCost = { 5000, -1 },
		},
	},
	menuCategory = {
		categories = {
			{
				-- Our own category, after the arch at 500: see that module for
				-- why the three are ordered the way a station gets built.
				category = "ml_modules",
				filterCategories = { "passenger" },
				order = 510,
			},
		},
	},
	type = "ml_concourse_hall",
	metadata = {
		-- Identical to the arch's, deliberately - see the header.
		catchmentPassenger = {
			radius = 175,
		},
		moreCapacity = {
			passenger = 100,
		},
		emissionConfig = {
			noise = 1,
			pollution = 2,
		},
		price = 30000,
		maintenanceCost = 5000,
		comfortFactor = 0.2,
	},
	updateScript = {
		fileName = "multi_layer_stations_1::/multi_layer_station.script@hallUpdateFn",
		params = {},
	},
	getModelsScript = {
		fileName = "multi_layer_stations_1::/multi_layer_station.script@hallGetModelsFn",
		params = {},
	},
	builderAudioRes = "::/gui/construction/sound/buildoze_module.builder_audio",
}
end
