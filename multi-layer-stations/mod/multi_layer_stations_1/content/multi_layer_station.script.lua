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
--- under "holding the elevated level up", the two concourses under "the
--- concourse".
---
--- **All of this is frozen at the first public release.** A slot id is a
--- savegame key and a slot type is the string a third-party module matches on,
--- so changing either orphans what players have built.
---
--- The concourse is **two** slot types as of 2026-10-26, and the rename of the
--- first one happened at the same time for exactly that reason: `ml_concourse`
--- had to say which of the two it was, and the only moment that rename is free
--- is before the first publish. There is no save anywhere with the old string
--- in it, so this is a rename and not a migration - and it is the last chance
--- to have one.
local SUPPORT_TYPE = "ml_support"
local CONCOURSE_ARCH_TYPE = "ml_concourse_arch"
local CONCOURSE_HALL_TYPE = "ml_concourse_hall"

--- Both concourse variants, as a set.
---
--- Read by everything that asks "is this a concourse" rather than "is this the
--- one over the road": the catchment sweep, the capacity sweep, the goods store
--- and the pedestrian link. The two modules declare the same numbers and get
--- the same treatment - see `ml_concourse_hall.module.lua` - so every one of
--- those four is a set membership test and not a branch.
local CONCOURSE_TYPES = {
	[CONCOURSE_ARCH_TYPE] = true,
	[CONCOURSE_HALL_TYPE] = true,
}

--- The arch module's own resource name, which `seedBothLevels` needs and which
--- is **frozen at the first public release** for the same reason the slot type
--- is: it is written into every savegame that has a station in it. The hall is
--- never seeded, so it needs no constant here.
local CONCOURSE_ARCH_MODULE = "multi_layer_stations_1::/ml_concourse_arch.module"

--- The id bases, and the arithmetic that keeps them from colliding - which is
--- worth writing down, because the first choice of base for the concourse did
--- collide and it would not have been visible until a player put a support
--- under the far end of a long station.
---
---     supports   600e6 + railSlotId * 10 + cell
---                rail slot ids reach ~10,817,100 (`passengerPlatformAddonSlotId`
---                = 10800000, plus 1000 * coordI + 10 * coordJ), so x10 + 9
---                takes supports up to ~708e6.
---     arch       800e6 + streetSlotId with the variant digits cleared
---                street slot ids are 200000 * (coordJ + 100) + 100 *
---                (coordI + 100) + variant, so ~21e6 at most: ~821e6.
---     hall       900e6 + that same cleared entrance id + 50 + tile
---                the hall layer is a **row** of cells along one entrance's
---                frontage, so its id has to say which entrance and which
---                cell. Clearing the variant leaves a street id ending in
---                `00`, and those two digits are what the tile index goes
---                in: tile 0 is the arch's own cell, so the row can run
---                from -49 to +49 - two kilometres of frontage either side
---                of an entrance, against a longest-ever station of a few
---                hundred metres. The top of the range is ~921e6.
---
--- 800e6 therefore clears the top of the support range with ~92e6 to spare,
--- and the hall layer takes the 900e6 band this comment used to reserve for
--- "anything added later". Anything after it needs to re-do this arithmetic -
--- and to stay under 2^31, which is what the whole scheme is really bounded
--- by: every id here is an integer the engine round-trips through a savegame.
local SUPPORT_SLOT_BASE = 600000000
local ARCH_SLOT_BASE = 800000000
local HALL_SLOT_BASE = 900000000

--- Tile 0 of a hall row is the arch's cell, and the index is stored unsigned.
--- 50 is the offset that makes that work; it is frozen with the ids.
local HALL_TILE_ZERO = 50
local HALL_TILE_MAX = 49

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
--- origin, then shifts across, then lifts.

