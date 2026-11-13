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

for _, listName in ipairs({ "Modes", "TileTypes", "Hazards", "PowerUps" }) do
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

if failures > 0 then
	error(failures .. " catalog test(s) failed")
end
print("catalog tests passed")
