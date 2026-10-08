--- Multi-layer Stations - v0.1: one rail platform at +12 m over one bus
--- platform at grade.
---
--- Structure follows the stock underground station: one DYNAMIC template with an
--- empty `data.params`. No parameters - the level layout is fixed at placement,
--- which is the accepted design, and `postConstructionModifiable` would not work
--- here anyway because the UI reads that flag off `desc.params` and no
--- template-based construction has any. See ../NOTES.md, "Editing".
---
--- The level at **grade** decides where this lives and what it snaps to, because
--- that is the level the player places against. This is rail-over-road, so its
--- ground level is a bus platform: it belongs in the road tab and snaps to
--- roads. The mirror variant, road-over-rail, will sit in the rail tab.

local function makeConstructionTemplates()
	return {
		{
			type = "DYNAMIC",
			configureLayerScript = {
				fileName = "::/gui/construction/construction_desc_layers.script@configureDefaultLayerFn",
				params = { heightmapContours = true },
			},
			configureHudIconsScript = {
				fileName = "::/gui/construction/construction_desc_hud_icons.script@configureStationHudIconsFn",
				params = { cargo = false },
			},
			availability = { yearFrom = 1900, yearTo = 0 },
			description = {
				name = _("Multi-layer Station"),
				description = _("An elevated train platform over a bus platform at street level. Two stations in one structure: connect a road to the lower level and a track to the upper one."),
				icon = "::/stations/rail/modular_station/station_era_c.tga",
				previewIcon = "::/stations/rail/modular_station/station_era_c_preview.tga",
				attributes = {
					noise = { 25, -1 },
					pollution = { 45, 350 },
					maintenanceCost = { 40000, -1 },
					cost = { 240000, -1 },
				},
				cargoTypeSet = {
					cargoClassesExcluded = {},
					cargoClassesIncluded = { "PASSENGERS" },
					cargoTypesExcluded = {},
					cargoTypesIncluded = {},
				},
			},
			data = { params = {} },
			menuCategory = {
				categories = {
					{
						category = "road_buildings",
						filterCategories = { "passenger" },
						order = 1500,
					},
				},
			},
		},
	}
end

function data()
return {
	configureLayerScript = {
		fileName = "::/gui/construction/construction_desc_layers.script@configureDefaultLayerFn",
		params = { heightmapContours = true },
	},
	configureHudIconsScript = {
		fileName = "::/gui/construction/construction_desc_hud_icons.script@configureStationHudIconsFn",
		params = { cargo = false },
	},
	namePrefix = _("{townName} Multi-layer Station"),
	subConstructionNamePrefix = "{constructionName}",
	description = {
		name = _("Multi-layer Station"),
		description = _("An elevated train platform over a bus platform at street level."),
		icon = "",
		previewIcon = "",
		attributes = {
			noise = { 25, -1 },
			pollution = { 45, 350 },
			maintenanceCost = { 40000, -1 },
			cost = { 240000, -1 },
		},
	},
	availability = { yearFrom = 1900, yearTo = 0 },
	soundConfig = {
		builderAudioRes = "::/gui/construction/sound/buildoze_construction_large.builder_audio",
	},
	order = 1500,
	params = {
		{
			-- The only option, and only while the viaduct is being settled.
			key = "mlBridge",
			name = _("Elevated track"),
			values = { _("Bridge"), _("No bridge") },
			defaultIndex = 1,
			displayMode = "Horizontal",
		},
	},
	updateScript = {
		fileName = "multi_layer_stations_1::/multi_layer_station.script@updateFn",
		params = {},
	},
	createTemplateScript = {
		fileName = "multi_layer_stations_1::/multi_layer_station.script@createTemplateFn",
		params = {},
	},
	constructionTemplates = makeConstructionTemplates(),
}
end
