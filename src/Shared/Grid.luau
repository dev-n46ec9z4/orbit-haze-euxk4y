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

return Grid
