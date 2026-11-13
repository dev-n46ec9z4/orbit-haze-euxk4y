-- Run: node tests/run.mjs
local Grid = require("./Grid")

local failures = 0
local function check(name: string, ok: boolean)
	if not ok then
		failures += 1
		print("FAIL " .. name)
	end
end

-- ringIndex: corners/edges are ring 0, centre of a 10x10 grid is ring 4.
check("ring corner", Grid.ringIndex(0, 0, 10) == 0)
check("ring edge", Grid.ringIndex(9, 5, 10) == 0)
check("ring inner", Grid.ringIndex(1, 1, 10) == 1)
check("ring centre", Grid.ringIndex(4, 5, 10) == 4 and Grid.ringIndex(5, 5, 10) == 4)

-- pickOuterFirst always exhausts the outer ring before touching the next one.
local cells = {}
for x = 0, 9 do
	for z = 0, 9 do
		table.insert(cells, { x = x, z = z })
	end
end
local function ringOf(cell)
	return Grid.ringIndex(cell.x, cell.z, 10)
end
local picked = Grid.pickOuterFirst(cells, 40, ringOf, math.random)
check("outer count", #picked == 40)
local outerOnly = 0
for _, cell in ipairs(picked) do
	if ringOf(cell) == 0 then
		outerOnly += 1
	end
end
-- Ring 0 of a 10x10 grid has 36 cells, so 36 from ring 0 and 4 from ring 1.
check("outer ring first", outerOnly == 36)
check("outer fewer than requested", #Grid.pickOuterFirst({ cells[1] }, 5, ringOf, math.random) == 1)

-- weightedPick respects boundaries.
local entries = { { id = "A", weight = 1 }, { id = "B", weight = 3 } }
check("weighted low", Grid.weightedPick(entries, 0) == "A")
check("weighted boundary", Grid.weightedPick(entries, 0.25) == "B")
check("weighted high", Grid.weightedPick(entries, 0.999) == "B")

-- waveInterval eases 1.2 -> 0.5 over the round and clamps.
check("wave start", math.abs(Grid.waveInterval(0, 60, 1.2, 0.5) - 1.2) < 1e-9)
check("wave mid", math.abs(Grid.waveInterval(30, 60, 1.2, 0.5) - 0.85) < 1e-9)
check("wave clamp", math.abs(Grid.waveInterval(90, 60, 1.2, 0.5) - 0.5) < 1e-9)

-- beamDistance: beam along +X through origin.
local d, ax, az = Grid.beamDistance(3, 2, 0, 0, 1, 0, 10)
check("beam perpendicular", math.abs(d - 2) < 1e-9 and ax == 0 and az == 1)
d = Grid.beamDistance(13, 0, 0, 0, 1, 0, 10)
check("beam past end", math.abs(d - 3) < 1e-9)
d, ax, az = Grid.beamDistance(0, 0, 0, 0, 1, 0, 10)
check("beam on line has normal", d < 1e-3 and math.abs(ax * ax + az * az - 1) < 1e-9)

-- shuffle keeps every element.
local list = { 1, 2, 3, 4, 5, 6 }
Grid.shuffle(list, math.random)
table.sort(list)
check("shuffle keeps elements", table.concat(list, ",") == "1,2,3,4,5,6")

-- Layouts ---------------------------------------------------------------------
local function layoutStats(layout: string)
	local count, maxHeight = 0, 0
	local cellsOn = {}
	for x = 0, 9 do
		cellsOn[x] = {}
		for z = 0, 9 do
			local on, height = Grid.layoutCell(layout, x, z, 10, 1.5)
			cellsOn[x][z] = on
			if on then
				count += 1
				maxHeight = math.max(maxHeight, height)
			end
		end
	end
	return count, maxHeight, cellsOn
end

local squareCount = layoutStats("Square")
check("square has 100 tiles", squareCount == 100)
local donutCount, _, donut = layoutStats("Donut")
check("donut has 84 tiles", donutCount == 84)
check("donut centre open", not donut[4][4] and not donut[3][6] and donut[2][2] and donut[0][9])
local crossCount, _, cross = layoutStats("Cross")
check("cross has 64 tiles", crossCount == 64)
check("cross corners open", not cross[0][0] and not cross[9][9] and cross[3][0] and cross[0][6])
local islandCount, _, islands = layoutStats("Islands")
check("islands has 64 tiles", islandCount == 64)
check("islands channels open", not islands[3][0] and not islands[6][5] and islands[2][2] and islands[4][4])
-- Every channel is exactly one cell wide, so neighbouring islands are one jump apart.
for i = 0, 9 do
	local channel = not islands[i][0]
	if channel then
		check("islands channel width at " .. i, islands[i - 1][0] and islands[i + 1][0])
	end
end
local pyramidCount, pyramidPeak = layoutStats("Pyramid")
check("pyramid full with 6 stud peak", pyramidCount == 100 and math.abs(pyramidPeak - 6) < 1e-9)
local _, edgeHeight = Grid.layoutCell("Pyramid", 0, 5, 10, 1.5)
check("pyramid edge at base", edgeHeight == 0)
check("unknown layout falls back to square", layoutStats("Nope") == 100)
-- Every layout leaves room for a full server of spawns.
for _, layout in ipairs({ "Square", "Donut", "Cross", "Islands", "Pyramid" }) do
	check("layout big enough: " .. layout, (layoutStats(layout)) >= 48)
end

-- scaleWave keeps smaller maps from emptying faster.
check("scale full", Grid.scaleWave(5, 100, 100) == 5)
check("scale islands", Grid.scaleWave(5, 64, 100) == 3 and Grid.scaleWave(3, 64, 100) == 2)
check("scale minimum", Grid.scaleWave(1, 10, 100) == 1)

-- pickDifferent never repeats when there's a choice.
local repeats = 0
for _ = 1, 200 do
	if Grid.pickDifferent({ "A", "B", "C" }, "B", math.random) == "B" then
		repeats += 1
	end
end
check("pickDifferent avoids last", repeats == 0)
check("pickDifferent single", Grid.pickDifferent({ "A" }, "A", math.random) == "A")

if failures > 0 then
	error(failures .. " grid test(s) failed")
end
print("grid tests passed")
