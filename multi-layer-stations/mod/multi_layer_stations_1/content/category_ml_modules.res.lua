--- A build-menu category of our own, in the MODULES menu, for the support and
--- the concourse.
---
--- See `category_ml_station.res.lua` for how a mod gets a category at all and
--- what the fields mean. The only choices worth stating here are the two
--- numbers.
---
--- `order = 4500` puts it after the stock module categories that a modular
--- station shows - Platforms at 2000, Building at 3000, Road Access and Tracks
--- at 4000 - and before Misc at 5000. These two modules belong at the end of
--- that row rather than in the middle of it: everything before them is part of
--- the station a player is used to, and these are the two pieces that only
--- exist here.
---
--- The name is deliberately not "Multi-layer Stations" like the ROAD category.
--- The menus are different widths and this one sits under a heading that is
--- already about one station, so the short form is less noise.
function data()
	return {
		type = "menu_category",
		data = {
			category = "ml_modules",
			order = 4500,
			name = _("Multi-layer"),
			icon = resolve("category_ml_modules.tga"),
			menu = "MODULES",
		}
	}
end
