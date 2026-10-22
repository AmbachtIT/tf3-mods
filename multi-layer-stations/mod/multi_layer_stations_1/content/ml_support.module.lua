--- A support for the elevated level: a brick facade filling one cell of the
--- support grid, from the ground to the underside of the level above.
---
--- Placed by the player rather than generated. Automatic supports were tried
--- and dropped: they looked wrong and fouled the bus station, and no automatic
--- rule can know what the player means to put underneath. The slots are aligned
--- to the grid of the level above, so a run of these reads as a continuous
--- arcade wall and leaves the spans the player skips open for roads.

function data()
return {
	availability = {
		yearFrom = 0,
		yearTo = 0,
	},
	description = {
		name = _("Elevated Support"),
		description = _("A brick support under the elevated level. Place these to carry the platforms above; leave gaps where roads need to pass through."),
		icon = "::/stations/rail/modular_station/stairs.tga",
		previewIcon = "::/stations/rail/modular_station/stairs_preview@2x.tga",
		attributes = {
			cost = { 8000, -1 },
			maintenanceCost = { 400, -1 },
		},
	},
	menuCategory = {
		categories = {
			{
				-- Our own category (`category_ml_modules.res.lua`), shared
				-- with the concourse, which sorts after this at 500.
				category = "ml_modules",
				filterCategories = { "passenger" },
				order = 400,
			},
		},
	},
	type = "ml_support",
	metadata = {
		price = 8000,
		maintenanceCost = 400,
	},
	updateScript = {
		fileName = "multi_layer_stations_1::/multi_layer_station.script@supportUpdateFn",
		params = {},
	},
	getModelsScript = {
		fileName = "multi_layer_stations_1::/multi_layer_station.script@supportGetModelsFn",
		params = {},
	},
	builderAudioRes = "::/gui/construction/sound/buildoze_module.builder_audio",
}
end