--- How far the rail level is shifted **across**, so that its platform lands on
--- the concourse instead of three columns away from it.
---
--- The arithmetic, all in construction space (2026-10-13):
---
---  * the quarter turn maps a rail-local `(x, y)` to `(-y, x)`, so a rail
---    **column** `i` - the 5 m pitch across the platforms - sits at
---    construction `y = 5i`, and the 40 m tiles run along construction x;
---  * the seed puts the platform at `i = 0` and the track at `i = 1`
---    (`TRACK_SLOT + 1000` is `1000 * i` in the rail station's id scheme), so
---    the deck was at `y = 0` and `y = 5`;
---  * the street entrance sits at `y = -15` and the concourse cell runs from
---    there to `y = -21`.
---
--- That left three unused column positions between the two - `y = -5`, `-10`
--- and `-15` - which is the 15 m this shift closes. The platform lands on
--- `y = -15`, its near edge on the concourse's near edge, and the track follows
--- at `y = -10`; the three spare columns are now on the *other* side, over the
--- bus platforms, where a player can extend into them.
---
--- **-15 is also the largest shift that works**, which is worth knowing before
--- anyone tries to centre the platform on the concourse more neatly. The
--- entrance reserves `x = -8 .. 8` by `y = -30 .. -15`, and a slot whose origin
--- is *inside* that rectangle cannot keep any reservation at all - no single cut
--- leaves one containing the origin - so it is zeroed, and a track module that
--- loses its rectangle can never be removed again (see "Round thirteen" in
--- NOTES.md). At `y = -15` the origin sits exactly **on** the boundary, which
--- the epsilon in `clipFootprint` treats as outside, so the column keeps a
--- 5 x 2.5 m strip to be picked by. At `-17.5` or `-18` it would not.
local RAIL_SHIFT_Y = -15.0

local RAIL_XF = transf.mul(
	transf.transl(vec3.new(0.0, RAIL_SHIFT_Y, PITCH)),
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

	-- **The concourse is seeded**, at the one slot the engine will offer.
	--
	-- Asked 2026-10-21: *"Am I correct to assume that the concourse was not
	-- added by default? If so, you may do that in the single location where I
	-- can actually build it."* Correct, and it is now. The id is the entrance's
	-- slot id with its variant digits cleared, which is exactly what
	-- `addArchSlots` hands out for the entrance seeded above.
	--
	-- It was *un*seeded on 2026-10-12, in round six, when module removal broke
	-- while a concourse was in the build. Round seven then found the real cause -
	-- reservations zeroed to nothing - and rounds nine to twelve rebuilt the slot
	-- so the concourse is picked from a clear band at its pier instead of over
	-- the entrance. Seeding is worth having back because the concourse is what
	-- gives either level a catchment of its own: without one a fresh station
	-- falls back to a default and warns about it.
	--
	-- Two things it re-exposes, both with a log line of their own:
	--
	-- - a **seeded** module's geometry is checked against the *world* when the
	--   construction is placed, where a player-added one is only checked against
	--   the construction (root `NOTES.md`, "A seeded module's geometry is checked
	--   against the world at placement"). So placing the station snapped to a
	--   road is the test, not placing it in free space: the check now meets a
	--   24 x 6 m cell, and what has to clear the road is the hole in it.
	-- - round six's symptom was removal, so removing a module while a concourse
	--   is in the build is the other test. The session that passed T5a never did
	--   it: the concourse went in last and nothing was deleted afterwards.
	--
	-- Deleting the one line below puts it back the way it was.
	seeded[ARCH_SLOT_BASE + streetMangle(55, 0, 0)] = CONCOURSE_ARCH_MODULE

	log.message(LOG .. "seeded: rail " .. tostring(tiles) .. " tiles ("
		.. tostring(tiles * 40) .. " m, era " .. era .. ")"
		.. " + 1 bus platform + entrance + 1 concourse arch, no station building"
		.. " on either level")
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

--- Hand rail's construction-level models back to the rail family.
---
--- A rail *module* writes into the merged result, and nearly all of them open
--- with `result = result.cargoStation` (`modules.script.lua:75`), so their
--- geometry lands in rail's own subconstruction and the lift finds it. One does
--- not. `trainstationutil.makeTrack` is handed the construction result and
--- writes, once per track tile:
---
---     result.models[#result.models + 1] = {
---         id = "/stations/rail/era_a/tn_underground_connection.mdl",
---         transf = transf.mul(transform, transf.transl(vec3.new(0, 0, 0))),
---         tag = tag,
---     }                      -- trainstationutil.lua:38
---
--- In stock that is harmless: rail's hook copies **every** construction-level
--- model into its own subconstruction (`modular_station.script.lua:1341`) and
--- only then calls `addLaneLists`, which builds the model's person lanes there.
--- Here the construction-level lists are *street's* - see `STREET_LEVEL_LISTS`
--- for why they have to be - so rail's hook never sees the model, and street's
--- hook buckets it into tag 2 and builds its lanes at grade instead.
---
--- `tn_underground_connection.mdl` is the rail station's pedestrian underpass:
--- eight lane nodes at z = -7, the tunnel that joins the foot of one platform
--- stair to the next. It is the only entry in the whole of
--- `legacytransportnetworks.lua` with lane nodes that deep that is not part of
--- an airport, which is why `z -7.0: 288 node(s) in 36 lane(s)` turned up under
--- a station with 36 tracks: 36 x 8, one per tile.
---
--- So the upper level's walkable network was cut at the foot of its own stairs.
--- Rail's own lanes stop at z = 5.0 - the stair feet, -7 lifted by 12 - and the
--- tunnel that should carry on from there was left at grade, in the other
--- family, twelve metres below. Nothing could cross, in either direction and
--- for neither passengers nor freight. That is what `0 node(s) shared between
--- the levels` and a train that will not unload have in common.
---
--- Moving the **model**, rather than its lanes, is what makes the rest fall
--- out: rail's hook absorbs it, `addLaneLists` builds the lanes in rail's
--- subconstruction, `liftRail` raises them with everything else, and street
--- never builds its copy at all.
---
--- Must run **before** either hook. The window is between the module pass,
--- which is what puts the model there, and street taking that list by
--- reference.
---
--- Matched on the `/stations/rail/` prefix rather than on the one file name, so
--- that any other rail model reaching construction level is moved too and named
--- in the log. Our own supports (`multi_layer_stations_1::/`) and street's
--- geometry do not match, and stay at grade.
local function moveRailModelsToRail(streetResult, railResult)
	local prefix = "/stations/rail/"
	local models = streetResult.models
	if models == nil then return end

	local kept, taken, names = {}, {}, {}
	for _i, m in ipairs(models) do
		local id = type(m) == "table" and m.id or nil
		if type(id) == "string" and string.sub(id, 1, #prefix) == prefix then
			taken[#taken + 1] = m
			names[id] = (names[id] or 0) + 1
		else
			kept[#kept + 1] = m
		end
	end

	if #taken == 0 then
		log.message(LOG .. "no rail models at construction level, so there is"
			.. " nothing to hand back to the rail family. If the upper level's"
			.. " person network still stops at the foot of its stairs, look for"
			.. " a rail module writing somewhere other than `result.models`.")
		return
	end

	-- Rewritten in place. The merged result and the street family point at this
	-- same table, and street's hook is about to take it by reference.
	for i = #models, 1, -1 do models[i] = nil end
	for i = 1, #kept do models[i] = kept[i] end

	railResult.models = railResult.models or {}
	for _i, m in ipairs(taken) do
		railResult.models[#railResult.models + 1] = m
	end

	local detail = {}
	for id, n in pairs(names) do
		detail[#detail + 1] = id .. " x" .. tostring(n)
	end
	table.sort(detail)
	log.message(LOG .. "moved " .. tostring(#taken) .. " rail model(s) off the"
		.. " construction level into the rail family, leaving "
		.. tostring(#kept) .. ": " .. table.concat(detail, ", ")
		.. ". A rail module added them through the merged result, which shares"
		.. " street's lists, so street would have bucketed them into its tag 2"
		.. " subconstruction and built their person lanes at grade. The"
		.. " underpass belongs 12 m up, joined to the stair feet at z = 5.")
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

--- The placeholder block: `support_block.mdl`, shipped with this mod.
---
--- A solid 1 m cube of stone, centred on its own origin, whose **collider is
--- exactly its mesh**. That file carries the full reasoning; both of those
--- properties are load-bearing here.
---
--- *Solid*, because the piece this mod drew for three rounds - the stone
--- bridge abutment, `stone_abut_rep_rep.mdl` - turns out to draw **two
--- parallel planes and nothing else**: 4 triangles across 2 faces, read out of
--- its vertex buffer with `tools/meshfaces.py`. Its `boundingInfo` says
--- 4.43 x 4 x 2 and its geometry is two sides of that box, 3.43 m apart. So
--- every version of the supports was an envelope made of flat faces, which is
--- what kept being reported from the game, and filling the volume with more of
--- the same could not have fixed it.
---
--- *Collider equals mesh*, because that is what lets a block stand flush in its
--- cell. The abutment's collider reached 0.70 m past its own geometry at a full
--- tile, and compensating for that was the whole of `fitSpan`, `SUPPORT_TILE`,
--- `tileCount` and the doubled-up "twin" copies - all gone with it.
---
--- One instance fills any box: scale by the box's size, translate to its
--- centre. A support is six models now rather than a hundred and forty-four.
local SUPPORT_BLOCK = "multi_layer_stations_1::/support_block.mdl"

--- How wide one panel of the block is drawn, across x and across y.
---
--- Added 2026-10-26, when a loading block finally showed what its UVs do: one
--- face of the cube is one fixed 0.25 x 0.333 crop of the material, and the
--- model's scale does not touch UVs, so a 40 m hall wall drawn as one instance
--- stretched that crop 20 to 1. Cutting the box up is the only thing that
--- changes the ratio of a face's metres to its texels - no material setting
--- can, because `texCoordScale` multiplies both axes at once.
---
--- 4 m is a cost choice as much as a look one, since the piece count is the
--- product of all three cuts: a 40 x 6 x 10.7 hall wall is 20 blocks at 4 m
--- against 5 before. The only thing that must not change is that the slices
--- land exactly on the box's own bounds, which `sliceCount` guarantees.
local SUPPORT_PANEL = 4.0

--- How tall one course of the block is drawn: the panel width times 4/3.
---
--- Not a free number any more. The crop a face samples is 0.25 of the texture
--- across by 0.3333 up, so on a square texture it is 0.75 as wide as it is
--- tall, and a face shows it undistorted only when its own width is 0.75 of its
--- height. At a 4 m panel that is a 5.33 m course, and the stone stops being
--- stretched in either direction.
---
--- It was 2 m until 2026-10-27, from back when the block carried masonry and
--- courses were meant to read as courses. Against a 4 m panel that is a 2.7:1
--- stretch, which is most of what was left of the smear.
local SUPPORT_COURSE = SUPPORT_PANEL * 4.0 / 3.0

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
--- **one per deck tile**, so a support is the same length as the platform or
--- track module it holds up.
--- `SUPPORT_TYPE` and `SUPPORT_SLOT_BASE` are declared at the top of the file,
--- because the module classifier needs them.
---
--- It was five cells of 7.8 m per tile until 2026-10-22, so that a player could
--- wall off some spans and leave others open for a road underneath. Reported
--- from the game: *"The supports are pretty short. You need five of them to
--- fully support a single platform module. And these five supports do not fully
--- cover the length of the platform module, there still is a small gap between
--- them."* Both halves are right, and the second is not fixable at that size:
--- the gaps are `SUPPORT_SEAM` either side of each cell plus the metre the
--- rail slot's own 39 m reservation leaves in a 40 m tile, so five cells carry
--- five gaps.
---
--- One cell per tile, sized to the **tile** rather than to the reservation,
--- leaves one 0.2 m seam between neighbours and nothing else. The cost is
--- granularity: a road under the deck now needs a whole tile left unsupported
--- rather than a 7.8 m slice, which is the trade the report asks for.
local DECK_TILE = 40.0

--- The slot types that make up the deck itself, as opposed to the things that
--- stand on it.
---
--- Read in two places, which is why it is up here with the constants: these
--- are the slots that get one tile-length support each, and a block in one of
--- them is a gap in the deck, which is what `dropUnreservableRailSlots`'
--- second pass refuses to build past. A block in a roof or a building slot is
--- just that slot.
local DECK_SLOT_TYPES = {
	track = true,
	passenger_platform = true,
	cargo_platform = true,
}

--- How finely a support cell is subdivided under things that are **not** deck
--- tiles - the station buildings, whose footprints are 11, 20 and 37 m deep.
--- A deck tile gets `DECK_TILE` in one piece instead.
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
--- `childId` is reached **through** `parentId`: the second half of stock's
--- stacked-slot idiom.
---
--- `result.dependentSlots[a] = { b, ... }` is how the rail station pairs a
--- platform with the roof and addon slots sitting on top of it
--- (`modular_station.script.lua:567-612`): those two have `spacing =
--- {0,0,0,0}`, so they have no ground of their own to be clicked on, and the
--- player reaches them by clicking the platform. It is a field of the
--- `Construction` component, not a Lua convention - the engine reads it and
--- saves it.
---
--- Round eight implemented the first half of that idiom (a slot stacked over
--- an occupied one) and not this half, and round ten is what it cost. Keyed by
--- the parent, so each parent carries a list; appending rather than assigning
--- keeps rail's own pairs, because `shareLists` hands the merged result rail's
--- table itself.
local function dependSlot(result, parentId, childId)
	result.dependentSlots = result.dependentSlots or {}
	local list = result.dependentSlots[parentId]
	if list == nil then
		list = {}
		result.dependentSlots[parentId] = list
	end
	for _i, id in ipairs(list) do
		if id == childId then return end
	end
	list[#list + 1] = childId
end

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

			-- A deck tile gets exactly one support, the length of the tile.
			-- `DECK_TILE` rather than `depth`, which is the slot's 39 m
			-- reservation: sizing to the reservation would leave the spare
			-- metre of every tile as a gap between neighbouring supports, and
			-- a continuous support under the deck is the whole point of the
			-- change (see `DECK_TILE`). The cell stays centred on the slot,
			-- because a platform tile's reservation is symmetric.
			local deckTile = DECK_SLOT_TYPES[tostring(slot.type)]
			if deckTile and width > 0.0 and depth > 0.0 then
				depth = DECK_TILE
			end

			-- At most 9 cells, because the slot id packs the cell index into one
			-- decimal digit.
			local cells = 0
			if width > 0.0 and depth > 0.0 then
				cells = deckTile and 1 or math.max(1, math.min(9,
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
		-- Support ids only: both concourse layers live above `ARCH_SLOT_BASE`.
		-- The arch is derived from an entrance rather than from the rail level,
		-- so it is not orphaned by this; the hall rows **are** bounded by the
		-- deck, and `addHallSlots` reports its own orphans for that reason.
		if type(slotId) == "number" and slotId >= SUPPORT_SLOT_BASE
			and slotId < ARCH_SLOT_BASE and not have[slotId] then
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

--- How much of its cell a placeholder leaves clear on every side, and now the
--- **only** inset there is.
---
--- 0.1 m leaves 0.2 m between two neighbours: enough that no two cells share a
--- face, little enough that a row of supports reads as continuous. The block
--- fills everything else, so a 5 m platform cell draws 4.8 m of stone.
---
--- It was 0.5 m plus a collider allowance until 2026-10-13, which together cost
--- 2 m of that cell. Both are gone, for different reasons: the allowance
--- because `support_block.mdl`'s collider **is** its mesh, so there is no
--- overhang left to buy off, and the half metre because the case for it never
--- held up - round three read the old piece's overhang as the reason a support
--- could be placed and not removed, rounds four to six could still remove
--- nothing, and round seven fixed removal by clipping the **reservations**.
---
--- 0.1 m until 2026-10-22, when a tile-length support made the arithmetic
--- visible: two neighbours each give up a seam, so the deck carried a 0.2 m
--- line of daylight at every tile boundary and beside the concourse, which uses
--- the same constant. Reported as *"a tiny gap between the supports and also
--- between the supports and the concourse - less than 1m but it's definitely
--- there"*, and 0.2 m is what it was.
---
--- 0.02 m is below anything the camera resolves and still **not zero**, which
--- is the point: the cells tile exactly at a 40 m pitch, so a zero seam would
--- leave two colliders meeting at a shared plane and any float error there is
--- an overlap rather than a gap. 4 cm of air per boundary buys that away for
--- nothing visible.
local SUPPORT_SEAM = 0.02

--- How thick a placeholder wall is: 1 m, or less in a cell too small for that.
local function wallThickness(width, depth)
	return math.min(1.0, width * 0.4, depth * 0.4)
end

--- Does `SUPPORT_BLOCK` resolve? Logged once, because the alternative is
--- silent.
---
--- This is the first resource this mod ships rather than borrows from the base
--- game, and an id the engine cannot find is drawn as a missing-model cube or
--- as nothing, with no complaint in the log (root NOTES.md: "A model silently
--- becomes a placeholder"). `_content.json` lists the file and the id is
--- `<modId>::/<file>`, the same shape the modules use; if that turns out to be
--- wrong, this line is the difference between knowing and guessing.
---
--- `api.res.modelRep` may not be reachable from every thread the module pass
--- runs on, so a failed *call* is reported as "unknown" rather than as a
--- missing model - the same caution `moduleMetadata` takes.
---
--- **And in practice it is never reachable here.** Every session logs
--- `could not ask (api.res.modelRep unavailable here)`, so this check has never
--- answered the question it was written for - it did not catch the model being
--- thrown away for a mod-relative resource path, which cost ten days of
--- looking at the engine's placeholder and calling it our art.
---
--- The authoritative evidence is the **importer's own warning at load**, which
--- names the file and the resources it could not find:
---
---     The following 1 models were removed because they reference an invalid
---     resource: * multi_layer_stations_1::/support_block.mdl ...
---
--- So grep the log for `were removed because` after changing any `.mdl`, and
--- treat this line as a courtesy rather than as a gate.
local blockChecked = false
local function checkBlock()
	if blockChecked then return end
	blockChecked = true
	local ok, idx = pcall(function()
		return api.res.modelRep.find(SUPPORT_BLOCK)
	end)
	if not ok then
		log.message(LOG .. "placeholder model " .. SUPPORT_BLOCK
			.. ": could not ask (api.res.modelRep unavailable here)")
	elseif idx == nil or idx < 0 then
		log.warning(LOG .. "placeholder model " .. SUPPORT_BLOCK
			.. " does not resolve - the supports and the concourse will draw"
			.. " nothing, or a missing-model cube. Check that _content.json"
			.. " lists support_block.mdl and that the mod id matches.")
	else
		log.message(LOG .. "placeholder model " .. SUPPORT_BLOCK
			.. " resolves (index " .. tostring(idx) .. ")")
	end
end

--- One solid block filling `x0..x1` by `y0..y1` by `z0..z1`, exactly.
---
--- The whole of the geometry now. `SUPPORT_BLOCK` is a unit cube centred on its
--- own origin with a collider to match, so a box is one instance: scale by the
--- size, translate to the centre, no rotation, no tiling, no twin, nothing to
--- compensate for. What is asked for is what is drawn and what the engine
--- thinks is there.
---
--- **No rotation, and that is a result rather than an omission.** Varying a
--- quarter-turn with the piece's place in the grid was tried on 2026-10-26, to
--- stop one crop of the texture repeating in rows. Reported from the game:
--- *"The texture looks worse than before. It appears there is some kind of
--- texture indexing problem since the rows are all translated in a stepped
--- fashion."* Which is exactly what it was. The four side crops of the concrete
--- are near enough identical in albedo - 3.4 of 255 mean absolute difference,
--- measured - but **13.8 in the normal map**, and a quarter-turn turns the
--- normal map with the piece, so neighbouring panels catch the sun differently
--- and the stretch runs across one and up the next. The turn count stepped by
--- one along a row and by three up a course, so the mismatch stepped
--- diagonally. Every piece laid the same way is a flat, continuous surface; it
--- is the variation that reads as a defect.
local function stoneBox(models, x0, x1, y0, y1, z0, z1)
	local w, d, h = x1 - x0, y1 - y0, z1 - z0
	if w <= 0.0 or d <= 0.0 or h <= 0.0 then return end
	checkBlock()
	models[#models + 1] = {
		id = SUPPORT_BLOCK,
		transf = transf.scaleXYZRotZTransl(vec3.new(w, d, h), 0.0,
			vec3.new((x0 + x1) * 0.5, (y0 + y1) * 0.5, (z0 + z1) * 0.5)),
	}
end

--- How many equal slices of `pitch` a span of `size` is cut into. At least one,
--- and rounded rather than floored so the slices land exactly on both ends.
local function sliceCount(size, pitch)
	return math.max(1, math.floor(size / pitch + 0.5))
end

--- The same box, cut into panels, so no face is stretched.
---
--- It used to cut in z only, in courses, which left a hall wall drawn as a
--- single 40 m x 2 m instance - one face, one crop, stretched 20:1. That is the
--- whole of *"the textures all look terrible"*, and the thing to understand
--- about it is that no material setting can undo it: the cube's UVs are fixed,
--- the model's scale does not touch them, and `texCoordScale` would multiply
--- both axes and so keep the ratio. Only the geometry can change it, by being
--- cut until a face is the shape of the crop it samples - 0.75 as wide as it is
--- tall, which is what `SUPPORT_COURSE` is derived from.
---
--- So the cut is in all three axes, every piece laid the same way up (see
--- `stoneBox`), and the price is the piece count, which is the product of the
--- three: `blocks` on the `support draw:` line is there to keep it visible.
local function stoneFill(models, x0, x1, y0, y1, z0, z1)
	local w, d, h = x1 - x0, y1 - y0, z1 - z0
	if w <= 0.0 or d <= 0.0 or h <= 0.0 then return end
	local nx = sliceCount(w, SUPPORT_PANEL)
	local ny = sliceCount(d, SUPPORT_PANEL)
	local nz = sliceCount(h, SUPPORT_COURSE)
	local px, py, pz = w / nx, d / ny, h / nz
	for i = 0, nx - 1 do
		for j = 0, ny - 1 do
			for k = 0, nz - 1 do
				stoneBox(models,
					x0 + px * i, x0 + px * (i + 1),
					y0 + py * j, y0 + py * (j + 1),
					z0 + pz * k, z0 + pz * (k + 1))
			end
		end
	end
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

--- The models a support module draws: a **solid** brick block standing on its
--- cell, from the ground to the underside of the level above.
---
--- Sized from the slot it was placed in rather than fixed, so one module serves
--- a 5 m platform span and a 15 m building footprint alike. `spacing` on a
--- support slot is symmetric by construction, so the cell is
--- `[-w/2, w/2] x [-d/2, d/2]`, and the block fills it as closely as the
--- collider allowance permits - `SUPPORT_SEAM` and `SUPPORT_TILE` are what make
--- that close rather than cautious.
---
--- **Solid since 2026-10-13, and the two versions before it were both wrong in
--- the same way.** It was four walls on the cell outline, which was already the
--- second attempt: the first laid every piece unrotated, so the "sides" were
--- more x-facing slabs rather than walls along y, and the footprint was right
--- while the thing drawn in it bore no relation to it. The four walls fixed
--- that and left a hollow box, defended at the time as "12 m of masonry reads
--- as a block rather than a support, and the inside of a closed box cannot be
--- seen".
---
--- Both of those are aesthetic arguments about a stand-in, and they cost the
--- one thing the stand-in is for. Reported from the game: *"I see parallel faces
--- that suggest the total shape of the envelope, not a full solid shape."* That
--- is the hollow box seen from outside - two wall faces with a void between
--- them - and a modder reading it cannot tell whether the real art has 1 m to
--- work in or 5. A solid block cannot be misread, so the volume is filled and
--- the aesthetics are left to whatever replaces it.
---
--- It is also **cheaper**, which is worth saying because the opposite is the
--- intuition: the four walls each paid for their own tiling and for a second
--- copy turned 180 degrees, and drew every corner twice. This is six boxes.
local function supportModels(width, depth)
	local models = {}
	local w = math.max(width - 2.0 * SUPPORT_SEAM, 0.0)
	local d = math.max(depth - 2.0 * SUPPORT_SEAM, 0.0)

	stoneFill(models, -w * 0.5, w * 0.5, -d * 0.5, d * 0.5, 0.0, PITCH)
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
--- The piece is a unit cube whose collider is its mesh, so its corners are
--- `+-0.5` in each axis and measuring the mesh measures the collider. That is
--- the whole reason this is now a sanity check rather than a compensation: a
--- `drawn` bigger than `cell` means a bug here, not a property of the art.
local function drawnExtent(models)
	local x0, x1, y0, y1 = math.huge, -math.huge, math.huge, -math.huge
	local corners = {
		{ -0.5, -0.5, 0.0 }, { 0.5, -0.5, 0.0 },
		{ -0.5, 0.5, 0.0 }, { 0.5, 0.5, 0.0 },
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
	return 5.0, DECK_TILE
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
--- One deck tile wide: 40 m, the length of a platform or track module.
---
--- The number has been worked out three times, from the inside out, and only
--- the last one comes from the deck:
---
---  * **20 m**, measured off the entrance module's ground face at x in [-5, 5].
---    That face is the 10 m carriageway, not the road: `entrance_new.street_template`
---    declares lanes of `width = 3, 5, 5, 3` - **16 m**, a 10 m carriageway with
---    3 m sidewalks - so 20 m left the legs 2 m clear of the road, standing on
---    the shoulder.
---  * **24 m**, which put them at x = +-12, 4 m clear of the road edge. Correct
---    and still too narrow to read as part of the structure: reported from the
---    game 2026-10-22, *"The concourse building also is a bit too narrow. They
---    need to be about 1 (current) support width wider at both ends so they
---    also align with the length of a platform or track module."*
---  * **40 m**, which is that request and `DECK_TILE` at the same time - one
---    support width was 7.8 m, and 24 + 2 * 7.8 is 39.6. Taking the tile
---    exactly means the concourse ends where the module above it ends, and the
---    supports either side of it line up with both.
---
--- The legs end up 20 m from the entrance centre, 12 m clear of the 16 m road,
--- which is clearance to spare rather than a constraint. What the extra width
--- does cost is **placement footprint**: the concourse is seeded, so its
--- geometry is checked against the world (root `NOTES.md`), and this is now
--- 40 m of it at the street frontage.
local CONCOURSE_W = DECK_TILE

--- The opening the entrance road passes through, between the piers.
---
--- This is `CONCOURSE_W`'s old value, and it is now its own number because
--- widening the cell to a deck tile widened the **hole** with it - the piers
--- stand on the cell's edges, so they went from x = +-12 to x = +-20 and the
--- road got 16 m of gap it has no use for. Reported from the game the same day:
--- *"The entrance for the road now is too wide. The old entrance size was
--- perfect."*
---
--- So the two numbers are separated. The span is what the road needs: piers at
--- +-12, an opening of 21.8 m between the stonework, which is the geometry that
--- was there before. Everything between the span and the cell edge is **filled
--- solid, full height**, so the extra width at each end reads as the support it
--- is the size of - which is what asking for "one support width wider at both
--- ends" means once the piers stay put.
local CONCOURSE_SPAN = 24.0

--- The hall's opening: none.
---
--- Zero is a real value here rather than a missing one - `concourseModels`
--- reads it and fills the cell instead of standing two piers - and it is the
--- only geometric difference between the two variants. Named so that the
--- module entry point says what it means.
local CONCOURSE_HALL_SPAN = 0.0

--- How high a hall's own footway stands, in metres: a street kerb.
---
--- 0.3 is where every piece of stock pedestrian geometry is.
--- `models/pedestrian_era_a/straight.mdl` - one 5 m piece of the perron that
--- rings the bus platforms - declares
--- `metadata.transportNetworkProvider.laneLists[1]` with both its nodes at
--- `z = 0.3`, and so does the station's sidewalk, because that is the height of
--- a street kerb in this game. Walking from a road onto a station is then
--- level, which is the whole point.
---
--- This has been both values in one day, and the round trip is the useful part.
--- It went to **grade** when the first run reported *"they do spawn little
--- hills in the terrain the pedestrians have to climb"* - 30 cm of hill, one per
--- hall, which is this constant exactly. The connection the engine generates
--- from a `linkable` lane is a real path edge, and a path edge pulls the terrain
--- up to meet its ends, so a node 30 cm over open ground is a node the ground
--- comes up to.
---
--- It came back, with the geometry it should have had from the start: *"If the
--- stock stations use 30cm to match the kerbs of streets, that's what we should
--- use too. Can you include a 30cm tall walkway in the generated mesh?"* Which
--- is the difference between ours and the perron's, and it was never the number
--- - a perron node's 0.3 is **the top of a kerb the model carries**, and ours
--- carried nothing. `concourseModels` now lays a `CONCOURSE_WALK_D` wide
--- walkway this tall along the hall's road-facing face, and the footway rides
--- on it.
---
--- So the lane and the stone agree, and the kerb the engine's path climbs is a
--- kerb rather than a hillside. Whether that is enough to settle the terrain is
--- a question for the run: if the ground still rises where the generated path
--- crosses unaligned grass between the road and the kerb, the lever left is a
--- terrain alignment face under the cell - stock's own answer, and an open
--- question in `../NOTES.md` already, because a 40 m block on a slope has the
--- same problem with or without a footway.
local CONCOURSE_WALK_Z = 0.3

--- How wide the hall's walkway is, in metres, measured in from its road-facing
--- face.
---
--- 2 m of the cell's 6, which leaves a 4 m deep building. A pavement rather
--- than a plaza: wide enough that the footway runs down the middle of it with a
--- metre either side, narrow enough that the hall still reads as a building
--- with a kerb in front of it instead of a kerb with a wall behind it.
---
--- Taken out of the cell, not added to it. Everything this module draws stays
--- inside its own 40 x 6 m, collider included, for the reason `concourseModels`
--- gives: the geometry is present when the engine checks placement against the
--- world, and this cell is already as deep as the entrance road will allow
--- (`CONCOURSE_D`).
local CONCOURSE_WALK_D = 2.0

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
--- 6 m centred at -3 covers y = 0 .. -6, leaving 4 m of clearance - and the
--- art is drawn a seam inside that, so the clearance is real. It also
--- happens to be where the concourse belongs: the elevated deck is one platform
--- and one track wide, so it crosses the entrance road close to the station
--- edge, not out at the kerb.
local CONCOURSE_D = 6.0

--- How deep the concourse's deck slab is, at the top of the structure.
---
--- The slab is what makes the placeholder show its **whole** footprint: the
--- piers only ever stand at the two ends, and 24 x 6 m is the envelope a
--- modder replacing this art has to work in. Putting it at the top rather than
--- at grade is not a compromise, it is what a concourse is - the road passes
--- underneath, and filling the footprint at ground level would wall it off and
--- put placeholder brick in the carriageway.
---
--- Half the level, so the structure reads as a mass carried on two piers rather
--- than as a lid on legs - the same reason the supports are solid rather than
--- hollow. It leaves **6 m of headroom** over the road underneath, which is
--- more than the stock street templates ask for, and the piers are 6 m tall.
local CONCOURSE_DECK = PITCH * 0.5

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

--- Where a concourse slot's origin sits, along the entrance's local x, and how
--- much ground it claims either side of it.
---
--- **This is the whole reason a concourse can be placed, measured over four
--- sessions on 2026-10-12/13.** The engine offers an empty slot only where its
--- reservation holds ground that no **occupied** slot is holding, and at the
--- entrance almost none of our cell qualifies: the three entrance variants
--- reserve out to x = +-8 and the `large_building` slot at the same transform
--- to +-10 (`modular_terminal.script.lua:2580-2584`), while the concourse cell
--- is only 24 m wide. x = 11 with a metre either side is the band from 10 to
--- 12 - inside our own cell, clear of every stock rectangle there, occupied or
--- not - and it is the one shape that has ever been offered on the entrance.
---
--- What was tried and is ruled out, so none of it gets re-tried:
---
---  * the full 24 x 6 m cell centred on the entrance: **no pip**, three
---    sessions running;
---  * the same cell with its origin moved onto this band: no pip either. It is
---    the rectangle that is filtered, not the origin;
---  * `spacing = {0,0,0,0}` plus `dependentSlots[entrance]`, which is exactly
---    what stock does for a platform roof: no pip, in a session whose log
---    proves the entry reached the engine. Side by side with this band in the
---    same build, the band took the module four times and the zero never did.
---
--- The cost is a 2 m x 6 m target at one pier instead of the whole span, and
--- the pip sits there rather than in the middle of the concourse. The art does
--- **not** move with it: `concourseModels` is handed `-CONCOURSE_FLANK` so the
--- piers still straddle the road, and `applyConcourse` puts the catchment back
--- over the entrance too. Those two compensations are not cosmetic - without
--- them a pier stands in the carriageway, which is what the probe looked like.
local CONCOURSE_FLANK = 11.0
local CONCOURSE_FLANK_HALF = 1.0

--- Where each variant's **cell centre** sits in its slot's own frame, along the
--- slot's local x.
---
--- The arch's slot origin is out on the flank, because that is the only ground
--- at an entrance the engine will offer, so everything that wants the middle of
--- the building - the art, the catchment circle - has to undo that offset. A
--- hall's origin *is* its cell centre, so its entry is zero. Two call sites
--- read this, and before it existed they each carried `-CONCOURSE_FLANK` as a
--- literal, which is not a number a second variant can share.
local CONCOURSE_CELL_OFFSET = {
	[CONCOURSE_ARCH_TYPE] = -CONCOURSE_FLANK,
	[CONCOURSE_HALL_TYPE] = 0.0,
}

--- The ground an **arch** occupies, as four distances from its slot's origin -
--- which is not its centre.
---
--- Deliberately not the same thing as the slot's `spacing` any more: that is
--- what the engine is told the slot claims (a 2 m band, all it will accept),
--- while this is the 24 x 6 m the piers actually stand in. The overlap
--- diagnostic needs the second one or it goes quiet about exactly the module it
--- was written for, and `slotBox` reads the centre back out of the asymmetry,
--- so the `CONCOURSE_FLANK` offset has to be in here too: left `11 + 12`,
--- right `12 - 11`.
---
--- A hall needs no equivalent: its reservation already *is* its cell, which is
--- the one simplification of being offered away from an entrance.
local function archCell()
	return { CONCOURSE_W * 0.5 + CONCOURSE_FLANK,
		CONCOURSE_W * 0.5 - CONCOURSE_FLANK,
		CONCOURSE_D * 0.5, CONCOURSE_D * 0.5 }
end

local function archSlot(id, entranceTransf)
	return {
		id = id,
		-- The entrance's own frame, shifted along its local -y, which is the
		-- direction its road runs in every orientation the street station
		-- emits - including the pi-rotated "top" entrances and the
		-- quarter-turned vertical ones - and out along its x to the band that
		-- can actually be clicked.
		transf = transf.mul(entranceTransf, transf.transl(vec3.new(
			CONCOURSE_FLANK, -CONCOURSE_D * 0.5, 0.0))),
		spacing = { CONCOURSE_FLANK_HALF, CONCOURSE_FLANK_HALF,
			CONCOURSE_D * 0.5, CONCOURSE_D * 0.5 },
		type = CONCOURSE_ARCH_TYPE,
		replaceable = true,
	}
end

local function addArchSlots(result, streetResult, modules, allModules)
	local seen = {}
	local added = 0
	for _i, slot in ipairs(streetResult.slots or {}) do
		if ENTRANCE_SLOT_TYPES[slot.type] and slot.transf ~= nil
			and modules[slot.id] ~= nil then
			local id = ARCH_SLOT_BASE + slot.id - (slot.id % 100)

			-- The concourse belongs to its entrance, so it goes when the
			-- entrance goes. Declared per occupied entrance variant, outside
			-- the `seen` guard; the slot itself is created once per position.
			--
			-- This is the removal cascade **only**. It was added as the way to
			-- make the slot clickable, on stock's roof-slot idiom, and measured
			-- not to be: a slot the engine has filtered out is not let back in
			-- by being somebody's dependent (see `CONCOURSE_FLANK`). It stays
			-- because the relationship is real and the engine's alternative is
			-- to orphan the module and drop it with a warning.
			dependSlot(result, slot.id, id)

			if not seen[id] then
				seen[id] = true
				result.slots[#result.slots + 1] = archSlot(id, slot.transf)
				added = added + 1
			end
		end
	end

	result.slotConfig = result.slotConfig or {}
	result.slotConfig[CONCOURSE_ARCH_TYPE] = { skipCollisionCheck = true }

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
		if slot.type == CONCOURSE_ARCH_TYPE then
			-- Three numbers, because they are three different things now: where
			-- the concourse stands, where the slot that offers it is, and how
			-- much ground that slot claims. A reservation that is not 2x6, or a
			-- pick point that is not `CONCOURSE_FLANK` from the cell, is the
			-- slot going back to a shape that was never offered.
			local sp = slot.spacing or { 0, 0, 0, 0 }
			local c = applyMat(slot.transf, { -CONCOURSE_FLANK, 0.0, 0.0 })
			parts[#parts + 1] = string.format(
				"%d cell@(%.1f,%.1f) pick@(%.1f,%.1f) reserves %.0fx%.0f occupied=%s",
				slot.id, c[1], c[2], slot.transf[13], slot.transf[14],
				sp[1] + sp[2], sp[3] + sp[4],
				tostring((allModules or {})[slot.id] ~= nil))
		end
	end
	if #parts > 0 then
		log.message(LOG .. "concourse arch slots "
			.. string.format("%.0fx%.0f: ", CONCOURSE_W, CONCOURSE_D)
			.. table.concat(parts, ", "))
	end
	return added
end

--- The hall row: one cell per deck tile along an entrance's frontage, in the
--- same 40 x 6 m band as that entrance's arch.
---
--- Asked for from the game 2026-10-26: *"The concourse currently sits over the
--- road entrance of the road station. I would like to add another concourse
--- building that doesn't have the tunnel for the road but does have pedestrian
--- connections. It should have the same footprint size as the concourse
--- building so it can be placed next to a concourse building."* So the cell is
--- the arch's cell, moved along the frontage by whole tiles - which is what
--- makes a row of them line up with the arch, with the supports and with the
--- platform modules overhead, all three of which are already on a 40 m pitch.
---
--- **Derived from the entrance, bounded by the deck.** Two different jobs, and
--- it matters which does which:
---
---  * the *frame* is the entrance's, as the arch's is. The row therefore runs
---    along the station frontage in every orientation the street station emits,
---    without this code knowing which way the construction faces, and cell `k`
---    of the row is at the entrance's local `x = k * CONCOURSE_W` by
---    construction rather than by arithmetic;
---  * the *extent* is the deck's. Each occupied deck tile is projected onto
---    that same local x and rounded to the cell pitch, and the row spans the
---    range those projections cover. A hall is a platform's length, so a
---    frontage longer than the deck above it would be a wall with nothing
---    behind it.
---
--- The range is filled in rather than taken tile by tile, and that is
--- deliberate: the deck **cannot** cross the entrance road - the cell over it
--- is withheld, which is the second half of T2's "extend the deck to the
--- entrance" - so going tile by tile would leave a gap in the frontage exactly
--- where the arch is meant to stand. It would also make a hall in the middle of
--- a row vanish the moment the platform above it was replaced. As it is, only
--- shortening the deck at its ends takes a hall's slot away.
---
--- Two cells are refused rather than offered:
---
---  * **tile 0**, which is the arch's own cell. A hall is solid, so putting one
---    where a road passes through would wall off the carriageway;
---  * **any cell within a tile's width of another entrance's cell**, for the
---    same reason, measured in plan between cell centres. A second entrance 40
---    m along the frontage keeps its arch and loses the hall that would have
---    stood on it.
---
--- A cell can still be refused *by the engine* after all that, and the known
--- case is a road the player has already built along the frontage: the module
--- collision check is height-blind and runs after our hook (see the cargo
--- station building in `../NOTES.md`), and a solid building beside a road is
--- exactly the shape that trips it. That is one module refused, not a broken
--- station, and it is in `TESTS.md` as a case to watch rather than something
--- this code can prevent.
local function addHallSlots(result, streetResult, railResult, xf, streetModules,
		railModules, allModules)
	-- The entrances, with the three variants collapsed onto one position - the
	-- same key `addArchSlots` uses, so an entrance's arch and its halls carry
	-- the same entrance id in two different bands. The variants are kept
	-- because the removal cascade is declared per occupied variant.
	local entrances, order = {}, {}
	for _i, slot in ipairs(streetResult.slots or {}) do
		if ENTRANCE_SLOT_TYPES[slot.type] and slot.transf ~= nil
			and streetModules[slot.id] ~= nil then
			local id = slot.id - (slot.id % 100)
			if entrances[id] == nil then
				entrances[id] = { transf = slot.transf, variants = {} }
				order[#order + 1] = id
			end
			local v = entrances[id].variants
			v[#v + 1] = slot.id
		end
	end

	result.slotConfig = result.slotConfig or {}
	result.slotConfig[CONCOURSE_HALL_TYPE] = { skipCollisionCheck = true }

	-- Every occupied deck tile, as a centre in construction space.
	local tiles = {}
	for _i, slot in ipairs(railResult.slots or {}) do
		if DECK_SLOT_TYPES[tostring(slot.type)] and slot.transf ~= nil
			and railModules[slot.id] ~= nil then
			tiles[#tiles + 1] = applyMat(transf.mul(xf, slot.transf),
				{ 0.0, 0.0, 0.0 })
		end
	end

	-- Each entrance's cell centre, which is what a hall cell has to stay clear
	-- of. An arch's cell is centred on its entrance in local x - its slot is
	-- not, which is `CONCOURSE_FLANK`'s whole story - and sits
	-- `CONCOURSE_D * 0.5` back along the road, which is where the band is.
	local blocked = {}
	for _i, id in ipairs(order) do
		blocked[#blocked + 1] = applyMat(entrances[id].transf,
			{ 0.0, -CONCOURSE_D * 0.5, 0.0 })
	end

	local near = CONCOURSE_W - 1.0
	local added, rows, placed = 0, {}, {}
	for _i, id in ipairs(order) do
		local t = entrances[id].transf
		local o = applyMat(t, { 0.0, 0.0, 0.0 })
		-- The entrance's own x axis, which is the direction the frontage runs
		-- in. Already a unit vector: both families build their transforms out
		-- of `rotZ` and `transl` alone.
		local ux, uy = t[1], t[2]

		local kMin, kMax = nil, nil
		for _j, pt in ipairs(tiles) do
			local along = (pt[1] - o[1]) * ux + (pt[2] - o[2]) * uy
			local k = math.floor(along / CONCOURSE_W + 0.5)
			if kMin == nil or k < kMin then kMin = k end
			if kMax == nil or k > kMax then kMax = k end
		end

		local offered, withheld = 0, 0
		for k = kMin or 0, kMax or -1 do
			local centre = applyMat(t,
				{ k * CONCOURSE_W, -CONCOURSE_D * 0.5, 0.0 })
			-- Two entrances can generate rows that overlap in the world, and
			-- two slots at one position would offer the player two buildings
			-- in the same ground. First row wins; the key is the cell centre
			-- to the metre, which is far finer than the 40 m pitch.
			local key = string.format("%.0f|%.0f", centre[1], centre[2])
			local keep = k ~= 0 and math.abs(k) <= HALL_TILE_MAX
				and placed[key] == nil
			if keep then
				for _j, b in ipairs(blocked) do
					local dx, dy = centre[1] - b[1], centre[2] - b[2]
					if dx * dx + dy * dy < near * near then
						keep = false
						break
					end
				end
			end

			if keep then
				local hallId = HALL_SLOT_BASE + id + HALL_TILE_ZERO + k
				result.slots[#result.slots + 1] = {
					id = hallId,
					transf = transf.mul(t, transf.transl(vec3.new(
						k * CONCOURSE_W, -CONCOURSE_D * 0.5, 0.0))),
					-- The cell itself, unlike the arch's 2 m band. There is no
					-- stock rectangle out here for the engine to filter the
					-- reservation against, so the slot can claim the ground it
					-- stands on and be clicked anywhere on it; whatever of that
					-- ground the bus station occupies is taken back by
					-- `clipEmptyOurSlots`, the same way a support's is.
					spacing = { CONCOURSE_W * 0.5, CONCOURSE_W * 0.5,
						CONCOURSE_D * 0.5, CONCOURSE_D * 0.5 },
					type = CONCOURSE_HALL_TYPE,
					replaceable = true,
				}
				placed[key] = hallId
				-- A hall belongs to its entrance exactly as an arch does, so it
				-- goes when the entrance goes. The engine's alternative is to
				-- orphan the module and drop it with a warning.
				for _j, variant in ipairs(entrances[id].variants) do
					dependSlot(result, variant, hallId)
				end
				added = added + 1
				offered = offered + 1
			else
				withheld = withheld + 1
			end
		end

		if kMin ~= nil then
			rows[#rows + 1] = string.format(
				"%d tiles %+d..%+d: %d offered, %d withheld",
				id, kMin, kMax, offered, withheld)
		else
			rows[#rows + 1] = string.format("%d no deck, so no row", id)
		end
	end

	-- Halls whose cell is in no row any more, which means the deck shrank past
	-- them. Reported here rather than in `addSupportSlots`' sweep, which
	-- deliberately stops below `ARCH_SLOT_BASE`: the two layers are orphaned by
	-- different things, and that sweep's "the level above them was removed" is
	-- only half the story here - a hall also goes when its entrance does.
	local have = {}
	for _i, slot in ipairs(result.slots or {}) do
		have[slot.id] = true
	end
	local orphans = 0
	for slotId, _entry in pairs(allModules or {}) do
		if type(slotId) == "number" and slotId >= HALL_SLOT_BASE
			and not have[slotId] then
			orphans = orphans + 1
		end
	end
	if orphans > 0 then
		log.warning(LOG .. tostring(orphans) .. " concourse hall module(s) have"
			.. " no slot any more - either the deck no longer reaches their cell"
			.. " or their entrance is gone. The engine will drop them.")
	end

	if #rows > 0 then
		log.message(LOG .. "concourse hall slots "
			.. string.format("%.0fx%.0f: ", CONCOURSE_W, CONCOURSE_D)
			.. table.concat(rows, "; "))
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
--- extend the catchment to where that entrance actually is - read back through
--- the slot's own frame, because an arch's slot origin is out on the cell's
--- flank (`CONCOURSE_FLANK`) and the catchment belongs over the entrance it
--- serves. Through the frame rather than in world x, so a rotated or mirrored
--- entrance comes out right, and through `CONCOURSE_CELL_OFFSET` rather than
--- through that constant, because a hall's origin is its own cell centre and
--- undoing an offset it does not have would push its catchment 11 m sideways.
---
--- Both variants are swept, which is the whole of what "a hall is a concourse"
--- means in code: same radius, same capacity, and a row of halls extends the
--- catchment along the frontage the way a second entrance extends it sideways.
--- Capacity of the goods store a single concourse module provides - either
--- variant, since a hall declares the same numbers as an arch and is counted by
--- the same sweep.
---
--- A fifth of a warehouse tile's 500 at `loadSpeedModifier` 2.0
--- (`warehouses/modules.script.lua:49`), and at half its load speed. The point
--- of this store is that freight **can** change level at all - two station
--- groups with no shared stock between them cannot exchange anything - not that
--- a station should be a distribution centre. Two concourses make 200, which
--- buffers a train's worth of one cargo and no more; anyone moving real volume
--- should still want a real warehouse next door, and that stays worth building.
---
--- A long frontage therefore multiplies the store, and that is accepted rather
--- than overlooked: a player who lines six halls up along a deck has built six
--- buildings and paid for six, and 600 units is still a third of what one
--- warehouse tile holds.
---
--- Chosen over 250 when asked, 2026-10-22: "keep, but smaller".
local CONCOURSE_STOCK_CAPACITY = 100

--- Give the station a goods store of its own, so freight can change level.
---
--- Freight does not pass from station to station. A station hands cargo to
--- **stock in its own catchment** and takes cargo from stock in its own
--- catchment - `catchmentAreaSystem.getStationCatchables(station, true)` is the
--- engine's own list of what it can reach. Stock is an industry, a town
--- building, or a warehouse.
---
--- Which is the whole reason freight would not cross this station. The probe of
--- 2026-10-22 confirmed the two levels are **two station groups**, one station
--- each (`stationGroupSystem.getStationGroup`), with no API to join them -
--- `cmd.d.tl` has no join or merge command. Both stations were entirely
--- capable, `cargoUnload` true on every terminal with a freight transfer
--- entry; there was simply nowhere between them to put a crate down. The stock
--- answer is to stand a warehouse in the shared catchment, and asked directly,
--- 2026-10-22: *"Is it possible to integrate warehouse functionality in the
--- concourse?"*
---
--- It is, and none of it is new machinery. A warehouse is stock and nothing
--- else - `warehouses/warehouse.script.lua` declares no station, no terminal
--- and no catchment, only
---
---     result.subconstructions[1].stocks     -- :331, STORAGE_STOCK entries
---     result.subconstructions[1].warehouse = { }
---
--- and those two fields are what produce the `STOCK_LIST` and `WAREHOUSE`
--- components (`engine.d.tl:1200`, `:1670`). So a subconstruction of ours can
--- carry them, and it stands inside both levels' catchment by construction.
---
--- `UNIVERSAL` with `mixedTypes` is the universal warehouse's own
--- configuration (`warehouse.script.lua:272-285`), and `UNIVERSAL` is every
--- freight class in the game - so this accepts anything but passengers, which
--- is what a transfer store between a railway and a road should do.
---
--- Attached to the street family's **catch-all** subconstruction, not to either
--- station's. It is the one that already holds the concourse's own geometry, so
--- it has models and therefore a position for the catchment query to find,
--- and putting `STATION` and `WAREHOUSE` on one entity is a combination the
--- base game never ships.
local function addConcourseStock(result, modules)
	local n = 0
	for _i, slot in ipairs(result.slots or {}) do
		local entry = modules[slot.id]
		if CONCOURSE_TYPES[slot.type] and entry ~= nil and type(entry) == "table" then
			n = n + 1
		end
	end
	if n == 0 then return 0, 0 end

	-- Geometry but no station: street's tag 2 bucket. Lowest tag first, so the
	-- choice is stable if another ever qualifies.
	local host = nil
	for _i, sub in ipairs(result.subconstructions or {}) do
		if sub.station == nil and #(sub.models or {}) > 0
			and (host == nil or (sub.tag or 0) < (host.tag or 0)) then
			host = sub
		end
	end
	if host == nil then
		log.warning(LOG .. "no subconstruction with geometry and no station of"
			.. " its own, so the concourse goods store has nowhere to live."
			.. " Freight will not be able to change level here.")
		return 0, 0
	end

	local capacity = CONCOURSE_STOCK_CAPACITY * n
	host.stocks = host.stocks or {}
	host.stocks[#host.stocks + 1] = {
		type = "STORAGE_STOCK",
		cargoTypes = {
			cargoClassesIncluded = { "UNIVERSAL" },
			cargoTypesExcluded = { "::/cargos/passengers/passengers.cargo" },
		},
		mixedTypes = true,
		capacity = capacity,
		loadSpeedModifier = 1.0,
	}
	-- No `loadIndicators`: those are model indices for the crate stacks a
	-- warehouse draws, and the concourse has no crate art. The store works
	-- without them, it just does not show its contents.
	host.warehouse = host.warehouse or {}

	return capacity, host.tag or 0
end

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
		if CONCOURSE_TYPES[slot.type] and entry ~= nil and type(entry) == "table" then
			mine[slot.id] = entry
			local catchment = entry.metadata and entry.metadata.catchmentPassenger
			if catchment ~= nil and catchment.radius ~= nil and slot.transf ~= nil then
				circles[#circles + 1] = {
					position = applyMat(slot.transf,
						{ CONCOURSE_CELL_OFFSET[slot.type] or 0.0, 0.0, 0.0 }),
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

--- What the engine was actually told about each station, in one line.
---
--- Written for the cargo question of 2026-10-22: *"cargo transfer does not seem
--- to be working as expected... I suspect the problem is that there is no cargo
--- pool"*. The result carries no answer to that question anywhere a reader can
--- see it, and the reason is that **nothing marks a station as a cargo
--- station**:
---
--- - `api.type.Station` is `tag`, `terminals`, `catchmentAreas` and `pool`, and
---   nothing else (`api/tealdef/api/type.d.tl:1318`);
--- - `api.type.CatchmentArea` is a position and a radius, so a circle has no
---   kind. `constructionutil.addCatchmentCircles(passengerStation, cargoStation,
---   ...)` reads `catchmentPassenger` and `catchmentCargo` off the modules, but
---   all it decides is *which station record* a circle lands on - and both stock
---   hosts here pass the **same** record for both arguments
---   (`modular_station.script.lua:1359`, `modular_terminal.script.lua:3240`);
--- - the pool is one integer. `metadata.moreCapacity.cargo` is summed by
---   `modulesutil.getStationPoolCapacities`, but no module in the install sets
---   it, rail throws the number away (`capacity = passCap`) and street adds it
---   to the same single `pool.capacity`. There is no second pool to fill.
---
--- What does make a station carry cargo is its **terminals**: each one's
--- `cargoTransferSpeeds` names the cargo classes it can transfer, and
--- `Terminal.cargoLoad` / `passengersLoad` follow from that. So "is this a
--- cargo station?" can only be answered by reading the terminals back out,
--- which is what this does.
local function logStations(result)
	local parts = {}
	for _i, sub in ipairs(result.subconstructions or {}) do
		local st = sub.station
		if st ~= nil then
			-- Over all terminals: which classes appear at all, and how many
			-- terminals can take cargo as opposed to passengers. A terminal can
			-- be both, so the two counts are not a partition of the first.
			-- Per class, the **transfer capability** and not just the
			-- permission: `length` is the length of terminal section serving
			-- that class and `loadSpeedModifier` scales the rate
			-- (`type.d.tl:1297-1304`). The rail host accumulates 40 m per
			-- cargo platform tile and sets the modifier to 1 for UNIVERSAL or
			-- 2 for a typed platform (`modular_station.script.lua:1042-1049`).
			-- A class listed with length 0 is a terminal that accepts the
			-- cargo and can never move a crate of it, which looks from the
			-- cab like a train refusing to unload.
			local seen, classes, lengths, speeds = {}, {}, {}, {}
			local nCargo, nPass = 0, 0
			-- The wait area is what lets anything board at all: `personEdges`
			-- are the lane edges cargo and passengers stand on
			-- (`type.d.tl:1278`), so a terminal with none is a stop a vehicle
			-- can pull up to and nothing can be handed over at. `capacity` is
			-- filled in by `constructionutil.addStationCapacities`, which both
			-- stock hooks call for themselves - but only for terminals whose
			-- own `passengers` flag is set, so a **cargo** terminal with no
			-- capacity is stock's normal and not a finding. It overflows into
			-- the pool, which is shared and untyped.
			local noEdges, cargoNoEdges, edges = 0, 0, 0
			for _j, terminal in ipairs(st.terminals or {}) do
				local cargo, pass = false, false
				for _k, speed in ipairs(terminal.cargoTransferSpeeds or {}) do
					local set = speed.cargoTypeSet or {}
					for _l, class in ipairs(set.cargoClassesIncluded or {}) do
						if not seen[class] then
							seen[class] = true
							classes[#classes + 1] = class
						end
						lengths[class] = (lengths[class] or 0) + (speed.length or 0)
						speeds[class] = speed.loadSpeedModifier or 0
						if class == "PASSENGERS" then pass = true
						else cargo = true end
					end
				end
				if cargo then nCargo = nCargo + 1 end
				if pass then nPass = nPass + 1 end

				local nEdges = #(terminal.personEdges or {})
				edges = edges + nEdges
				if nEdges == 0 then
					noEdges = noEdges + 1
					if cargo then cargoNoEdges = cargoNoEdges + 1 end
				end
			end

			local radii = {}
			for _j, circle in ipairs(st.catchmentAreas or {}) do
				radii[#radii + 1] = string.format("%.0f", circle.radius or 0.0)
			end

			local transfer = {}
			for _j, class in ipairs(classes) do
				transfer[#transfer + 1] = string.format("%s %.0fm x%.3g", class,
					lengths[class] or 0, speeds[class] or 0)
			end

			local pool = st.pool or {}
			parts[#parts + 1] = string.format(
				"tag %s: %d terminal(s), %d taking cargo, %d taking passengers,"
				.. " classes %s; %d catchment circle(s) r=%s; pool capacity %s"
				.. " over %d edge(s); wait areas: %d person edge(s) over the"
				.. " terminals, %d terminal(s) with none (%d of those take cargo);"
				.. " transfer %s",
				tostring(sub.tag), #(st.terminals or {}), nCargo, nPass,
				#classes > 0 and table.concat(classes, "+") or "none",
				#(st.catchmentAreas or {}),
				#radii > 0 and table.concat(radii, "/") or "-",
				tostring(pool.capacity or 0), #(pool.edges or {}),
				edges, noEdges, cargoNoEdges,
				#transfer > 0 and table.concat(transfer, ", ") or "-")
		end
	end
	if #parts > 0 then
		log.message(LOG .. "station records: " .. table.concat(parts, " | ")
			.. ". A station takes cargo only if a terminal's"
			.. " cargoTransferSpeeds say so - the catchment circles and the"
			.. " pool are untyped and serve both. UNIVERSAL is every freight"
			.. " type in the game: each `*.cargo.lua` lists UNIVERSAL plus one"
			.. " of BULK/LIQUID/FLATBED/GOODS, and only passengers sit outside"
			.. " it. So an untyped cargo platform accepts everything a typed"
			.. " one does.")
	end
end

--- Placeholder art: a pier either side of the road, carrying a deck slab that
--- spans the whole cell.
---
--- The slab is there to show the envelope - see `CONCOURSE_DECK`. Below it the
--- footprint is deliberately **open**, because the 16 m entrance road runs
--- through the middle of this cell: the piers sit at x = +-12, which clears
--- `entrance_new.street_template`'s lanes of 3, 5, 5, 3 by 4 m. Measuring
--- against the 10 m carriageway instead left them 2 m clear and on the
--- shoulder, which the engine refused - see `CONCOURSE_W`.
---
--- Everything stays **inside the cell**, collider included, in all three
--- directions, which costs nothing now beyond `SUPPORT_SEAM`: the block's
--- collider is its mesh. That is not tidiness - a module's geometry is present
--- when the engine runs its placement check against the world, and a 10 m deep
--- version of this cell was refused for reaching the road's own snap node (see
--- `CONCOURSE_D`).
---
--- It is a stand-in for the tunnel portal that is the real answer (`PLAN.md`
--- Phase 10 step 3), reusing the support brick - and `brickFill`, so it is
--- solid and finished on every face - so it lines up with whatever supports
--- stand next to it.
---
--- **Both variants are drawn from here**, and `span` is what tells them apart:
--- 24 m of opening for the arch over its road, and zero for the hall, which
--- fills its cell and is the piece a player puts either side of the arch. One
--- function rather than two because they must agree exactly - same cell, same
--- deck thickness, same stone, same seam - and two copies of this arithmetic
--- would drift at the first change.
---
--- `cx` is where the cell's centre is **in the slot's own frame**, and it is not
--- zero: the slot's origin is out on the flank, because that is the only ground
--- at an entrance the engine will offer (`CONCOURSE_FLANK`), while the piers
--- have to straddle the road 11 m away from it. `addModel` draws in the slot's
--- frame, so every x here is measured from the origin, and passing the wrong
--- `cx` does not shift the art a little - it stands a pier in the carriageway.
local function concourseModels(width, depth, span, cx)
	local models = {}
	local w = math.max(width - 2.0 * SUPPORT_SEAM, 0.0)
	local d = math.max(depth - 2.0 * SUPPORT_SEAM, 0.0)
	local t = wallThickness(w, d)
	local hw, hd = w * 0.5, d * 0.5
	-- The opening, a seam inside the span for the same reason the cell is.
	local hs = math.min(math.max(span * 0.5 - SUPPORT_SEAM, 0.0), hw)
	local deck = math.min(CONCOURSE_DECK, PITCH * 0.5)
	cx = cx or 0.0

	if hs <= 0.0 then
		-- The hall: no opening, so no piers. What divides the cell instead is
		-- the **walkway**, 30 cm of stone along the road-facing face with the
		-- building standing behind it - which is what carries the footway's own
		-- height, and is the one thing the perron pieces had that our lanes did
		-- not (`CONCOURSE_WALK_Z`).
		--
		-- The cell's own -y is the road side, because the cell hangs off the
		-- entrance's frame at `-CONCOURSE_D * 0.5`, away from the platforms.
		--
		-- These two fills meet on a shared plane, and that is fine here: a
		-- shared plane is a hazard at a **cell boundary**, where two separately
		-- placed modules and their float error meet, which is what
		-- `SUPPORT_SEAM` buys off. Inside one module's own mesh the courses of
		-- `stoneFill` already share planes by the dozen.
		local walk = math.min(CONCOURSE_WALK_D, d)
		stoneFill(models, cx - hw, cx + hw, -hd, -hd + walk,
			0.0, CONCOURSE_WALK_Z)
		stoneFill(models, cx - hw, cx + hw, -hd + walk, hd, 0.0, PITCH - deck)
	else
		-- The piers flank the **road**, not the cell: they stand on the span's
		-- edges, run the cell's full depth, and stop under the deck.
		stoneFill(models, cx - hs, cx - hs + math.min(t, hs), -hd, hd,
			0.0, PITCH - deck)
		stoneFill(models, cx + hs - math.min(t, hs), cx + hs, -hd, hd,
			0.0, PITCH - deck)
		-- Whatever the cell has beyond the span is solid, full height, so the
		-- ends read as the supports they are the size of and line up with the
		-- real ones either side. With `span == width` there is nothing here and
		-- the piece is what it was before 2026-10-22.
		if hw > hs then
			stoneFill(models, cx - hw, cx - hs, -hd, hd, 0.0, PITCH - deck)
			stoneFill(models, cx + hs, cx + hw, -hd, hd, 0.0, PITCH - deck)
		end
	end
	-- The deck: the whole footprint, at the top, where it reads as a structure
	-- crossing the road rather than a plug in it. This is the piece that shows
	-- the envelope, so it is the one that must not be shaved.
	stoneFill(models, cx - hw, cx + hw, -hd, hd, PITCH - deck, PITCH)
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
				if id >= HALL_SLOT_BASE then
					family = "ours/concourse-hall"
				elseif id >= ARCH_SLOT_BASE then
					family = "ours/concourse-arch"
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

--- What is left of `b` once every obstacle has been cut clear of it, or nil if
--- nothing usable is.
---
--- Pulled out of `trimReservations` so the question "would this slot keep a
--- rectangle?" can be asked **before** a module is in it. That is what
--- `dropUnreservableRailSlots` needs: a slot the answer is nil for must not be
--- offered at all, because filling it produces a module that cannot be removed
--- again.
---
--- `square` is the caller's check that the slot's axes are the construction's,
--- swapped at worst; a slot that fails it cannot have four distances written
--- back, and so dies on its first overlap.
local function clipAgainstAll(b, obstacles, crossOnly, square)
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
	return b, fouled
end

--- Is a rectangle readable as four distances from its own slot's origin?
---
--- Both families build their transforms out of `rotZ` and `transl`, and
--- `RAIL_XF` turns the rail level by 90 degrees, so a slot's axes are the
--- construction's axes swapped at worst. If that ever stops being true, a
--- rectangle has to be zeroed rather than written back as four distances that
--- do not describe it.
local function axisAligned(b)
	return math.min(math.abs(b.u[1]), math.abs(b.u[2])) < RESERVATION_EPS
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
				local b0 = slotFootprint(slot, frameOf(slot))
				local b, fouled = clipAgainstAll(b0, obstacles, crossOnly,
					axisAligned(b0))
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

--- Cuts an **empty** slot of ours clear of occupied stock ground at its own
--- level, so the engine will still offer it.
---
--- `trimReservations` deliberately leaves empty slots alone - an empty slot's
--- rectangle is the only thing the cursor can find it by, and round eight is
--- what taking it away costs. That was safe while a support cell was 5 x 7.8 m,
--- because a cell that size either sat clear of everything at grade or sat
--- wholly inside a bus platform, and the second case is what
--- `dependOnOccupiedGround` reports.
---
--- A tile-length cell changes the arithmetic. 5 x 40 m under the deck will
--- clip the corner of a bus platform or an entrance while its own origin is
--- nowhere near either, and round twelve's rule is about the **rectangle**,
--- not the origin: the 24 x 6 m concourse cell got no pip for three sessions
--- while containing the clear 2 m band that eventually worked. So a support
--- whose cell catches an occupied rectangle anywhere along its length would
--- simply never be offered, with nothing in the log to say why - the origin
--- test above would not see it.
---
--- Hence a cut rather than a refusal, and `clipFootprint` is already the right
--- shape for it: one axis-aligned cut, the cheapest one that keeps the slot's
--- own origin inside what is left, and never below `RESERVATION_MIN`. The
--- support still **draws** its whole cell - `supportModels` reads
--- `supportCells`, not `spacing` - so this shortens the click target and not
--- the stone.
---
--- Same level only, which is the point: the obstacle list is occupied stock
--- slots that are not rail's, so the platform 12 m overhead is not in it. A
--- support under an occupied platform overlaps it in plan by design, and the
--- engine offers it anyway - which is the evidence that its own check reads z.
local function clipEmptyOurSlots(result, railSlots, modules)
	local obstacles = {}
	for _i, slot in ipairs(result.slots or {}) do
		local sp = slot.spacing
		if sp ~= nil and (sp[1] + sp[2] + sp[3] + sp[4]) > 0.0
			and (railSlots or {})[slot] == nil
			and type(slot.id) == "number" and slot.id < OUR_SLOT_MIN
			and (modules or {})[slot.id] ~= nil then
			obstacles[#obstacles + 1] = slotFootprint(slot, nil)
		end
	end

	local clipped, stuck, example = 0, 0, nil
	if #obstacles > 0 then
		for _i, slot in ipairs(result.slots or {}) do
			local sp = slot.spacing
			if type(slot.id) == "number" and slot.id >= OUR_SLOT_MIN
				and sp ~= nil and (sp[1] + sp[2] + sp[3] + sp[4]) > 0.0
				and (modules or {})[slot.id] == nil then
				local b0 = slotFootprint(slot, nil)
				local b, fouled = clipAgainstAll(b0, obstacles, false,
					axisAligned(b0))
				if fouled and b ~= nil then
					local to = footprintSpacing(b)
					slot.spacing = to
					clipped = clipped + 1
					if example == nil then
						example = string.format("%d %.1fx%.1f -> %.1fx%.1f",
							slot.id, sp[1] + sp[2], sp[3] + sp[4],
							to[1] + to[2], to[3] + to[4])
					end
				elseif fouled then
					-- No single cut keeps the origin inside, so the cell is
					-- buried rather than clipped. Left alone on purpose: a
					-- zeroed rectangle is not more clickable than an
					-- overlapping one, and `dependOnOccupiedGround` is what
					-- reports this slot.
					stuck = stuck + 1
				end
			end
		end
	end

	local line = "empty slots of ours cut clear of occupied ground at their own"
		.. " level: " .. tostring(clipped) .. "; buried with no cut that keeps"
		.. " the origin: " .. tostring(stuck)
	if example ~= nil then
		line = line .. "; e.g. " .. example
	end
	line = line .. ". The module still draws its whole cell."
	log.message(LOG .. line)
end

--- **Do not offer a rail slot that could not keep a reservation.**
---
--- Reported 2026-10-13, round thirteen: *"I can place platforms and tracks over
--- the bus station. If I extend them too far so the track is above the
--- concourse mesh, I can't delete the track, even if I have deleted the
--- concourse. When hovering over the track with the module delete tool, the
--- track doesn't light up in yellow."*
---
--- No highlight is the same symptom as no pip, and the same cause. The log of
--- that session has it exactly:
---
---     cross: 8395000 rail/track (-0.0,-25.0,12.0) 5.0x39.0
---         vs 20015503 street/street_terminal_entrance_exit (0.0,-22.5,0.0)
---            16.0x15.0 dz=12.0
---     trimmed the reserved ground: ... 2 zeroed because no single cut would do
---
--- The entrance reserves 16 x 15 m and the track column is 5 m wide, so the
--- entrance spans the **whole width** of the track's rectangle: no cut in x
--- leaves anything, and a cut in y has to drop the slot's own origin at
--- y = -25, which is inside the entrance's -30 .. -15. So no rectangle
--- containing that origin can avoid the entrance, `trimReservations` zeroes it,
--- and a track module has nothing else to be found by - it draws one invisible
--- model (root NOTES.md). Nothing to do with the concourse, which is why
--- deleting the concourse did not help: the entrance was always the obstacle,
--- and the concourse just happens to stand on it.
---
--- The honest answer is the rule from round twelve, applied to stock's slots
--- rather than to ours: **a slot that cannot hold a rectangle must not be
--- offered.** So the empty ones go out of the list before the engine sees it,
--- and the deck stops one tile short of the entrance instead of extending into
--- a tile whose module could never be removed again.
---
--- Only **empty** slots, on purpose. Dropping an occupied one orphans its
--- module, and an orphan is a configuration the engine can call invalid
--- outright - which would turn "one module I cannot delete" into "a
--- construction I cannot edit". A player who already built there keeps the
--- stuck module and the warning; the guard is about not getting there again.
---
--- Rail only. Street is stock, at grade, and was there first; our own slots are
--- placed where we chose to put them and are reported by
--- `dependOnOccupiedGround` instead.
local function dropUnreservableRailSlots(result, railSlots, xf, modules)
	local obstacles = {}
	for _i, slot in ipairs(result.slots or {}) do
		local sp = slot.spacing
		if sp ~= nil and (sp[1] + sp[2] + sp[3] + sp[4]) > 0.0
			and (railSlots or {})[slot] == nil
			and type(slot.id) == "number" and slot.id < OUR_SLOT_MIN
			and (modules or {})[slot.id] ~= nil then
			obstacles[#obstacles + 1] = slotFootprint(slot, nil)
		end
	end

	local dropped, examples = 0, {}
	local blockedColumns = {}
	if #obstacles > 0 then
		-- Backwards, so removing an entry cannot skip the next one.
		for i = #(result.slots or {}), 1, -1 do
			local slot = result.slots[i]
			local sp = slot.spacing
			if (railSlots or {})[slot] ~= nil and sp ~= nil
				and (sp[1] + sp[2] + sp[3] + sp[4]) > 0.0
				and type(slot.id) == "number"
				and (modules or {})[slot.id] == nil then
				local b0 = slotFootprint(slot, xf)
				-- `crossOnly` matches the trim's first pass: two decks 12 m
				-- apart overlap by design, and that is the overlap being
				-- clipped here. A same-level overlap would be a real bug and is
				-- left for the diagnostic to shout about.
				local b = clipAgainstAll(b0, obstacles, true, axisAligned(b0))
				if b == nil then
					table.remove(result.slots, i)
					dropped = dropped + 1
					if DECK_SLOT_TYPES[tostring(slot.type)] then
						blockedColumns[#blockedColumns + 1] = b0.oy
					end
					if #examples < 3 then
						examples[#examples + 1] = string.format("%d %s at (%.1f,%.1f)",
							slot.id, tostring(slot.type), b0.ox, b0.oy)
					end
				end
			end
		end
	end

	local line = "rail slots not offered, because no reservation of theirs"
		.. " would survive the level below: " .. tostring(dropped)
	if #examples > 0 then
		line = line .. "; " .. table.concat(examples, ", ")
	end
	line = line .. ". A module there could never be removed again."
	log.message(LOG .. line)

	-- Second pass: **and nothing past it, either.**
	--
	-- Reported 2026-10-21, with the first pass working: *"I can extend it
	-- towards the street and beyond, except adjacent to the concourse. [...]
	-- However, it is possible to add a track or platform on the other side of
	-- the concourse. I don't like this behaviour. It should not be possible to
	-- extend the station on the side where the concourse is built, since that
	-- will become glitchy."*
	--
	-- Both halves of that are the first pass being too literal. It withholds a
	-- *slot*, and a column is four of them: the entrance is 16 m of a 40 m tile,
	-- so only the tile directly over it loses its rectangle, while the tiles
	-- either side of it at the same column are clear in x and keep theirs. And
	-- a column two tiles further out is clear of the entrance altogether, so
	-- the deck could hop the road and carry on - which is the "other side of the
	-- concourse" above, and a deck with a hole in it over the one place a train
	-- would have to cross.
	--
	-- So the rule is the deck's, not the slot's: **the deck ends at the first
	-- column it may not use.** Find the nearest blocked column on each side of
	-- the columns that are actually occupied, and withhold every empty rail slot
	-- at or past it. Only `DECK_SLOT_TYPES` propagate - a building slot that
	-- cannot keep a rectangle says nothing about whether the deck can continue -
	-- and only empty slots are touched, for the same reason as the first pass:
	-- dropping an occupied one orphans its module.
	local minOcc, maxOcc = nil, nil
	for _i, slot in ipairs(result.slots or {}) do
		if (railSlots or {})[slot] ~= nil and type(slot.id) == "number"
			and DECK_SLOT_TYPES[tostring(slot.type)]
			and (modules or {})[slot.id] ~= nil then
			local oy = slotFootprint(slot, xf).oy
			if minOcc == nil or oy < minOcc then minOcc = oy end
			if maxOcc == nil or oy > maxOcc then maxOcc = oy end
		end
	end
	-- An empty deck still has a side: the seeded platform's own column.
	if minOcc == nil then minOcc, maxOcc = RAIL_SHIFT_Y, RAIL_SHIFT_Y end

	local below, above = nil, nil
	for _i, y in ipairs(blockedColumns) do
		if y < minOcc - RESERVATION_EPS then
			if below == nil or y > below then below = y end
		elseif y > maxOcc + RESERVATION_EPS then
			if above == nil or y < above then above = y end
		end
	end

	local beyond = 0
	if below ~= nil or above ~= nil then
		-- Backwards, so removing an entry cannot skip the next one.
		for i = #(result.slots or {}), 1, -1 do
			local slot = result.slots[i]
			local sp = slot.spacing
			if (railSlots or {})[slot] ~= nil and sp ~= nil
				and (sp[1] + sp[2] + sp[3] + sp[4]) > 0.0
				and type(slot.id) == "number"
				and (modules or {})[slot.id] == nil then
				local oy = slotFootprint(slot, xf).oy
				if (below ~= nil and oy <= below + RESERVATION_EPS)
					or (above ~= nil and oy >= above - RESERVATION_EPS) then
					table.remove(result.slots, i)
					beyond = beyond + 1
				end
			end
		end
	end

	local seen, cols = {}, {}
	for _i, y in ipairs(blockedColumns) do
		local key = string.format("%.1f", y)
		if not seen[key] then
			seen[key] = true
			cols[#cols + 1] = y
		end
	end
	table.sort(cols)
	local names = {}
	for _i, y in ipairs(cols) do
		names[#names + 1] = string.format("%.1f", y)
	end
	local limits = {}
	if below ~= nil then
		limits[#limits + 1] = string.format("y <= %.1f", below)
	end
	if above ~= nil then
		limits[#limits + 1] = string.format("y >= %.1f", above)
	end
	log.message(LOG .. "deck columns blocked at y = "
		.. (#names > 0 and table.concat(names, ", ") or "none")
		.. "; rail slots not offered because the deck cannot reach past one: "
		.. tostring(beyond)
		.. (#limits > 0 and " (" .. table.concat(limits, " or ") .. ")" or "")
		.. ". The deck ends where the entrance starts.")
	return dropped + beyond
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
	-- Our own slots claim less ground than they stand on, so for the
	-- *occupies* pass - the one that is handed `original` - measure the cell
	-- instead, or the diagnostic goes quiet about exactly the modules it was
	-- written for.
	--
	-- Only that pass. The other one asks what the **engine** holds, and
	-- substituting there reported the concourse as its whole 40 x 6 m cell
	-- against an entrance that its real 2 m band does not touch: one phantom
	-- `reserved` pair on every rebuild with a concourse in it, logged as a
	-- warning, standing in front of any real overlap that might turn up
	-- (2026-10-22).
	if original ~= nil then
		local cell = supportCells[slot.id]
		if cell ~= nil then
			sp = { cell[1] * 0.5, cell[1] * 0.5, cell[2] * 0.5, cell[2] * 0.5 }
		elseif slot.id >= ARCH_SLOT_BASE and slot.id < HALL_SLOT_BASE then
			sp = archCell()
		end
		-- A hall needs no substitution: its reservation is its cell, so the
		-- number already in `sp` is the one this pass wants. Taking the arch's
		-- asymmetric cell for it instead would report the building 11 m from
		-- where it stands.
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

--- Is this pair an arch and the entrance it was derived from?
---
--- They overlap at grade **by design** - the arch spans that entrance's road,
--- and its slot id is that entrance's with the variant digits cleared - so
--- counting the pair would mean the same-level count is never zero, and a count
--- that is never zero cannot report anything.
---
--- The arch only. A hall is deliberately offered **off** every entrance, so a
--- hall overlapping one is not by design and is exactly the kind of thing this
--- diagnostic exists to shout about; the id test excludes it anyway, since the
--- hall band carries a tile index in the digits this comparison expects to be
--- zero.
local function archOverItsEntrance(a, b)
	local lo, hi = a.id, b.id
	if lo > hi then lo, hi = hi, lo end
	return hi >= ARCH_SLOT_BASE and hi < HALL_SLOT_BASE and lo < OUR_SLOT_MIN
		and hi - ARCH_SLOT_BASE == lo - (lo % 100)
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
			if boxesOverlap(a, b) and not archOverItsEntrance(a, b) then
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
			if boxesOverlap(a, b) and not archOverItsEntrance(a, b) then
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

--- Which of our slots stand on ground an **occupied stock slot** already
--- holds - which is to say: **which of our slots the engine will never offer.**
---
--- That is the finding of rounds nine to twelve, in one line. An empty slot is
--- offered where its reservation holds ground no occupied slot is holding, so a
--- slot of ours inside somebody else's rectangle gets no pip at all, and no
--- declaration fixes it: not `skipCollisionCheck`, not `replaceable`, not
--- moving the origin, not `dependentSlots`. Only a reservation on clear ground
--- does, which is what `CONCOURSE_FLANK` is.
---
--- So this is a **report**, and a loud one: every slot it counts is a slot the
--- player cannot use. The concourse is clear of it by construction now; what
--- remains is the one support cell that stands in the bus platform, which has
--- no clear band of its own to retreat to - its cell is in the middle of the
--- platform's, not at its edge. See NOTES.md, round twelve, for the two honest
--- options there.
---
--- It also declares the cascade while it is here (`dependSlot`), which is the
--- part of stock's idiom that does still apply: a slot of ours standing in an
--- occupied stock slot should go when that slot goes, rather than orphaning its
--- module. It is **not** what makes anything clickable - that was measured.
---
--- Height is in the test even though it is not in the collision check: a
--- support at grade and the platform 12 m above it are not claiming the same
--- ground as far as a reservation is concerned, while a support and the bus
--- platform beside it are.
---
--- Only the **origin** is tested, not the whole rectangle, because the origin
--- is what says which stock slot a slot of ours is *inside* - and a slot that
--- merely overlaps at an edge still has ground of its own and is offered
--- normally.
local function dependOnOccupiedGround(result, railSlots, xf, modules)
	local covers = {}
	for _i, slot in ipairs(result.slots or {}) do
		if type(slot.id) == "number" and slot.id < OUR_SLOT_MIN
			and slot.spacing ~= nil and slot.transf ~= nil
			and (modules or {})[slot.id] ~= nil then
			covers[#covers + 1] = {
				id = slot.id,
				type = slot.type,
				box = slotFootprint(slot, (railSlots or {})[slot] and xf or nil),
			}
		end
	end

	local ours, buried, examples = 0, 0, {}
	for _i, slot in ipairs(result.slots or {}) do
		if type(slot.id) == "number" and slot.id >= OUR_SLOT_MIN
			and slot.transf ~= nil then
			ours = ours + 1
			local o = applyMat(slot.transf, { 0.0, 0.0, 0.0 })
			for _j, c in ipairs(covers) do
				local b = c.box
				if math.abs(b.z - o[3]) < 1.0
					and o[1] > b.x0 + RESERVATION_EPS
					and o[1] < b.x1 - RESERVATION_EPS
					and o[2] > b.y0 + RESERVATION_EPS
					and o[2] < b.y1 - RESERVATION_EPS then
					buried = buried + 1
					dependSlot(result, c.id, slot.id)
					if #examples < 3 then
						examples[#examples + 1] = string.format(
							"%d %s at (%.1f,%.1f) under %d %s",
							slot.id, tostring(slot.type), o[1], o[2],
							c.id, tostring(c.type))
					end
					break
				end
			end
		end
	end

	local line = "our slots the engine will not offer, because their"
		.. " reservation is inside an occupied stock slot's: "
		.. tostring(buried) .. " of " .. tostring(ours)
	if #examples > 0 then
		line = line .. "; " .. table.concat(examples, "; ")
	end
	log.message(LOG .. line)

	-- The table as the engine will get it, ours named. The cascade only - see
	-- the header; this is not what makes a slot clickable.
	--
	-- Still logged, because it is the only way to see that the dependency
	-- survived the merge:
	-- `shareLists` hands the merged result **rail's own** `dependentSlots`
	-- table, so a write that lands in a copy instead would be invisible, and
	-- the symptom - a slot that still cannot be clicked - is the same symptom
	-- as the dependency not being the mechanism at all. Those two have to stay
	-- separable in the log.
	local parents, mine, shown = 0, 0, {}
	for parent, children in pairs(result.dependentSlots or {}) do
		parents = parents + 1
		for _i, child in ipairs(children) do
			if type(child) == "number" and child >= OUR_SLOT_MIN then
				mine = mine + 1
				if #shown < 4 then
					shown[#shown + 1] = tostring(parent) .. " -> " .. tostring(child)
				end
			end
		end
	end
	local dep = "dependent slots: " .. tostring(parents) .. " parent(s), "
		.. tostring(mine) .. " of them pointing at a slot of ours"
	if #shown > 0 then
		dep = dep .. "; " .. table.concat(shown, ", ")
	end
	log.message(LOG .. dep)

	return buried, ours
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

--- What a tool asked us about, and what we answered - deduped the same way.
---
--- `isAffectedByToolFn` is the gate *above* `upgradeFn`, and it is the half
--- that has never been visible. Both T4 failures were silent refusals, and the
--- answer to each one was to make the decision print; this is the same move one
--- level up. Reported 2026-10-21: *"If I drag a high speed track over a regular
--- track, I can't build it because it would collide."* A collision is the
--- **builder** talking, not the upgrade path, so the question is whether the
--- engine ever offers the drag to this construction at all. If nothing is
--- logged here while the cursor refuses, it never asked.
local lastToolLog = nil
local function logTool(line)
	if line ~= lastToolLog then
		lastToolLog = line
		log.message(LOG .. "tool " .. line)
	end
end

--- Everything a tool config will tell us about itself, defensively.
---
--- `pairs` over it may not be legal - these come from the engine and are not
--- necessarily plain tables - so the iteration is in a `pcall` and the known
--- field names are the fallback. On the tool thread an error here would present
--- as the station simply not being offered, which is the symptom we are chasing.
local TOOL_CONFIG_FIELDS = { "streetTemplate", "catenary", "trackType",
	"tramTrack", "tramCatenary", "bridgeType", "tunnelType" }

local function toolConfigText(cfg)
	if cfg == nil then return "nil" end
	local parts = {}
	local ok = pcall(function()
		for k, v in pairs(cfg) do
			parts[#parts + 1] = tostring(k) .. "=" .. tostring(v)
		end
	end)
	if not ok or #parts == 0 then
		parts = {}
		for _i, k in ipairs(TOOL_CONFIG_FIELDS) do
			local v = nil
			pcall(function() v = cfg[k] end)
			if v ~= nil then
				parts[#parts + 1] = k .. "=" .. tostring(v)
			end
		end
	end
	table.sort(parts)
	return #parts > 0 and table.concat(parts, " ") or "{}"
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
--- The per-family subconstruction tag bases, 100 apart.
---
--- Named because `findLevelNodes` reads them too: a subconstruction's tag is
--- the only thing that says which **level** its lanes belong to, once they have
--- all been lifted into construction space. Frozen at the first public release,
--- because a tag is how a savegame's subconstruction is recognised after a
--- rebuild - see `finish`.
local STREET_TAG_BASE = 1
local RAIL_TAG_BASE = 101

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
--- Every pair of person nodes an existing lane **already joins**, both ways
--- round.
---
--- This exists because of a crash, and the crash is worth the paragraph.
--- Reported 2026-10-22: *"Placing a freight platform crashed the game."* The
--- report file says
---
---     Duplicate edge error, TransportNetworkSystem.cpp:299 CheckDuplicateEdges
---     Error at position (-2310.45, 964.96, 13.73) and (-2310.45, 964.96, 5.63)
---     (tangents are (0, 0, -8.1) (0, 0, -8.1)) types: 0000000000000001
---
--- - a vertical 8.1 m `PERSON` edge, present twice. 8.1 m is exactly the span
--- `linkLevels` logs, so one of the two was ours.
---
--- The cause is in `findLevelNodes`' own scoring. It picks the closest pair in
--- **plan**, so a pair sharing an (x, y) scores zero and always wins - and the
--- pair that most reliably shares an (x, y) is *the two ends of a lane that is
--- already there*. Adding a second lane between them is then a duplicate edge,
--- which is fatal rather than merely redundant. A freight platform is what
--- exposed it: the pairs chosen before were coincident in plan but unconnected,
--- so no duplicate was ever emitted.
---
--- Treating every **consecutive** pair of nodes in a lane as joined
--- over-detects, because `laneutil.createLane` makes two nodes per curve and a
--- multi-curve lane is therefore pairs rather than a chain. That is the safe
--- direction: an over-detected edge costs one candidate pair out of tens of
--- thousands, and a missed one costs the game.
---
--- The crossing count it also returns was meant to answer "does anything of
--- stock's already join the levels?", and does not: an edge belongs to one
--- lane list and a lane list to one subconstruction, so an edge straddling the
--- midpoint is a stub inside one family, not a connection between two. It is
--- kept because a rail lane that dives 8 m below its own deck is worth seeing
--- in the log, but `findLevelNodes` answers the real question by counting
--- **shared nodes**.
local function personEdgeKeys(result, dz)
	local keys = {}
	local crossing, example = 0, nil
	local mid = dz * 0.5
	for _i, sub in ipairs(result.subconstructions or {}) do
		for _j, lane in ipairs(sub.laneLists or {}) do
			if isPersonLane(lane) then
				local prev, prevP = nil, nil
				for _k, node in ipairs(lane.nodes or {}) do
					local p = applyMat(lane.transf, node[1])
					local k = nodeKey(p)
					if prev ~= nil then
						keys[prev .. "|" .. k] = true
						keys[k .. "|" .. prev] = true
						if (prevP[3] <= mid) ~= (p[3] <= mid) then
							crossing = crossing + 1
							if example == nil then
								example = string.format(
									"(%.1f,%.1f,%.1f) -> (%.1f,%.1f,%.1f)",
									prevP[1], prevP[2], prevP[3],
									p[1], p[2], p[3])
							end
						end
					end
					prev, prevP = k, p
				end
			end
		end
	end
	return keys, crossing, example
end

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

--- The z values a set of person nodes occupies, as "min..max" plus the three
--- commonest values and their counts.
---
--- A level that is one walkable surface should read as one value. Anything else
--- is a stub hanging off that surface, and picking a stub as the end of the
--- interchange lane is how the link came to run from 7 m underground: the
--- `linked levels:` line has read `street (32.5,0.0,-7.0)` since the tag-based
--- classification went in, and nothing said whether -7 was a real place to
--- stand or a dead end inside the ground.
local function zSpread(nodes)
	local counts, order = {}, {}
	local lo, hi = nil, nil
	for _i, p in ipairs(nodes) do
		local z = p[3]
		if lo == nil or z < lo then lo = z end
		if hi == nil or z > hi then hi = z end
		local k = string.format("%.1f", z)
		if counts[k] == nil then
			counts[k] = 0
			order[#order + 1] = k
		end
		counts[k] = counts[k] + 1
	end
	table.sort(order, function(a, b) return counts[a] > counts[b] end)
	local top = {}
	for i = 1, math.min(3, #order) do
		top[i] = order[i] .. " x" .. tostring(counts[order[i]])
	end
	return string.format("%.1f..%.1f, %d distinct, commonest %s",
		lo or 0.0, hi or 0.0, #order,
		#top > 0 and table.concat(top, " / ") or "-")
end

--- Every pedestrian node a link may use, split by level, plus the edges that
--- already join two of them.
---
--- Derived from the assembled lane lists rather than from guessed coordinates:
--- both families' person lanes come from their **models** via `addLaneLists`,
--- which positions them with `lane.transf` and keeps the nodes model-local, so
--- the real world positions are only knowable after the hooks have run.
---
--- It used to choose the pair as well, and `nearestPair` now does that: with
--- one lane per concourse there is one list of candidates and several choices
--- made from it, and the diagnostics in here are about the candidates rather
--- than about any one lane. Vehicle nodes are excluded here, once, for all of
--- them - a PERSON node coincident with a vehicle node is the hard crash this
--- whole section is careful about.
local function findLevelNodes(result, dz)
	local lowNodes, highNodes = {}, {}
	local avoid = vehicleNodeKeys(result)
	local rejected = 0

	-- **Which level a node belongs to is its subconstruction's tag, not its z.**
	--
	-- Height was the obvious test and it is wrong, which the freight-platform
	-- crash is what finally showed. Rail's lanes are lifted wholesale by
	-- `liftLanes`, and some of them hang *below* the deck: a platform addon -
	-- the stairs or underpass - descends about 8 m from the platform, so after
	-- the lift its bottom node sits at **z = +5**, five metres in the air and
	-- comfortably under any midpoint test. `p[3] > dz * 0.5` therefore filed
	-- that node as "grade", and since it shares an (x, y) with its own upper
	-- end, the closest-pair-in-plan search picked the two ends of one stock
	-- lane and drew a second lane between them.
	--
	-- Two bugs in one, and the duplicate is only the louder:
	--
	--  * the engine calls a second edge between the same two nodes a duplicate
	--    and dies - `personEdgeKeys` below is the guard for that;
	--  * and the link has therefore been joining **rail to rail** all along.
	--    Every session's `linked levels:` line reads `-> (…,5.0) -> (…,13.1)`,
	--    which is the addon stub at both ends. It never reached the street
	--    level, which is the one thing it exists to do, and that is the best
	--    explanation yet of why passengers transfer by teleporting (T6 step 5).
	--
	-- A tag says which family a subconstruction came from and survives the
	-- lift, so it is the honest test.
	-- Per subconstruction and per lane list as well as per level, because
	-- "288 of the 430 street nodes are at z = -7.0" was not something either
	-- family's models could explain: nothing in
	-- `street/modular_street_station/*.mdl` has geometry within metres of -7.
	-- So the depth is coming from a lane's `transf`, and which subconstruction
	-- and which lane list it is, is the whole question.
	local byTag = {}
	local function note(tag, laneIndex, p)
		local key = tostring(tag)
		local bucket = byTag[key]
		if bucket == nil then
			bucket = { nodes = {}, lanes = {} }
			byTag[key] = bucket
		end
		bucket.nodes[#bucket.nodes + 1] = p
		local zKey = string.format("%.1f", p[3])
		local lanes = bucket.lanes[zKey]
		if lanes == nil then
			lanes = {}
			bucket.lanes[zKey] = lanes
		end
		lanes[laneIndex] = (lanes[laneIndex] or 0) + 1
	end

	for _i, sub in ipairs(result.subconstructions or {}) do
		local isRail = (sub.tag or 0) >= RAIL_TAG_BASE
		for _j, lane in ipairs(sub.laneLists or {}) do
			if isPersonLane(lane) then
				for _k, node in ipairs(lane.nodes or {}) do
					local p = applyMat(lane.transf, node[1])
					note(sub.tag, _j, p)
					if avoid[nodeKey(p)] then
						rejected = rejected + 1
					elseif isRail then
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

	-- A pair an existing lane already joins must not be picked: a second lane
	-- between the same two nodes is a duplicate edge, and the engine treats
	-- that as fatal. See `personEdgeKeys`.
	-- **Does anything of stock's already join the levels?** An *edge* cannot
	-- answer that, and reading it that way was wrong: a lane list belongs to
	-- exactly one subconstruction, so no stock edge spans the two families.
	-- What joins them is a node they **share** - the engine welds person nodes
	-- that coincide - so the test is a coincidence test over the two candidate
	-- sets, which the tag now separates honestly.
	--
	-- This replaces the "existing person lane(s) already cross between the
	-- levels: 90 edge(s)" line, which counted edges straddling z = dz/2 within
	-- one family. Its own example gave it away - `(80.0,27.5,13.1) ->
	-- (80.0,27.5,5.0)` is a rail platform addon descending from the deck, both
	-- ends rail. T6 step 5 was half-answered on the strength of it; it should
	-- be asked again.
	local highKeys = {}
	for _i, hi in ipairs(highNodes) do highKeys[nodeKey(hi)] = true end
	local shared = 0
	for _i, lo in ipairs(lowNodes) do
		if highKeys[nodeKey(lo)] then shared = shared + 1 end
	end
	log.message(LOG .. "person nodes: " .. tostring(#lowNodes) .. " street (z "
		.. zSpread(lowNodes) .. "), " .. tostring(#highNodes) .. " rail (z "
		.. zSpread(highNodes) .. "); " .. tostring(shared)
		.. " node(s) shared between the levels. Zero shared means the lane we"
		.. " draw is the only way across, so it had better end somewhere a"
		.. " person can stand.")

	local tagKeys = {}
	for key, _bucket in pairs(byTag) do tagKeys[#tagKeys + 1] = key end
	table.sort(tagKeys, function(a, b) return tonumber(a) < tonumber(b) end)
	for _i, key in ipairs(tagKeys) do
		local bucket = byTag[key]
		local zKeys = {}
		for zKey, _lanes in pairs(bucket.lanes) do zKeys[#zKeys + 1] = zKey end
		table.sort(zKeys, function(a, b) return tonumber(a) > tonumber(b) end)
		local detail = {}
		for _j, zKey in ipairs(zKeys) do
			local n, lanes = 0, 0
			for _laneIndex, count in pairs(bucket.lanes[zKey]) do
				n = n + count
				lanes = lanes + 1
			end
			detail[#detail + 1] = string.format("z %s: %d node(s) in %d lane(s)",
				zKey, n, lanes)
		end
		log.message(LOG .. "  person nodes of subconstruction tag " .. key
			.. " (" .. tostring(#bucket.nodes) .. "): "
			.. table.concat(detail, "; "))
	end

	local joined, crossing, crossingExample = personEdgeKeys(result, dz)
	if crossing > 0 then
		log.message(LOG .. "person edge(s) straddling z = "
			.. string.format("%.1f", dz * 0.5) .. " inside a single family: "
			.. tostring(crossing) .. ", e.g. " .. tostring(crossingExample)
			.. ". Not an interchange - see the shared-node count above")
	end
	return lowNodes, highNodes, joined
end

--- The nodes of one level within `r` of an anchor, in plan.
---
--- Purely a cost control, and the cost is real: a session on 2026-10-23
--- reported **142 street and 2208 rail** person nodes, so one unrestricted pair
--- search is 313,000 iterations - which was affordable when `linkLevels` ran it
--- once, and is not now that it runs once per concourse module. Six halls and
--- an arch would be two million iterations of a double loop, on a path the
--- engine re-runs while the player **hovers** a module.
---
--- Correctness does not depend on the radius: `nearestPair` falls back to the
--- whole list if a restricted search finds nothing, so this can only make the
--- common case cheap, never make it wrong.
local function nodesNear(nodes, anchor, r)
	local out = {}
	local r2 = r * r
	for _i, p in ipairs(nodes) do
		local dx, dy = p[1] - anchor[1], p[2] - anchor[2]
		if dx * dx + dy * dy <= r2 then
			out[#out + 1] = p
		end
	end
	return out
end

--- How far from a concourse to look for its stairs, in metres, in order.
---
--- 60 m is the cell's own 40 m plus half a tile either side, which is where a
--- building's own stairs ought to be; 120 m is three tiles, for a station whose
--- walkable nodes are sparse. Past that the search goes wide and takes the
--- whole station, which is what it always did.
local ANCHOR_RADII = { 60.0, 120.0 }

--- The closest usable pair in two candidate lists, biased toward `anchor`.
local function pickPair(lowNodes, highNodes, joined, dz, anchor)
	local best, bestLow, bestHigh, alreadyJoined, flat = nil, nil, nil, 0, 0
	for _i, lo in ipairs(lowNodes) do
		local loKey = nodeKey(lo)
		local bias = 0.0
		if anchor ~= nil then
			local ax, ay = lo[1] - anchor[1], lo[2] - anchor[2]
			bias = ax * ax + ay * ay
		end
		for _j, hi in ipairs(highNodes) do
			local dx, dy = hi[1] - lo[1], hi[2] - lo[2]
			local d = dx * dx + dy * dy + bias
			if best == nil or d < best then
				if joined[loKey .. "|" .. nodeKey(hi)] then
					alreadyJoined = alreadyJoined + 1
				elseif hi[3] - lo[3] < dz * 0.5 then
					-- Not a climb between levels. With the families separated
					-- this should not happen, so it is counted rather than
					-- silently skipped.
					flat = flat + 1
				else
					best, bestLow, bestHigh = d, lo, hi
				end
			end
		end
	end
	return bestLow, bestHigh, flat, alreadyJoined
end

--- The pair of person nodes one lane should join, nearest to `anchor`.
---
--- Split out of `findLevelNodes` on 2026-10-26, when the link stopped being one
--- lane for the whole station and became one lane per concourse module. The
--- selection is unchanged with `anchor == nil`, which is what a station with no
--- concourse still gets: the closest pair in plan, anywhere on the structure.
---
--- The anchor is folded into the same score rather than used to pre-sort the
--- candidates, and the units are why it is sound: both terms are squared plan
--- distances in metres, so a pair 5 m from the building that climbs 30 m across
--- scores 925 against 3604 for one 60 m away that climbs 2 m. Near the building
--- wins, short still breaks ties, and nothing needs a weighting constant that
--- would have to be guessed.
---
--- Tried near the anchor first and over everything afterwards, for the cost
--- reason in `nodesNear`. The widening is what keeps it honest: a restricted
--- search that finds no pair - because every candidate is already joined, or
--- because a hall stands where nothing walks - is not allowed to be the answer.
---
--- The two refusals are the ones this function has always had, and they are not
--- tidiness - each is a crash the engine does not survive:
---
---  * a pair an existing person lane already joins would be a **duplicate
---    edge**, fatal at `TransportNetworkSystem.cpp:299`. That is why `joined`
---    is passed in and why `linkLevels` writes each lane it draws back into it;
---  * a pair that does not climb at least half the pitch is not an interchange
---    at all, and with the families separated by tag it should not occur - so it
---    is counted and reported rather than silently dropped.
local function nearestPair(lowNodes, highNodes, joined, dz, anchor)
	local lo, hi, flat, alreadyJoined = nil, nil, 0, 0
	if anchor ~= nil then
		for _i, r in ipairs(ANCHOR_RADII) do
			local lows = nodesNear(lowNodes, anchor, r)
			local highs = nodesNear(highNodes, anchor, r)
			if #lows > 0 and #highs > 0 then
				lo, hi, flat, alreadyJoined =
					pickPair(lows, highs, joined, dz, anchor)
				if lo ~= nil then break end
			end
		end
	end
	if lo == nil then
		lo, hi, flat, alreadyJoined =
			pickPair(lowNodes, highNodes, joined, dz, anchor)
	end

	if flat > 0 then
		log.message(LOG .. "skipped " .. tostring(flat) .. " candidate pair(s)"
			.. " that climbed less than " .. string.format("%.1f", dz * 0.5)
			.. " m - a lane between them would not be an interchange")
	end

	if alreadyJoined > 0 then
		log.message(LOG .. "skipped " .. tostring(alreadyJoined)
			.. " better-scoring candidate pair(s) an existing person lane"
			.. " already joins - a second lane between the same two nodes is a"
			.. " duplicate edge, which the engine treats as fatal")
	end

	return lo, hi
end

--- Where each placed concourse module wants its stairs, in construction space.
---
--- This is what closes `PLAN.md` Phase 10 step 2, which had been parked on a
--- decision rather than on work: *"with a concourse present the link should
--- start at the concourse's slot instead, which makes it deterministic and puts
--- it where the stairs art will be"*, blocked behind "first decide whether the
--- link stays at all". That was settled in game on 2026-10-23 - passengers walk
--- it, and the levels share no other node - so the anchor is worth having.
---
--- Both variants anchor one, because both are the same building: a hall is
--- where a player puts the rest of the frontage, and a frontage you cannot
--- climb from would make the hall a decoration. It is also what the module was
--- asked for - *"does have pedestrian connections"*.
---
--- Read off the cell centre rather than the slot origin, through
--- `CONCOURSE_CELL_OFFSET`, for the same reason the catchment circle is: an
--- arch's origin sits 11 m out on its flank.
local function concourseAnchors(result, modules)
	local anchors = {}
	for _i, slot in ipairs(result.slots or {}) do
		local entry = (modules or {})[slot.id]
		if CONCOURSE_TYPES[slot.type] and entry ~= nil and slot.transf ~= nil then
			anchors[#anchors + 1] = {
				id = slot.id,
				-- The type and the frame as well as the point, because
				-- `hallWalkways` builds geometry in the cell's own axes and
				-- only one of the two variants gets a footway.
				type = slot.type,
				transf = slot.transf,
				p = applyMat(slot.transf,
					{ CONCOURSE_CELL_OFFSET[slot.type] or 0.0, 0.0, 0.0 }),
			}
		end
	end
	return anchors
end

--- A hall's own footway, and the pedestrian connection the module was asked
--- for.
---
--- Reported from the game on 2026-10-26, with both variants placed and their
--- volumes right: *"there are no pedestrian connections from the new concourse
--- to the road next to it."*
---
--- The reason is that **the arch never had any of its own**. Its cell is the
--- entrance's cell, so everything that connects it is stock geometry standing
--- in the same place: the entrance module's street edge reaching out to the
--- road (`modular_street_station/modules.script.lua:106-117`), and the perron
--- pieces ringing the platforms, whose *models* carry person lanes marked
--- `linkable`. A hall is a whole deck tile along the frontage from any of that,
--- and what it had was a solid building with no walkable geometry at all.
---
--- `linkable` is the entire mechanism, and it is one flag.
--- `laneutil.createLane(curves, modes, speed, width, linkable)` copies it onto
--- the lane (`scripts/construction/laneutil.lua`), and a linkable person lane
--- is the one the engine will join to the street network. The clearest shipped
--- example is a town building: one curve, named `entrance_linkable`, built with
--- `createLane(..., true)`, and that is the whole of how every house in a town
--- reaches the pavement (`buildings/townbuildingutil.lua:207` - the only `lua`
--- in the install that passes it, the rest being declared inside `.mdl` files).
--- Our interchange lanes pass `false`, and still should: they run between two
--- nodes we chose and must not be re-pointed at a road.
---
--- So each placed hall gets a small network of its own, in its cell's frame, on
--- the walkway `concourseModels` lays along its road-facing face - see
--- `CONCOURSE_WALK_Z`, which is a street kerb's 30 cm and needs that stone
--- under it:
---
---  * a **frontage** lane from the cell's left edge through its centre to its
---    right edge. Two curves rather than one, because `createLane` makes two
---    nodes per curve and a coincident node is the only thing that joins two
---    lanes - the centre has to *be* a node for anything to attach there.
---    Adjacent halls meet at a shared cell edge, so a row of them is one
---    continuous footway for free, and that is what the row was for;
---  * a **kerb** spur from the centre out to the cell's road-facing face, in a
---    lane list of its own with `linkable = true`. Its own list because the
---    flag is per lane list - which is why stock gives it a curve of its own
---    too;
---  * a **grade link** from the centre to the nearest person node the station
---    already had, ending exactly on it. Both ends are at kerb height, so it is
---    level by construction. Without this curve a hall's footway is an island
---    reachable only from the road, since lanes join at coincident nodes and
---    nowhere else (root `NOTES.md`).
---
--- The climb then starts at the cell centre instead of at whatever node
--- happened to be nearest: the centre is in `lowNodes` by the time
--- `nearestPair` runs, and the hall's own anchor scores it at zero. That is
--- the node the stairs art will hang on.
---
--- Two refusals, both of them crashes rather than tidiness, and both already
--- written down: a node coincident with a **vehicle** lane node is fatal on the
--- simulation thread, so every node here is checked against `vehicleNodeKeys`
--- and a curve with either end on one is dropped; and a second edge between two
--- nodes is a duplicate edge, equally fatal, so every curve is checked against
--- `joined` and registered in it.
---
--- The arch gets none of this, deliberately. Its cell holds the carriageway,
--- so a footway across it would be laid over the road it spans - and it is
--- already the one place on the frontage where the stock entrance has put a
--- pedestrian connection of its own.
local function hallWalkways(result, sub, anchors, joined, lowNodes)
	local avoid = vehicleNodeKeys(result)
	-- The station's own grade nodes, before any of ours join the list: a hall
	-- links to the station, whichever order the halls are visited in.
	local grade = {}
	for i = 1, #lowNodes do grade[i] = lowNodes[i] end

	local halls, lanes, refused, lines = 0, 0, 0, {}

	local function addCurves(curves, linkable)
		local usable = {}
		for _i, c in ipairs(curves) do
			local a, b = c[1], c[2]
			local ka, kb = nodeKey(a), nodeKey(b)
			if ka == kb or avoid[ka] or avoid[kb] or joined[ka .. "|" .. kb] then
				refused = refused + 1
			else
				usable[#usable + 1] = {
					{ a[1], a[2], a[3] }, { b[1], b[2], b[3] },
				}
				joined[ka .. "|" .. kb] = true
				joined[kb .. "|" .. ka] = true
			end
		end
		if #usable == 0 then return end
		sub.laneLists[#sub.laneLists + 1] =
			laneutil.createLane(usable, { "PERSON" }, 2, 2, linkable)
		lanes = lanes + 1
	end

	for _i, a in ipairs(anchors) do
		if a.type == CONCOURSE_HALL_TYPE and a.transf ~= nil then
			local hw, hd = CONCOURSE_W * 0.5, CONCOURSE_D * 0.5
			-- Down the middle of the walkway, not down the middle of the cell:
			-- the frontage lane is on the 2 m of stone at the face, with a
			-- metre either side of it, and the rest of the cell is the
			-- building it runs past.
			local wy = -hd + CONCOURSE_WALK_D * 0.5
			local c = applyMat(a.transf, { 0.0, wy, CONCOURSE_WALK_Z })
			local l = applyMat(a.transf, { -hw, wy, CONCOURSE_WALK_Z })
			local r = applyMat(a.transf, { hw, wy, CONCOURSE_WALK_Z })
			-- The kerb, on the cell's own edge: the cell hangs off the
			-- entrance's frame at `-CONCOURSE_D * 0.5`, away from the platforms
			-- and towards whatever the entrance is snapped to, so -y is the
			-- road side and this node is the top of the kerb the engine's own
			-- path has to climb.
			local o = applyMat(a.transf, { 0.0, -hd, CONCOURSE_WALK_Z })

			local g, gd = nil, nil
			for _j, p in ipairs(grade) do
				local dx, dy = p[1] - c[1], p[2] - c[2]
				local d = dx * dx + dy * dy
				if gd == nil or d < gd then g, gd = p, d end
			end

			addCurves({ { l, c }, { c, r } }, false)
			addCurves({ { c, o } }, true)
			if g ~= nil then addCurves({ { c, g } }, false) end

			lowNodes[#lowNodes + 1] = c
			halls = halls + 1
			lines[#lines + 1] = string.format(
				"%s centre (%.1f,%.1f,%.1f), kerb (%.1f,%.1f,%.1f) linkable,"
				.. " grade link to (%.1f,%.1f,%.1f) %.1f m away",
				tostring(a.id), c[1], c[2], c[3], o[1], o[2], o[3],
				g and g[1] or 0.0, g and g[2] or 0.0, g and g[3] or 0.0,
				gd and math.sqrt(gd) or -1.0)
		end
	end

	if halls > 0 then
		log.message(LOG .. "hall footways: " .. tostring(halls) .. " hall(s), "
			.. tostring(lanes) .. " lane list(s), " .. tostring(refused)
			.. " curve(s) refused; " .. table.concat(lines, "; ")
			.. ". The kerb spur is the linkable one - that is what the engine"
			.. " joins to the street network, the way it joins a town"
			.. " building's door to the pavement. The rest joins only where"
			.. " nodes coincide")
	end
end

--- Join the two levels' pedestrian networks: one lane per concourse module, or
--- one lane for the station when it has no concourse at all.
---
--- Without this there is **no path between the levels at all**: the street
--- station's person lanes are at grade, the rail station's at +12, and nothing
--- spans the gap. Passengers then never board the feeder bus either, because a
--- journey is only taken when the whole route exists - which reads as the
--- station being ignored rather than broken. Measured 2026-10-23: `0 node(s)
--- shared between the levels`, with both families filed correctly, so stock
--- joins them nowhere and these lanes are the only route across.
---
--- One lane per concourse as of 2026-10-26, where it used to be exactly one for
--- the whole station. What that buys is a frontage that works the way it looks:
--- a row of halls 200 m long had one staircase at whichever end the closest
--- pair of nodes happened to be, and every passenger in the station walked to
--- it. Now each building has its own.
---
--- The unanchored fallback stays, and deliberately: a station whose concourse
--- has been demolished keeps its link rather than silently stranding everyone
--- who is already travelling. It is the same lane this function drew before
--- there was anything to anchor to.
---
--- Deliberately two-point curves. Lanes join where their nodes **coincide**, so
--- each end is placed exactly on an existing person node and there are no
--- intermediate nodes - an intermediate node is what would risk landing on a
--- vehicle lane, and a PERSON-to-BUS junction crashes the game (root
--- NOTES.md). `findLevelNodes` is what keeps vehicle nodes out of the
--- candidates; `joined` is what keeps two lanes off one pair of nodes, and each
--- lane drawn here goes into it both ways round before the next one is chosen.
--- They are bare diagonals for now; a stairs model can be hung on them once the
--- art is more than a placeholder.
local function linkLevels(result, dz, modules)
	local lowNodes, highNodes, joined = findLevelNodes(result, dz)

	local sub = result.subconstructions[1]
	if sub == nil then return end
	sub.laneLists = sub.laneLists or {}

	-- `false` rather than an empty list, so the loop body is the same for the
	-- anchored and the unanchored case and there is only one place that draws a
	-- lane.
	local anchors = concourseAnchors(result, modules)
	-- Before the climbs are chosen, not after: a hall's footway puts its cell
	-- centre into `lowNodes`, and that is the node its own climb should start
	-- at.
	hallWalkways(result, sub, anchors, joined, lowNodes)
	if #anchors == 0 then anchors = { false } end

	local links, lines, failed = 0, {}, {}
	for _i, a in ipairs(anchors) do
		local lo, hi = nearestPair(lowNodes, highNodes, joined, dz,
			a and a.p or nil)
		if lo == nil or hi == nil then
			-- Collected rather than warned about here: `updateFn` runs on every
			-- hover frame, and a station with no walkable upper level would
			-- otherwise put one warning per concourse into the log several
			-- times a second.
			failed[#failed + 1] = a and tostring(a.id) or "unanchored"
		else
			sub.laneLists[#sub.laneLists + 1] = laneutil.createLane(
				{ { { lo[1], lo[2], lo[3] }, { hi[1], hi[2], hi[3] } } },
				{ "PERSON" }, 2, 2, false)
			-- Both ways round, matching `personEdgeKeys`, so the next anchor
			-- cannot choose this pair again.
			local loKey, hiKey = nodeKey(lo), nodeKey(hi)
			joined[loKey .. "|" .. hiKey] = true
			joined[hiKey .. "|" .. loKey] = true
			links = links + 1
			lines[#lines + 1] = string.format(
				"%s street (%.1f,%.1f,%.1f) -> rail (%.1f,%.1f,%.1f), a climb"
				.. " of %.1f m",
				a and tostring(a.id) or "unanchored",
				lo[1], lo[2], lo[3], hi[1], hi[2], hi[3], hi[3] - lo[3])
		end
	end

	if #failed > 0 then
		log.warning(LOG .. "no pedestrian link possible for "
			.. tostring(#failed) .. " of " .. tostring(#anchors)
			.. " concourse(s) (" .. table.concat(failed, ", ") .. "): "
			.. tostring(#lowNodes) .. " person nodes at grade, "
			.. tostring(#highNodes) .. " above")
	end

	if #lines > 0 then
		log.message(LOG .. "linked levels: " .. tostring(links) .. " lane(s), "
			.. table.concat(lines, "; ") .. ", from " .. tostring(#lowNodes)
			.. " street and " .. tostring(#highNodes) .. " rail person nodes."
			.. " The ends are chosen by subconstruction tag, not by height: a"
			.. " lifted platform addon hangs at z = 5 and used to count as grade")
	end
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
	for _i, src in ipairs({ { streetResult, STREET_TAG_BASE, STREET_DIR },
			{ railResult, RAIL_TAG_BASE, nil } }) do
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

	local stockCap, stockTag = addConcourseStock(result, modules or {})
	if stockCap > 0 then
		log.message(LOG .. "concourse goods store: " .. tostring(stockCap)
			.. " of UNIVERSAL storage on subconstruction tag "
			.. tostring(stockTag) .. ", marked as a warehouse. This is what"
			.. " lets freight change level: a station hands cargo to stock in"
			.. " its own catchment, never to another station, and both levels'"
			.. " catchment covers this.")
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
	--- distinguishable on screen: the cell read back is wrong (a cell of
	--- `5.0x40.0` under a station building means `supportCell` fell back
	--- without finding the slot - under a deck tile the fallback and the real
	--- answer are now the same number, which is only lucky), the frame
	--- is wrong (`addModel` multiplies by `result.slots[i].transf`, so this is
	--- the slot's own transform - if its translation is not at grade under the
	--- platform, the slot is misplaced, not the art), or the art does not fill
	--- the frame it is given, which is the only one the models can be blamed
	--- for. Deduped on the whole line, so it costs one line per distinct cell.
	---
	--- `drawn` is the envelope of what was emitted, colliders included
	--- (`drawnExtent`), and it comes out exactly `2 * SUPPORT_SEAM` inside
	--- `cell` - 4.8 x 7.6 in a 5.0 x 7.8 cell - because the block's collider is
	--- its mesh and the seam is the only inset left. Anything else is a bug
	--- here: larger means geometry reaching into the neighbouring cell, which is
	--- what the bulldozer refuses a removal over, and smaller means the cell is
	--- not being filled after all.
	supportUpdateFn = function(captureParams, result, transform, tag, slotId, addModel, constrParams)
		local w, d = supportCell(result, slotId)
		local models = supportModels(w, d)
		local dw, dd = drawnExtent(models)
		local t = transform
		logSupportDraw(string.format(
			"slot=%d cell=%.1fx%.1f drawn=%.1fx%.1f blocks=%d at (%.1f,%.1f,%.1f) xAxis=(%.2f,%.2f)",
			slotId, w, d, dw, dd, #models,
			t and t[13] or 0.0, t and t[14] or 0.0, t and t[15] or 0.0,
			t and t[1] or 0.0, t and t[2] or 0.0))
		for _i, m in ipairs(models) do
			addModel(m.id, m.transf, tag, result.models)
		end
	end,

	--- The placement preview.
	supportGetModelsFn = function(captureParams, params)
		-- No slot context during the preview, so show a **deck tile's** cell,
		-- which is what nearly every support stands in.
		--
		-- This is its own entry point, and that is why the ghost was wrong:
		-- reported 2026-10-22, *"It looks like the support is stretched while
		-- scaling. When hovering to place the cube is about the old size. The
		-- support grows to its current, correct size upon placement."* Nothing
		-- was being stretched - the preview is drawn here and the placed module
		-- by `supportUpdateFn`, and this one still read `SUPPORT_CELL_D`, which
		-- is now only the subdivision pitch under a station building. The cursor
		-- carried a 5 x 8 m block and the slot took a 5 x 40 m one.
		--
		-- A support under a building cell is still previewed a tile long, which
		-- is the cost of there being no slot context on this call: the module
		-- does not know where it is about to go.
		return supportModels(5.0, DECK_TILE)
	end,

	--- The arch's geometry. Placeholder art - see `concourseModels`.
	---
	--- The catchment and capacity this module exists for are **not** applied
	--- here: a module's `updateFn` runs in stage 2, and the station records it
	--- has to write into are assembled by the two families' hooks in stage 3.
	--- So the module declares the numbers in its own `metadata` and
	--- `applyConcourse` reads them back out after the hooks. Same reason the
	--- pedestrian link cannot live here either - and the same reason both
	--- variants need nothing here but their art.
	archUpdateFn = function(captureParams, result, transform, tag, slotId, addModel, constrParams)
		for _i, m in ipairs(concourseModels(CONCOURSE_W, CONCOURSE_D,
				CONCOURSE_SPAN, -CONCOURSE_FLANK)) do
			addModel(m.id, m.transf, tag, result.models)
		end
	end,

	--- The placement preview, offset exactly like the real thing so that what
	--- the cursor drags is where the arch lands.
	archGetModelsFn = function(captureParams, params)
		return concourseModels(CONCOURSE_W, CONCOURSE_D, CONCOURSE_SPAN,
			-CONCOURSE_FLANK)
	end,

	--- The hall's geometry: the same cell with no road through it.
	---
	--- No `cx` offset, unlike the arch: a hall's slot origin is its own cell
	--- centre, because out along the frontage there is no stock rectangle to
	--- dodge and the slot can hold the ground it stands on. That is the one
	--- place the two variants' numbers differ, and `CONCOURSE_CELL_OFFSET` is
	--- where it is written down for the code that needs both.
	hallUpdateFn = function(captureParams, result, transform, tag, slotId, addModel, constrParams)
		for _i, m in ipairs(concourseModels(CONCOURSE_W, CONCOURSE_D,
				CONCOURSE_HALL_SPAN, 0.0)) do
			addModel(m.id, m.transf, tag, result.models)
		end
	end,

	--- The hall's placement preview. The cursor carries the whole cell, which
	--- is what it will fill - a hall has no slot-context problem of the kind
	--- `supportGetModelsFn` describes, because every hall cell is a deck tile.
	hallGetModelsFn = function(captureParams, params)
		return concourseModels(CONCOURSE_W, CONCOURSE_D, CONCOURSE_HALL_SPAN,
			0.0)
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
			local affected = desc ~= nil and desc.roadType == 0
			logTool("add{" .. toolConfigText(conConfigAdd) .. "} remove{"
				.. toolConfigText(conConfigRemove) .. "} roadType="
				.. tostring(desc ~= nil and desc.roadType or "no desc")
				.. " -> " .. tostring(affected))
			return affected
		end
		logTool("add{" .. toolConfigText(conConfigAdd) .. "} remove{"
			.. toolConfigText(conConfigRemove) .. "} no streetTemplate -> true")
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
		local nRail, nStreet, nSupport, nArch, nHall = 0, 0, 0, 0, 0
		for _k, _v in pairs(railModules) do nRail = nRail + 1 end
		for _k, _v in pairs(streetModules) do nStreet = nStreet + 1 end
		for slotId, _v in pairs(params.modules or {}) do
			if type(slotId) == "number" then
				-- Counted by id band, highest first, because the bands are
				-- contiguous and an arch read as a hall would be invisible in
				-- a log that only ever showed one total.
				if slotId >= HALL_SLOT_BASE then
					nHall = nHall + 1
				elseif slotId >= ARCH_SLOT_BASE then
					nArch = nArch + 1
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
		local arches = addArchSlots(result, streetResult, streetModules,
			params.modules)
		-- After the arch's, and reading **both** families: a hall row takes its
		-- frame from the entrance and its extent from the deck. Order does not
		-- matter against the arch - the two layers never contend for a cell,
		-- which is what withholding tile 0 is for - but it is where a reader
		-- expects it.
		local halls = addHallSlots(result, streetResult, railResult, RAIL_XF,
			streetModules, railModules, params.modules)
		-- Must be after `addSupportSlots`, which sizes supports from the rail
		-- slots' reservations, and before the diagnostic, which takes the
		-- originals so it can still report what the modules occupy.
		local reservations = trimReservations(result, railSlots, params.modules,
			RAIL_XF)
		-- After the trim, which is where "a slot that cannot keep a rectangle"
		-- is defined, and before the diagnostics, so their counts are over the
		-- slots the engine is actually given.
		dropUnreservableRailSlots(result, railSlots, RAIL_XF, params.modules)
		-- After the rail guard and before the diagnostics, for the same reason:
		-- a tile-length support cell has to be cut clear of the bus station at
		-- grade or the engine will not offer it at all.
		clipEmptyOurSlots(result, railSlots, params.modules)
		logSlotOverlaps(result, railSlots, RAIL_XF, params.modules, reservations)
		logOrphanModules(result, params.modules)
		-- Last, because it depends on every slot of ours existing: it is what
		-- routes the ones standing on occupied stock ground through it.
		dependOnOccupiedGround(result, railSlots, RAIL_XF, params.modules)

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
			-- Before either hook. The module pass has left rail's
			-- underpass model in the shared - street's - model list, and
			-- street's hook is what buckets that list and builds its lanes.
			moveRailModelsToRail(streetResult, railResult)

			if streetHook ~= nil then streetHook(...) end
			if railHook ~= nil then railHook(...) end

			liftRail(result, railResult, RAIL_XF, railSlots)
			finish(result, streetResult, railResult, params.modules)
			-- After finish: it is what re-reads both families' subconstructions,
			-- so this is the first point at which every lane list exists.
			linkLevels(result, PITCH, params.modules)

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
				.. " arch=" .. tostring(nArch)
				.. " hall=" .. tostring(nHall) .. "; "
				.. tostring(supports) .. " support slots, "
				.. tostring(arches) .. " arch slots, "
				.. tostring(halls) .. " hall slots, "
				.. tostring(#(result.subconstructions or {}))
				.. " subconstructions (tags " .. table.concat(tags, ",") .. "), "
				.. tostring(stations) .. " stations, "
				.. tostring(#(result.slots or {})) .. " slots, "
				.. tostring(#(result.edgeLists or {})) .. " edge lists, rail at +"
				.. tostring(PITCH))
			logStations(result)
		end

		return result
	end,
}
end
