-- Run: node tests/run.mjs
-- Checks that every id used by Config has player-facing text in Catalog (so the HUD
-- guide covers every feature) and that every Catalog entry is complete.

local Catalog = require("./Catalog")
local Config = require("./Config")

local failures = 0
local function check(name: string, ok: boolean)
	if not ok then
		failures += 1
		print("FAIL " .. name)
	end
end

for _, listName in ipairs({ "Modes", "TileTypes", "Hazards", "PowerUps", "Maps", "Environments", "Modifiers" }) do
	local seen = {}
	for _, entry in ipairs(Catalog[listName]) do
		check(listName .. " entry complete: " .. tostring(entry.id), type(entry.id) == "string"
			and type(entry.name) == "string"
			and type(entry.description) == "string"
			and #entry.description > 0
			and type(entry.color) == "table")
		check(listName .. " unique id: " .. entry.id, not seen[entry.id])
		seen[entry.id] = true
	end
end

for _, weight in ipairs(Config.TILE_TYPE_WEIGHTS) do
	check("tile type in catalog: " .. weight.id, Catalog.find(Catalog.TileTypes, weight.id) ~= nil)
	check("tile weight positive: " .. weight.id, weight.weight > 0)
end
for _, entry in ipairs(Catalog.TileTypes) do
	local weighted = false
	for _, weight in ipairs(Config.TILE_TYPE_WEIGHTS) do
		weighted = weighted or weight.id == entry.id
	end
	check("catalog tile has weight: " .. entry.id, weighted)
end

check("mode order matches catalog", #Config.MODE_ORDER == #Catalog.Modes)
local knownHazards = { Meteor = true, Sweeper = true, RowCollapse = true } -- Hazards.luau RUNNERS
for _, modeId in ipairs(Config.MODE_ORDER) do
	local mode = Config.Modes[modeId]
	check("mode settings: " .. modeId, mode ~= nil)
	check("mode in catalog: " .. modeId, Catalog.find(Catalog.Modes, modeId) ~= nil)
	if mode then
		check("mode pattern: " .. modeId, mode.pattern == "Random" or mode.pattern == "OuterFirst")
		check("mode wave sizes: " .. modeId, mode.waveMin >= 1 and mode.waveMax >= mode.waveMin)
		check("mode intervals: " .. modeId, mode.hazardInterval > 0 and mode.powerUpInterval > 0)
		for _, hazard in ipairs(mode.hazards) do
			check("hazard implemented: " .. hazard, knownHazards[hazard] == true)
			check("hazard in catalog: " .. hazard, Catalog.find(Catalog.Hazards, hazard) ~= nil)
		end
	end
end

-- Maps, environments, modifiers: order lists, settings and catalog text line up.
local function checkOrdered(label: string, order: { string }, settings: { [string]: any }, list)
	check(label .. " order matches catalog", #order == #list)
	local settingCount = 0
	for _ in pairs(settings) do
		settingCount += 1
	end
	check(label .. " settings match order", settingCount == #order)
	for _, id in ipairs(order) do
		check(label .. " settings: " .. id, settings[id] ~= nil)
		check(label .. " in catalog: " .. id, Catalog.find(list, id) ~= nil)
	end
end
checkOrdered("map", Config.MAP_ORDER, Config.Maps, Catalog.Maps)
checkOrdered("environment", Config.ENVIRONMENT_ORDER, Config.Environments, Catalog.Environments)
checkOrdered("modifier", Config.MODIFIER_ORDER, Config.Modifiers, Catalog.Modifiers)
-- First round is the original game.
check("first map is Square", Config.MAP_ORDER[1] == "Square")
check("first environment is Clear", Config.ENVIRONMENT_ORDER[1] == "Clear")
check("first modifier is None", Config.MODIFIER_ORDER[1] == "None")

for id, map in pairs(Config.Maps) do
	for _, hazard in ipairs(map.blockedHazards) do
		check("blocked hazard exists: " .. id .. "/" .. hazard, knownHazards[hazard] == true)
	end
end
-- Every mode keeps at least one hazard on every map.
for modeId, mode in pairs(Config.Modes) do
	for mapId, map in pairs(Config.Maps) do
		local remaining = 0
		for _, hazard in ipairs(mode.hazards) do
			if not table.find(map.blockedHazards, hazard) then
				remaining += 1
			end
		end
		check("hazards left for " .. modeId .. " on " .. mapId, remaining > 0)
	end
end

for id, env in pairs(Config.Environments) do
	check("environment gravity: " .. id, env.gravityScale > 0 and env.gravityScale <= 1)
	check("environment gusts: " .. id, env.gustInterval == 0 or env.gustInterval > Config.GUST_WARN_TIME)
	check("environment lighting table: " .. id, type(env.lighting) == "table")
end
check("clear environment changes nothing", next(Config.Environments.Clear.lighting) == nil
	and Config.Environments.Clear.gravityScale == 1)

for id, mod in pairs(Config.Modifiers) do
	check("modifier complete: " .. id, type(mod.waveIntervalScale) == "number"
		and type(mod.powerUpIntervalScale) == "number"
		and type(mod.maxPowerUps) == "number"
		and type(mod.regrowInterval) == "number"
		and type(mod.allIce) == "boolean"
		and type(mod.bonusCoins) == "number")
	check("modifier ranges: " .. id, mod.waveIntervalScale > 0 and mod.powerUpIntervalScale > 0
		and mod.maxPowerUps >= 1 and mod.regrowInterval >= 0 and mod.bonusCoins >= 0)
end
check("regrow outlasts ghost phase", Config.Modifiers.Regrowth.regrowInterval > Config.REGROW_TIME)

-- Rescue / lava interaction (mirrors PowerUps.rescueHeight and Environment lava limits):
-- the rescue must trigger above the highest lava, and below the tiles so nobody standing
-- on the arena is "rescued".
local surfaceY = Config.ARENA_CENTER.Y + Config.TILE_SIZE.Y / 2
local tileBottom = Config.ARENA_CENTER.Y - Config.TILE_SIZE.Y / 2
local function rescueHeight(killY)
	return math.max(Config.ARENA_CENTER.Y - Config.RESCUE_DROP_DEPTH, killY + 3)
end
local maxLava = surfaceY - Config.LAVA_MAX_BELOW_SURFACE
check("lava stays below tiles", maxLava < tileBottom)
check("rescue above max lava", rescueHeight(maxLava) > maxLava)
check("rescue below tile bottoms", rescueHeight(maxLava) < tileBottom)
check("rescue above kill plane", rescueHeight(Config.KILL_PLANE_Y) > Config.KILL_PLANE_Y)

if failures > 0 then
	error(failures .. " catalog test(s) failed")
end
print("catalog tests passed")
