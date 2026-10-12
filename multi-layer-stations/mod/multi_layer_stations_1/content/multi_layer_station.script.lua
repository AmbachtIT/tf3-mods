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
--- For `getStationPoolCapacities`. Safe from a resource script: it pulls in
--- only `vec3` and `mat4`, no GUI. (`constructionutil` is heavier - it reaches
--- for `asset_util` and the street serialisers - and is not needed here.)
local modulesutil = require "::/scripts/construction/modulesutil.lua"

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

--- Our own slot layers, declared up here because the module classifier below
--- needs them. What each one is for is documented where it is built: supports
--- under "holding the elevated level up", the concourse under "the concourse".
---
--- **All of this is frozen at the first public release.** A slot id is a
--- savegame key and a slot type is the string a third-party module matches on,
--- so changing either orphans what players have built.
local SUPPORT_TYPE = "ml_support"
local CONCOURSE_TYPE = "ml_concourse"

--- The id bases, and the arithmetic that keeps them from colliding - which is
--- worth writing down, because the first choice of base for the concourse did
--- collide and it would not have been visible until a player put a support
--- under the far end of a long station.
---
---     supports   600e6 + railSlotId * 10 + cell
---                rail slot ids reach ~10,817,100 (`passengerPlatformAddonSlotId`
---                = 10800000, plus 1000 * coordI + 10 * coordJ), so x10 + 9
---                takes supports up to ~708e6.
---     concourse  800e6 + streetSlotId with the variant digits cleared
---                street slot ids are 200000 * (coordJ + 100) + 100 *
---                (coordI + 100) + variant, so ~21e6 at most: ~821e6.
---
--- 800e6 therefore clears the top of the support range with ~92e6 to spare.
--- Anything added later goes **above** 900e6, or re-does this arithmetic.
local SUPPORT_SLOT_BASE = 600000000
local CONCOURSE_SLOT_BASE = 800000000

--- The low water mark for "a slot this mod invented". Everything at or above it
--- belongs to us and to neither stock family.
local OUR_SLOT_MIN = SUPPORT_SLOT_BASE

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

--- **No station building is seeded on either level.** The concourse is the
--- station building now, for both levels at once, so a seeded one on top of it
--- is a second building the player did not ask for and has to delete twice.
--- The slots are untouched, so anyone who wants one still places it.
---
--- Kept because it cost a round to work out and Phase 8 will want it again:
--- the rail building's slot is `mainBuildingSlotId + 10 * k + offset`
--- (`modular_station.script.lua:218`), where `mainBuildingSlotId = 3400000`
--- (`:39`), `offset = 0` below three tracks, and `k = 2` when the platform's
--- tile span is odd - which ours is, running -1..2. So `3400020` for this
--- layout. It is inferred from the seeding side rather than read off the slot
--- creation, because building slots come out of loops at `:690-780` that are
--- not worth reverse-engineering; a wrong id there presents as "no catchment"
--- rather than as a misplaced building, since `addCatchmentCircles` needs a
--- matching slot to take its position from. The street side's is
--- `MangleId({coordI, 0, moduleVariants.small_building})`
--- (`modular_terminal.script.lua:2629`), `small_building = 2`.

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

	-- One bus platform plus the entrance, the same shape the stock street
	-- station seeds for a single platform (see pick-single-platform-side's
	-- notes for the slot layout).
	local busDir = "::/stations/street/modular_street_station/"
	seeded[streetMangle(0, 0, 0)] = busDir .. "passenger_platform.module"
	seeded[streetMangle(0, 1, 0)] = busDir .. "passenger_platform.module"
	seeded[streetMangle(55, 0, 3)] = busDir .. "entrance_exit.module"

	-- **The concourse is not seeded**, and that is a deliberate step back.
	--
	-- It was seeded, because it is what makes the station work - without one,
	-- catchment and waiting capacity fall back to a default and the log says
	-- so. But module removal is refused for every module in this construction
	-- *except the concourse itself*, and the concourse is the newest thing in
	-- here: the regression window is this seeding change plus the concourse
	-- feature, and nothing else. A configuration that is invalid while the
	-- concourse is in it, and valid the moment it is gone, is exactly what the
	-- bulldozer behaves like.
	--
	-- Seeding is also the half of it with a known engine asymmetry behind it: a
	-- **seeded** module's geometry is checked against the *world* when the
	-- construction is placed, where a player-added one is only checked against
	-- the construction (root `NOTES.md`, "A seeded module's geometry is checked
	-- against the world at placement"). So a seeded module of ours near the
	-- entrance road is the one piece of this that is known to be treated
	-- differently from everything else.
	--
	-- Leaving it to the player costs a default catchment on a fresh station,
	-- which is logged and survivable, and it is the same conclusion supports
	-- and the viaduct both reached: nothing automatic can know what the player
	-- means a station to be. If removal works on a station with no concourse
	-- and breaks again when one is placed, the concourse is the cause and
	-- seeding was not the half that mattered. The id it would use is the
	-- entrance's slot id with its variant digits cleared -
	-- `CONCOURSE_SLOT_BASE + streetMangle(55, 0, 0)` for the entrance seeded
	-- above - which is what `addConcourseSlots` hands out.

	log.message(LOG .. "seeded: rail " .. tostring(tiles) .. " tiles ("
		.. tostring(tiles * 40) .. " m, era " .. era .. ")"
		.. " + 1 bus platform + entrance, no concourse and no station"
		.. " building on either level")
	return seeded
end

--- Which of the three parties owns a module: `"ours"`, `"street"` or
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
--- module. A third-party module in one of our slots - the point of publishing
--- this - would not have `ml_support` in its name, and under the old name test
--- it fell through to the rail bucket, where rail's `pairs(params.modules)`
--- sweep would count it and `GetCoord` would decode its id to nonsense.
---
--- The bucket is `"ours"` rather than naming a particular layer: which of our
--- layers a slot belongs to is a question for the code that owns that layer,
--- and it answers it from the id base, not from here.
---
--- Anything that matches nothing is reported and then placed by id band. The
--- bands are deliberately wider than the real ranges: the point is to classify
--- a stranger plausibly rather than to re-derive the mangling.
local RAIL_ID_MAX = 15000000
local STREET_ID_MAX = 500000000

local function familyOf(slotId, entry)
	if type(slotId) == "number" and slotId >= OUR_SLOT_MIN then
		return "ours"
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
---
--- The width is the one number that was wrong, and it mattered: the piece is
--- **4.43 m** wide, not 4.4. `stone_abut_rep_rep.mdl`'s `boundingInfo` is
--- `bbMin.x = -2.21521`, `bbMax.x = 2.216`, against `y = 0 .. 4` and
--- `z = 0 .. 2` - so it is anchored at its own back edge in y and its bottom in
--- z, but **centred** in x. See `tileCount` for why a width that is not a
--- divisor of the cell is a problem rather than a rounding detail.
local SUPPORT_BRICK = "::/infrastructure/bridge/stone/stone_abut_rep_rep.mdl"
local SUPPORT_BRICK_W = 4.43
local SUPPORT_BRICK_D = 4.0
local SUPPORT_BRICK_H = 2.0

--- The brick's **collider**, which is not its mesh - and is why a support can
--- be placed and then refused for colliding with its neighbour.
---
--- `stone_abut_rep_rep.mdl` declares a `BOX` collider of halfExtents
--- `{1.71561, 2, 1}` at `(1.20039, 2, 1)`, so in model space it covers
--- `x = -0.52 .. 2.92` against a mesh of `x = -2.22 .. 2.22`. It is not centred
--- on the piece it belongs to, and it reaches 0.70 m past the mesh's own `+x`
--- edge. Scaled to a tile of `step` metres that overhang is
--- `step * (2.916 / 4.43 - 0.5)`, and since every slab is drawn twice - the
--- twin turned 180 degrees - the pair overhangs its tile at **both** ends, and
--- it is the collider rather than the mesh that bounds the pair.
---
--- With the walls standing on the cell outline that put ~0.8 m of collider into
--- the next cell on every side, while the brickwork itself sat neatly inside
--- its own. Nothing on screen says so; what says so is the bulldozer refusing
--- the module. Hence `fitSpan` and the `drawn` figure in the log.
local SUPPORT_BRICK_COLL_MIN = -0.51522
local SUPPORT_BRICK_COLL_MAX = 2.916
local SUPPORT_BRICK_OVERHANG = SUPPORT_BRICK_COLL_MAX / SUPPORT_BRICK_W - 0.5

--- How many copies of a `piece`-long brick to lay along a `span`, at least one.
---
--- Paired with scaling each copy to `span / n`, which is what keeps the
--- brickwork inside its cell. Laying the piece at its own size and stepping by
--- `span / n` does not: for a 5 m platform cell, `ceil(5 / 4.43)` is 2 columns
--- at a 2.5 m step, and a 4.43 m piece at each of them covers -3.47 .. 0.97 and
--- -0.97 .. 3.47. That is ~2 m of doubled masonry down the middle of the cell
--- and ~1 m hanging over each edge, so the cells either side of a platform -
--- 5 m apart, by the rail grid - overlap each other's brickwork as well. Which
--- is what "the supports look off" is: the footprint is right, the thing drawn
--- in it is 6.9 m wide.
---
--- Rounds **up**, so a tile is never longer than the piece itself. That is a
--- collider bound, not a taste in brickwork: `SUPPORT_BRICK_OVERHANG` grows
--- with the tile, so rounding to the nearest count - which could stretch a
--- tile to 1.5 pieces - let the overhang reach 1.0 m, more than the clearance
--- a cell can give it. Capping the tile at `piece` caps the overhang at
--- `piece * 0.158`, which is 0.70 m, and which `fitSpan` can then solve
--- against. The price is squeezed masonry on spans that do not divide: a 3.0 m
--- pier face is one piece at 69%.
---
--- The epsilon keeps a span that *is* a whole number of pieces from rounding up
--- to one more than it needs.
local function tileCount(span, piece)
	return math.max(1, math.ceil(span / piece - 0.001))
end

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

--- The cell each support slot stands in, by slot id: `{width, depth}`.
---
--- This exists because a support slot reserves **no ground at all** - see
--- `addSupportSlots` - so the module can no longer read its own size back off
--- `spacing`. Rebuilt whenever the slots are, and read by the module pass,
--- which the engine runs afterwards in the same build.
local supportCells = {}

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
	supportCells = {}
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
					-- The cell this support fills, as reserved ground.
					-- Symmetric, because the offset is already baked into the
					-- transform above.
					--
					-- This was `{ 0, 0, 0, 0 }` for three rounds, on stock's
					-- idiom for a slot stacked over another one: the platform
					-- roof and addon slots sit above an occupied platform slot
					-- and declare exactly that
					-- (`modular_station.script.lua:567-612`). The idiom has a
					-- second half this mod does not implement - those slots are
					-- listed in `dependentSlots` of the platform under them -
					-- and without it a zero reservation is **a slot the player
					-- cannot click**. The concourse slot proved it: there in
					-- the log every rebuild, `occupied=false`, and no module
					-- slot offered in the game. A rectangle is the only thing
					-- an *empty* slot has to be found by, because nothing is
					-- drawn there yet.
					--
					-- The flat collision check the zero was for is only over
					-- **modules**, so `trimReservations` takes the reservation
					-- away again once something is standing here - by which
					-- time the module's own brickwork is what the cursor finds.
					spacing = { width * 0.5, width * 0.5,
						cellD * 0.5, cellD * 0.5 },
					type = SUPPORT_TYPE,
					replaceable = true,
				}
				supportCells[SUPPORT_SLOT_BASE + slot.id * 10 + k] =
					{ width, cellD }
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
		-- Support ids only: the concourse layer lives above `CONCOURSE_SLOT_BASE`
		-- and is not derived from the rail level, so it is not orphaned by this.
		if type(slotId) == "number" and slotId >= SUPPORT_SLOT_BASE
			and slotId < CONCOURSE_SLOT_BASE and not have[slotId] then
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

