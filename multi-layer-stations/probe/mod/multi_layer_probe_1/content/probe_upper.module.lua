--- The module for the stock rail station's added +12 m slot layer.
---
--- Its `type` matches the slot type that probe_upper_slots.script invents, so
--- it is the only module the game will offer for those slots - and the only
--- thing that can land in one. The model is the 26 m exclamation marker purely
--- because it is impossible to miss: if one appears 12 m above a platform, a
--- module was placed into a slot at height and rendered there.

function data()
return {
	availability = {
		yearFrom = 0,
		yearTo = 0,
	},
	description = {
		name = _("ML probe: upper marker"),
		description = _("Probe module. Only fits the +12 m slot layer this mod adds to the modular rail station."),
		icon = "::/stations/rail/modular_station/stairs.tga",
		previewIcon = "::/stations/rail/modular_station/stairs_preview@2x.tga",
		attributes = {
			cost = { 1000, -1 },
			maintenanceCost = { 100, -1 },
		},
	},
	menuCategory = {
		categories = {
			{
				category = "modules_building",
				filterCategories = { "passenger" },
				order = 99000,
			},
		},
	},
	type = "ml_upper_slot",
	metadata = {
		price = 1000,
		maintenanceCost = 100,
	},
	updateScript = {
		fileName = "multi_layer_probe_1::/probe_upper_slots.script@upperModuleUpdateFn",
		params = {},
	},
	getModelsScript = {
		fileName = "multi_layer_probe_1::/probe_upper_slots.script@upperModuleGetModelsFn",
		params = {},
	},
	builderAudioRes = "::/gui/construction/sound/buildoze_module.builder_audio",
}
end
