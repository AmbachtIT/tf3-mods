-- TEMPORARY DIAGNOSTIC - remove before release.
--
-- Registers the station-topology probe. A game script is the only place our
-- code sees the *entities* the construction turned into, which is where the
-- remaining cargo question lives: the construction log can show that both
-- station records are capable, and cannot show whether the engine put them in
-- one station group.
--
-- `.gs.lua` files are picked up automatically for any enabled mod, so this
-- needs no registration beyond existing. See `town_clustering.gs.lua` and
-- `ec_probe_report.gs.lua` for the same shape.
function data()
	return {
		updateScript = {
			fileName = "multi_layer_stations_1::/ml_probe.script@update",
		},
	}
end