--- One wall of a cell, drawn **twice**.
---
--- The brick has one finished face, and which way that face points is not
--- something this mod can read off the model, so every slab is emitted again
--- turned through 180 degrees. The two copies fill the same volume, so the wall
--- is finished on both sides whichever way round the mesh is, and no
--- orientation has to be guessed. That is the placeholder bargain: twice the
--- models, and nothing that looks hollow from one side and solid from the
--- other.
---
--- `x0..x1` by `y0..y1` is the wall's footprint in the slot's own frame, and
--- `alongY` says which way it runs. The brick is `SUPPORT_BRICK_W` long in x by
--- `SUPPORT_BRICK_D` deep in y, anchored at `y = 0` and centred in x, so:
---
---  * a wall running along x is laid unrotated at `y0`, and its twin at `y1`
---    turned by pi - which puts that copy's own anchor on the far edge, so both
---    cover `y0..y1`;
---  * a wall running along y needs a quarter turn first, +pi/2 anchored at `x1`
---    and -pi/2 anchored at `x0`.
---
--- Both are scaled to the tile they are laid in, which is what keeps the
--- brickwork inside the cell - see `tileCount`.
local function brickWall(models, x0, x1, y0, y1, alongY)
	local courses = math.max(1, math.floor(PITCH / SUPPORT_BRICK_H + 0.5))
	local length = alongY and (y1 - y0) or (x1 - x0)
	local thick = alongY and (x1 - x0) or (y1 - y0)
	if length <= 0.0 or thick <= 0.0 then return end

	local n = tileCount(length, SUPPORT_BRICK_W)
	local step = length / n
	local scale = vec3.new(step / SUPPORT_BRICK_W,
		thick / SUPPORT_BRICK_D, 1.0)

	for i = 0, n - 1 do
		for c = 0, courses - 1 do
			local z = c * SUPPORT_BRICK_H
			local a, b
			if alongY then
				local cy = y0 + step * (i + 0.5)
				a = { math.pi * 0.5, vec3.new(x1, cy, z) }
				b = { -math.pi * 0.5, vec3.new(x0, cy, z) }
			else
				local cx = x0 + step * (i + 0.5)
				a = { 0.0, vec3.new(cx, y0, z) }
				b = { math.pi, vec3.new(cx, y1, z) }
			end
			for _j, t in ipairs({ a, b }) do
				models[#models + 1] = {
					id = SUPPORT_BRICK,
					transf = transf.scaleXYZRotZTransl(scale, t[1], t[2]),
				}
			end
		end
	end
end

--- How much of its cell a support leaves clear on every side.
---
--- This reads as cosmetic - "the supports are wider than they need to be" - and
--- it is the deletion bug. The walls used to stand on the cell outline, and
--- with the collider overhang above, two supports in neighbouring cells
--- overlapped by ~1.6 m of collider each way. In the rail grid neighbours are
--- 5.0 m apart across the platforms and 7.8 m along them, so **every adjacent
--- pair collided**, and the bulldozer refuses a module whose geometry collides
--- with another module's. `skipCollisionCheck` does not reach that check: it is
--- a `SlotConfig` field, read by the builder, and the refusal comes from
--- `ModuleBulldozerAction.cpp`. The same mechanism refused the concourse's
--- placement when its piers hung over the kerb, which is the second time this
--- mod has paid for geometry leaving its cell - see `concourseModels`.
---
--- Half a metre of ground is left clear on every side, measured against the
--- **envelope** rather than the brickwork - so the gap between two supports in
--- neighbouring cells is a full metre of nothing, not a hairline the engine can
--- round the wrong way. It also answers the look: a 5 m platform cell draws a
--- 3.0 m pier rather than a slab flush with its neighbour.
local SUPPORT_MARGIN = 0.5

--- The span to draw in a `cell`-metre direction so the envelope - collider
--- overhang included - stays `SUPPORT_MARGIN` inside it.
---
--- Insetting by a fixed amount does not work, because the overhang is a
--- fraction of the *tile*, so it grows with whatever is left after the inset:
--- a flat 0.75 m off a 5 m cell leaves a 3.5 m pier whose collider reaches
--- 2.30 m, which is 0.20 m from the cell edge rather than the 0.75 m the inset
--- appeared to buy. Solving it the other way round -
--- `span * (1 + 2 * overhang / n) = cell - 2 * margin` - puts the clearance
--- where it was promised, and because `n` is `tileCount(span)` the answer is
--- found by iterating twice from the unadjusted span. The `n` matters: without
--- it a 40 m building cell would shrink to 29.6 m instead of 37.7 m, since its
--- nine tiles each overhang a ninth as much as one long tile would.
local function fitSpan(cell)
	local free = cell - 2.0 * SUPPORT_MARGIN
	-- A cell too small to give the margin away twice over still draws
	-- something, scaled down far enough that the overhang cannot escape it.
	if free <= 0.0 then return cell * 0.5 end
	local span = free
	for _i = 1, 3 do
		span = free / (1.0 + 2.0 * SUPPORT_BRICK_OVERHANG
			/ tileCount(span, SUPPORT_BRICK_W))
	end
	return span
end

--- How much of a cell a support leaves clear where it butts **end to end**
--- against the next one.
---
--- Small on purpose, and the asymmetry with `SUPPORT_MARGIN` is the point: a
--- collider only overhangs along the direction its wall *runs*, not across its
--- thickness. In a four-walled cell the `y` extremes are the end walls'
--- thickness, which is exact, and the side walls are inset far enough that
--- their own overhang cannot reach past it - so `y` needs no allowance for the
--- collider at all, only a seam so two supports in a row do not share a face.
---
--- Giving `y` the full `SUPPORT_MARGIN` instead is what made a row of supports
--- too short: it cost 1 m of a 7.8 m cell to compensate for an overhang that
--- is not there, leaving 2.4 m gaps in what should read as a continuous
--- support under the span.
local SUPPORT_SEAM = 0.1

