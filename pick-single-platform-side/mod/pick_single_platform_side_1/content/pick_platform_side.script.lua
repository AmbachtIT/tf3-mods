--- Pick Single Platform Side - lets a one-platform street station put its
--- platform on the other side of the entrance.
---
--- The bus station and the cargo truck station are one modular construction,
--- ::/stations/street/modular_street_station/modular_terminal.con. Its
--- createTemplateFn seeds platform modules by slot coordinate, with the
--- entrance sitting between coordI -1 and 0:
---
---     platforms = 1  ->  coordI  0                 (lopsided)
---     platforms = 2  ->  coordI  0, -1
---     platforms = 4  ->  coordI  1, 0, -1, -2
---
--- Only the single-platform case is asymmetric, so mirroring the platform
--- slots with coordI -> -1 - coordI is provably a no-op for 2 and 4 and swaps
--- the sides for 1. That is the whole mod.
---
--- Nothing else needs to change: updateFn in the stock script derives the
--- layout from whichever slots are occupied and already handles a lone
--- coordI == -1 platform - the configuration a player can reach by hand today
--- by adding a left module and deleting the right one. See NOTES.md.

local util = require "::/scripts/util.tl"

local LOG = "[pick-platform-side] "
local SELF = "pick_single_platform_side_1::/pick_platform_side.script"
local STATION = "/stations/street/modular_street_station/modular_terminal.con"
local STATION_DIR = "::/stations/street/modular_street_station"

-- Slot ids, as packed by modular_terminal.script.lua.
local function mangle(coordI, coordJ, variant)
	return 200000 * (coordJ + 100) + 100 * (coordI + 100) + variant
end

local function demangle(slotId)
	local variant = slotId % 100
	local rest = (slotId - variant) / 100
	local i = rest % 2000
	return i - 100, (rest - i) / 2000 - 100, variant
end

-- moduleVariants in modular_terminal.script.lua. Only these two are platforms;
-- everything else (above all the entrance, at the coordI == 55 sentinel) must
-- pass through a mirror untouched.
local PASSENGER_TERMINAL = 0
local CARGO_TERMINAL = 1

local function isPlatform(variant)
	return variant == PASSENGER_TERMINAL or variant == CARGO_TERMINAL
end

local function makeSideParam()
	return {
		key = "platformSide",
		-- "Platform Orientation" and "Standard" are already in the base game's
		-- gettext catalogs for every shipped language, so they localise for
		-- free. "Other side" is not, and comes from this mod's strings.json.
		name = _("Platform Orientation"),
		values = { _("Standard"), _("Other side") },
		defaultIndex = 1,
		displayMode = "Horizontal",
		checkEnabledScript = {
			fileName = SELF .. "@checkSideEnabledFn",
			params = {},
		},
	}
end

--- Absolute ref to the stock createTemplateFn.
---
--- The stock .con declares it relatively ("modular_terminal.script@..."), which
--- would resolve against *our* folder once we are the ones calling it, so it
--- has to be made absolute against the construction's own directory. Derived
--- from the fileName the modifier is handed rather than hardcoded, so a moved
--- or renamed stock script shows up as a log line instead of a silent miss.
local function absoluteStockRef(conFileName, ref)
	if ref == nil or ref == "" then
		return nil
	end
	if string.find(ref, "::", 1, true) or string.sub(ref, 1, 1) == "/" then
		return ref
	end
	local dir = string.match(conFileName, "^(.*)/[^/]*$")
	if dir == nil then
		return nil
	end
	return dir .. "/" .. ref
end

