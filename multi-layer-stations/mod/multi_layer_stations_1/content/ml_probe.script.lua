-- TEMPORARY DIAGNOSTIC - remove before release.
--
-- Answers what the construction log cannot: what the engine made of our two
-- station records once they became entities.
--
-- Round one established that they are **two separate station groups**, one
-- station each, both fully cargo-capable (`cargoUnload=4` and `cargoUnload=2`).
-- There is no API to join them, so that is simply what one construction with
-- two station records produces.
--
-- Which turns out to be the wrong thing to have been chasing. Freight in this
-- game does not pass from station to station; it passes from a station to
-- **stock in that station's catchment**, and back out again. That is what a
-- warehouse is - `warehouse.script.lua` has no station or terminal at all,
-- only `STORAGE_STOCK` entries - and it is why the working half of the test
-- line needs one between its truck station and its train station.
--
-- So the question this probe now answers is: can both of our stations reach
-- the same stock? `catchmentAreaSystem.getStationCatchables(station, true)`
-- is the engine's own answer, per station, for cargo.
--
-- Everything here is read-only, and every engine call is wrapped: a probe that
-- crashes the session teaches nothing.
--
-- The report prefix is `[ml-probe]`, distinct from the construction's
-- `[multi-layer]`, so the two can be grepped apart.

local PREFIX = "[ml-probe] "
-- Game milliseconds. One report every ten seconds is enough to catch, and
-- slow enough not to bury the rest of the log.
local INTERVAL_MS = 10000

local lastReportAt = nil

local lines = nil