--- How thick a placeholder wall is: 1 m, or less in a cell too small for that.
local function wallThickness(width, depth)
	return math.min(1.0, width * 0.4, depth * 0.4)
end

--- What a support module was asked to draw, and in which frame. Deduped the
--- same way and for the same reason as `logUpgrade`: the engine runs the module
--- pass on every rebuild, so one line per distinct cell is the useful rate.
local lastSupportDraw = nil
local function logSupportDraw(line)
	if line ~= lastSupportDraw then
		lastSupportDraw = line
		log.message(LOG .. "support draw: " .. line)
	end
end

--- The models a support module draws: a brick box standing on its cell, from
--- the ground to the underside of the level above.
---
--- Sized from the slot it was placed in rather than fixed, so one module serves
--- a 5 m platform span and a 15 m building footprint alike. `spacing` on a
--- support slot is symmetric by construction, so the cell is
--- `[-w/2, w/2] x [-d/2, d/2]`, and the four walls stand on the outline of the
--- box that `fitSpan` and `SUPPORT_SEAM` fit **inside** that, not on the
--- cell's own edge.
---
--- That outline is the point, and it is what the previous version got wrong.
--- It laid every piece unrotated, so the "sides" of the cell were more
--- x-facing slabs rather than walls along y, and with the cell one course wide
--- the result was two walls across it - one on the near edge, one through the
--- middle - and nothing at all on the other three. Hence "the geometry does
--- not coincide with the slot": the footprint was right, the thing drawn in it
--- bore no relation to it.
---
--- Hollow rather than solid: 12 m of masonry filling the footprint reads as a
--- block rather than a support, and the inside of a closed box cannot be seen.
local function supportModels(width, depth)
	local models = {}
	-- Across the cell the end walls run the full width, so that direction pays
	-- for their collider overhang (`fitSpan`). Along it, only a seam.
	local w = fitSpan(width)
	local d = math.max(depth - 2.0 * SUPPORT_SEAM, 0.0)
	local t = wallThickness(w, d)
	local hw, hd = w * 0.5, d * 0.5

	-- The side walls are inset by the end walls' thickness, so no two walls of
	-- a cell claim the same ground - except where that is not enough to swallow
	-- their own overhang, which only arises in a cell too narrow for a 1 m
	-- wall.
	local side = math.max(t, SUPPORT_SEAM
		+ SUPPORT_BRICK_OVERHANG * math.min(d, SUPPORT_BRICK_W))

	brickWall(models, -hw, hw, -hd, -hd + t, false)
	brickWall(models, -hw, hw, hd - t, hd, false)
	brickWall(models, -hw, -hw + t, -hd + side, hd - side, true)
	brickWall(models, hw - t, hw, -hd + side, hd - side, true)
	return models
end

--- The envelope a set of support models occupies, **colliders included**, in
--- the frame they were built in.
---
--- Worth measuring rather than reasoning about: the whole deletion problem was
--- geometry leaving its cell by an amount nothing on screen showed, so the log
--- now carries it as two numbers beside the cell it has to fit in. A `drawn`
--- wider than `cell` means a module is reaching into its neighbour again.
---
--- Only the collider's corners are needed. It is the collider that is wider
--- than the piece (`SUPPORT_BRICK_COLL_MIN .. _MAX` against a mesh centred on
--- zero), and it is flush with the mesh in y and z.
local function drawnExtent(models)
	local x0, x1, y0, y1 = math.huge, -math.huge, math.huge, -math.huge
	local corners = {
		{ SUPPORT_BRICK_COLL_MIN, 0.0, 0.0 },
		{ SUPPORT_BRICK_COLL_MAX, 0.0, 0.0 },
		{ SUPPORT_BRICK_COLL_MIN, SUPPORT_BRICK_D, 0.0 },
		{ SUPPORT_BRICK_COLL_MAX, SUPPORT_BRICK_D, 0.0 },
	}
	for _i, m in ipairs(models) do
		for _j, c in ipairs(corners) do
			local q = applyMat(m.transf, c)
			x0, x1 = math.min(x0, q[1]), math.max(x1, q[1])
			y0, y1 = math.min(y0, q[2]), math.max(y1, q[2])
		end
	end
	if x1 < x0 then return 0.0, 0.0 end
	return x1 - x0, y1 - y0
end

--- The cell a support module sits in, read back off its slot. Falls back to one
--- platform-sized span if the slot cannot be found, so a stale module from an
--- older savegame still draws something rather than nothing.
local function supportCell(result, slotId)
	local cell = supportCells[slotId]
	if cell ~= nil then return cell[1], cell[2] end
	-- `spacing` is zero on a support slot now, so this only ever answers for a
	-- slot built by something else; it is kept because it costs nothing and
	-- the fallback below is a guess.
	for _i, slot in ipairs(result.slots or {}) do
		if slot.id == slotId and slot.spacing ~= nil
			and slot.spacing[1] + slot.spacing[2] > 0.0 then
			return slot.spacing[1] + slot.spacing[2], slot.spacing[3] + slot.spacing[4]
		end
	end
	return 5.0, SUPPORT_CELL_D
end

--------------------------------------------------------------------------------
-- the concourse: what makes a multi-layer station a station
--------------------------------------------------------------------------------

--- A concourse spans the bus entrance road and is where the station's catchment
--- and waiting capacity come from - **for both levels at once**.
---
--- This is the third time this mod has arrived at the same conclusion, so it is
--- worth stating as the principle it is: *nothing automatic can know what the
--- player means a station to be.* Supports became player-placed because no rule
--- can know what is under the deck; the viaduct went for the same reason; and
--- catchment has been a hidden default with a warning attached, which is
--- neither how the stock stations behave nor an honest failure. Making it a
--- placed object settles `PLAN.md` Phase 6's open question - "whether to keep
--- the floor" - by making the floor something the player can see.
---
--- Why this does something the stock stations cannot: on the rail side
--- catchment comes only from `main_building_*` / `side_building_*` / `stairs`,
--- on the street side only from `entrance*`, and each one feeds **its own**
--- station record. A multi-layer station is one structure whose two levels
--- share a single StationGroup, so one building serving both is the honest
--- model, and a module of ours is the only thing that can do it - it is in
--- neither family's module map, so neither family's catchment sweep can see it.
---
--- 24 m wide, and the number comes from the **street template**, not from the
--- ground face.
---
--- 20 m was the first answer, measured off the entrance module's ground face at
--- x in [-5, 5] - but that face is the 10 m carriageway, and the road is wider
--- than its carriageway. `entrance_new.street_template` declares lanes of
--- `width = 3, 5, 5, 3`: **16 m**, a 10 m carriageway with 3 m sidewalks either
--- side. So a 20 m concourse leaves its legs just 2 m clear of the road, which
--- is to say standing on the shoulder.
---
--- 24 m puts them at x = +-12, 4 m clear of the road edge. It costs the neat
--- match with a stock `*_20_20` building, which is a fair trade for legs that
--- are not in the road.
local CONCOURSE_W = 24.0

--- 6 m deep, which is **not** a styling choice - it is the largest depth that
--- keeps the concourse out of the road.
---
--- The first attempt was 10 m, reasoned from the entrance edge's snap *node* at
--- y = -15, and it broke placement two ways at once. The number that matters is
--- not the snap node, it is the entrance module's **snapPoint**, at
--- `transl(0, -15 + 5, 0)` - local **y = -10**
--- (`modular_street_station/modules.script.lua:119-122`). That is the point the
--- engine aligns to an existing road, so a road snapped to this station lands
--- *at* y = -10. A 10 m cell centred at -5 reaches exactly that far, so:
---
---  * snapping the station to a road put the road inside the concourse
---    footprint, and placement was refused as a collision - while placing in
---    free space, where there is no road yet, worked;
---  * and once a road *was* connected there, the concourse could no longer be
---    replaced after being demolished, because re-placing it re-checks against
---    that road. The seeded one survived only because it predated the road.
---
--- 6 m centred at -3 covers y = 0 .. -6, leaving 4 m of clearance. It also
--- happens to be where the concourse belongs: the elevated deck is one platform
--- and one track wide, so it crosses the entrance road close to the station
--- edge, not out at the kerb.
local CONCOURSE_D = 6.0

