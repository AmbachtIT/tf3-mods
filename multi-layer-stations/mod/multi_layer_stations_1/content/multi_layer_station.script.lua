--- Multi-layer Stations - rail over road.
---
--- Level 0 is the stock modular **street** station, delegated. Level +1 is the
--- stock modular **rail** station, delegated and lifted 12 m. Two separate
--- station records, so the game presents them as two stations the player can
--- inspect and name independently.
---
--- Both levels are therefore fully modular with the game's own modules, and the
--- lower level gets the bus station's real layout, entrance and snapping instead
--- of a hand-built approximation.
---
--- Everything load-bearing here was established by `../probe` and by a long
--- debugging session; see `../NOTES.md` and the root `NOTES.md`. The facts this
--- file is built on, each of which cost a round to find:
---
---  1. A construction is built in three stages: `updateFn`, then the engine's
---     module pass, then `terminateConstructionHook`. Both stock families do
---     almost all their work in the hook, so that is the only place to
---     post-process their output.
---  2. An **empty** `terrainAlignmentLists` makes the engine fit the terrain to
---     the geometry. An off-grade level needs a tiny `LESS` anchor at grade, not
---     an empty list.
---  3. Resource names inside a delegated result are base-game-relative and must
---     be prefixed with `::`, or the game silently draws placeholder cubes.
---  4. The stock hook shares model tables between `result` and its
---     subconstruction, so a lift has to track identity or it doubles.
---  5. Slot ids survive a savegame, so the module map may not be re-keyed later.
---  6. Two subconstructions must not share a `tag`, or the game crashes.
---
--- The one genuinely new thing here is hosting **two** families in one
--- construction. It works because their modules reach for disjoint field names
--- on the result they are handed - rail modules want `cargoStation`, `GetCoord`,
--- `connector`; street modules want `passengerStation`, `DemangleId`,
--- `coord2terminalInfo` - so one merged table can satisfy both. See
--- ../NOTES.md, "Picking a transport type per level".

local util = require "::/scripts/util.tl"
local vec3 = require "::/scripts/vec3.tl"
local transf = require "::/scripts/mat4.tl"
local laneutil = require "::/scripts/construction/laneutil.lua"

local LOG = "[multi-layer] "

--- The level pitch. See ../NOTES.md, "How tall is a level? 12 m".
local PITCH = 12.0

local RAIL_SCRIPT = "::/stations/rail/modular_station/modular_station.script"
local STREET_SCRIPT = "::/stations/street/modular_street_station/modular_terminal.script"

--- The era a missing `year` falls back to.
---
--- The engine puts `year` into every construction's params - `constructionComp.params["year"]`,
--- read at `gui/construction/construction.tl:4355` - and both stock families
--- rely on it: street does a bare `params.year >= eraCStart`
--- (`modular_terminal.script.lua:1357`) and rail a bare `year >= eraCStart`.
--- A nil would therefore not degrade, it would raise "attempt to compare nil
--- with number" *inside stock code*, where the traceback points at a file this
--- mod does not own. One default here turns a hard failure into a wrong era.
local FALLBACK_YEAR = 1990

--- Our own slot layer, declared up here because the module classifier below
--- needs it. The reasoning behind player-placed supports is further down, at
--- "holding the elevated level up".
local SUPPORT_TYPE = "ml_support"
--- Clear of both families: rail ids reach about 11e6, street about 20e6.
--- `slot.id * 10 + k` keeps the mapping stable across rebuilds, which matters
--- because `params.modules` is keyed by it and survives a savegame.
---
--- **Frozen at the first public release.** A slot id is a savegame key, so
--- changing this orphans every support a player has placed.
local SUPPORT_SLOT_BASE = 600000000

--- **Leave the elevated track's `snapNodes` alone.** Confirmed 2026-10-09; see
--- ../NOTES.md, "A station's snapNodes are load-bearing".
---
--- v0.1 converted them into `freeNodes`, on the theory that "a snap node is
--- where the engine joins the edge to the world, and at +12 that is where it
--- brings the ground up to meet it". The theory was wrong on both halves: the
--- terrain is fine without the conversion, and emptying `snapNodes` broke
--- module editing as soon as a track was connected - every module except the
--- one at the connection refused with "construction not possible".

--- What is done to the rail level: **turn it a quarter turn, then raise it.**
---
--- The two families' own axes agree out of the box - the rail tracks and the bus
--- roadway both run along y - which puts the bus exit parallel to the tracks.
--- That is almost always the wrong arrangement: a road feeding a station should
--- cross it, not run alongside it.
---
--- The quarter turn is applied to the **rail** level rather than the street
--- level, even though it is the bus station that looks wrong. Only the relative
--- angle matters, and this way is far cheaper and safer:
---
---  * the rail level is already being transformed, so the rotation composes into
---    the matrix at no extra cost, while rotating the street level would need a
---    second transform pass over the family whose tables are shared;
---  * the rail level is off-grade, so its ground faces and terrain alignment are
---    discarded anyway - rotating the street level would mean rotating its
---    alignment faces and ground textures too, which is more code and more to
---    get wrong;
---  * the snap point belongs to the street family and stays put, so the station
---    still aligns its bus exit to the road it snaps to. The tracks then come
---    out perpendicular to that road, which is the point.
---
--- `transf.mul(A, B)` applies B first, so this rotates about the construction
--- origin and then lifts.
local RAIL_XF = transf.mul(
	transf.transl(vec3.new(0.0, 0.0, PITCH)),
	transf.rotZ(math.rad(90.0)))

--------------------------------------------------------------------------------
-- resource names and resolving stock functions
--------------------------------------------------------------------------------

--- Where the street family's content lives, for resolving its **bare-relative**
--- resource ids. See `absoluteRes`.
local STREET_DIR = "/stations/street/modular_street_station/"

--- Make a base-game resource name absolute from inside a mod.
---
--- A path starting with `/` resolves inside **this mod's** namespace, not the
--- base game. True of `require`, of `ScriptRef` fileNames, of module names
--- returned from a template function, and of model ids and `.street_template`
--- names inside a delegated result - where an unresolvable id does not error,
--- the game just draws a placeholder cube.
---
--- There is a **third** form, and it was being missed: an id with no leading
--- slash at all, which resolves against the *resource's own directory*. One
--- module file mixes all three - `era_c_passenger_building_10_10.module.lua`
--- has `::/assets/...`, `/assets/...` and bare
--- `models/sidebuildings/streetstation_sidebuilding_era_c_s1.mdl` side by side.
--- The bare one came through here unchanged and then resolved inside this mod:
---
---     Resource error: referenced model not found:
---     'multi_layer_stations_1::/models/sidebuildings/streetstation_sidebuilding_era_c_s1.mdl'
---     in 'multi_layer_stations_1::/multi_layer_station.con (key: id)'
---
--- so the bus station's side building was a missing model on every rebuild.
--- `baseDir` is what a bare name is relative to; without one a bare name is
--- still passed through, which is correct for the rail family - it uses no bare
--- ids at all (checked across both `.zip`s: street has 42, rail none).
local function absoluteRes(name, baseDir)
	if type(name) ~= "string" then
		return name
	end
	if string.find(name, "::", 1, true) then
		return name
	end
	if string.sub(name, 1, 1) == "/" then
		return "::" .. name
	end
	if baseDir ~= nil then
		return "::" .. baseDir .. name
	end
	return name
end

--- Resolved stock functions, cached **only on success**. Each engine thread has
--- its own Lua state and `util.useFn` is not equally willing in all of them;
--- caching a failure turns a transient miss into a permanent one.
local resolved = {}

local function tryResolve(ref)
	local ok, fn = pcall(util.useFn, ref)
	if ok and type(fn) == "function" then
		resolved[ref] = fn
		return fn
	end
	return nil
end

--- `sibling` is another function in the same script; resolving it first appears
--- to get the file loaded into this state, after which the wanted ref resolves.
local function resolveFn(ref, sibling)
	if resolved[ref] then
		return resolved[ref]
	end
	local fn = tryResolve(ref)
	if fn ~= nil then
		return fn
	end
	if sibling ~= nil then
		tryResolve(sibling)
		fn = tryResolve(ref)
		if fn ~= nil then
			return fn
		end
	end
	log.warning(LOG .. "could not resolve " .. tostring(ref))
	return nil
end

--------------------------------------------------------------------------------
-- seeding
--------------------------------------------------------------------------------

