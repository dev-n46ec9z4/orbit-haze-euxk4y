-- Pure helpers for arena maths (no Roblox APIs, so tests/grid.test.luau can run them
-- with the standalone Luau CLI).

local Grid = {}

export type RandomInt = (n: number) -> number

-- 0 = outermost ring of a size x size grid, increasing toward the centre.
function Grid.ringIndex(x: number, z: number, size: number): number
	return math.min(x, z, size - 1 - x, size - 1 - z)
end

-- In-place Fisher-Yates shuffle. `random(n)` must return an integer in [1, n].
function Grid.shuffle<T>(list: { T }, random: RandomInt): { T }
	for i = #list, 2, -1 do
		local j = random(i)
		list[i], list[j] = list[j], list[i]
	end
	return list
end

-- Picks up to `count` items, always taking from the outermost ring that still has
-- items; ties within a ring are broken randomly.
function Grid.pickOuterFirst<T>(items: { T }, count: number, ringOf: (T) -> number, random: RandomInt): { T }
	local byRing: { [number]: { T } } = {}
	local rings = {}
	for _, item in ipairs(items) do
		local ring = ringOf(item)
		if not byRing[ring] then
			byRing[ring] = {}
			table.insert(rings, ring)
		end
		table.insert(byRing[ring], item)
	end
	table.sort(rings)

	local result = {}
	for _, ring in ipairs(rings) do
		local bucket = Grid.shuffle(byRing[ring], random)
		for _, item in ipairs(bucket) do
			if #result >= count then
				return result
			end
			table.insert(result, item)
		end
	end
	return result
end

-- `roll` in [0, 1). Entries are { id, weight }.
function Grid.weightedPick(entries: { { id: string, weight: number } }, roll: number): string
	local total = 0
	for _, entry in ipairs(entries) do
		total += entry.weight
	end
	local target = roll * total
	for _, entry in ipairs(entries) do
		target -= entry.weight
		if target < 0 then
			return entry.id
		end
	end
	return entries[#entries].id
end

-- Seconds between waves: eases linearly from startInterval to endInterval over the round.
function Grid.waveInterval(elapsed: number, roundTime: number, startInterval: number, endInterval: number): number
	local alpha = math.clamp(elapsed / roundTime, 0, 1)
	return startInterval + (endInterval - startInterval) * alpha
end

-- Distance (XZ plane) from point (px, pz) to a beam through (cx, cz) pointing along
-- (dx, dz) (unit vector) with the given half-length. Returns distance and the unit
-- vector from the beam toward the point (falls back to the beam normal).
function Grid.beamDistance(
	px: number,
	pz: number,
	cx: number,
	cz: number,
	dx: number,
	dz: number,
	halfLength: number
): (number, number, number)
	local rx, rz = px - cx, pz - cz
	local along = math.clamp(rx * dx + rz * dz, -halfLength, halfLength)
	local ox, oz = rx - dx * along, rz - dz * along
	local distance = math.sqrt(ox * ox + oz * oz)
	if distance < 1e-3 then
		return distance, -dz, dx
	end
	return distance, ox / distance, oz / distance
end

-- Arena layouts. Returns whether cell (x, z) of a size x size grid holds a tile, and
-- how many studs that tile is raised. `step` is the per-ring rise for "Pyramid".
function Grid.layoutCell(layout: string, x: number, z: number, size: number, step: number): (boolean, number)
	local ring = Grid.ringIndex(x, z, size)
	if layout == "Donut" then
		-- Centre 4x4 (for size 10) is open: rings 0-2 stay.
		return ring < math.floor(size / 2) - 2, 0
	elseif layout == "Cross" then
		-- Two 4-wide arms through the middle.
		local lo = math.floor((size - 4) / 2)
		local hi = lo + 3
		return (x >= lo and x <= hi) or (z >= lo and z <= hi), 0
	elseif layout == "Islands" then
		-- Single-cell channels split the grid into 9 islands; gaps are one tile wide
		-- (8 studs edge to edge), which is a normal running jump.
		local function channel(i: number): boolean
			return i == 3 or i == size - 4
		end
		return not (channel(x) or channel(z)), 0
	elseif layout == "Pyramid" then
		return true, ring * step
	end
	return true, 0 -- "Square"
end

-- Scales a wave's tile count by how big the map is compared with the full square, so
-- smaller layouts don't empty faster. Never returns less than 1.
function Grid.scaleWave(count: number, mapTiles: number, fullTiles: number): number
	return math.max(1, math.floor(count * mapTiles / fullTiles + 0.5))
end

-- Random element of `list` that differs from `last` when possible.
function Grid.pickDifferent<T>(list: { T }, last: T?, random: RandomInt): T
	local candidates = {}
	for _, item in ipairs(list) do
		if item ~= last then
			table.insert(candidates, item)
		end
	end
	if #candidates == 0 then
		return list[1]
	end
	return candidates[random(#candidates)]
end

return Grid