--- One concourse slot per entrance, at grade, spanning the entrance road.
---
--- Derived from the **street** family's slots, the same way `addSupportSlots`
--- derives from rail's - that machinery is already tested, and deriving means
--- a second entrance gets a second concourse for free.
---
--- The id deliberately **drops the variant digits**. Street slot ids are
--- `200000 * (coordJ + 100) + 100 * (coordI + 100) + variant`, and the three
--- entrance variants - `hor_entrance_exit` (3), `hor_entrance` (4), `hor_exit`
--- (5) - are emitted as three separate slots at the *same transform*
--- (`modular_terminal.script.lua:2596-2610`). Keying off the raw slot id would
--- therefore both create duplicate concourse slots at one position and move the
--- concourse's own id when a player swapped an entrance for an exit, orphaning
--- the module. `slotId - slotId % 100` is the position without the variant.
---
--- Called from `updateFn`, before the module pass, for the same reason the
--- support slots are.
local ENTRANCE_SLOT_TYPES = {
	street_terminal_entrance_exit = true,
	street_terminal_entrance = true,
	street_terminal_exit = true,
}

local function addConcourseSlots(result, streetResult, modules, allModules)
	local seen = {}
	local added = 0
	for _i, slot in ipairs(streetResult.slots or {}) do
		if ENTRANCE_SLOT_TYPES[slot.type] and slot.transf ~= nil
			and modules[slot.id] ~= nil then
			local id = CONCOURSE_SLOT_BASE + slot.id - (slot.id % 100)
			if not seen[id] then
				seen[id] = true
				-- The entrance's own frame, shifted along its local -y, which
				-- is the direction its road runs in every orientation the
				-- street station emits - including the pi-rotated "top"
				-- entrances and the quarter-turned vertical ones.
				result.slots[#result.slots + 1] = {
					id = id,
					transf = transf.mul(slot.transf,
						transf.transl(vec3.new(0.0, -CONCOURSE_D * 0.5, 0.0))),
					-- The concourse cell, as reserved ground - without which
					-- there is nothing to click to place one (see the support
					-- slot above, which is where that was learned the hard
					-- way). A concourse spans the entrance road on purpose, so
					-- this does overlap the street entrance's own tile by
					-- design; `trimReservations` takes it away again once a
					-- concourse is standing in it, and by then the concourse
					-- itself is what the cursor finds.
					spacing = { CONCOURSE_W * 0.5, CONCOURSE_W * 0.5,
						CONCOURSE_D * 0.5, CONCOURSE_D * 0.5 },
					type = CONCOURSE_TYPE,
					replaceable = true,
				}
				added = added + 1
			end
		end
	end

	result.slotConfig = result.slotConfig or {}
	result.slotConfig[CONCOURSE_TYPE] = { skipCollisionCheck = true }

	-- Where each concourse cell actually is, in world coordinates, and how deep.
	--
	-- Logged next to the existing `snapPoint:` line on purpose: those two
	-- positions are the ones that must not overlap, and reading them off the
	-- same rebuild is what turns "placement is refused as a collision" from a
	-- guess into a measurement. `skipCollisionCheck` does not help here - it
	-- governs a slot against the rest of the construction, not the
	-- construction against the world.
	-- Occupancy is in here on purpose. "I cannot place the module" has two
	-- completely different causes - the slot is not there, so nothing is
	-- offered; or the slot is there and the placement is refused - and they
	-- need separating before anything else. An `occupied=false` line means the
	-- slot exists and the refusal is a collision; no line at all means the
	-- slot is gone and the entrance it derives from is the thing to look at.
	local parts = {}
	for _i, slot in ipairs(result.slots or {}) do
		if slot.type == CONCOURSE_TYPE then
			parts[#parts + 1] = string.format("%d@(%.1f,%.1f) occupied=%s",
				slot.id, slot.transf[13], slot.transf[14],
				tostring((allModules or {})[slot.id] ~= nil))
		end
	end
	if #parts > 0 then
		log.message(LOG .. "concourse slots "
			.. string.format("%.0fx%.0f: ", CONCOURSE_W, CONCOURSE_D)
			.. table.concat(parts, ", "))
	end
	return added
end

