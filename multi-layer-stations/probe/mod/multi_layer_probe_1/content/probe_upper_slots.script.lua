--- Phase 3b, second attempt: add a slot layer at +12 m to the *stock* modular
--- rail station.
---
--- Why not the standalone probe_slots.con any more: a construction is only
--- selectable if one of its subconstructions carries a STATION, VEHICLE_DEPOT,
--- INDUSTRY or WAREHOUSE component. `getSubconstructionDescriptionAndSortKey`
--- (gui/entity_window/make_entity_window.tl:46-101) returns nil for anything
--- else, and the entity window skips subconstructions with no description. A
--- construction that is pure geometry therefore cannot be clicked, so its slots
--- can never be reached and `postConstructionModifiable` can never be seen.
---
--- Rather than grow a station onto a throwaway probe, borrow one that already
--- works. The stock modular rail station is selectable, already has a modules
--- list, and is the thing the real mod will be wrapping anyway - so this probe
--- is a rehearsal for the real technique as well as an answer.
---
--- The upper slots get their own type, `ml_upper_slot`, deliberately. Giving
--- them the stock `passenger_platform` type would let a stock platform module
--- land in one, and that module immediately calls `result.GetCoord(slotId)` -
--- which only knows the ids the stock script generated, so it would return nil
--- and crash on the next line. A private type plus a private module keeps the
--- two worlds apart.

local util = require "::/scripts/util.tl"
local vec3 = require "::/scripts/vec3.tl"
local transf = require "::/scripts/mat4.tl"
local laneutil = require "::/scripts/construction/laneutil.lua"
local constructionutil = require "::/scripts/construction/constructionutil.lua"

local LOG = "[ml-probe] "
local SELF = "multi_layer_probe_1::/probe_upper_slots.script"
local STATION = "/stations/rail/modular_station/modular_station.con"

local PITCH = 12.0
local UPPER_TYPE = "ml_upper_slot"
--- Stock slot ids are baseSlotId + 1000*i + 10*j, so they stay well inside
--- +-200000. 5e7 is clear of that with room to spare.
local ID_OFFSET = 50000000

local MARKER = "::/assets/markers/marker_exclamation.mdl"
--- A 40 m x 5 m x 1.12 m platform deck, origin at one end
--- (bbMin {0,-2.51,0}, bbMax {40,2.51,1.12}). Borrowed purely because it is a
--- recognisable slab; the probe is not trying to look good.
local DECK = "::/stations/rail/era_c/perron_5.mdl"
local ROAD = "::/infrastructure/street/country/country_new_small.street_template"
local BRIDGE = "::/infrastructure/bridge/concrete.bridge"

--- A straight 2-point curve, the shape laneutil and addEdges both want.
local function seg(a, b)
	return { a, b }
end

