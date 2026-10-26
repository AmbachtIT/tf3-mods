--- The concourse, road-arch variant: the building that makes a multi-layer
--- station a station, in the one cell the entrance road passes through.
---
--- There are two of these modules and they are the **same building**, in the
--- same 40 x 6 m cell, differing only in whether a road goes through it:
---
---  * this one spans the entrance road, so its ground floor is two piers and an
---    opening (`CONCOURSE_SPAN`), and it is offered on the entrance only;
---  * `ml_concourse_hall` fills its cell solid, and is offered along the rest
---    of the frontage so a row of them reads as one building.
---
--- Everything below - the catchment, the capacity, the goods store, the
--- pedestrian link to the level above - both variants have, and have equally.
--- The split is the art and the ground they are offered on, nothing else. That
--- is why the two share `applyConcourse`, `addConcourseStock` and one entry in
--- the frozen-ids list rather than being two features.
---
--- It spans the bus entrance road at grade and is where the station's catchment
--- and waiting capacity come from - **for both levels at once**, which is the
--- thing no stock module can do. On the rail side catchment comes only from
--- `main_building_*` / `side_building_*` / `stairs`, on the street side only
--- from `entrance*`, and each feeds its own station record. A multi-layer
--- station is one structure whose two levels share a single StationGroup, so
--- one building serving both is the honest model.
---
--- The numbers below are **data, not code**: `multi_layer_station.script`'s
--- `applyConcourse` reads `metadata.catchmentPassenger.radius` and
--- `metadata.moreCapacity.passenger` straight off this desc and applies them to
--- both stations. That is deliberate - it keeps the balance in the module
--- where a reader expects it, and it is the same shape the stock building
--- modules use, so the two are comparable.
---
--- Why the script does the applying rather than this module's `updateFn`: a
--- module runs in **stage 2** of a construction build, and the station records
--- are assembled by the two stock families' hooks in **stage 3** (root
--- `NOTES.md`, "A modular construction is built in three stages"). At
--- `updateFn` time there is nothing to write into yet. The pedestrian link is
--- deferred for the same reason - it needs every lane list to exist, which is
--- only true after both hooks have run.
---
--- Still to come, tracked in `../PLAN.md`: the art should be a tunnel portal
--- over the road rather than the two brick piers it draws today.

function data()
return {
	availability = {
		yearFrom = 0,
		yearTo = 0,
	},
	description = {
		name = _("Concourse - Road Arch"),
		description = _("Spans the entrance road and serves both levels. Provides the station's passenger catchment and waiting capacity - a multi-layer station needs at least one concourse to attract passengers at all - a goods store that lets freight change level, the way a warehouse does between two separate stations, and the stairs passengers walk up to reach the elevated platforms. Offered on the entrance; use Concourse - Hall for the rest of the frontage."),
		icon = "multi_layer_stations_1::/ml_concourse_arch.tga",
		previewIcon = "multi_layer_stations_1::/ml_concourse_arch_preview.tga",
		attributes = {
			cost = { 30000, -1 },
			maintenanceCost = { 5000, -1 },
		},
	},
	menuCategory = {
		categories = {
			{
				-- Our own category (`category_ml_modules.res.lua`), not
				-- `modules_building`, as of 2026-10-22. The order now only
				-- sorts the three modules in it against each other: the
				-- support comes first at 400 because it is the one a player
				-- places repeatedly, and the two concourses follow in the order
				-- a station is built in - the arch over the entrance first,
				-- then the halls either side of it.
				category = "ml_modules",
				filterCategories = { "passenger" },
				order = 500,
			},
		},
	},
	type = "ml_concourse_arch",
	metadata = {
		-- 175 m, matching a street entrance rather than the 150 m of a rail
		-- station building: the concourse is the station's street-level public
		-- face, and that is what the stock street entrance is worth.
		catchmentPassenger = {
			radius = 175,
		},
		-- 100 each side. A stock `main_building_2` is worth 50 and a
		-- `*_passenger_building_10_10` rather less, so one concourse is
		-- deliberately generous - it is standing in for a building on both
		-- levels, and a station with one concourse and nothing else should be
		-- viable.
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
		fileName = "multi_layer_stations_1::/multi_layer_station.script@archUpdateFn",
		params = {},
	},
	getModelsScript = {
		fileName = "multi_layer_stations_1::/multi_layer_station.script@archGetModelsFn",
		params = {},
	},
	builderAudioRes = "::/gui/construction/sound/buildoze_module.builder_audio",
}
end
