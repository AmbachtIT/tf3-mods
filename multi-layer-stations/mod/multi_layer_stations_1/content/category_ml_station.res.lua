--- A build-menu category of our own, in the ROAD menu, for the station.
---
--- **A mod can add a menu category**, which is not obvious: the categories look
--- like engine furniture and most of them are shipped from
--- `gui/construction/menu/menu_categories/`. They are ordinary resources. The
--- build menu collects them with
---
---     local allCategoriesIds = api.res.genericRep.getAllOfType("menu_category")
---
--- (`gui/construction/construction_react_util.tl`), so every resource of this
--- type is picked up wherever it lives, and stock itself ships some from
--- content folders rather than from `gui/` - `street/country/category_roads_country.res.lua`
--- is the precedent this file follows.
---
--- `category` is the id a construction's `menuCategory.categories[].category`
--- names. `menu` picks the top-level menu, and the values stock uses are ROAD,
--- ROADS, RAIL, TRACKS, WATER, AIR, INDUSTRY, LANDSCAPING, TOWN, PERKS,
--- WAREHOUSE and MODULES. `order` sorts the categories inside one menu: ROAD
--- holds Buildings at 100, Tools at 1000 and assets at 8000, so 150 puts this
--- directly after Buildings, where the station used to live.
---
--- The icon is `resolve()`d against this file's own folder and the file that
--- has to be there is `<name>@2x.tga` - the `@2x` is the engine's, not part of
--- the name. 48 x 48, 8bpp greyscale, bright glyph on black; see
--- `tools/make_menu_icon.py`, which draws it and carries the measurements.
function data()
	return {
		type = "menu_category",
		data = {
			category = "ml_station",
			order = 150,
			name = _("Multi-layer Stations"),
			icon = resolve("category_ml_station.tga"),
			menu = "ROAD",
		}
	}
end