local function say(msg)
	if lines ~= nil then
		lines[#lines + 1] = msg
		return
	end
	local line = PREFIX .. msg
	if log ~= nil and log.message ~= nil then
		log.message(line)
	else
		print(line)
	end
end

--- Emit a report only if it differs from the last one.
---
--- The update runs on every `Sim Pool` thread, each with its own Lua state, so
--- the interval guard below is per state and the first version of this printed
--- the same block six times a second. Collecting the report and comparing it
--- with the last one collapses that to one block per actual change, which is
--- also what makes the log readable while the game runs.
local lastText = nil

local function emit(fn)
	lines = {}
	local ok, err = pcall(fn)
	local collected = lines
	lines = nil
	if not ok then
		say("report failed: " .. tostring(err))
		return
	end
	local text = table.concat(collected, " ;; ")
	if text == lastText then return end
	lastText = text
	for _, msg in ipairs(collected) do say(msg) end
end

local function count(t)
	if t == nil then return 0 end
	local n = 0
	for _ in pairs(t) do n = n + 1 end
	return n
end

local function getComponent(entity, componentType)
	local ok, c = pcall(api.engine.getComponent, entity, componentType)
	if ok then return c end
	return nil
end

local function try(fn, ...)
	local ok, v = pcall(fn, ...)
	if ok then return v end
	return nil
end

--- Like `try`, but says which of the two nothings happened.
---
--- `try` returning nil cannot be told apart from a call that legitimately
--- returned an empty list, and the first version of the problem reporting below
--- printed nothing at all - which read as "no problems" while the game was
--- showing red markers. Worth the extra return value.
local function tryX(fn, ...)
	local ok, v = pcall(fn, ...)
	if not ok then return nil, tostring(v) end
	return v, nil
end

--- The names of every cargo type in a `CargoTypeSet`.
---
--- `forEachCargoType` is the engine's own iterator over a set
--- (`res.d.tl:86`), which saves interpreting `cargoClassesIncluded` and the
--- include/exclude lists by hand, and `cargoTypeRep.getName` turns the ids
--- into something readable.
local function cargoNames(set, limit)
	local names = {}
	pcall(function()
		api.res.cargoTypeRep.forEachCargoType(set, function(id)
			if limit == nil or #names < limit then
				local n = api.res.cargoTypeRep.getName(id)
				names[#names + 1] = tostring(n):gsub("^.*/", ""):gsub("%.cargo$", "")
			end
		end)
	end)
	if #names == 0 then return "?" end
	return table.concat(names, ",")
end

--- Name an enum value, given the `api.type` record that defines it.
---
--- The records in `type.d.tl` are integer constants - `LineStationProblem` is
--- `StopUseless`, `CargoTypeUnloadUseless` and so on - so a reverse map turns
--- the engine's complaint into its own word for it. Wrapped because some of
--- these are native tables that `pairs` refuses; the number alone is still
--- better than nothing.
local function enumName(enumTable, value)
	local ok, name = pcall(function()
		for k, v in pairs(enumTable) do
			if v == value then return k end
		end
		return nil
	end)
	if ok and name ~= nil then return name end
	return tostring(value)
end

--- One stock, in full.
---
--- `cargoType` matters as much as `cargoTypes`: a stock may be *assigned* a
--- single cargo type rather than carrying a set, which is how a specialised
--- warehouse bay and a town building's input work, and `api.cmd` has a command
--- to set or reset it (`cmd.d.tl:799`). A set of `?` with a `cargoType` named
--- is a perfectly healthy stock; both nil would not be.
local function describeStock(s)
	local ct = "none"
	pcall(function()
		if s.cargoType ~= nil and s.cargoType >= 0 then
			ct = tostring(api.res.cargoTypeRep.getName(s.cargoType))
				:gsub("^.*/", ""):gsub("%.cargo$", "")
		end
	end)
	return string.format("%s cap=%s cargoType=%s mixed=%s set=[%s]",
		enumName(api.type.StockListType, s.type), tostring(s.capacity), ct,
		tostring(s.mixedTypes), cargoNames(s.cargoTypes, 6))
end

--- Our constructions, by file name over a full ECS scan.
---
--- `CONSTRUCTION` is one of the component types the engine will let Lua
--- enumerate; most are not (`getEntitiesWithComponent` on, say,
--- `PERSON_CAPACITY` raises "Cannot loop over this component type"). Reaching
--- everything else *through* the construction is therefore the only way in.
local function findOurConstructions()
	local found = {}
	local all = try(api.engine.getEntitiesWithComponent,
		api.type.ComponentType.CONSTRUCTION)
	for _, entity in pairs(all or {}) do
		local c = getComponent(entity, api.type.ComponentType.CONSTRUCTION)
		if c ~= nil and c.fileName ~= nil
			and string.find(c.fileName, "multi_layer_station", 1, true) then
			found[#found + 1] = { entity = entity, construction = c }
		end
	end
	return found
end

--- How many of a station's terminals can actually move freight.
---
--- The engine derives `cargoLoad`/`cargoUnload` itself - no stock script sets
--- them - so the honest construction-time answer is "does this terminal carry
--- a cargoTransferSpeeds entry for something other than PASSENGERS". Read both
--- here, because this is the one place the derived flags are visible.
local function terminalSummary(station)
	local terminals = station ~= nil and station.terminals or nil
	if terminals == nil then return "terminals=?" end

	local cargo, unload, zeroLength = 0, 0, 0
	for _, terminal in pairs(terminals) do
		local takesCargo = false
		for _, speed in pairs(terminal.cargoTransferSpeeds or {}) do
			local classes = speed.cargoTypeSet ~= nil
				and speed.cargoTypeSet.cargoClassesIncluded or {}
			for _, cls in pairs(classes) do
				if cls ~= "PASSENGERS" then
					takesCargo = true
					-- A class a terminal accepts over zero metres is one it can
					-- never move a crate of, which looks like a refusal to
					-- unload from the cab.
					if (speed.length or 0) == 0 then
						zeroLength = zeroLength + 1
					end
				end
			end
		end
		if takesCargo then cargo = cargo + 1 end
		if terminal.cargoUnload then unload = unload + 1 end
	end

	return string.format("terminals=%d cargo-capable=%d cargoUnload=%d%s",
		count(terminals), cargo, unload,
		zeroLength > 0 and string.format(" ZERO-LENGTH=%d", zeroLength) or "")
end

--- A stock warehouse of the player's, for comparison.
---
--- The decisive control: the save already contains a warehouse that works,
--- between a truck station and a train station. If its stocks differ from the
--- concourse's in some field - an assigned `cargoType`, a rule, anything - that
--- difference is the answer, and reading it costs one more construction scan.
---
--- Reported once, for the first one found, with its throughput so that "works"
--- is visible rather than assumed.
local function reportReferenceWarehouse()
	local all = try(api.engine.getEntitiesWithComponent,
		api.type.ComponentType.CONSTRUCTION)
	for _, entity in pairs(all or {}) do
		local c = getComponent(entity, api.type.ComponentType.CONSTRUCTION)
		if c ~= nil and c.fileName ~= nil
			and string.find(c.fileName, "warehouse", 1, true) then
			for _, sub in pairs(c.subconstructions or {}) do
				local sl = getComponent(sub, api.type.ComponentType.STOCK_LIST)
				if sl ~= nil then
					say(string.format(
						"reference warehouse %d (%s), subconstruction %d:"
						.. " stocks=%d rules=%d delivered/yr=%s shipped/yr=%s",
						entity, tostring(c.fileName), sub,
						count(sl.stocks), count(sl.rules),
						tostring(try(api.engine.util.stock.getCargoDeliveredPerYear, sub)),
						tostring(try(api.engine.util.stock.getCargoShippedPerYear, sub))))
					for i, s in pairs(sl.stocks or {}) do
						say(string.format("    their stock %s: %s", tostring(i),
							describeStock(s)))
					end
					return
				end
			end
		end
	end
	say("no warehouse construction of the player's found to compare against")
end

local function report()
	local ours = findOurConstructions()
	if #ours == 0 then
		say("no multi_layer_station construction found in the world yet")
		return
	end

	reportReferenceWarehouse()

	for _, probe in pairs(ours) do
		local c = probe.construction
		local stations = {}
		for _, s in pairs(c.stations or {}) do stations[#stations + 1] = s end

		say(string.format("construction %d: %d station(s), %d subconstruction(s)",
			probe.entity, #stations, count(c.subconstructions)))

		-- Our own goods store, if the concourse put one there. Named here so
		-- that the shared-catchment ids below can be recognised as ours, and so
		-- that "the stock exists but nothing can reach it" is distinguishable
		-- from "the stock was never created".
		for _, sub in pairs(c.subconstructions or {}) do
			local stockList = getComponent(sub, api.type.ComponentType.STOCK_LIST)
			local warehouse = getComponent(sub, api.type.ComponentType.WAREHOUSE)
			if stockList ~= nil or warehouse ~= nil then
				local capacity = 0
				for _, s in pairs(stockList ~= nil and stockList.stocks or {}) do
					capacity = capacity + (s.capacity or 0)
				end
				-- Whether anything has actually passed through it. The
				-- difference between "the store is reachable" and "the store
				-- is used" is the whole question once catchment is satisfied.
				local inPerYear = try(
					api.engine.util.stock.getCargoDeliveredPerYear, sub)
				local outPerYear = try(
					api.engine.util.stock.getCargoShippedPerYear, sub)
				say(string.format(
					"  subconstruction %d: stocks=%d capacity=%d warehouse=%s"
					.. " delivered/yr=%s shipped/yr=%s",
					sub, count(stockList ~= nil and stockList.stocks or {}),
					capacity, warehouse ~= nil and "yes" or "no",
					tostring(inPerYear), tostring(outPerYear)))
				for i, s in pairs(stockList ~= nil and stockList.stocks or {}) do
					say(string.format("    our stock %s: %s", tostring(i),
						describeStock(s)))
				end
			end
		end

		local groups = {}
		-- entity -> how many of our stations can reach it
		local cargoReach = {}
		for _, stationEntity in pairs(stations) do
			local station = getComponent(stationEntity,
				api.type.ComponentType.STATION)
			local group = try(
				api.engine.system.stationGroupSystem.getStationGroup,
				stationEntity)
			local stops = try(
				api.engine.system.lineSystem.getLineStopsForStation,
				stationEntity)
			local cargoCatch = try(
				api.engine.system.catchmentAreaSystem.getStationCatchables,
				stationEntity, true)

			if group ~= nil then
				groups[tostring(group)] = (groups[tostring(group)] or 0) + 1
			end
			for _, e in pairs(cargoCatch or {}) do
				cargoReach[e] = (cargoReach[e] or 0) + 1
			end

			say(string.format(
				"  station %d: group=%s %s catchment=%d lineStops=%s cargoCatchables=%s",
				stationEntity, tostring(group), terminalSummary(station),
				station ~= nil and count(station.catchmentAreas) or 0,
				stops ~= nil and tostring(count(stops)) or "?",
				cargoCatch ~= nil and tostring(count(cargoCatch)) or "ERROR"))
		end

		-- The whole question, in one number. Anything both stations can reach is
		-- a place the train can put planks down and the trucks can pick them up
		-- again; a warehouse standing in the shared catchment is the stock
		-- mechanism for exactly that.
		local shared, sharedList = 0, {}
		for e, n in pairs(cargoReach) do
			if n >= #stations and #stations > 1 then
				shared = shared + 1
				if #sharedList < 8 then sharedList[#sharedList + 1] = tostring(e) end
			end
		end
		say(string.format("  -> %d cargo stock(s) reachable from EVERY station%s%s",
			shared,
			shared > 0 and ": " .. table.concat(sharedList, ", ") or "",
			shared == 0 and ". Nothing both levels can reach, so freight has"
				.. " nowhere to change mode - the concourse goods store is"
				.. " either absent or out of catchment."
				or ". Freight can change level through these."))

		-- What each of them actually is. A store will take planks and hold
		-- them; only an InputStock *consumes* them, and a route exists only if
		-- something at the far end does. This is where "nothing nearby wants
		-- this cargo" becomes visible instead of inferred.
		for e, n in pairs(cargoReach) do
			local sl = getComponent(e, api.type.ComponentType.STOCK_LIST)
			if sl ~= nil then
				local bits = {}
				for i, s in pairs(sl.stocks or {}) do
					bits[#bits + 1] = describeStock(s)
					if i >= 4 then break end
				end
				say(string.format("    stock %s (reached by %d of our station(s)): %s",
					tostring(e), n, table.concat(bits, "; ")))
			end
		end

		local distinct = 0
		local names = {}
		for g, n in pairs(groups) do
			distinct = distinct + 1
			names[#names + 1] = g .. " x" .. tostring(n)
		end
		table.sort(names)

		say("  -> " .. tostring(distinct) .. " station group(s) ("
			.. table.concat(names, ", ") .. "). Expected to be one per station"
			.. " and not fixable from here; what matters is the shared stock"
			.. " count above.")

		-- What each group can carry, as the engine sees it. `getCarriers` with
		-- station = -1 returns the superset over all terminals, which is the
		-- quickest check that a group is known to handle both RAIL and ROAD.
		-- The engine's own complaints, which is what the red markers on a
		-- line are. `getLineStationProblems` is reported per (line, station
		-- group) pair, so it says *which stop* of which line is unhappy, and
		-- `LineStationProblem` names the reason - `CargoTypeUnloadUseless` and
		-- friends are much more specific than "it does not work".
		local stationProblems, spErr = tryX(
			api.engine.util.line.getLineStationProblems)
		local lineProblems, lpErr = tryX(api.engine.util.line.getLineProblems)
		say(string.format("  line problems world-wide: perStop=%s perLine=%s",
			spErr ~= nil and ("ERROR " .. spErr) or tostring(count(stationProblems)),
			lpErr ~= nil and ("ERROR " .. lpErr) or tostring(count(lineProblems))))
		stationProblems = stationProblems or {}
		lineProblems = lineProblems or {}

		-- Unfiltered. Filtering these by our own group entity found nothing
		-- while the game showed red markers, so print the lot and let the ids
		-- speak: ours are named in the station lines above.
		for _, pr in pairs(stationProblems) do
			say(string.format("    perStop: line=%s group=%s %s",
				tostring(pr[1]), tostring(pr[2]),
				enumName(api.type.LineStationProblem, pr[3])))
		end
		for _, pr in pairs(lineProblems) do
			say(string.format("    perLine: line=%s %s", tostring(pr[1]),
				enumName(api.type.LineProblem, pr[2])))
		end

		for g in pairs(groups) do
			local groupEntity = tonumber(g)
			local sg = groupEntity ~= nil and getComponent(groupEntity,
				api.type.ComponentType.STATION_GROUP) or nil
			local carriers = groupEntity ~= nil and try(
				api.engine.system.stationGroupSystem.getCarriers,
				groupEntity, -1, -1) or nil
			local lines = groupEntity ~= nil and try(
				api.engine.system.lineSystem.getLinesForStationGroup,
				groupEntity) or nil
			say(string.format("  group %s: stations=%d carriers=%s lines=%d",
				g, sg ~= nil and count(sg.stations) or 0,
				carriers ~= nil and tostring(count(carriers[1] or {})) or "?",
				lines ~= nil and count(lines) or 0))

			-- Per-stop detail for this group's lines: `noPath` and
			-- `incompatibleStop` are flags the summaries do not carry.
			for _, line in pairs(lines or {}) do
				local stops = try(api.engine.util.line.getDetailedLineProblems,
					line)
				local flags = {}
				for i, stop in pairs(stops or {}) do
					local s = stop ~= nil and stop[1] or stop
					if type(s) == "table" then
						local bad = {}
						if s.empty then bad[#bad + 1] = "empty" end
						if s.noPath then bad[#bad + 1] = "noPath" end
						if s.duplicateStop then bad[#bad + 1] = "duplicate" end
						if s.incompatibleStop then
							bad[#bad + 1] = "incompatible"
						end
						if #bad > 0 then
							flags[#flags + 1] = "stop " .. tostring(i) .. ": "
								.. table.concat(bad, "+")
						end
					end
				end
				if #flags > 0 then
					say(string.format("    line %s detail: %s", tostring(line),
						table.concat(flags, "; ")))
				end
			end
		end
	end
end

function data()
	return {
		update = function(_userParams, _state, dt)
			if dt == 0.0 then return end

			local world = api.engine.util.getWorld()
			local gameTime = getComponent(world, api.type.ComponentType.GAME_TIME)
			if gameTime == nil then return end

			local now = gameTime.gameTime
			if lastReportAt ~= nil and now - lastReportAt < INTERVAL_MS then
				return
			end
			lastReportAt = now

			emit(report)
		end,
	}
end