--- Slot id bases from `modular_station.script.lua:41-46`; a slot id is
--- `base + 1000 * coordI + 10 * coordJ`, confirmed in-game by the probe.
local PASSENGER_PLATFORM_SLOT = 7400000
local TRACK_SLOT = 8400000

--- The rail station building's slot.
---
--- `mainBuildingSlotId = 3400000` (`modular_station.script.lua:39`), and the
--- stock seeding's non-head branch uses `mainBuildingSlotId + 10 * k + offset`
--- (`:218`), with `offset = 0` for fewer than three tracks and `k = 2` when the
--- platform's tile span is odd - which ours is, running -1..2.
---
--- Unlike the platform slots, this is **not** read off the slot creation:
--- building slots come from loops at `:690-780` that are not worth
--- reverse-engineering. The id is inferred from the seeding side instead, and
--- the catchment fallback in `finish` warns loudly if it turns out not to land
--- in a real slot - `addCatchmentCircles` needs a matching slot to take the
--- position from, so a wrong id presents as "no catchment", not as a misplaced
--- building.
local MAIN_BUILDING_SLOT = 3400000 + 10 * 2

--- Stairs are **not** seeded, deliberately.
---
--- The slots exist - the diagnostic reports `rail_building_size4=4`, one per
--- platform tile - but only one of the two sides is created per tile, depending
--- on which neighbouring cells are free (`modular_station.script.lua:833-851`),
--- and that is not predictable when seeding runs. Guessing `+1` produced a
--- module with no slot to live in, which the game reports as
--- "1 module will be removed".
---
--- They are freely placeable from the Buildings tab instead, which is all that
--- is needed to compare them against a station building.
---
--- Kept for reference: the slot ids are `stairsSlotId + 10 * coordJ` and `+ 1`,
--- with `stairsSlotId = 9400000` (`modular_station.script.lua:44`).
--- Stairs are worth placing by hand and comparing against a station building:
--- stock buildings have ground-level entrances and facade detail that read as
--- street level however they are supported, whereas stairs going **down** from a
--- platform edge are exactly what an elevated station should have, so that art
--- reads correctly unmodified. Stairs also carry catchment (radius 100 against
--- the building's 150), so they can stand in for a building entirely.


--- A platform tile is 40 m (`platformLength`), so four tiles is 160 m - the
--- stock station's own default length. Centred on the origin.
local PLATFORM_J_FROM = -1
local PLATFORM_J_TO = 2

--- Street station slot ids: `200000 * (coordJ + 100) + 100 * (coordI + 100) +
--- variant`, from `modular_terminal.script.lua`. Variant 0 is a passenger
--- terminal, 3 the entrance, and the entrance sits at the sentinel coordI 55.
local function streetMangle(coordI, coordJ, variant)
	return 200000 * (coordJ + 100) + 100 * (coordI + 100) + variant
end

local function eraFor(year)
	if year == nil or year == 0 then return "c" end
	if year < 1950 then return "a" end
	if year < 1990 then return "b" end
	return "c"
end

--- Seed both levels ourselves rather than delegating to the stock seeding
--- functions.
---
--- Delegating that was a mistake once already: `util.useFn` succeeds on some
--- engine threads and not others, so placements silently alternated between the
--- stock module set and a fallback and came out different sizes. Seeding here is
--- deterministic. Geometry is still delegated, where a failure is loud.
---
--- Track modules carry the `/trainstation___` prefix plus the track's street
--- template, which is how the stock seeding names them
--- (`modular_station.script.lua:155-160`).
local function seedBothLevels(year)
	local era = eraFor(year)
	local seeded = {}

	local platform =
		"::/stations/rail/modular_station/platform_passenger_era_" .. era .. ".module"
	local track =
		"::/trainstation___/infrastructure/track/standard/standard.street_template"
	local tiles = 0
	for j = PLATFORM_J_FROM, PLATFORM_J_TO do
		seeded[PASSENGER_PLATFORM_SLOT + 10 * j] = platform
		seeded[TRACK_SLOT + 1000 + 10 * j] = track
		tiles = tiles + 1
	end

	-- A station building, raised with the rest of the level.
	--
	-- Not decoration: on the rail side catchment and pool capacity come **only**
	-- from building modules (`main_building_*`, `side_building_*`, `stairs`),
	-- never from platforms, so a station without one attracts nobody. Stock
	-- stations behave the same way - none of them passes a `defaultCatchment`
	-- to `addCatchmentCircles`, so stripping the last building off a stock
	-- modular station leaves it running lines and collecting no passengers.
	seeded[MAIN_BUILDING_SLOT] =
		"::/stations/rail/modular_station/main_building_1_era_" .. era .. ".module"


	-- One bus platform plus the entrance, the same shape the stock street
	-- station seeds for a single platform (see pick-single-platform-side's
	-- notes for the slot layout).
	local busDir = "::/stations/street/modular_street_station/"
	seeded[streetMangle(0, 0, 0)] = busDir .. "passenger_platform.module"
	seeded[streetMangle(0, 1, 0)] = busDir .. "passenger_platform.module"
	seeded[streetMangle(55, 0, 3)] = busDir .. "entrance_exit.module"
	-- And a street building, for the same reason as the rail one: on this side
	-- `moreCapacity` - the station's pool capacity - comes only from
	-- `era_*_passenger_building_*`. Slot id from
	-- `MangleId({coordI, 0, moduleVariants.small_building})`
	-- (`modular_terminal.script.lua:2629`), with `small_building = 2`.
	seeded[streetMangle(0, 0, 2)] =
		busDir .. "era_" .. era .. "_passenger_building_10_10.module"

	log.message(LOG .. "seeded: rail " .. tostring(tiles) .. " tiles ("
		.. tostring(tiles * 40) .. " m, era " .. era .. ") + station building"
		.. " + 1 bus platform")
	return seeded
end

--- Which of the three parties owns a module: `"support"`, `"street"` or
--- `"rail"`.
---
--- Primary test is the **module name**, because the two families' slot id
--- spaces overlap in principle even though they do not in practice - street is
--- `200000 * (coordJ + 100) + 100 * (coordI + 100) + variant`
--- (`modular_terminal.script.lua:1164`), so a sufficiently negative coordJ
--- reaches down into rail's 3.4e6-11.2e6.
---
--- Our own slots are decided by **id**, not name, and that is deliberate: the
--- id is ours to hand out, whereas the name belongs to whoever authored the
--- module. A third-party support module - the point of publishing this - would
--- not have `ml_support` in its name, and under the old name test it fell
--- through to the rail bucket, where rail's `pairs(params.modules)` sweep would
--- count it and `GetCoord` would decode its id to nonsense.
---
--- Anything that matches nothing is reported and then placed by id band. The
--- bands are deliberately wider than the real ranges: the point is to classify
--- a stranger plausibly rather than to re-derive the mangling.
local RAIL_ID_MAX = 15000000
local STREET_ID_MAX = 500000000

local function familyOf(slotId, entry)
	if type(slotId) == "number" and slotId >= SUPPORT_SLOT_BASE then
		return "support"
	end

	local name = (type(entry) == "table" and entry.name) or entry
	if type(name) == "string" then
		if string.find(name, "/stations/street/", 1, true) then
			return "street"
		end
		if string.find(name, "/stations/rail/", 1, true)
			or string.find(name, "/trainstation_", 1, true) then
			return "rail"
		end
	end

	-- A module from neither family and not in one of our slots. Say so once per
	-- rebuild rather than guessing silently: "my module behaves oddly on the
	-- upper level" is otherwise unattributable from a log.
	local byBand = "rail"
	if type(slotId) == "number" and slotId > RAIL_ID_MAX and slotId <= STREET_ID_MAX then
		byBand = "street"
	end
	log.warning(LOG .. "module '" .. tostring(name) .. "' in slot "
		.. tostring(slotId) .. " belongs to neither stock family and is not in"
		.. " one of our slots - routing it to the " .. byBand .. " level by id."
		.. " If this is a mod-added module, give it slot type '" .. SUPPORT_TYPE
		.. "' or name it under /stations/rail/ or /stations/street/.")
	return byBand
end

--- Report a module edit: what the engine asked for, and what the map looks
--- like afterwards.
---
--- One line per actual edit, not per hover frame, so it is cheap - and it is
--- kept in for the beta deliberately. "Construction not possible" is reported
--- by the engine with **nothing whatsoever in the log**, so without this there
--- is no way to distinguish an edit the engine refused from one that never
--- reached `updateFn` in the first place. Pair it with the module counts on the
--- `built:` line: a delete that is being applied shows one fewer module there
--- on the next rebuild.
local function countModules(params)
	local n = 0
	for _k, _v in pairs(params.modules or {}) do n = n + 1 end
	return n
end

local function logChange(route, params, change, fam, before)
	local entry = change.module or (params.modules or {})[change.slotId]
	local name = (type(entry) == "table" and entry.name) or entry
	log.message(LOG .. "module " .. (change.added and "add" or "remove")
		.. " slot=" .. tostring(change.slotId)
		.. " family=" .. tostring(fam)
		.. " via=" .. route
		.. " modules=" .. tostring(before) .. "->"
		.. tostring(countModules(params))
		.. " name=" .. tostring(name))
end

--- Split a module map by which family owns each module.
---
--- Our own support modules are in neither bucket: the engine instantiates them
--- from the construction's own `params.modules`, and handing one to a stock
--- family would only have it iterate over something it cannot interpret.
local function splitModules(modules)
	local rail, street = {}, {}
	for slotId, entry in pairs(modules or {}) do
		local fam = familyOf(slotId, entry)
		if fam == "street" then
			street[slotId] = entry
		elseif fam == "rail" then
			rail[slotId] = entry
		end
	end
	return rail, street
end

--------------------------------------------------------------------------------
-- lifting a delegated family in z
--------------------------------------------------------------------------------

--- Column-major mat4 times a point, as the stock scripts do it.
local function applyMat(m, p)
	if m == nil then
		return { p[1], p[2], p[3] }
	end
	return {
		m[1] * p[1] + m[5] * p[2] + m[9]  * p[3] + m[13],
		m[2] * p[1] + m[6] * p[2] + m[10] * p[3] + m[14],
		m[3] * p[1] + m[7] * p[2] + m[11] * p[3] + m[15],
	}
end

--- Compose `xf` onto an existing transform.
---
--- Takes a matrix rather than a height, so the elevated level can be rotated as
--- well as raised in the same pass.
local function xfTransf(m, xf)
	return transf.mul(xf, m)
end

--- Into a **new** table: point tables inside the stock scripts' `generatedData`
--- are shared between every instance of a model, so editing one in place would
--- move geometry in unrelated constructions.
local function xfPos(p, xf)
	return applyMat(xf, p)
end

--- A **direction**, not a position: the linear part of the matrix only, with no
--- translation.
---
--- Edge and lane entries are `{ position, tangent }` pairs, and a tangent has to
--- be rotated with its position while ignoring any shift. Missing this is what
--- broke the quarter turn: the positions moved and the tangents did not, so the
--- engine saw track whose curve direction disagreed with its geometry and
--- refused it with "too much curvature". A pure translation hid the bug
--- completely, because translating a direction vector is a no-op - which is why
--- it only appeared once a rotation was added.
local function xfDir(d, xf)
	if xf == nil or d == nil then
		return d
	end
	return {
		xf[1] * d[1] + xf[5] * d[2] + xf[9]  * d[3],
		xf[2] * d[1] + xf[6] * d[2] + xf[10] * d[3],
		xf[3] * d[1] + xf[7] * d[2] + xf[11] * d[3],
	}
end

--- A single tiny `LESS` face at grade: "terrain no higher than this" over a
--- 20 cm square. As close to a no-op as the shape allows, but **not nothing** -
--- an empty list makes the engine fit terrain to the geometry. The stock script
--- substitutes exactly this when its own lists would be empty
--- (`modular_station.script.lua:1323-1335`).
local function gradeAnchor()
	return {
		type = "LESS",
		faces = { {
			{  0.1, -0.1, 0.0, 1.0 },
			{  0.1,  0.1, 0.0, 1.0 },
			{ -0.1,  0.1, 0.0, 1.0 },
			{ -0.1, -0.1, 0.0, 1.0 },
		} },
	}
end

--- A complete but empty result, for the case where a stock `updateFn` cannot be
--- resolved at all.
---
--- Returning a bare `{}` was the previous behaviour and it is not safe: every
--- stock construction hands the engine a full set of lists, and the engine
--- reads them without checking - `updateFn` returning `{}` leaves it to walk
--- fields that are not there. This returns the same shape with nothing in it,
--- so the failure is "an empty construction plus a warning in the log" instead
--- of an exception from inside the builder.
---
--- `terrainAlignmentLists` carries the grade anchor rather than being empty,
--- for the usual reason: an empty list means "fit the terrain to the geometry".
local function emptyResult()
	return {
		models = {}, colliders = {}, groundFaces = {}, laneLists = {},
		edgeLists = {}, slots = {}, slotConfig = {}, subconstructions = {},
		labelText = {}, dependentSlots = {},
		terrainAlignmentLists = { gradeAnchor() },
		cost = 0, maintenanceCost = 0,
	}
end

--- Entries already lifted in this pass. The stock hook copies `result.models`
--- into its subconstruction by reference, so without this a shared entry gets
--- lifted twice and ends up at +24.
local lifted = nil

local function liftModels(list, xf)
	for _i, m in ipairs(list or {}) do
		if m.transf and not lifted[m] then
			lifted[m] = true
			m.transf = xfTransf(m.transf, xf)
		end
		m.id = absoluteRes(m.id)
	end
end

local function liftColliders(list, xf)
	for _i, c in ipairs(list or {}) do
		if c.transf and not lifted[c] then
			lifted[c] = true
			c.transf = xfTransf(c.transf, xf)
		end
	end
end

--- A lane is positioned either by its own `transf` (what `addLaneLists` makes
--- from a model) or by absolute node positions (what `laneutil.createLane`
--- makes). Both occur in one station.
local function liftLanes(list, xf)
	for _i, lane in ipairs(list or {}) do
		if lifted[lane] then
			-- already handled through a list that shares this table
		elseif lane.transf then
			lifted[lane] = true
			lane.transf = xfTransf(lane.transf, xf)
		else
			lifted[lane] = true
			for j, node in ipairs(lane.nodes or {}) do
				lane.nodes[j] = { xfPos(node[1], xf), xfDir(node[2], xf), node[3] }
			end
		end
	end
end

local function liftStation(station, xf)
	if station == nil then return end
	for i, area in ipairs(station.catchmentAreas or {}) do
		station.catchmentAreas[i] = {
			position = xfPos(area.position, xf),
			radius = area.radius,
		}
	end
end

local function liftSubconstruction(sub, xf)
	liftModels(sub.models, xf)
	liftColliders(sub.colliders, xf)
	liftLanes(sub.laneLists, xf)
	liftStation(sub.station, xf)
	-- Off-grade: the terrain must not follow, and ground textures would be
	-- painted 12 m below. Anchored at grade rather than emptied.
	sub.terrainAlignmentLists = { gradeAnchor() }
	sub.groundFaces = {}
end

--- Lift only the rail family's share of the now-shared lists.
---
--- Since all three parties point at the same tables, "which half is the rail
--- level" has to be decided per entry:
---
---  * **subconstructions** come straight from `railResult`, because both hooks
---    reassign that field and so hand them back separated;
---  * **edge lists** by `type == "TRACK"`, street's being `"STREET"`, since
---    that one list really is shared;
---  * **slots** by identity, captured before the merge.
---
--- Model, collider and lane entries are not lifted at the construction level:
--- both families move theirs into subconstructions in their hooks, so anything
--- left at the top is a surprise and gets logged rather than silently moved.
local function liftRail(result, railResult, xf, railSlots)
	lifted = {}

	-- The hooks reassign `subconstructions`, so rail's are back in its own
	-- table by now and need no discriminator.
	for _i, sub in ipairs(railResult.subconstructions or {}) do
		liftSubconstruction(sub, xf)
	end

	for _i, el in ipairs(result.edgeLists or {}) do
		if el.params ~= nil then
			el.params.type = absoluteRes(el.params.type)
		end
		if el.type == "TRACK" and #(el.edges or {}) > 0 then
			for j, edge in ipairs(el.edges or {}) do
				el.edges[j] = { xfPos(edge[1], xf), xfDir(edge[2], xf) }
			end
			-- **No bridge.** `edgeType` is left at its default, `NORMAL`, so
			-- the elevated track carries no structure of its own.
			--
			-- It used to be `BRIDGE` on `stone.bridge`, which did render a
			-- viaduct - but a bridge type is a *generic* answer to "hold this
			-- up", and it has no idea there is a bus station underneath it, so
			-- its pillars and abutments pushed straight through the lower
			-- level. That is the same argument that already moved supports out
			-- of `updateFn` and into player-placed modules: nothing automatic
			-- can know what the player means to put under the deck.
			--
			-- So the deck is bare, and looking tidy is a job for modules with
			-- art made for it. `alignTerrain = false` stays - that is the
			-- explicit "do not deform the ground along this edge" control
			-- (`construction_util_serialized.d.tl:153`, the airfield
			-- precedent), and it is unrelated to the edge having a structure.
			el.alignTerrain = false

			-- `snapNodes` is deliberately left exactly as `trainstationutil`
			-- built it. See the note at the top of the file.
		end
	end

	for _i, slot in ipairs(result.slots or {}) do
		if railSlots[slot] and slot.transf then
			slot.transf = xfTransf(slot.transf, xf)
		end
	end

	-- Guard, not a diagnostic: a track run always has two ends, so a TRACK edge
	-- list that has edges but **no** snap nodes means something in this file
	-- stripped them. That exact state is what broke module editing once a track
	-- was connected, and it is invisible from the game - the engine refuses the
	-- rebuild with nothing in the log. Cheap to check, so check it rather than
	-- rely on the comment above surviving the next edit.
	for i, el in ipairs(result.edgeLists or {}) do
		if el.type == "TRACK" and #(el.edges or {}) > 0
			and #(el.snapNodes or {}) == 0 then
			log.warning(LOG .. "track edge list " .. tostring(i) .. " has "
				.. tostring(#el.edges) .. " edges and no snapNodes. Modules"
				.. " will not be deletable once a track is connected - see"
				.. " ../NOTES.md, \"A station's snapNodes are load-bearing\".")
		end
	end
end

--------------------------------------------------------------------------------
-- merging the two families
--------------------------------------------------------------------------------

--- Lists that both families write into and read back.
---
--- These cannot be withheld from the merged table and reconciled afterwards.
--- Modules mutate the result they are handed *during the module pass*, between
--- the two `updateFn`s and the two hooks - a track module calls
--- `findOrMakeNewEdgeListNum`, which does `pairs(result.edgeLists)` and died on
--- nil when they were held back. So all three parties - both families and the
--- merged table - have to point at **the same tables**.
--- Lists the merged result needs of its own, so that a module writing into one
--- does not hit nil - but which are **not** aliased back into either family.
---
--- Sharing these was the previous attempt and it failed twice over. Both hooks
--- *reassign* `result.subconstructions = {}` rather than appending
--- (`modular_station.script.lua:1338`), so a shared table is abandoned the
--- moment a hook runs - the symptom was `0 subconstructions, 0 stations`. And
--- rail's hook absorbs `result.models` wholesale into its own subconstruction,
--- so a shared models list would have it swallow street's geometry as well,
--- after street had already taken it.
--- Construction-level lists that must be **street's own tables**, because the
--- street hook wraps them into a subconstruction of its own and then builds
--- lanes from them (`modular_terminal.script.lua:3214-3226`):
---
---     table.insert(result.subconstructions, {
---         models = result.models, colliders = result.colliders,
---         laneLists = result.laneLists, ..., tag = 2 })
---     legacytransportnetworks.addLaneLists(result)
---
--- Its entrance module adds `entr_cross.mdl` through a two-argument `addModel`,
--- which lands at construction level. Give the merged result a private list and
--- that model goes somewhere street never looks: it wraps an empty
--- subconstruction, `addLaneLists` builds no lanes for the entrance crossing,
--- and a bus can enter the station but has no path out.
---
--- Rail is unaffected - its hook reads its own `railResult.models`. The residual
--- risk is a rail module writing construction-level, which would put its
--- geometry at grade; that is logged rather than hidden.
--- `poolConfig` is in here for the same reason as `models`, and it is the field
--- that kept passenger traffic at exactly zero. `modulesutil.addPoolEdges`
--- writes `result.poolConfig` from inside a module - so, the merged table - and
--- the street hook reads it back with
--- `modulesutil.getStationPoolEdges(result)` from its own. Read nil, and
--- `station.pool.edges` comes out empty: the station has no waiting area, so
--- nobody can queue and nobody ever boards. No warning, no error.
---
--- Derived by listing every `result.<field>` the street modules write and every
--- one its hook reads, instead of finding them one failure at a time.
local STREET_LEVEL_LISTS = {
	"models", "colliders", "laneLists", "terrainAlignmentLists", "groundFaces",
	"labelText", "poolConfig",
}
--- `subconstructions` is deliberately not in that list: **both** hooks reassign
--- it, so any sharing is abandoned the moment one runs.
local SHARED_SET = {
	edgeLists = true, slots = true, slotConfig = true, subconstructions = true,
}
for _i, k in ipairs(STREET_LEVEL_LISTS) do SHARED_SET[k] = true end

--- Point both families and the merged result at one set of shared lists.
---
--- `edgeLists` keeps **rail's own table**, not a fresh one, because rail indexes
--- it positionally: `edgeListHasCatenary` is `{false, true, false, true}` for
--- its four track lists (`modular_station.script.lua:476`, read back at `:995`).
--- Putting anything in front of those would silently mis-key the catenary
--- lookup. Street's list is empty at this point - its modules have not run yet -
--- so nothing is lost by adopting rail's, and street's entries land after
--- rail's four.
local function shareLists(streetResult, railResult)
	local result = {}

	-- Private fields: street wins a collision, being the level at grade that
	-- needs no transformation; rail's own names fill in the rest.
	for k, v in pairs(streetResult) do
		if not SHARED_SET[k] then result[k] = v end
	end
	for k, v in pairs(railResult) do
		if result[k] == nil and not SHARED_SET[k] then result[k] = v end
	end

	railResult.edgeLists = railResult.edgeLists or {}
	for _i, el in ipairs(streetResult.edgeLists or {}) do
		railResult.edgeLists[#railResult.edgeLists + 1] = el
	end
	streetResult.edgeLists = railResult.edgeLists
	result.edgeLists = railResult.edgeLists

	-- Slots and slotConfig: the union, on the merged result only. The engine
	-- reads these for the module pass. Each family keeps its own copy, which is
	-- what its hook iterates.
	result.slots = {}
	for _i, src in ipairs({ railResult, streetResult }) do
		for _j, s in ipairs(src.slots or {}) do
			result.slots[#result.slots + 1] = s
		end
	end

	result.slotConfig = {}
	for _i, src in ipairs({ streetResult, railResult }) do
		for k, v in pairs(src.slotConfig or {}) do
			if result.slotConfig[k] == nil then result.slotConfig[k] = v end
		end
	end

	-- Every slot type gets `skipCollisionCheck`.
	--
	-- Two levels stacked 12 m apart overlap in plan by design, so a collision
	-- check against the rest of the construction rejects placements that are
	-- perfectly fine. The street station already sets this on all five of its
	-- own slot types (`modular_terminal.script.lua:1301-1325`); the rail station
	-- sets `slotConfig = {}` and so has none, which made every attempt to add a
	-- station building fail with "construction not possible" and highlight the
	-- bus station below as the obstruction - including attempts nowhere near it.
	for _i, slot in ipairs(result.slots or {}) do
		local cfg = result.slotConfig[slot.type]
		if cfg == nil then
			result.slotConfig[slot.type] = { skipCollisionCheck = true }
		else
			cfg.skipCollisionCheck = true
		end
	end

	-- Point the construction level at street's own tables, so its hook finds
	-- whatever the modules put there.
	for _i, k in ipairs(STREET_LEVEL_LISTS) do
		streetResult[k] = streetResult[k] or {}
		result[k] = streetResult[k]
	end
	result.subconstructions = {}

	return result
end

--- Make every resource name in a subconstruction absolute.
---
--- This has to run over **both** families, not just the one being lifted. It
--- originally lived inside the lift, so only the rail level got it, and the
--- street level came out with its platform models missing and a fallback sand
--- texture on the ground - both stock scripts name their models and ground
--- textures base-game-relative (`/stations/street/.../entr_cross.mdl`,
--- `/stations/shared/industry_floor_high_priority.gtex`), and neither errors
--- when unresolvable. A model silently becomes a placeholder; a ground texture
--- silently becomes sand.
--- `baseDir` is the family's own resource directory, for the bare-relative ids
--- only street uses. Passing it per family is why this is called from the
--- per-family loop in `finish` rather than over the merged list.
local function absolutiseSub(sub, baseDir)
	for _i, m in ipairs(sub.models or {}) do
		m.id = absoluteRes(m.id, baseDir)
	end
	for _i, face in ipairs(sub.groundFaces or {}) do
		for _j, mode in ipairs(face.modes or {}) do
			mode.key = absoluteRes(mode.key, baseDir)
		end
	end
end

--------------------------------------------------------------------------------
-- holding the elevated level up: a player-placed support layer
--------------------------------------------------------------------------------

--- A brick course from the stone bridge's abutment: 4.4 x 4 x 2 m
--- (`stone.bridge.lua:24-27`), built to be tiled and to carry a deck. Six
--- courses make the 12 m pitch.
---
--- Borrowed art, and it shows - it is an abutment with one finished face, so a
--- four-sided cell presents its unfinished side on two of them. It was also
--- chosen partly to match the stone viaduct that used to carry the track, and
--- that viaduct is gone, so the one argument for *stone* specifically has gone
--- with it. This is placeholder art pending models made for the job.
local SUPPORT_BRICK = "::/infrastructure/bridge/stone/stone_abut_rep_rep.mdl"
local SUPPORT_BRICK_D = 4.0
local SUPPORT_BRICK_H = 2.0

--- Supports are **placed by the player**, on their own slot layer at grade
--- aligned to the grid of the level above.
---
--- The previous attempt put stone pillars under every occupied tile
--- automatically. It looked bad and it fouled the bus station, and it could not
--- have known better: automatic placement has no idea what the player intends
--- to put underneath. The engine's own pillar-dodging
--- (`Proposal.Context.extendProposalRedoPillars`) is unavailable to us, since it
--- only applies to bridges the engine generates from edges.
---
--- So the supports become modules. The slots sit under the elevated platforms,
--- subdivided along each 40 m tile so a player can wall off the spans they want
--- and leave the rest open for roads.
--- `SUPPORT_TYPE` and `SUPPORT_SLOT_BASE` are declared at the top of the file,
--- because the module classifier needs them.
local SUPPORT_CELL_D = 8.0

--- Real footprints of the things that sit on the elevated level, by slot type.
---
--- `spacing` is the wrong source for these. It is the **slot reservation**, not
--- the thing in it: all three station buildings reserve the same `{10, 5}` in x,
--- 15 m, while the buildings themselves are 18.5, 20 and 40 m wide. Sizing
--- supports off spacing therefore fitted the middle one and missed the other two
--- in both directions.
---
--- Measured from the model bounding boxes, **including the connector pieces the
--- module places either side of the main model** - `station_1_main` alone is
--- 18.5 m but its `_con_1_lft`/`_rgt` reach +-10.03, so the built width is 20.1.
--- `cy` matters as much as the size: a building's footprint sits **behind** its
--- slot origin in y, not centred on it.
local FOOTPRINTS = {
	rail_building_size1 = { w = 20.1, d = 11.0, cy = -5.5 },
	rail_building_size2 = { w = 20.0, d = 20.0, cy = -10.0 },
	rail_building_size3 = { w = 40.0, d = 37.0, cy = -17.5 },
}

--- One support slot per cell, under **everything** on the elevated level.
---
--- Driven by each slot's own `spacing`, which is `{left, right, back, front}` as
--- half-extents from the slot centre, so the footprint of anything up there is
--- readable without special-casing its type. Platform tiles come out 5 x 39 m;
--- station buildings are 15 m wide and 10, 20 or 40 m deep and offset in x
--- (`mainBuildingSlotSpacing1-3`, `modular_station.script.lua:634-636`). The
--- first version only handled platforms, which left the station buildings with
--- no support slots underneath them at all.
---
--- Track tiles **are** included, as of 2026-10-09. They used to be skipped
--- because the `BRIDGE` edge type put a viaduct under them; with the bridge
--- gone (see `liftRail`) they would otherwise be the one part of the deck with
--- no way to support it at all. Their `spacing` is the same 5 x 39 m as a
--- platform tile, so they need no special case.
---
--- Called from `updateFn`, not the hook: the engine reads `slots` for the module
--- pass before any hook runs, so they must exist by then. Both the rail slots
--- and the level transform are known at that point.
local function addSupportSlots(result, railResult, xf, modules, allModules)
	local added = 0
	local sized = {}
	for _i, slot in ipairs(railResult.slots or {}) do
		local sp = slot.spacing
		if sp ~= nil and modules[slot.id] ~= nil then
			-- A measured footprint where we have one, falling back to the slot
			-- reservation otherwise - which is right for platform tiles, whose
			-- spacing does describe the tile.
			local fp = FOOTPRINTS[slot.type]
			local width = fp and fp.w or (sp[1] + sp[2])
			local depth = fp and fp.d or (sp[3] + sp[4])
			local offX = fp and 0.0 or (sp[2] - sp[1]) * 0.5
			local offY = fp and fp.cy or (sp[4] - sp[3]) * 0.5

			-- Some slots reserve nothing at all - the stairs slots are
			-- `{0, 0, 0, 0}` - and a support for a zero footprint is a pile of
			-- bricks at a point. Stairs reach the ground by themselves anyway.
			if width < 1.0 or depth < 1.0 then
				width, depth = 0.0, 0.0
			end

			-- At most 9 cells, because the slot id packs the cell index into one
			-- decimal digit.
			local cells = 0
			if width > 0.0 and depth > 0.0 then
				cells = math.max(1, math.min(9,
					math.floor(depth / SUPPORT_CELL_D + 0.5)))
			end
			local cellD = depth / cells

			if cells > 0 then
				sized[slot.type] = { width, cellD, cells }
			end

			local m = transf.mul(xf, slot.transf)
			for k = 1, cells do
				local ly = offY - depth * 0.5 + cellD * (k - 0.5)
				local world = applyMat(m, { offX, ly, 0.0 })

				-- Keep the level's rotation, drop to the ground.
				local base = {}
				for n = 1, 16 do base[n] = m[n] end
				base[13], base[14], base[15] = world[1], world[2], 0.0

				result.slots[#result.slots + 1] = {
					id = SUPPORT_SLOT_BASE + slot.id * 10 + k,
					transf = base,
					-- Symmetric, because the offset is already baked into the
					-- transform above. The module reads this to size itself.
					spacing = { width * 0.5, width * 0.5, cellD * 0.5, cellD * 0.5 },
					type = SUPPORT_TYPE,
					replaceable = true,
				}
				added = added + 1
			end
		end
	end

	result.slotConfig = result.slotConfig or {}
	result.slotConfig[SUPPORT_TYPE] = { skipCollisionCheck = true }

	-- Support modules whose slot no longer exists.
	--
	-- A support slot is only created where the rail level has a module above it
	-- (`modules[slot.id] ~= nil` in the loop above), so **removing a platform
	-- orphans the supports under it**. The engine's answer to a module with no
	-- slot is to drop it - "N modules will be removed" - which is survivable,
	-- but it is also the first thing to suspect when a module edit is refused
	-- outright, and it is invisible otherwise.
	local have = {}
	for _i, slot in ipairs(result.slots or {}) do
		have[slot.id] = true
	end
	local orphans = 0
	for slotId, _entry in pairs(allModules or {}) do
		if type(slotId) == "number" and slotId >= SUPPORT_SLOT_BASE
			and not have[slotId] then
			orphans = orphans + 1
		end
	end
	if orphans > 0 then
		log.warning(LOG .. tostring(orphans) .. " support module(s) have no slot"
			.. " any more - the level above them was removed. The engine will"
			.. " drop them.")
	end

	-- What footprint each kind of thing got, and what slot types exist at all.
	-- The second half is how to tell whether a stairs slot
	-- (`rail_building_size4`) was created: the rail station only makes one where
	-- a platform occupies the outermost column *and* the neighbouring cells are
	-- free (`modular_station.script.lua:833-851`), so it may simply not be
	-- there - which is indistinguishable, from the outside, from a wrong seed id.
	local kinds = {}
	for _i, slot in ipairs(railResult.slots or {}) do
		kinds[slot.type] = (kinds[slot.type] or 0) + 1
	end
	local parts = {}
	for t, n in pairs(kinds) do
		parts[#parts + 1] = t .. "=" .. tostring(n)
	end
	log.message(LOG .. "rail slot types: " .. table.concat(parts, " "))

	local fparts = {}
	for t, fp in pairs(sized) do
		fparts[#fparts + 1] = t .. " " .. string.format("%.1fx%.1f", fp[1], fp[2])
			.. " x" .. tostring(fp[3])
	end
	log.message(LOG .. "support footprints: " .. table.concat(fparts, ", ")
		.. " (" .. tostring(added) .. " slots)")

	return added
end

--- The models a support module draws: a brick box filling its cell, from the
--- ground to the underside of the level above.
---
--- Sized from the slot it was placed in rather than fixed, so one module serves
--- a 5 m platform span and a 15 m building footprint alike. `spacing` on a
--- support slot is symmetric by construction, so the cell is
--- `[-w/2, w/2] x [-d/2, d/2]`.
---
--- Tiled from one abutment course so the brickwork lines up between adjacent
--- modules: the course is 4.4 wide x 4 deep x 2 tall, and it anchors at its own
--- back edge in y.
local function supportModels(width, depth)
	local models = {}
	local courses = math.max(1, math.floor(PITCH / SUPPORT_BRICK_H + 0.5))
	local cols = math.max(1, math.ceil(width / 4.4))
	local rows = math.max(1, math.ceil(depth / SUPPORT_BRICK_D))

	local colStep = width / cols
	for i = 0, cols - 1 do
		local x = -width * 0.5 + colStep * (i + 0.5)
		for r = 0, rows - 1 do
			-- A **facade**, not a solid block: only the outer ring of the cell
			-- gets brickwork. Filling the footprint read as a lump of masonry
			-- rather than a support, and it is also a lot of models for geometry
			-- nobody can see. Walls still line up between adjacent cells, so a
			-- run of supports reads as a continuous arcade.
			local onEdge = (i == 0) or (i == cols - 1)
				or (r == 0) or (r == rows - 1)
			if onEdge then
				local y = -depth * 0.5 + r * SUPPORT_BRICK_D
				for c = 0, courses - 1 do
					models[#models + 1] = {
						id = SUPPORT_BRICK,
						transf = transf.transl(vec3.new(x, y, c * SUPPORT_BRICK_H)),
					}
				end
			end
		end
	end
	return models
end

--- The cell a support module sits in, read back off its slot. Falls back to one
--- platform-sized span if the slot cannot be found, so a stale module from an
--- older savegame still draws something rather than nothing.
local function supportCell(result, slotId)
	for _i, slot in ipairs(result.slots or {}) do
		if slot.id == slotId and slot.spacing ~= nil then
			return slot.spacing[1] + slot.spacing[2], slot.spacing[3] + slot.spacing[4]
		end
	end
	return 5.0, SUPPORT_CELL_D
end

--------------------------------------------------------------------------------
-- vertical circulation between the levels
--------------------------------------------------------------------------------

local function isPersonLane(lane)
	for _i, mode in ipairs(lane.transportModes or {}) do
		if mode == "PERSON" then return true end
	end
	return false
end

--- A position key for "is this the same node as that one", to 1 cm.
---
--- Lanes join where their nodes **coincide**, and the engine's own test is
--- exact, so this is only used the conservative way round: a near-match counts
--- as a match and the candidate is rejected. Over-rejecting costs a warning;
--- under-rejecting costs an assertion failure on the simulation thread.
local function nodeKey(p)
	return string.format("%.2f,%.2f,%.2f", p[1], p[2], p[3])
end

--- Every node belonging to a lane that is **not** a person lane.
---
--- This is the one hard safety rule in the whole file. A PERSON lane that
--- shares a node with a vehicle lane kills the game outright:
---
---     Assertion `person0 == person1' failed.
---     TransportNetworkSystem.cpp:116, IsValidTransition
---
--- (root NOTES.md, "A PERSON lane must never share a node with a vehicle
--- lane"). The link below attaches to an existing person node, which is the
--- correct way to join two person lanes - but if a stock family ever puts a
--- person node and a bus node at the same position, attaching there turns a
--- latent coincidence into a fatal one. So those positions are excluded as
--- link endpoints, and a station with no safe endpoint gets a warning and no
--- link rather than a crash.
local function vehicleNodeKeys(result)
	local keys = {}
	for _i, sub in ipairs(result.subconstructions or {}) do
		for _j, lane in ipairs(sub.laneLists or {}) do
			if not isPersonLane(lane) then
				for _k, node in ipairs(lane.nodes or {}) do
					keys[nodeKey(applyMat(lane.transf, node[1]))] = true
				end
			end
		end
	end
	return keys
end

--- Pick one pedestrian node at grade and one on the elevated platform.
---
--- Derived from the assembled lane lists rather than from guessed coordinates:
--- both families' person lanes come from their **models** via `addLaneLists`,
--- which positions them with `lane.transf` and keeps the nodes model-local, so
--- the real world positions are only knowable after the hooks have run.
---
--- Of the candidates at each level, take the pair that is closest together in
--- plan, so the stairs are as short and as central as possible.
local function findLevelNodes(result, dz)
	local lowNodes, highNodes = {}, {}
	local avoid = vehicleNodeKeys(result)
	local rejected = 0

	for _i, sub in ipairs(result.subconstructions or {}) do
		for _j, lane in ipairs(sub.laneLists or {}) do
			if isPersonLane(lane) then
				for _k, node in ipairs(lane.nodes or {}) do
					local p = applyMat(lane.transf, node[1])
					if avoid[nodeKey(p)] then
						rejected = rejected + 1
					elseif p[3] > dz * 0.5 then
						highNodes[#highNodes + 1] = p
					else
						lowNodes[#lowNodes + 1] = p
					end
				end
			end
		end
	end

	if rejected > 0 then
		log.message(LOG .. "skipped " .. tostring(rejected) .. " person node(s)"
			.. " that coincide with a vehicle lane node")
	end

	local best, bestLow, bestHigh = nil, nil, nil
	for _i, lo in ipairs(lowNodes) do
		for _j, hi in ipairs(highNodes) do
			local dx, dy = hi[1] - lo[1], hi[2] - lo[2]
			local d = dx * dx + dy * dy
			if best == nil or d < best then
				best, bestLow, bestHigh = d, lo, hi
			end
		end
	end

	return bestLow, bestHigh, #lowNodes, #highNodes
end

--- Join the two levels' pedestrian networks with one lane.
---
--- Without this there is **no path between the levels at all**: the street
--- station's person lanes are at grade, the rail station's at +12, and nothing
--- spans the gap. Passengers then never board the feeder bus either, because a
--- journey is only taken when the whole route exists - which reads as the
--- station being ignored rather than broken.
---
--- Deliberately a single two-point curve. Lanes join where their nodes
--- **coincide**, so the two ends are placed exactly on existing person nodes and
--- there are no intermediate nodes - an intermediate node is what would risk
--- landing on a vehicle lane, and a PERSON-to-BUS junction crashes the game
--- (root NOTES.md). It is a bare diagonal for now; a stairs model can be hung
--- on it once the routing is confirmed.
local function linkLevels(result, dz)
	local lo, hi, nLow, nHigh = findLevelNodes(result, dz)
	if lo == nil or hi == nil then
		log.warning(LOG .. "no pedestrian link possible: " .. tostring(nLow)
			.. " person nodes at grade, " .. tostring(nHigh) .. " above")
		return
	end

	local sub = result.subconstructions[1]
	if sub == nil then return end
	sub.laneLists = sub.laneLists or {}
	sub.laneLists[#sub.laneLists + 1] = laneutil.createLane(
		{ { { lo[1], lo[2], lo[3] }, { hi[1], hi[2], hi[3] } } },
		{ "PERSON" }, 2, 2, false)

	log.message(LOG .. "linked levels: (" .. string.format("%.1f,%.1f,%.1f", lo[1], lo[2], lo[3])
		.. ") -> (" .. string.format("%.1f,%.1f,%.1f", hi[1], hi[2], hi[3])
		.. "), from " .. tostring(nLow) .. " grade and " .. tostring(nHigh)
		.. " elevated person nodes")
end

--- Final tidy-up after both hooks. The lists are already shared, so there is
--- nothing to collect - only to reconcile.
local function finish(result, streetResult, railResult)
	-- Re-read each family's own fields: both hooks **reassign**
	-- `result.subconstructions`, so whatever the merged table held before is
	-- stale. Grade level first, so its subconstruction is index 1.
	--
	-- Tags are assigned from a **per-family base**, not from the position in
	-- the combined list. Two reasons:
	--
	--  * they have to be unique, because a duplicate crashes the game outright
	--    (root NOTES.md, "Two subconstructions must not share a tag") - and
	--    each family invents low numbers of its own, so the raw tags collide;
	--  * `PopulateOld2NewSubconstructions` matches a rebuild's subconstructions
	--    to the previous ones **by tag**. Numbering 1..n over the concatenation
	--    makes the rail level's tag depend on how many subconstructions the
	--    street level happened to produce, so deleting the last street module
	--    would silently renumber the rail station from 2 to 1 and break that
	--    match on the very next rebuild.
	--
	-- Bases are 100 apart, which is far more headroom than either family uses.
	-- **Frozen at the first public release**: a tag is how a savegame's
	-- subconstruction is recognised after a rebuild.
	result.subconstructions = {}
	for _i, src in ipairs({ { streetResult, 1, STREET_DIR }, { railResult, 101, nil } }) do
		local base = src[2]
		for j, sub in ipairs(src[1].subconstructions or {}) do
			sub.tag = base + j - 1
			absolutiseSub(sub, src[3])
			result.subconstructions[#result.subconstructions + 1] = sub
		end
	end

	-- Guarantee every station has a catchment area.
	--
	-- Without one a station **cannot collect or discharge a single passenger**,
	-- which looks like the station being ignored rather than broken: lines
	-- route, vehicles run, nothing boards. The log says so plainly -
	-- `no catchment areas generated for station` from
	-- `constructionutil.addCatchmentCircles` - and that warning sat in the log
	-- unexplained for several rounds.
	--
	-- The cause is that catchment is attached to **particular modules**, not to
	-- platforms: on the rail side only `main_building_*`, `side_building_*` and
	-- `stairs` declare `catchmentPassenger`, and our seeding places a platform
	-- and a track and nothing else. Seeding a station building would also fix
	-- it, but a station's ability to carry passengers should not depend on a
	-- cosmetic choice, and for a two-level station we want to decide this
	-- ourselves anyway. Radii match the stock modules: 150 m for a rail station
	-- building, 175 m for a street entrance.
	--- Pool capacity has the same shape of problem. It is summed from
	--- `metadata.moreCapacity` over the placed modules
	--- (`modulesutil.getStationPoolCapacities`), and **only building modules
	--- declare it** - the platforms carry `capacityPassenger` in their
	--- description attributes, which is display text, not capacity. So our
	--- seeding yields `pool.capacity = 0`, and a station with no capacity holds
	--- no waiting passengers. Two independent reasons for the same symptom.
	for _i, sub in ipairs(result.subconstructions or {}) do
		local station = sub.station
		if station ~= nil then
			station.catchmentAreas = station.catchmentAreas or {}
			if #station.catchmentAreas == 0 then
				station.catchmentAreas[1] = {
					position = { 0.0, 0.0, 0.0 },
					radius = 175,
				}
				log.warning(LOG .. "a station had no catchment of its own -"
					.. " falling back to a default. For the rail level that"
					.. " means MAIN_BUILDING_SLOT is not landing in a real slot.")
			end

			station.pool = station.pool or { edges = {} }
			if (station.pool.capacity or 0) == 0 then
				station.pool.capacity = 200
				log.message(LOG .. "gave a station a default pool capacity")
			end
		end
	end

	-- Anchored at grade, not emptied: an empty list makes the engine fit the
	-- terrain to the geometry.
	result.terrainAlignmentLists = { gradeAnchor() }

	result.cost = (streetResult.cost or 0) + (railResult.cost or 0)
	result.maintenanceCost =
		(streetResult.maintenanceCost or 0) + (railResult.maintenanceCost or 0)

	-- Report the snap point, because "the exit road snaps but the station does
	-- not rotate" has two quite different explanations and they need separating.
	--
	-- The street station's entrance module sets `result.snapPoint` with a
	-- `transf` built from its own slot transform
	-- (`modules.script.lua:120-123`), so the frame carries an orientation and
	-- the engine should align the construction to the edge it snaps to. If that
	-- is arriving intact, the rotation is the engine's business and something
	-- else is wrong. If it is missing, what is being seen is only the entrance
	-- *edge* snapping through its `snapNodes = { 1 }`, which is edge-level and
	-- says nothing about the construction's orientation.
	-- Report the one that will actually be **used**, which is the module's.
	-- This read used to be `streetResult.snapPoint or result.snapPoint` - the
	-- other way round from the line below that picks the winner - so it
	-- faithfully printed the hook's origin default on every rebuild and
	-- reported `fromStreetResult=true` while the good one was in use. A
	-- diagnostic that contradicts the code is worse than none.
	local sp = result.snapPoint or streetResult.snapPoint
	if sp == nil then
		log.warning(LOG .. "no snapPoint on the result - the station cannot"
			.. " orient itself to a road")
	else
		local t = sp.transf
		log.message(LOG .. "snapPoint: transl=("
			.. string.format("%.1f,%.1f,%.1f", t and t[13] or 0, t and t[14] or 0, t and t[15] or 0)
			.. ") xAxis=("
			.. string.format("%.2f,%.2f", t and t[1] or 0, t and t[2] or 0)
			.. ") edgeTypes=" .. tostring(sp.snapToBaseEdgeTypes
				and #sp.snapToBaseEdgeTypes or 0)
			.. " source=" .. (result.snapPoint ~= nil and "module" or "streetHook"))
	end

	-- The level at grade decides what the construction snaps to, and the one to
	-- keep is the **module's**, not the family's.
	--
	-- Two snap points are written, to different tables:
	--
	--  * the entrance module writes a good one, offset ~10 m out along the
	--    entrance road, to the result *it* was handed - the merged table
	--    (`modules.script.lua:120-123`);
	--  * the street hook then writes its own default, with **no `transf` at
	--    all**, to its own table (`modular_terminal.script.lua:3295`) - so that
	--    one sits at the construction origin.
	--
	-- Preferring `streetResult`'s took the origin default, which is why the
	-- station snapped by its centre instead of by the end of the bus entrance.
	-- The stock station does not have this problem because both writes land in
	-- one table, the hook's wins, and its origin *is* its entrance - whereas
	-- ours is the shared centre of a two-level structure.
	result.snapPoint = result.snapPoint or streetResult.snapPoint
end

--------------------------------------------------------------------------------

function data()
return {
	createTemplateFn = function(captureParams, params)
		return seedBothLevels(params.year)
	end,

	--- The support module's geometry. Drawn into the construction level, which
	--- is street's own table and therefore stays at grade - these must not be
	--- lifted with the level they hold up.
	supportUpdateFn = function(captureParams, result, transform, tag, slotId, addModel, constrParams)
		local w, d = supportCell(result, slotId)
		for _i, m in ipairs(supportModels(w, d)) do
			addModel(m.id, m.transf, tag, result.models)
		end
	end,

	--- The placement preview.
	supportGetModelsFn = function(captureParams, params)
		-- No slot context during the preview, so show a platform-sized span.
		return supportModels(5.0, SUPPORT_CELL_D)
	end,

	--- What happens to `params.modules` when the player adds or removes one
	--- module.
	---
	--- Delegating this was missing, and the symptom is subtle enough to be
	--- worth spelling out. **A street passenger platform is two slots, not
	--- one.** `preProcessFn` (`modular_terminal.script.lua:1219-1269`) is what
	--- knows that: adding one at `coordJ = 0` also writes `coordJ = 1`, and
	--- removing either one removes both. Without it the engine does the plain
	--- thing - set or clear the one slot the player clicked - and the lower
	--- level builds half platforms that the player cannot clear properly. Our
	--- own seeding already wrote both halves, so placement looked right and
	--- only *editing* was wrong, which is why it was easy to miss.
	---
	--- Rail declares no `preProcessFn` at all, so for rail slots - and for our
	--- supports - the plain assignment below *is* the stock behaviour. Rail's
	--- paired slots are handled by the engine through `result.dependentSlots`
	--- instead, which the merge already carries through.
	---
	--- The change has to be routed, not just forwarded: street's version calls
	--- its own `DemangleId` on `change.slotId`, so handing it a rail slot id
	--- would decode to an arbitrary `(coordI, coordJ)` and could write a rail
	--- module into a street slot.
	preProcessFn = function(captureParams, params, change)
		params = params or {}
		params.modules = params.modules or {}

		local before = countModules(params)

		local entry = change.module
		if not change.added then
			entry = params.modules[change.slotId]
		end

		-- Clearing a slot that is already empty: nothing to route and nothing
		-- to classify, so do not make `familyOf` guess at a nil.
		if entry == nil then
			params.modules[change.slotId] = nil
			logChange("plain", params, change, "empty-slot", before)
			return params
		end

		local fam = familyOf(change.slotId, entry)

		if fam == "street" then
			local fn = resolveFn(STREET_SCRIPT .. "@preProcessFn",
				STREET_SCRIPT .. "@updateFn")
			if fn ~= nil then
				-- The whole param table, not just the street share: street's
				-- version only ever touches ids it mangles itself, and it has
				-- to write the paired half into the map we hand back.
				local ok, out = pcall(fn, {}, params, change)
				if ok and out ~= nil then
					logChange("street", out, change, fam, before)
					return out
				end
				log.warning(LOG .. "the street preProcessFn failed ("
					.. tostring(out) .. ") - falling back to a plain"
					.. " single-slot edit, which will leave half platforms")
			end
		end

		if change.added then
			params.modules[change.slotId] = change.module
		else
			params.modules[change.slotId] = nil
		end
		logChange("plain", params, change, fam, before)
		return params
	end,


	--- Does one of the build tools act on this construction?
	---
	--- Rail's answer (`modular_station.script.lua:343-349`) is the one we want:
	--- yes for a track street template, yes for the catenary tool, no for a
	--- road one. The street family's answer is only about tram track, which
	--- this construction does not offer (`tramTrack` is pinned to 1), so there
	--- is nothing to combine.
	isAffectedByToolFn = function(captureParams, params, conConfigAdd, conConfigRemove)
		local fn = resolveFn(RAIL_SCRIPT .. "@isAffectedByToolFn",
			RAIL_SCRIPT .. "@updateFn")
		if fn == nil then
			return false
		end
		local ok, out = pcall(fn, {}, params, conConfigAdd, conConfigRemove)
		if ok then
			return out
		end
		log.warning(LOG .. "the rail isAffectedByToolFn failed: " .. tostring(out))
		return false
	end,

	--- The track-upgrade and catenary tools, on the elevated level.
	---
	--- Without this the elevated track is whatever the seeding chose and stays
	--- that way forever: there is no construction param for track type, and the
	--- track-type and catenary choices on a stock modular station are made
	--- *after* placement, by dragging the upgrade tool over it. So a
	--- multi-layer station could never be electrified, which quietly rules out
	--- every electric locomotive.
	---
	--- Rail's `upgradeFn` does the real work - it rewrites the module names
	--- along the track row, following `metadata.catenaryAdd` /
	--- `catenaryRemove` for the catenary tool and
	--- `"::/trainstation_" .. resName:gsub("::", "__")` for a track type. That
	--- second form is exactly the `::/trainstation___/...` name our seeding
	--- uses, so the two agree.
	---
	--- Gated on the slot being rail's. `SwapModule` sets `.name` on whatever it
	--- finds at the id it is given without checking what it is, so letting a
	--- street slot through would turn a bus platform into a track module.
	upgradeFn = function(captureParams, params, slotId, constructionConfig)
		params = params or {}
		local entry = (params.modules or {})[slotId]
		-- An empty slot, which the tool may well drag across. Rail's own
		-- version returns early on this too; the point of checking here is to
		-- keep `familyOf` from reporting an unclassifiable nil.
		if entry == nil then
			return params
		end
		if familyOf(slotId, entry) ~= "rail" then
			return params
		end
		local fn = resolveFn(RAIL_SCRIPT .. "@upgradeFn",
			RAIL_SCRIPT .. "@updateFn")
		if fn == nil then
			return params
		end
		local ok, out = pcall(fn, {}, params, slotId, constructionConfig)
		if ok and out ~= nil then
			return out
		end
		log.warning(LOG .. "the rail upgradeFn failed: " .. tostring(out))
		return params
	end,

	updateFn = function(captureParams, params)
		params = params or {}
		local year = params.year or FALLBACK_YEAR

		local streetFn = resolveFn(STREET_SCRIPT .. "@updateFn",
			STREET_SCRIPT .. "@createTemplateFn")
		local railFn = resolveFn(RAIL_SCRIPT .. "@updateFn",
			RAIL_SCRIPT .. "@createTemplateFn")
		if streetFn == nil or railFn == nil then
			log.warning(LOG .. "a stock updateFn is unavailable - nothing to build")
			return emptyResult()
		end

		local railModules, streetModules = splitModules(params.modules)

		-- Module accounting, per family, on every rebuild.
		--
		-- This is here because "construction not possible" is reported by the
		-- engine with nothing in the log, so the only way to tell a rejected
		-- *proposal* from a module map that never changed is to watch the
		-- counts across hovers. A delete preview must show one fewer than the
		-- rebuild before it; if it does not, the edit is not reaching
		-- `updateFn` and the fault is in `preProcessFn`, not in the geometry.
		local nRail, nStreet, nSupport = 0, 0, 0
		for _k, _v in pairs(railModules) do nRail = nRail + 1 end
		for _k, _v in pairs(streetModules) do nStreet = nStreet + 1 end
		for slotId, _v in pairs(params.modules or {}) do
			if type(slotId) == "number" and slotId >= SUPPORT_SLOT_BASE then
				nSupport = nSupport + 1
			end
		end

		-- Each family sees only its own modules. Both read very little:
		-- street wants modules/tramTrack/year, rail wants modules/year.
		local streetResult = streetFn({}, {
			modules = streetModules,
			tramTrack = 1,
			year = year,
		})
		local railResult = railFn({}, {
			modules = railModules,
			year = year,
		})

		local streetHook = streetResult.terminateConstructionHook
		local railHook = railResult.terminateConstructionHook

		-- Captured before the merge, while the two families' slots are still
		-- separable.
		local railSlots = {}
		for _i, s in ipairs(railResult.slots or {}) do
			railSlots[s] = true
		end

		local result = shareLists(streetResult, railResult)

		-- Must be before the module pass, which the engine runs off `slots`.
		local supports = addSupportSlots(result, railResult, RAIL_XF, railModules,
			params.modules)

		-- Run-once guard. Everything in the hook is a **mutation** of tables the
		-- engine already holds - the rail level is lifted in place - so a second
		-- invocation would not redo the work, it would lift an already-lifted
		-- level to +24 and renumber tags on top of themselves. The engine calls
		-- the hook once per `updateFn`, so this never fires today; it is here
		-- because the failure mode is "the upper deck is at the wrong height
		-- and nothing in the log says why", which is expensive to diagnose.
		local hookRan = false

		result.terminateConstructionHook = function(...)
			if hookRan then
				log.warning(LOG .. "terminateConstructionHook called twice for"
					.. " one updateFn - ignoring the second call. The result is"
					.. " mutated in place, so re-running it would double the lift.")
				return
			end
			hookRan = true

			-- Each family's hook closes over its own result table, but those
			-- tables now point at the same lists, so both assemble into one
			-- place and whichever runs second sees the other's work.
			if streetHook ~= nil then streetHook(...) end
			if railHook ~= nil then railHook(...) end

			liftRail(result, railResult, RAIL_XF, railSlots)
			finish(result, streetResult, railResult)
			-- After finish: it is what re-reads both families' subconstructions,
			-- so this is the first point at which every lane list exists.
			linkLevels(result, PITCH)

			local stations = 0
			for _i, sub in ipairs(result.subconstructions or {}) do
				if sub.station then stations = stations + 1 end
			end
			local tags = {}
			for _i, sub in ipairs(result.subconstructions or {}) do
				tags[#tags + 1] = tostring(sub.tag)
			end
			log.message(LOG .. "built: modules rail=" .. tostring(nRail)
				.. " street=" .. tostring(nStreet)
				.. " support=" .. tostring(nSupport) .. "; "
				.. tostring(supports) .. " support slots, "
				.. tostring(#(result.subconstructions or {}))
				.. " subconstructions (tags " .. table.concat(tags, ",") .. "), "
				.. tostring(stations) .. " stations, "
				.. tostring(#(result.slots or {})) .. " slots, "
				.. tostring(#(result.edgeLists or {})) .. " edge lists, rail at +"
				.. tostring(PITCH))
		end

		return result
	end,
}
end