--- The second station: a minimal bus deck at +PITCH, bolted onto the rail
--- station as an extra subconstruction.
---
--- The question it exists to answer is whether **two station records in one
--- construction join a single StationGroup**, so that a train on level 0 and a
--- bus on level +1 are one station for passengers. A two-level station has one
--- station record per level, so if they do not group, interchange is broken and
--- the whole design needs rethinking. Secondary: whether a station record at
--- +12 gets working terminals and catchment at all, and whether a STREET edge
--- at +12 behaves like the TRACK edge already proven by probe_bridge.
---
--- Indices in a terminal are all 0-based, and the second number of a pair is a
--- *curve* index, not a node index - `addStationCapacities` reads
--- `laneLists[edge[1] + 1].nodes[edge[2] * 2 + 1]`
--- (`constructionutil.lua:561-564`), and each 2-point curve contributes two
--- nodes.
--- `oneStation` picks between the two shapes a two-level station could take:
---
---  * false - the deck gets its **own** `station` record in its own
---    subconstruction. Two stations in one construction. Confirmed in-game to
---    produce two separately selectable stations, so passengers can only
---    transfer by walking the pedestrian network between them.
---  * true  - the deck's terminal is appended to the **rail station's existing**
---    `station` record, which means one station with terminals at two heights.
---    Its lanes have to live in the rail subconstruction's own `laneLists`,
---    because terminal indices are relative to the subconstruction that owns
---    the station.
local function addBusDeck(result, oneStation)
	local z = PITCH

	local host = oneStation and result.cargoStation or nil
	if oneStation and (host == nil or host.station == nil) then
		log.warning(LOG .. "one-station mode: no rail station record to attach to,"
			.. " falling back to a separate station")
		host = nil
		oneStation = false
	end

	local sub = host or {
		models = {},
		colliders = {},
		terrainAlignmentLists = {},
		groundFaces = {},
		laneLists = {},
		tag = 7,
	}
	sub.laneLists = sub.laneLists or {}
	sub.models = sub.models or {}
	sub.colliders = sub.colliders or {}

	-- Terminal index pairs are relative to the owning subconstruction, so when
	-- borrowing the rail station's we have to offset past the lanes it already
	-- has.
	local base = #sub.laneLists

	sub.models[#sub.models + 1] = { id = DECK, transf = transf.transl(vec3.new(-20.0, 2.0, z)) }
	sub.models[#sub.models + 1] = { id = MARKER, transf = transf.transl(vec3.new(0.0, 8.0, z)) }

	sub.colliders[#sub.colliders + 1] = {
		type = "BOX",
		transf = transf.transl(vec3.new(0.0, 2.0, z + 1.0)),
		params = { halfExtents = { 20.0, 3.0, 2.0 } },
	}

	-- lane 0: the bus lane. Curve 1 ends at the middle, which is the stop.
	sub.laneLists[#sub.laneLists + 1] = laneutil.createLane({
		seg({ -15.0, 0.0, z }, { 0.0, 0.0, z }),
		seg({ 0.0, 0.0, z }, { 15.0, 0.0, z }),
	}, { "BUS" }, 40, 3, false)

	-- lane 1: where passengers wait, alongside the bus lane.
	sub.laneLists[#sub.laneLists + 1] = laneutil.createLane({
		seg({ -15.0, 4.0, z }, { 0.0, 4.0, z }),
		seg({ 0.0, 4.0, z }, { 15.0, 4.0, z }),
	}, { "PERSON" }, 2, 2, false)

	-- lane 2: the bit nobody has solved yet - pedestrian access from grade up
	-- to +12. One long diagonal segment does the climbing, exactly as the stock
	-- underground station's stairs do in the other direction. `linkable` is what
	-- lets the ground end join the street network.
	sub.laneLists[#sub.laneLists + 1] = laneutil.createLane({
		seg({ 0.0, 4.0, z }, { 0.0, 12.0, z }),
		seg({ 0.0, 12.0, z }, { 0.0, 24.0, 0.0 }),
		seg({ 0.0, 24.0, 0.0 }, { 0.0, 32.0, 0.0 }),
	}, { "PERSON" }, 2, 2, true)

	-- `vehicleEdges` is what was missing on the first attempt, and it is why the
	-- line editor said "can't connect stops": `vehicleNode` only marks where a
	-- vehicle stands, not the drivable path through the stop. Every stock ROAD
	-- terminal sets it (modules.script.lua:92-98 and :501 in the street
	-- station; the airports too). The tram-based underground station does not,
	-- which is why copying that one as a template came up short - trams follow
	-- track edges instead.
	--
	-- Note the field is absent from the TerminalDef record
	-- (construction_util_serialized.d.tl:173-184), which declares only four of
	-- these fields. Shipped content wins, as usual.
	local bus, plat, ramp = base + 0, base + 1, base + 2
	local terminal = {
		personEdges = { { plat, 0 }, { plat, 1 }, { ramp, 0 }, { ramp, 1 }, { ramp, 2 } },
		personNodes = { { plat, 0 }, { plat, 1 }, { ramp, 0 }, { ramp, 1 }, { ramp, 2 } },
		vehicleNode = { bus, 1 },
		vehicleEdges = { { bus, 0 }, { bus, 1 } },
		transportModes = { "BUS" },
		passengers = true,
		cargo = false,
	}

	if oneStation then
		table.insert(sub.station.terminals, terminal)
	else
		sub.station = {
			terminals = { terminal },
			tag = 7,
			pool = { edges = {}, capacity = 0 },
			catchmentAreas = { { position = { 0.0, 0.0, 0.0 }, radius = 200 } },
		}
		result.subconstructions = result.subconstructions or {}
		result.subconstructions[#result.subconstructions + 1] = sub
	end

	constructionutil.addStationCapacities(sub)

	-- Road stubs out to either end so a bus can actually be driven up here.
	-- STREET at +12 as a BRIDGE is the untested half of the road-over-rail
	-- ordering; TRACK at +12 is already proven.
	local before = #(result.edgeLists or {})
	for _i, e in ipairs({
		{ seg({ 15.0, 0.0, z }, { 30.0, 0.0, z }) },
		{ seg({ -15.0, 0.0, z }, { -30.0, 0.0, z }) },
	}) do
		constructionutil.addEdges(e, result, "STREET",
			{ type = ROAD, edgeType = "BRIDGE", edgeTypeName = BRIDGE },
			false, {}, { 1 })   -- node 1 is the outer end, left open
	end
	for i = before + 1, #result.edgeLists do
		result.edgeLists[i].alignTerrain = false
	end

	log.message(LOG .. "bus deck added at +" .. tostring(z)
		.. (oneStation and " [one station, terminal appended to the rail station]"
		                or " [separate station]")
		.. ": lanes " .. tostring(bus) .. "/" .. tostring(plat) .. "/" .. tostring(ramp)
		.. " of " .. tostring(#sub.laneLists)
		.. ", " .. tostring(#sub.station.terminals) .. " terminal(s) on that station, "
		.. tostring(#(result.subconstructions or {})) .. " subconstructions total, "
		.. tostring(#result.edgeLists - before) .. " road stubs")
end

--- Make a stock ScriptRef resolvable from inside this mod.
---
--- Two different traps, and the stock rail station hits the second one:
---
---  * a *relative* ref ("modular_station.script@updateFn") resolves against our
---    folder once we are the caller, so it has to be joined to the
---    construction's own directory;
---  * a ref starting with "/" resolves inside *our* mod's namespace, not the
---    base game - the same rule that makes `require "/scripts/vec3.tl"` fail
---    with "module 'multi_layer_probe_1::/scripts/vec3.tl' not found". It needs
---    the "::" prefix.
---
--- The stock rail station declares
--- "/stations/rail/modular_station/modular_station.script@updateFn", i.e. the
--- second case.
local function stockRef(conFileName, ref)
	if ref == nil or ref == "" then
		return nil
	end
	if string.find(ref, "::", 1, true) then
		return ref
	end
	if string.sub(ref, 1, 1) == "/" then
		return "::" .. ref
	end
	local dir = string.match(conFileName, "^(.*)/[^/]*$")
	if dir == nil then
		return nil
	end
	return dir .. "/" .. ref
end

local resolved = {}

local function resolveFn(ref)
	if resolved[ref] == nil then
		local ok, fn = pcall(util.useFn, ref)
		resolved[ref] = (ok and type(fn) == "function") and fn or false
		if resolved[ref] == false then
			log.message(LOG .. "could not resolve stock updateFn (" .. tostring(ref) .. ")")
		end
	end
	return resolved[ref] or nil
end

local function makeParam(key, name, values, defaultIndex)
	return {
		key = key,
		name = name,
		values = values,
		defaultIndex = defaultIndex,
		displayMode = "Horizontal",
		-- The point of the probe: declared at type.d.tl:1774 and honoured by
		-- entity_window_util.tl:1893-1912, but set by no shipped construction.
		postConstructionModifiable = true,
	}
end

function data()
return {
	runFn = function(captureParams, settings, allModParams)
		addModifier("loadConstruction", function(fileName, data)
			if not string.find(fileName, STATION, 1, true) then
				return data
			end

			local ref = stockRef(fileName, data.updateScript and data.updateScript.fileName)
			if ref == nil then
				log.message(LOG .. "no updateScript on " .. tostring(fileName))
				return data
			end

			local patched = 0
			for _i, template in ipairs(data.constructionTemplates or {}) do
				local params = template.data and template.data.params
				if params ~= nil then
					params[#params + 1] = makeParam("mlUpper", _("ML: upper slots"),
						{ _("Off"), _("On") }, 2)
					params[#params + 1] = makeParam("mlSlotHeight", _("ML: slot height"),
						{ _("Unset"), _("12 m") }, 1)
					params[#params + 1] = makeParam("mlStripTerrain", _("ML: strip terrain"),
						{ _("Off"), _("On") }, 1)
					params[#params + 1] = makeParam("mlBusDeck", _("ML: bus deck +12m"),
						{ _("Off"), _("On") }, 1)
					params[#params + 1] = makeParam("mlOneStation", _("ML: one station"),
						{ _("Two stations"), _("One station") }, 1)
					patched = patched + 1
				end
			end

			if patched == 0 then
				log.message(LOG .. "no template params on " .. tostring(fileName))
				return data
			end

			data.updateScript = {
				fileName = SELF .. "@upperSlotsUpdateFn",
				params = {
					stockRef = ref,
					stockParams = (data.updateScript and data.updateScript.params) or {},
				},
			}

			log.message(LOG .. "patched " .. tostring(patched) .. " rail station templates, "
				.. "stock updateFn at " .. ref)
			return data
		end)
	end,

	--- Calls the stock updateFn, then bolts a second slot layer on top of
	--- whatever it produced.
	upperSlotsUpdateFn = function(captureParams, params)
		params = params or {}

		local fn = resolveFn(captureParams.stockRef)
		if fn == nil then
			-- No useful fallback exists - reproducing 1300 lines of station is
			-- not on. Fail loudly and let the station come out empty.
			log.warning(LOG .. "stock updateFn unavailable, station will be broken")
			return {}
		end

		local result = fn(captureParams.stockParams or {}, params)

		-- Terrain stripping has to happen in terminateConstructionHook, not
		-- here. A construction is built in three stages:
		--
		--   1. updateFn           - slots, basic state, installs the hook
		--   2. the engine runs each placed module's updateScript
		--   3. terminateConstructionHook() - everything else
		--
		-- The rail station's hook spans modular_station.script.lua:855-1364 and
		-- is where its terrain alignment, connectors, terminals and
		-- subconstruction assembly all happen; the modules add their own
		-- alignment in stage 2. Stripping right here caught neither, which is
		-- why the first attempt logged "stripped 0".
		local wantStrip = (params.mlStripTerrain or 1) == 2
		local wantBusDeck = (params.mlBusDeck or 1) == 2
		local wantOneStation = (params.mlOneStation or 1) == 2

		if wantStrip or wantBusDeck then
			local stockHook = result.terminateConstructionHook
			result.terminateConstructionHook = function(...)
				if stockHook ~= nil then
					stockHook(...)
				end
				if wantBusDeck then
					-- After the stock hook, so result.subconstructions and
					-- result.edgeLists are both fully assembled and we are only
					-- appending.
					addBusDeck(result, wantOneStation)
				end
				if not wantStrip then
					return
				end
				local cleared = 0
				if result.terrainAlignmentLists then
					cleared = cleared + #result.terrainAlignmentLists
					result.terrainAlignmentLists = {}
				end
				for _i, sub in ipairs(result.subconstructions or {}) do
					if sub.terrainAlignmentLists then
						cleared = cleared + #sub.terrainAlignmentLists
						sub.terrainAlignmentLists = {}
					end
				end

				-- terrainAlignmentLists is only half of it. An edge list
				-- deforms the ground along its own edges unless it says
				-- otherwise, which is why the airfield sets this on its runway
				-- and taxiway (airfield.script.lua:344-352). A station's track
				-- edges will flatten the ground under them regardless of what
				-- the alignment lists say.
				local edges = 0
				for _i, el in ipairs(result.edgeLists or {}) do
					el.alignTerrain = false
					edges = edges + 1
				end

				log.message(LOG .. "stripped " .. tostring(cleared)
					.. " terrain alignment entries, alignTerrain=false on "
					.. tostring(edges) .. " edge lists (in hook)")
			end
		end

		if (params.mlUpper or 2) ~= 2 then
			return result
		end

		if result.slots == nil then
			log.message(LOG .. "stock result has no slots - nothing to stack onto")
			return result
		end

		local useSlotHeight = (params.mlSlotHeight or 1) == 2

		-- Snapshot first: we are appending to the list we are reading.
		local ground = {}
		for _i, slot in ipairs(result.slots) do
			if slot.type == "passenger_platform" then
				ground[#ground + 1] = slot
			end
		end

		local added = 0
		for _i, slot in ipairs(ground) do
			local upper = {
				id = slot.id + ID_OFFSET,
				transf = transf.mul(slot.transf, transf.transl(vec3.new(0.0, 0.0, PITCH))),
				type = UPPER_TYPE,
				spacing = slot.spacing,
				replaceable = true,
			}
			if useSlotHeight then
				upper.height = PITCH
			end
			result.slots[#result.slots + 1] = upper
			added = added + 1
		end

		result.slotConfig = result.slotConfig or {}
		result.slotConfig[UPPER_TYPE] = { skipCollisionCheck = true }

		log.message(LOG .. "added " .. tostring(added) .. " upper slots at +"
			.. tostring(PITCH) .. " (type " .. UPPER_TYPE .. ", slot.height "
			.. (useSlotHeight and "set" or "unset") .. "), "
			.. tostring(#result.slots) .. " slots total")

		return result
	end,

	--- The module for an upper slot. Writes into result.cargoStation, which is
	--- the subconstruction the stock station actually inserts - the same field
	--- every stock rail module reaches for.
	upperModuleUpdateFn = function(captureParams, result, transform, tag, slotId, addModel, constrParams)
		local sub = result.cargoStation
		if sub == nil or sub.models == nil then
			log.warning(LOG .. "upper module: no result.cargoStation to draw into (slot "
				.. tostring(slotId) .. ")")
			return
		end

		addModel(MARKER, transf.transl(vec3.new(0.0, 0.0, 0.0)), tag, sub.models)

		log.message(LOG .. "upper module placed in slot " .. tostring(slotId)
			.. " at z=" .. tostring(transform and transform[15] or "?"))
	end,

	upperModuleGetModelsFn = function(captureParams, params)
		return { { id = MARKER, transf = transf.transl(vec3.new(0.0, 0.0, 0.0)) } }
	end,
}
end