--- Catchment and waiting capacity from the concourse modules, onto **both**
--- station records.
---
--- Mirrors `constructionutil.addCatchmentCircles`
--- (`constructionutil.lua:531-546`) rather than calling it, and the reason is
--- its signature: it maps `metadata.catchmentPassenger` to the *passenger*
--- station and `metadata.catchmentCargo` to the *cargo* station. Both of ours
--- are passenger stations, so there is no way to ask it for "this radius, on
--- both" without either calling it twice - which makes its zero-catchment
--- warning fire spuriously, duplicating the one we already emit - or
--- mislabelling the module's metadata as cargo. The sweep is a dozen lines, so
--- it is cheaper to own it than to work around it.
---
--- What is **not** reimplemented is the pool capacity:
--- `modulesutil.getStationPoolCapacities` takes the module map and the result,
--- has no side effects, and does exactly the right thing, so it is called.
---
--- The circle's position comes from the slot, exactly as the stock function
--- does it, which is what makes a second concourse over a second entrance
--- extend the catchment to where that entrance actually is.
local function applyConcourse(result, stations, modules)
	-- **Only our own slots.** Both sweeps below would otherwise pick up the
	-- stock building modules as well - they declare the same
	-- `catchmentPassenger` and `moreCapacity` fields - and each family's hook
	-- has already counted its own. Sweeping the whole slot list would add
	-- every stock building's catchment and capacity a second time, to both
	-- stations. The filter is the whole reason this takes a copy of the map
	-- rather than using `params.modules` directly.
	local mine = {}
	local circles = {}
	for _i, slot in ipairs(result.slots or {}) do
		local entry = modules[slot.id]
		if slot.type == CONCOURSE_TYPE and entry ~= nil and type(entry) == "table" then
			mine[slot.id] = entry
			local catchment = entry.metadata and entry.metadata.catchmentPassenger
			if catchment ~= nil and catchment.radius ~= nil and slot.transf ~= nil then
				circles[#circles + 1] = {
					position = { slot.transf[13], slot.transf[14], slot.transf[15] },
					radius = catchment.radius,
				}
			end
		end
	end

	local passCap = modulesutil.getStationPoolCapacities(mine, result)

	for _i, station in ipairs(stations) do
		station.catchmentAreas = station.catchmentAreas or {}
		for _j, c in ipairs(circles) do
			station.catchmentAreas[#station.catchmentAreas + 1] =
				{ position = c.position, radius = c.radius }
		end
		if passCap > 0 then
			station.pool = station.pool or { edges = {} }
			station.pool.capacity = (station.pool.capacity or 0) + passCap
		end
	end

	return #circles, passCap
end

--- Placeholder art: one pier either side of the road, full height.
---
--- Deliberately **not** the support module's four-sided box, which would wall
--- the road off. Two things it has to respect:
---
---  * it stays **strictly inside the cell**, because a seeded module's geometry
---    is present when the engine runs the placement collision check, so
---    anything that pokes out towards the kerb refuses the placement (see
---    `CONCOURSE_D`). Each pier is a wall along y, inset by its own thickness,
---    so it stands on the cell's edge rather than astride it - the brick is
---    centred in x, and at `+-width/2` unrotated it hung 2.2 m over the side;
---  * the piers are at x = +-12, which clears the **16 m** entrance road
---    (`entrance_new.street_template`: lanes of 3, 5, 5, 3) by 4 m. Measuring
---    against the 10 m carriageway instead left them 2 m clear and on the
---    shoulder, which the engine refused - see `CONCOURSE_W`.
---
--- It is a stand-in for the tunnel portal that is the real answer (`PLAN.md`
--- Phase 10 step 3), reusing the support brick - and `brickWall`, so the piers
--- are finished on both sides - so it lines up with whatever supports stand
--- next to it.
local function concourseModels(width, depth)
	local models = {}
	-- Inset along the cell's depth only. The piers' `x` is load-bearing - it is
	-- what clears the 16 m road - and a wall running along y has no collider
	-- overhang across its thickness, so x is already exact. Along y the pair of
	-- twins did reach ~0.5 m past the cell ends; `fitSpan` pulls that in.
	local d = fitSpan(depth)
	local t = wallThickness(width, d)
	local hw, hd = width * 0.5, d * 0.5

	brickWall(models, -hw, -hw + t, -hd, hd, true)
	brickWall(models, hw - t, hw, -hd, hd, true)
	return models
end

--- Which modules have no slot to stand in, in **any** family?
---
--- The support-specific version of this is in `addSupportSlots`, and it was too
--- narrow. The removal previews in the log show why: removing the street
--- entrance takes the concourse slot with it, because that slot is derived from
--- the entrance - the build reports `0 concourse slots` while the concourse
--- module is still in `params.modules`. Removing the bus platform cascades to
--- the entrance in street's own code and does the same. A module with no slot
--- is one of the few configurations the engine can call invalid outright, so it
--- belongs in the log by name for every family, not just for ours.
---
--- Logs one line either way, because "no orphans" is the interesting half when
--- a removal has just been refused.
local function logOrphanModules(result, modules)
	local have = {}
	for _i, slot in ipairs(result.slots or {}) do
		if slot.id ~= nil then have[slot.id] = true end
	end
	local orphans, names, total = 0, {}, 0
	for id, _entry in pairs(modules or {}) do
		total = total + 1
		if type(id) == "number" and not have[id] then
			orphans = orphans + 1
			if #names < 6 then
				local family = "street"
				if id >= CONCOURSE_SLOT_BASE then
					family = "ours/concourse"
				elseif id >= SUPPORT_SLOT_BASE then
					family = "ours/support"
				elseif id < 20000000 then
					family = "rail"
				end
				names[#names + 1] = tostring(id) .. " " .. family
			end
		end
	end
	local line = "modules with no slot: " .. tostring(orphans) .. " of "
		.. tostring(total)
	if orphans > 0 then
		line = line .. "; " .. table.concat(names, ", ")
		log.warning(LOG .. line)
	else
		log.message(LOG .. line)
	end
	return orphans
end

--- Clips the **rail** level's reserved ground clear of the street level's.
---
--- This is the blunt end of a chain of findings, and it is worth writing the
--- chain down because the conclusion looks reckless on its own.
---
---  1. The engine's module collision check is **flat** - height is not in it.
---     Proven twice here: a rail station building at +12 was refused as
---     colliding with the bus station at grade until `skipCollisionCheck` went
---     on every slot type, and a support reserving ground under the deck it
---     holds up made the whole station un-bulldozable.
---  2. `skipCollisionCheck` does not reach the bulldozer. It is a `SlotConfig`
---     field read by `UI::ModuleBuilder`; the refusal comes from
---     `ModuleBulldozerAction.cpp`, which carries its own
---     `Invalid Configuration, {count} Modules Will Collide`.
---  3. So while any two occupied modules reserve overlapping ground, **no
---     module in the construction can be removed** - the message is about the
---     configuration, not about the module under the cursor.
---  4. Zeroing our own slots was not enough, because the overlaps that remain
---     are **stock against stock**: a rail passenger platform at +12, and the
---     track beside it, against the bus platform at grade. Two decks stacked
---     12 m apart is the entire point of this mod, so those overlaps are not a
---     bug to fix - they are the design, seen by a check that cannot see
---     height.
---
--- Every cross-level pair has a rail slot in it, so trimming the rail level's
--- reservations is enough and the street level keeps its own.
---
--- Round seven: zeroing the rail level outright **cost the tracks**. A platform
--- could still be bulldozed; a track could not, and the log says it was never
--- even refused - not one `module remove slot=84...` line was written in a
--- session of trying, so the engine never built a candidate configuration at
--- all. A refusal previews and then does not commit, which is what the
--- platforms did while the concourse was seeded. This was a miss: nothing
--- under the cursor.
---
--- Which is what a zeroed reservation would do to a track and to nothing else,
--- because a track module's geometry is one invisible model.
--- `trackmodule.script.lua` emits a single `tn_underground_connection.mdl`, and
--- that file is `collider = { type = "NONE" }`, has no mesh under its
--- `RootNode`, and spans z -5 to -1: it is the person-network provider for the
--- subway under the rails, not something a ray can hit. Everything a player
--- sees of a track is the **edges**, and an edge carries no slot tag. So the
--- only thing that can say "this track is under the cursor" is the slot
--- rectangle - while a platform, which has a real mesh with a real collider,
--- never needed it. One cause, and it predicts the asymmetry exactly as
--- reported.
---
--- So: clip, do not zero. A rail slot keeps as much of its reservation as it
--- can have without overlapping an occupied slot on the other level. The
--- bulldozer's flat check finds nothing between the decks, and every slot still
--- has a rectangle to be picked by. Four candidate cuts per obstacle, the
--- cheapest by area wins, and a cut must leave the slot's own origin inside the
--- rectangle: `spacing` is four distances measured from that origin, so a
--- rectangle that does not contain it cannot be written back without inflating
--- over the obstacle again.
---
--- Only **occupied** slots are touched. The check is over modules, so an empty
--- slot cannot be half of a colliding pair, which means every slot a player has
--- yet to build in keeps exactly the rectangle stock gave it.
---
--- What this does **not** touch: terrain alignment, the placement check against
--- the world (that is geometry, not reservations), and street's own slots.

--- A slot's reserved rectangle in construction space, from its live `spacing`.
---
--- `spacing` is `{left, right, back, front}` from the slot's origin, so the
--- rectangle is not centred on it unless the halves match.
local function slotFootprint(slot, xf)
	local sp = slot.spacing
	local t = xf ~= nil and transf.mul(xf, slot.transf) or slot.transf
	local o = applyMat(t, { 0.0, 0.0, 0.0 })
	local b = {
		x0 = math.huge, x1 = -math.huge, y0 = math.huge, y1 = -math.huge,
		ox = o[1], oy = o[2], z = o[3],
		u = { t[1], t[2] }, v = { t[5], t[6] },
	}
	for _i, p in ipairs({ { -sp[1], -sp[3] }, { sp[2], -sp[3] },
			{ sp[2], sp[4] }, { -sp[1], sp[4] } }) do
		local c = applyMat(t, { p[1], p[2], 0.0 })
		b.x0, b.x1 = math.min(b.x0, c[1]), math.max(b.x1, c[1])
		b.y0, b.y1 = math.min(b.y0, c[2]), math.max(b.y1, c[2])
	end
	return b
end

--- `spacing` for a trimmed footprint: the four distances from the slot's own
--- origin, along the slot's own axes, that span it.
---
--- Exact only while those axes are at a right angle to the construction's,
--- which `trimReservations` checks before it clips anything.
local function footprintSpacing(b)
	local sp = { 0.0, 0.0, 0.0, 0.0 }
	for _i, p in ipairs({ { b.x0, b.y0 }, { b.x1, b.y0 },
			{ b.x1, b.y1 }, { b.x0, b.y1 } }) do
		local dx, dy = p[1] - b.ox, p[2] - b.oy
		local du = dx * b.u[1] + dy * b.u[2]
		local dv = dx * b.v[1] + dy * b.v[2]
		sp[1] = math.max(sp[1], -du)
		sp[2] = math.max(sp[2], du)
		sp[3] = math.max(sp[3], -dv)
		sp[4] = math.max(sp[4], dv)
	end
	return sp
end

local RESERVATION_EPS = 0.001
--- How much of a rectangle has to survive a cut for it to be worth having. A
--- sliver is as good as nothing to pick a track by, and taking the whole width
--- off one axis is what zeroing already does, more honestly.
local RESERVATION_MIN = 1.0

--- A shared edge is not an overlap: rail's own platform and track cells touch
--- exactly at a 5 m pitch.
local function footprintsOverlap(a, b)
	return a.x0 < b.x1 - RESERVATION_EPS and a.x1 > b.x0 + RESERVATION_EPS
		and a.y0 < b.y1 - RESERVATION_EPS and a.y1 > b.y0 + RESERVATION_EPS
end

--- The cheapest of the four single cuts that takes `b` clear of `obstacle`, or
--- nil if none of them leaves a usable rectangle around the slot's origin.
local function clipFootprint(b, obstacle)
	local w, d = b.x1 - b.x0, b.y1 - b.y0
	local cuts = {
		{ "x1", obstacle.x0, obstacle.x0 - b.x0, w, d,
			b.ox <= obstacle.x0 + RESERVATION_EPS },
		{ "x0", obstacle.x1, b.x1 - obstacle.x1, w, d,
			b.ox >= obstacle.x1 - RESERVATION_EPS },
		{ "y1", obstacle.y0, obstacle.y0 - b.y0, d, w,
			b.oy <= obstacle.y0 + RESERVATION_EPS },
		{ "y0", obstacle.y1, b.y1 - obstacle.y1, d, w,
			b.oy >= obstacle.y1 - RESERVATION_EPS },
	}
	local best, bestLoss = nil, math.huge
	for _i, cut in ipairs(cuts) do
		local remain, was, across, keepsOrigin = cut[3], cut[4], cut[5], cut[6]
		local loss = (was - remain) * across
		if keepsOrigin and remain >= RESERVATION_MIN and loss < bestLoss then
			best, bestLoss = { cut[1], cut[2] }, loss
		end
	end
	if best == nil then return nil end
	local out = {}
	for k, v in pairs(b) do out[k] = v end
	out[best[1]] = best[2]
	return out
end

--- Who yields to whom.
---
--- Street is never trimmed: it is at grade, it is stock, and it was here first.
--- Rail yields to street, but only **across levels** - two decks 12 m apart
--- overlap by design, two things at grade do not, and trimming a same-level
--- overlap away would hide a real bug. Our own slots yield to both at **any**
--- level, because every overlap they have is deliberate: a support stands under
--- the deck it holds up and alongside the bus station, and a concourse spans
--- the entrance road.
---
--- Ours are not trimmed against each other. Support cells touch exactly at
--- their pitch, which is not an overlap, and if a concourse and a support ever
--- do foul each other that is a layout question, not something to paper over -
--- `logSlotOverlaps` reports it as a same-level pair.
local function trimReservations(result, railSlots, modules, xf)
	local function occupied(slot)
		local sp = slot.spacing
		return sp ~= nil and type(slot.id) == "number"
			and (modules or {})[slot.id] ~= nil
			and (sp[1] + sp[2] + sp[3] + sp[4]) > 0.0
	end
	local function isRail(slot) return (railSlots or {})[slot] ~= nil end
	local function isOurs(slot) return slot.id >= OUR_SLOT_MIN end
	local function frameOf(slot) return isRail(slot) and xf or nil end

	local original, clipped, zeroed, kept, example = {}, 0, 0, 0, nil

	-- `pick` chooses the slots to trim, `block` the occupied slots they must
	-- stay clear of. Obstacles are read at the start of the pass, so a later
	-- pass sees what an earlier one already trimmed.
	local function pass(pick, block, crossOnly)
		local obstacles = {}
		for _i, slot in ipairs(result.slots or {}) do
			if occupied(slot) and block(slot) then
				obstacles[#obstacles + 1] = slotFootprint(slot, frameOf(slot))
			end
		end

		for _i, slot in ipairs(result.slots or {}) do
			if occupied(slot) and pick(slot) then
				local sp = slot.spacing
				local b = slotFootprint(slot, frameOf(slot))
				-- Both families build their transforms out of `rotZ` and
				-- `transl`, and `RAIL_XF` turns the rail level by 90 degrees,
				-- so a slot's axes are the construction's axes swapped at
				-- worst. If that ever stops being true, zero the slot rather
				-- than write back four distances that do not describe the
				-- rectangle they came from.
				local square = math.min(math.abs(b.u[1]), math.abs(b.u[2]))
					< RESERVATION_EPS
				local fouled = false
				for _j, obstacle in ipairs(obstacles) do
					-- Same level means within a metre in z.
					if (not crossOnly or math.abs(b.z - obstacle.z) >= 1.0)
						and footprintsOverlap(b, obstacle) then
						fouled = true
						b = square and clipFootprint(b, obstacle) or nil
						if b == nil then break end
					end
				end
				if fouled then
					if original[slot] == nil then original[slot] = sp end
					if b == nil then
						slot.spacing = { 0.0, 0.0, 0.0, 0.0 }
						zeroed = zeroed + 1
					else
						local to = footprintSpacing(b)
						slot.spacing = to
						clipped = clipped + 1
						if example == nil then
							example = string.format("%d %.1fx%.1f -> %.1fx%.1f",
								slot.id, sp[1] + sp[2], sp[3] + sp[4],
								to[1] + to[2], to[3] + to[4])
						end
					end
				else
					kept = kept + 1
				end
			end
		end
	end

	pass(isRail, function(slot) return not isRail(slot) and not isOurs(slot) end,
		true)
	pass(isOurs, function(slot) return not isOurs(slot) end, false)

	local line = "trimmed the reserved ground: " .. tostring(clipped)
		.. " slot(s) clipped clear of what they are not allowed to overlap, "
		.. tostring(zeroed) .. " zeroed because no single cut would do, "
		.. tostring(kept) .. " untouched"
	if example ~= nil then
		line = line .. "; e.g. " .. example
	end
	line = line .. ". Occupied slots only: an empty slot keeps its rectangle,"
		.. " which is the only thing the cursor can find it by."
	log.message(LOG .. line)
	return original
end

--- Which **occupied** slots reserve the same ground, in construction space?
---
--- `Invalid configuration, N modules will collide` is an engine message, and it
--- lives in `ModuleBulldozerAction.cpp` - the *bulldozer*, not the builder.
--- That matches the symptom exactly: a support can be placed and then not
--- removed again. Nothing in Lua is reachable from that check, so the only way
--- to see what it sees is to compute the overlaps ourselves and read them off
--- the log.
---
--- Rewritten 2026-10-12, because the first version's warning was an artefact
--- that looked like an answer. It compared our own slots only, and read every
--- `spacing` as axis-aligned in construction space. `RAIL_XF` rotates the rail
--- level by 90 degrees, so a rail-derived slot's local x runs along
--- construction **y** - and reading `spacing` the other way round turns a
--- platform cell and the track cell beside it (5 m wide, 5 m apart, touching
--- exactly) into a 2.8 m overlap. It reported 20 pairs on a four-tile station,
--- which is exactly the 4 tiles x 5 cells of platform/track pairs and nothing
--- else: all of it false.
---
--- So this version
---
---  * uses each slot's own axes rather than the construction's;
---  * covers **all three** families, because our supports stand at grade under
---    the rail deck and alongside the bus station, and a cross-family overlap
---    was never tested at all. Rail's slots are still in rail's own frame when
---    this runs - `liftRail` mutates them later, from the hook - so they get
---    `RAIL_XF` applied here, which is also what puts them at z = 12;
---  * counts **occupied** slots only. The message says *modules*, and an empty
---    slot reserving ground is normal - rail emits `passenger_platform` and
---    `track` for one cell at the same transform and the same rectangle
---    (`modular_station.script.lua:559-560`), so a sweep over all slots can
---    never be quiet;
---  * splits same-level from cross-level pairs. A support at grade under a
---    platform at +12 overlaps in plan **by design**; it is only a problem if
---    the engine's check ignores height, and that is worth knowing separately
---    from two things fouling each other at grade, which is a problem either
---    way.
---
--- It always logs one line, including when it finds nothing: "the diagnostic
--- ran and was quiet" and "the diagnostic did not run" are otherwise the same
--- absence.
local function slotBox(slot, xf, family, original)
	-- The geometry wants the reservation as it was *before* `trimReservations`
	-- took it away, because the diagnostic is about what the modules occupy.
	local sp = (original or {})[slot] or slot.spacing
	-- Our own slots reserve nothing on purpose, so measure what they *occupy*
	-- instead - otherwise the diagnostic goes quiet about exactly the modules it
	-- was written for.
	local cell = supportCells[slot.id]
	if cell ~= nil then
		sp = { cell[1] * 0.5, cell[1] * 0.5, cell[2] * 0.5, cell[2] * 0.5 }
	elseif slot.id >= CONCOURSE_SLOT_BASE then
		sp = { CONCOURSE_W * 0.5, CONCOURSE_W * 0.5,
			CONCOURSE_D * 0.5, CONCOURSE_D * 0.5 }
	end
	local t = xf ~= nil and transf.mul(xf, slot.transf) or slot.transf
	-- `spacing` is `{left, right, back, front}` from the slot origin, so the
	-- rectangle's centre is offset from it unless the halves match.
	local c = applyMat(t, { (sp[2] - sp[1]) * 0.5, (sp[4] - sp[3]) * 0.5, 0.0 })
	return {
		id = slot.id,
		type = slot.type,
		family = family,
		cx = c[1], cy = c[2], cz = c[3],
		-- The slot's own axes in construction space, unit length: both families
		-- build their transforms out of `rotZ` and `transl` alone.
		u = { t[1], t[2] },
		v = { t[5], t[6] },
		hw = (sp[1] + sp[2]) * 0.5,
		hd = (sp[3] + sp[4]) * 0.5,
	}
end

--- Separating-axis test for two rectangles at any rotation.
---
--- A shared edge is not an overlap, which it must not be: rail's own columns
--- touch exactly at a 5 m pitch, and so do our support cells along a tile.
--- `d > r - eps` separates at `d == r`, and the epsilon keeps floating point
--- from turning a shared edge into a 1e-13 overlap.
local function boxesOverlap(a, b)
	local eps = 0.001
	local dx, dy = b.cx - a.cx, b.cy - a.cy
	for _i, ax in ipairs({ a.u, a.v, b.u, b.v }) do
		local d = math.abs(dx * ax[1] + dy * ax[2])
		local ra = math.abs(a.u[1] * ax[1] + a.u[2] * ax[2]) * a.hw
			+ math.abs(a.v[1] * ax[1] + a.v[2] * ax[2]) * a.hd
		local rb = math.abs(b.u[1] * ax[1] + b.u[2] * ax[2]) * b.hw
			+ math.abs(b.v[1] * ax[1] + b.v[2] * ax[2]) * b.hd
		if d > ra + rb - eps then return false end
	end
	return true
end

local function describeBox(b)
	return string.format("%d %s/%s (%.1f,%.1f,%.1f) %.1fx%.1f",
		b.id, b.family, tostring(b.type), b.cx, b.cy, b.cz, b.hw * 2, b.hd * 2)
end

local function logSlotOverlaps(result, railSlots, xf, modules, original)
	local boxes, live = {}, {}
	for _i, slot in ipairs(result.slots or {}) do
		local id = slot.id
		if type(id) == "number" and slot.transf ~= nil and slot.spacing ~= nil
			and (modules or {})[id] ~= nil then
			local family, slotXf = "street", nil
			if id >= OUR_SLOT_MIN then
				family = "ours"
			elseif (railSlots or {})[slot] then
				family, slotXf = "rail", xf
			end
			boxes[#boxes + 1] = slotBox(slot, slotXf, family, original)
			-- And the same slot again at the size the engine can *see* it,
			-- which after `trimReservations` is not the size it occupies. A
			-- trimmed rail slot is still visible, just smaller, so the
			-- `visible` flag alone no longer answers the question that matters:
			-- whether two rectangles the engine holds still overlap.
			local sp = slot.spacing
			if sp[1] + sp[2] + sp[3] + sp[4] > 0.0 then
				live[#live + 1] = slotBox(slot, slotXf, family, nil)
			end
		end
	end

	-- Same level means within a metre in z: the two decks are 12 m apart, so
	-- there is nothing in between to be ambiguous about.
	local same, cross, reserved, examples = 0, 0, 0, {}
	for i = 1, #boxes do
		for j = i + 1, #boxes do
			local a, b = boxes[i], boxes[j]
			if boxesOverlap(a, b) then
				local dz = math.abs(a.cz - b.cz)
				local level = dz < 1.0 and "same" or "cross"
				if level == "same" then same = same + 1 else cross = cross + 1 end
				if examples[level] == nil then
					examples[level] = describeBox(a) .. " vs " .. describeBox(b)
						.. string.format(" dz=%.1f", dz)
				end
			end
		end
	end

	-- What is left for the engine to call a collision: the live rectangles,
	-- after trimming, against each other.
	for i = 1, #live do
		for j = i + 1, #live do
			local a, b = live[i], live[j]
			if boxesOverlap(a, b) then
				reserved = reserved + 1
				if examples.reserved == nil then
					examples.reserved = describeBox(a) .. " vs " .. describeBox(b)
						.. string.format(" dz=%.1f", math.abs(a.cz - b.cz))
				end
			end
		end
	end

	local line = "occupied slot overlaps: " .. tostring(same)
		.. " at the same level, " .. tostring(cross) .. " across levels, out of "
		.. tostring(#boxes) .. " modules; " .. tostring(reserved)
		.. " pair(s) of reserved rectangles still overlap after trimming, out of "
		.. tostring(#live) .. " that reserve any"
	if examples.reserved ~= nil then
		line = line .. "; reserved: " .. examples.reserved
	end
	if examples.same ~= nil then
		line = line .. "; same: " .. examples.same
	end
	if examples.cross ~= nil then
		line = line .. "; cross: " .. examples.cross
	end
	-- `reserved` is the number that matters now: an overlap the engine cannot
	-- see cannot be the collision it refuses a removal over.
	if reserved > 0 then
		log.warning(LOG .. line)
	else
		log.message(LOG .. line)
	end
	return same, cross, reserved
end

--------------------------------------------------------------------------------
-- the track-type and catenary tools
--------------------------------------------------------------------------------

--- These are **reimplemented, not delegated**, and that is the whole point.
---
--- Delegating them did not work: `util.useFn` could not resolve
--- `modular_station.script@isAffectedByToolFn` on whatever thread the build
--- tools run on - 5542 failures in one session - so our wrapper returned
--- `false`, the engine never offered the station to either tool, and neither
--- electrification nor a track-type change did anything. Resolving a sibling
--- first did not help, which is as far as the documented workaround goes (root
--- NOTES.md, "`util.useFn` is per-thread, and not equally willing on every
--- thread").
---
--- The root `NOTES.md` rule already said not to do this: *"a delegated stock
--- call is fine for geometry, where a failure degrades to nothing drawn and is
--- obvious. It is a bad idea for anything that decides the shape of the
--- result."* These decide which modules exist, so they belong here. They use
--- only `api.res.*`, which the stock station uses in the same two functions, so
--- there is nothing left to resolve.

--- The module name for a track street template.
---
--- Mirrors `ResNameToModuleName` (`modular_station.script.lua:359-363`): the
--- engine generates one module per track street template under this prefix, and
--- `::` in the resource name becomes `__`. An absolute `::/infrastructure/...`
--- therefore becomes `::/trainstation___/infrastructure/...` - the three
--- underscores our own seeding uses, which is how the two agree.
local function trackModuleName(resName)
	return "::/trainstation_" .. (tostring(resName):gsub("::", "__"))
end

--- A copy deep enough to retarget module names without touching the original.
---
--- The stock version is `table_util.copy(params)`, a fully recursive deep copy.
--- That is more than is needed and a lot more than is cheap - a module entry
--- carries its whole desc, `generatedData` and all. Only `params`, `modules`
--- and the entries whose `name` is rewritten have to be fresh; everything
--- inside an entry can stay shared.
local function copyParamsShallowModules(params)
	local out = {}
	for k, v in pairs(params) do out[k] = v end
	out.modules = {}
	for slotId, entry in pairs(params.modules or {}) do
		if type(entry) == "table" then
			local e = {}
			for k, v in pairs(entry) do e[k] = v end
			out.modules[slotId] = e
		else
			out.modules[slotId] = entry
		end
	end
	return out
end

--- The metadata behind a `params.modules` entry, resolved from the module
--- **resource** rather than read off the entry.
---
--- This is the shape stock rail's `upgradeFn` uses -
--- `api.res.moduleRep.get(find(name)).metadata`
--- (`modular_station.script.lua:384`) - and the asymmetry with its own
--- `updateFn`, which reads `entry.metadata` directly (`:495`), is the whole
--- point: the entry handed to `upgradeFn` is the stored one, not the enriched
--- one the module pass builds, so `entry.metadata` is not there to be read.
--- Gating on it is what made the catenary tool highlight the station, offer the
--- upgrade, and then silently change nothing.
---
--- The entry's own metadata stays as a fallback, for the case where the module
--- resource cannot be found but the engine did populate the entry.
local function moduleMetadata(entry)
	local name = type(entry) == "table" and entry.name or nil
	if type(name) == "string" and name ~= "" then
		local ok, desc = pcall(function()
			return api.res.moduleRep.get(api.res.moduleRep.find(name))
		end)
		if ok and desc ~= nil and desc.metadata ~= nil then
			return desc.metadata
		end
	end
	return (type(entry) == "table" and entry.metadata) or nil
end

--- One line per upgrade decision, deduped against the last one.
---
--- The upgrade tools are the one path in this mod with no visible failure mode:
--- `isAffectedByToolFn` says yes, the cursor offers the upgrade, and if
--- `upgradeFn` then declines there is nothing on screen - or in the log - to
--- say so. T4 has now cost two rounds to exactly that silence, so the decision
--- is logged. The dedup is because the engine calls `upgradeFn` once per drag
--- step, which would otherwise flood.
local lastUpgradeLog = nil
local function logUpgrade(line)
	if line ~= lastUpgradeLog then
		lastUpgradeLog = line
		log.message(LOG .. "upgrade " .. line)
	end
end

--- Read the original, write the copy - exactly as the stock version does, which
--- is what makes the two row walks below terminate sensibly.
local function swapModule(params, copy, slotId, to)
	local entry = params.modules[slotId]
	if entry ~= nil and entry.name ~= to then
		copy.modules[slotId].name = to
		return true
	end
	return false
end

--- Walk a track row in both directions from the slot the tool hit.
---
--- A track row is `base + 1000 * coordI + 10 * coordJ`, so +-10 steps along it.
--- The walk stops at the first slot that is empty or already has the target
--- name, which is stock behaviour (`SwapRow`, `:365-377`).
local function swapRow(params, copy, slotId, to)
	local id = slotId
	while swapModule(params, copy, id, to) do id = id + 10 end
	id = slotId
	while swapModule(params, copy, id, to) do id = id - 10 end
end

--- `catenaryAdd` / `catenaryRemove` name the module to swap to. Only the track
--- modules declare them, so this is self-limiting.
local function swapCatenary(params, copy, slotId, field)
	local meta = moduleMetadata(params.modules[slotId])
	local to = meta and meta[field] or nil
	if to == nil then
		return false
	end
	copy.modules[slotId].name = to
	return true
end

local function swapRowCatenary(params, copy, slotId, field)
	local id = slotId
	while swapCatenary(params, copy, id, field) do id = id + 10 end
	id = slotId
	while swapCatenary(params, copy, id, field) do id = id - 10 end
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
local function finish(result, streetResult, railResult, modules)
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
	-- The concourse goes first, because it is what the fallback below is a
	-- fallback *for*. Both station records get its catchment and its capacity:
	-- the two levels are one StationGroup and one structure, so one building
	-- serving both is the honest model.
	local stations = {}
	for _i, sub in ipairs(result.subconstructions or {}) do
		if sub.station ~= nil then
			stations[#stations + 1] = sub.station
		end
	end
	local nCircles, poolAdded = applyConcourse(result, stations, modules or {})
	if nCircles > 0 then
		log.message(LOG .. "concourse: " .. tostring(nCircles)
			.. " catchment circle(s) and +" .. tostring(poolAdded)
			.. " pool capacity on each of " .. tostring(#stations) .. " stations")
	end

	for _i, sub in ipairs(result.subconstructions or {}) do
		local station = sub.station
		if station ~= nil then
			station.catchmentAreas = station.catchmentAreas or {}
			if #station.catchmentAreas == 0 then
				station.catchmentAreas[1] = {
					position = { 0.0, 0.0, 0.0 },
					radius = 175,
				}
				-- Since no station building is seeded any more, this has one
				-- expected cause and one real one, and the `concourse:` line
				-- for the same rebuild tells them apart:
				--
				--  1. no concourse is placed, because the player removed it and
				--     put nothing else up. The fallback is doing its job and
				--     the station keeps working. There is no `concourse:` line;
				--  2. a concourse *is* placed and its numbers did not reach the
				--     station records - `applyConcourse` found the slot and the
				--     station list did not line up with it. That is a bug here,
				--     not a player choice. There is a `concourse:` line and
				--     this warning as well.
				--
				-- Both cases used to be reachable a third way, through the
				-- seeded building's slot id drifting after a game update. That
				-- is gone with the seeding.
				log.warning(LOG .. "a station had no catchment of its own -"
					.. " falling back to a default. Expected when no concourse"
					.. " is placed; if the 'concourse:' line for this rebuild"
					.. " says one was applied, then its catchment did not reach"
					.. " this station and that is a bug.")
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
	---
	--- The `support draw:` line is here because "the geometry does not coincide
	--- with the slot" has three possible causes and they are not
	--- distinguishable on screen: the cell read back is wrong (a fallback
	--- `5.0x8.0` means `supportCell` did not find the slot at all), the frame
	--- is wrong (`addModel` multiplies by `result.slots[i].transf`, so this is
	--- the slot's own transform - if its translation is not at grade under the
	--- platform, the slot is misplaced, not the art), or the art does not fill
	--- the frame it is given, which is the only one the models can be blamed
	--- for. Deduped on the whole line, so it costs one line per distinct cell.
	---
	--- `drawn` is the envelope of what was emitted, colliders included
	--- (`drawnExtent`). It has to come out **smaller** than `cell` by about
	--- `2 * SUPPORT_MARGIN` in each direction; bigger than `cell` means geometry
	--- is reaching into the neighbouring cell, which is what the bulldozer
	--- refuses a removal over.
	supportUpdateFn = function(captureParams, result, transform, tag, slotId, addModel, constrParams)
		local w, d = supportCell(result, slotId)
		local models = supportModels(w, d)
		local dw, dd = drawnExtent(models)
		local t = transform
		logSupportDraw(string.format(
			"slot=%d cell=%.1fx%.1f drawn=%.1fx%.1f at (%.1f,%.1f,%.1f) xAxis=(%.2f,%.2f)",
			slotId, w, d, dw, dd,
			t and t[13] or 0.0, t and t[14] or 0.0, t and t[15] or 0.0,
			t and t[1] or 0.0, t and t[2] or 0.0))
		for _i, m in ipairs(models) do
			addModel(m.id, m.transf, tag, result.models)
		end
	end,

	--- The placement preview.
	supportGetModelsFn = function(captureParams, params)
		-- No slot context during the preview, so show a platform-sized span.
		return supportModels(5.0, SUPPORT_CELL_D)
	end,

	--- The concourse's geometry. Placeholder art - see `concourseModels`.
	---
	--- The catchment and capacity this module exists for are **not** applied
	--- here: a module's `updateFn` runs in stage 2, and the station records it
	--- has to write into are assembled by the two families' hooks in stage 3.
	--- So the module declares the numbers in its own `metadata` and
	--- `applyConcourse` reads them back out after the hooks. Same reason the
	--- pedestrian link cannot live here either.
	concourseUpdateFn = function(captureParams, result, transform, tag, slotId, addModel, constrParams)
		for _i, m in ipairs(concourseModels(CONCOURSE_W, CONCOURSE_D)) do
			addModel(m.id, m.transf, tag, result.models)
		end
	end,

	concourseGetModelsFn = function(captureParams, params)
		return concourseModels(CONCOURSE_W, CONCOURSE_D)
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
	--- Same answer as the stock rail station
	--- (`modular_station.script.lua:343-349`): yes for a **track** street
	--- template, no for a road one, yes for everything else - which is what
	--- lets the catenary tool through. The street family's answer is only about
	--- tram track, which this construction does not offer, so there is nothing
	--- to combine.
	---
	--- `roadType == 0` is TRACK; the comparison is the stock one.
	isAffectedByToolFn = function(captureParams, params, conConfigAdd, conConfigRemove)
		local template = conConfigAdd and conConfigAdd.streetTemplate or nil
		if template then
			local rep = api.res.streetTemplateRep
			local desc = rep.get(rep.find(template))
			return desc ~= nil and desc.roadType == 0
		end
		return true
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
	--- The work is rewriting module names along the track row: the generated
	--- `::/trainstation___/...` module for a track type, or whatever
	--- `metadata.catenaryAdd` / `catenaryRemove` names for the catenary tool.
	---
	--- Gated **twice**, and the second gate is stricter than stock's. Stock
	--- `SwapModule` assigns `.name` to whatever it finds at the slot id it is
	--- handed, without checking what that module is, so a street slot getting
	--- through would turn a bus platform into a track module. On top of that we
	--- require `metadata.track`, the field rail's own `updateFn` uses to
	--- recognise a track module - so a platform or a building can never be
	--- renamed into a track by a mis-aimed tool.
	---
	--- That second gate has to read the metadata off the module **resource**,
	--- not off the `params.modules` entry. Reading the entry is what broke T4
	--- the second time: every upgrade was declined here, and declining is
	--- invisible. See `moduleMetadata`.
	upgradeFn = function(captureParams, params, slotId, constructionConfig)
		params = params or {}
		params.modules = params.modules or {}
		constructionConfig = constructionConfig or {}

		-- An empty slot, which the tool may well drag across.
		local entry = params.modules[slotId]
		if entry == nil or type(entry) ~= "table" then
			logUpgrade("slot=" .. tostring(slotId) .. " is empty - nothing to"
				.. " change")
			return params
		end
		local fam = familyOf(slotId, entry)
		if fam ~= "rail" then
			logUpgrade("slot=" .. tostring(slotId) .. " family=" .. tostring(fam)
				.. " - only the rail level has upgradable track")
			return params
		end
		-- From the module resource, not from `entry.metadata`: see
		-- `moduleMetadata`.
		local meta = moduleMetadata(entry)
		if meta == nil or not meta.track then
			logUpgrade("slot=" .. tostring(slotId) .. " name="
				.. tostring(entry.name) .. " is not a track module - ignored")
			return params
		end

		local copy = copyParamsShallowModules(params)
		if constructionConfig.streetTemplate then
			swapRow(params, copy, slotId,
				trackModuleName(constructionConfig.streetTemplate))
			logUpgrade("slot=" .. tostring(slotId) .. " track type -> "
				.. tostring(constructionConfig.streetTemplate) .. ", row now "
				.. tostring(copy.modules[slotId].name))
		elseif constructionConfig.catenary then
			local field = constructionConfig.catenary == 2 and "catenaryAdd"
				or "catenaryRemove"
			swapRowCatenary(params, copy, slotId, field)
			logUpgrade("slot=" .. tostring(slotId) .. " " .. field
				.. " -> " .. tostring(copy.modules[slotId].name))
		else
			logUpgrade("slot=" .. tostring(slotId) .. " the tool asked for"
				.. " neither a track type nor a catenary change - ignored")
			return params
		end
		return copy
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
		local nRail, nStreet, nSupport, nConcourse = 0, 0, 0, 0
		for _k, _v in pairs(railModules) do nRail = nRail + 1 end
		for _k, _v in pairs(streetModules) do nStreet = nStreet + 1 end
		for slotId, _v in pairs(params.modules or {}) do
			if type(slotId) == "number" then
				if slotId >= CONCOURSE_SLOT_BASE then
					nConcourse = nConcourse + 1
				elseif slotId >= SUPPORT_SLOT_BASE then
					nSupport = nSupport + 1
				end
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
		local concourses = addConcourseSlots(result, streetResult, streetModules,
			params.modules)
		-- Must be after `addSupportSlots`, which sizes supports from the rail
		-- slots' reservations, and before the diagnostic, which takes the
		-- originals so it can still report what the modules occupy.
		local reservations = trimReservations(result, railSlots, params.modules,
			RAIL_XF)
		logSlotOverlaps(result, railSlots, RAIL_XF, params.modules, reservations)
		logOrphanModules(result, params.modules)

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
			finish(result, streetResult, railResult, params.modules)
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
				.. " support=" .. tostring(nSupport)
				.. " concourse=" .. tostring(nConcourse) .. "; "
				.. tostring(supports) .. " support slots, "
				.. tostring(concourses) .. " concourse slots, "
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
