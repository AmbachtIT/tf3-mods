--- Multi-layer Stations - v0.1: one rail platform at +12 m over one bus
--- platform at grade.
---
--- Structure follows the stock underground station: one DYNAMIC template with an
--- empty `data.params`. No parameters - the level layout is fixed at placement,
--- which is the accepted design, and `postConstructionModifiable` would not work
--- here anyway because the UI reads that flag off `desc.params` and no
--- template-based construction has any. See ../NOTES.md, "Editing".
---
--- Note the two distinct param readers, which is easy to conflate: the
--- *placement toolbar* takes `desc.params` **plus** `template.data.params`
--- (`construction_react_util.tl:1057`), while the *post-construction* panel
--- looks only at `desc.params` (`entity_window_util.tl:1893`). So a top-level
--- param does show up at placement time even on a template-based construction.
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
			-- `rail` adds the signal list to the HUD while this is being
			-- placed and `cargo` adds the warehouses, which is all these two
			-- flags do (`construction_desc_react_util.getStationHudIconsConfig`).
			-- Both are true here because both are true of the station: it has
			-- tracks that want signalling, and its upper level takes the stock
			-- cargo platforms. Stock's own rail station passes `rail = true`
			-- and sets `cargo` per template; we have one template for both.
			configureHudIconsScript = {
				fileName = "::/gui/construction/construction_desc_hud_icons.script@configureStationHudIconsFn",
				params = { cargo = true, rail = true },
			},
			-- 1930, not 1900, and the number comes from the **seeded track**.
			--
			-- `seedBothLevels` seeds `track/standard/standard`, whose own
			-- `yearFrom` is 1930 (`NOTES.md`, round sixteen), so a station
			-- placed before then came with a track type that did not exist yet.
			-- Asked for directly, 2026-10-22: *"Is it possible to only enable
			-- the station in 1930?"*
			--
			-- The alternative was to pick `track/simple/simple` below 1930 and
			-- keep the station available from 1900. Not taken: an elevated
			-- concrete deck is not a 1900 structure anyway, and one era boundary
			-- is cheaper to reason about than two code paths.
			availability = { yearFrom = 1930, yearTo = 0 },
			description = {
				name = _("Multi-layer Station"),
				description = _("An elevated train platform over a bus platform at street level. Two stations in one structure: connect a road to the lower level and a track to the upper one."),
				icon = "multi_layer_stations_1::/ml_station.tga",
				previewIcon = "multi_layer_stations_1::/ml_station_preview.tga",
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
						-- Our own category, shipped as
						-- `category_ml_station.res.lua` - see that file for how
						-- a mod can add one. It was `road_buildings`, among the
						-- stock bus stops, until 2026-10-22.
						category = "ml_station",
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
	-- See the template's copy above for what these two flags do.
	configureHudIconsScript = {
		fileName = "::/gui/construction/construction_desc_hud_icons.script@configureStationHudIconsFn",
		params = { cargo = true, rail = true },
	},
	-- "Bremen Central", not "Bremen Multi-layer Station". The mod's name has no
	-- business being in the station's, and a multi-level interchange is the
	-- kind of station a town calls its central one. Stock uses the same shape -
	-- the street station is `{townName} Station`.
	namePrefix = _("{townName} Central"),
	subConstructionNamePrefix = "{constructionName}",
	description = {
		name = _("Multi-layer Station"),
		description = _("An elevated train platform over a bus platform at street level."),
		-- The template's icons are what the build menu shows
		-- (`construction_react_util.tl:1080` prefers `template.desc.icon`), but
		-- these have to be real resources all the same: an empty string here
		-- produces `Texture error: Could not find texture ''`, which is
		-- indistinguishable in the log from the engine's own instance of it.
		-- Our own placeholder art, not the stock era-c station's, as of
		-- 2026-10-22. Referenced **without** the `@2x` the files carry: the
		-- engine appends it, which is how stock does it too - `wh_bulk.module.lua`
		-- asks for `::/warehouses/icons/wh_bulk_preview.tga` and only
		-- `wh_bulk_preview@2x.tga` ships. See `tools/make_menu_art.py`.
		icon = "multi_layer_stations_1::/ml_station.tga",
		previewIcon = "multi_layer_stations_1::/ml_station_preview.tga",
		attributes = {
			noise = { 25, -1 },
			pollution = { 45, 350 },
			maintenanceCost = { 40000, -1 },
			cost = { 240000, -1 },
		},
	},
	availability = { yearFrom = 1930, yearTo = 0 },
	soundConfig = {
		builderAudioRes = "::/gui/construction/sound/buildoze_construction_large.builder_audio",
	},
	order = 1500,
	-- No construction parameters, deliberately.
	--
	-- Top-level `params` are **not** inert on a template-based construction:
	-- `construction_react_util.tl:1057-1067` concatenates `desc.params` with
	-- `template.data.params` and hands the lot to the placement toolbar. So a
	-- param declared here and read by nobody is a control the player can move
	-- to no effect.
	--
	-- There was one - `mlBridge`, Bridge / No bridge - left over from settling
	-- the viaduct, and the script never looked at it. It is gone rather than
	-- implemented, because a param list is also a savegame contract: stored
	-- values come back as 1-based indices into `values`, so inserting an option
	-- later silently changes the meaning of every station already built (root
	-- NOTES.md, "Construction parameters are keyed by name"). Better to ship
	-- none than to ship one that has to change.
	params = {},
	updateScript = {
		fileName = "multi_layer_stations_1::/multi_layer_station.script@updateFn",
		params = {},
	},
	createTemplateScript = {
		fileName = "multi_layer_stations_1::/multi_layer_station.script@createTemplateFn",
		params = {},
	},
	-- Both stock families declare these, and the parts of module editing they
	-- are responsible for do not work without them. See the script for what
	-- each one is for; in short: `preProcessScript` is what makes a street
	-- platform two slots rather than one, and `upgradeScript` is the only way
	-- the elevated track can ever be electrified.
	preProcessScript = {
		fileName = "multi_layer_stations_1::/multi_layer_station.script@preProcessFn",
		params = {},
	},
	isAffectedByToolScript = {
		fileName = "multi_layer_stations_1::/multi_layer_station.script@isAffectedByToolFn",
		params = {},
	},
	upgradeScript = {
		fileName = "multi_layer_stations_1::/multi_layer_station.script@upgradeFn",
		params = {},
	},
	constructionTemplates = makeConstructionTemplates(),
}
end