--- Reproduces the stock seeding, used only if the stock function cannot be
--- resolved at placement time (see resolveStockFn). Module names are absolute
--- because they are being returned from a file in a different folder; the stock
--- .con uses the same `::/stations/street/modular_street_station/...` form for
--- its own icons.
local function seedLikeStock(params)
	local cargo = (params.templateIndex or 0) >= 3
	local variant = cargo and CARGO_TERMINAL or PASSENGER_TERMINAL
	local module = STATION_DIR .. "/passenger_platform.module"

	if cargo then
		local bySpecialization = {
			[0] = "cargo_platform.module",
			[1] = "cargo_platform_liquid.module",
			[2] = "cargo_platform_bulk.module",
			[3] = "cargo_platform_flatbed.module",
			[4] = "cargo_platform_goods.module",
		}
		local name = bySpecialization[(params.specialization or 1) - 1]
		module = STATION_DIR .. "/" .. (name or "cargo_platform.module")
	end

	local platforms = params.platforms or 1
	local result = {}

	result[mangle(0, 0, variant)] = module
	result[mangle(0, 1, variant)] = module
	if platforms > 2 then
		result[mangle(1, 0, variant)] = module
		result[mangle(1, 1, variant)] = module
	end

	result[mangle(55, 0, 3)] = STATION_DIR .. "/entrance_exit.module"

	if platforms > 1 then
		result[mangle(-1, 0, variant)] = module
		result[mangle(-1, 1, variant)] = module
	end
	if platforms > 2 then
		result[mangle(-2, 0, variant)] = module
		result[mangle(-2, 1, variant)] = module
	end

	return result
end

local stockFnCache = nil
local stockFnFailed = false

local function resolveStockFn(ref)
	if stockFnCache ~= nil or stockFnFailed then
		return stockFnCache
	end
	-- util.useFn goes through `loaderHelper`, which is what actually gets the
	-- stock script loaded. It is not certain to be reachable from a resource
	-- script, hence the pcall and the fallback.
	local ok, fn = pcall(util.useFn, ref)
	if ok and type(fn) == "function" then
		stockFnCache = fn
		return fn
	end
	stockFnFailed = true
	log.message(LOG .. "could not resolve stock createTemplateFn (" .. tostring(ref)
		.. "), falling back to our own seeding - please report this")
	return nil
end

function data()
return {
	runFn = function(captureParams, settings, allModParams)
		addModifier("loadConstruction", function(fileName, data)
			-- Plain find, not a pattern: the needle contains / and .
			if not string.find(fileName, STATION, 1, true) then
				return data
			end

			local stockRef = absoluteStockRef(fileName,
				data.createTemplateScript and data.createTemplateScript.fileName)
			if stockRef == nil then
				log.message(LOG .. "no createTemplateScript on " .. tostring(fileName)
					.. " - leaving it alone")
				return data
			end

			-- Add the parameter to every template that offers a platform count,
			-- rather than to a hardcoded list, so an added era or a re-enabled
			-- cargo specialisation picks it up too.
			local patched = 0
			for _i, template in ipairs(data.constructionTemplates or {}) do
				local params = template.data and template.data.params
				if params ~= nil then
					local at = nil
					for index, param in ipairs(params) do
						if param.key == "platforms" then
							at = index
						end
					end
					if at ~= nil then
						table.insert(params, at + 1, makeSideParam())
						patched = patched + 1
					end
				end
			end

			if patched == 0 then
				log.message(LOG .. "found no template with a 'platforms' param on "
					.. tostring(fileName) .. " - leaving it alone")
				return data
			end

			data.createTemplateScript = {
				fileName = SELF .. "@createTemplateFn",
				params = {
					stockRef = stockRef,
					stockParams = (data.createTemplateScript.params or {}),
				},
			}

			log.message(LOG .. "patched " .. patched .. " templates of " .. tostring(fileName)
				.. ", wrapping " .. stockRef)

			return data
		end)
	end,

	createTemplateFn = function(captureParams, params)
		-- captureParams is whatever survived the round trip through
		-- createTemplateScript.params; treat it as untrusted.
		local capture = captureParams or {}
		local result
		local stockFn = resolveStockFn(capture.stockRef)
		if stockFn ~= nil then
			result = stockFn(capture.stockParams or {}, params)
		else
			result = seedLikeStock(params)
		end

		-- 1 = Standard, 2 = Other side. Absent means an older savegame or a
		-- hidden param, both of which mean "leave it as the stock layout".
		if (params.platformSide or 1) ~= 2 then
			return result
		end

		local mirrored = {}
		for slotId, module in pairs(result) do
			local coordI, coordJ, variant = demangle(slotId)
			if isPlatform(variant) then
				mirrored[mangle(-1 - coordI, coordJ, variant)] = module
			else
				mirrored[slotId] = module
			end
		end

		return mirrored
	end,

	--- The two symmetric layouts have no side to pick, so the parameter only
	--- shows up for a single platform.
	checkSideEnabledFn = function(captureParams, params)
		if (params.platforms or 1) == 1 then
			return "Enabled"
		end
		return "Hidden"
	end,
}
end
