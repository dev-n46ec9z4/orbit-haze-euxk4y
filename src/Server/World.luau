-- Procedural world geometry: sky lobby and the falling-tile arena.
-- Every instance is fully configured before it is parented.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local Colors = Config.Colors

local World = {}

local TILE_INTACT = "Intact"
local TILE_FALLING = "Falling"

local function makePart(props: { [string]: any }): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in pairs(props) do
		(part :: any)[key] = value
	end
	return part
end

-- Lobby -----------------------------------------------------------------------

local lobbySpawn: SpawnLocation? = nil

function World.buildLobby(): Model
	local existing = Workspace:FindFirstChild("Lobby")
	if existing then
		existing:Destroy()
	end

	local origin = Config.LOBBY_POSITION
	local size = Config.LOBBY_SIZE
	local halfX, halfZ = size.X / 2, size.Z / 2
	local floorTop = origin.Y + size.Y / 2
	local barrierHeight = Config.LOBBY_BARRIER_HEIGHT

	local model = Instance.new("Model")
	model.Name = "Lobby"

	local floor = makePart({
		Name = "Floor",
		Size = size,
		CFrame = CFrame.new(origin),
		Material = Enum.Material.Slate,
		Color = Colors.LobbyFloor,
	})
	floor.Parent = model
	model.PrimaryPart = floor

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "LobbySpawn"
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.AllowTeamChangeOnTouch = false
	spawn.Duration = 0
	spawn.Size = Vector3.new(10, 1, 10)
	spawn.CFrame = CFrame.new(origin.X, floorTop + 0.5, origin.Z)
	spawn.Material = Enum.Material.Neon
	spawn.Color = Colors.SpawnPad
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.BottomSurface = Enum.SurfaceType.Smooth
	spawn.Parent = model
	lobbySpawn = spawn

	-- Translucent barriers around the platform edge.
	local walls = {
		{ Vector3.new(size.X, barrierHeight, 1), Vector3.new(0, 0, halfZ - 0.5) },
		{ Vector3.new(size.X, barrierHeight, 1), Vector3.new(0, 0, -halfZ + 0.5) },
		{ Vector3.new(1, barrierHeight, size.Z), Vector3.new(halfX - 0.5, 0, 0) },
		{ Vector3.new(1, barrierHeight, size.Z), Vector3.new(-halfX + 0.5, 0, 0) },
	}
	for index, wall in ipairs(walls) do
		local wallSize, offset = wall[1], wall[2]
		local center = Vector3.new(origin.X + offset.X, floorTop + barrierHeight / 2, origin.Z + offset.Z)

		local barrier = makePart({
			Name = "Barrier" .. index,
			Size = wallSize,
			CFrame = CFrame.new(center),
			Material = Enum.Material.Glass,
			Color = Colors.LobbyBarrier,
			Transparency = 0.7,
			CastShadow = false,
		})
		barrier.Parent = model

		-- Warm neon trim along the floor edge and along the barrier top.
		for _, trimY in ipairs({ floorTop + 0.25, floorTop + barrierHeight + 0.25 }) do
			local trimSize = Vector3.new(
				if wallSize.X > 1 then wallSize.X else 1.2,
				0.5,
				if wallSize.Z > 1 then wallSize.Z else 1.2
			)
			local trim = makePart({
				Name = "Trim" .. index,
				Size = trimSize,
				CFrame = CFrame.new(center.X, trimY, center.Z),
				Material = Enum.Material.Neon,
				Color = Colors.WarmNeon,
				CanCollide = false,
				CastShadow = false,
			})
			trim.Parent = model
		end
	end

	-- Warm corner lights.
	for _, corner in ipairs({ { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }) do
		local pillar = makePart({
			Name = "CornerPillar",
			Size = Vector3.new(1.5, barrierHeight, 1.5),
			CFrame = CFrame.new(
				origin.X + corner[1] * (halfX - 0.75),
				floorTop + barrierHeight / 2,
				origin.Z + corner[2] * (halfZ - 0.75)
			),
			Material = Enum.Material.Neon,
			Color = Colors.WarmNeon,
			CastShadow = false,
		})
		local light = Instance.new("PointLight")
		light.Color = Colors.WarmNeon
		light.Range = 18
		light.Brightness = 1.5
		light.Parent = pillar
		pillar.Parent = model
	end

	model.Parent = Workspace
	return model
end

-- Returns a CFrame on the lobby platform near the spawn pad.
function World.getLobbyCFrame(): CFrame
	local base = if lobbySpawn and lobbySpawn.Parent
		then lobbySpawn.Position
		else Config.LOBBY_POSITION + Vector3.new(0, Config.LOBBY_SIZE.Y / 2 + 1, 0)
	local offset = Vector3.new(math.random(-8, 8), 4, math.random(-8, 8))
	return CFrame.new(base + offset)
end

-- Arena -----------------------------------------------------------------------

function World.buildArena(): Model
	local existing = Workspace:FindFirstChild("Arena")
	if existing then
		existing:Destroy()
	end

	local model = Instance.new("Model")
	model.Name = "Arena"

	local tiles = Instance.new("Folder")
	tiles.Name = "Tiles"
	tiles.Parent = model

	local grid = Config.GRID_SIZE
	local tileSize = Config.TILE_SIZE
	local pitch = tileSize.X + Config.TILE_GAP
	local centerOffset = (grid - 1) / 2
	local center = Config.ARENA_CENTER

	for x = 0, grid - 1 do
		for z = 0, grid - 1 do
			local color = if (x + z) % 2 == 0 then Colors.TileA else Colors.TileB
			local tile = makePart({
				Name = string.format("Tile_%d_%d", x, z),
				Size = tileSize,
				CFrame = CFrame.new(
					center.X + (x - centerOffset) * pitch,
					center.Y,
					center.Z + (z - centerOffset) * pitch
				),
				Material = Enum.Material.SmoothPlastic,
				Color = color,
			})
			tile:SetAttribute("State", TILE_INTACT)
			tile.Parent = tiles
		end
	end

	model.Parent = Workspace
	return model
end

local function getIntactTiles(arena: Model): { BasePart }
	local result = {}
	local tiles = arena:FindFirstChild("Tiles")
	if not tiles then
		return result
	end
	for _, tile in ipairs(tiles:GetChildren()) do
		if tile:IsA("BasePart") and tile:GetAttribute("State") == TILE_INTACT then
			table.insert(result, tile)
		end
	end
	return result
end

function World.countIntactTiles(arena: Model?): number
	if not arena then
		return 0
	end
	return #getIntactTiles(arena)
end

-- Returns `count` spawn CFrames above random distinct intact tiles (cycling if needed).
function World.getSpawnCFrames(arena: Model, count: number): { CFrame }
	local tiles = getIntactTiles(arena)
	local result = {}
	if #tiles == 0 then
		for _ = 1, count do
			table.insert(result, CFrame.new(Config.ARENA_CENTER + Vector3.new(0, 4, 0)))
		end
		return result
	end

	-- Fisher-Yates shuffle
	for i = #tiles, 2, -1 do
		local j = math.random(i)
		tiles[i], tiles[j] = tiles[j], tiles[i]
	end

	local lift = Config.TILE_SIZE.Y / 2 + 3
	for i = 1, count do
		local tile = tiles[((i - 1) % #tiles) + 1]
		table.insert(result, CFrame.new(tile.Position + Vector3.new(0, lift, 0)))
	end
	return result
end

local function dropTile(tile: BasePart)
	tile:SetAttribute("State", TILE_FALLING)

	task.spawn(function()
		local flashes = 3
		local step = Config.TILE_FLASH_TIME / (flashes * 2)
		tile.Material = Enum.Material.Neon
		for _ = 1, flashes do
			if not tile.Parent then
				return
			end
			tile.Color = Colors.TileWarn
			task.wait(step)
			if not tile.Parent then
				return
			end
			tile.Color = Colors.TileWarnDim
			task.wait(step)
		end
		if not tile.Parent then
			return
		end

		tile.Color = Colors.TileWarn
		tile.Anchored = false
		pcall(function()
			tile:SetNetworkOwner(nil)
		end)

		task.delay(Config.TILE_DESTROY_DELAY, function()
			if tile.Parent then
				tile:Destroy()
			end
		end)
	end)
end

-- Drops up to `count` random intact tiles. Returns how many were dropped.
function World.dropWave(arena: Model?, count: number): number
	if not arena or not arena.Parent then
		return 0
	end
	local intact = getIntactTiles(arena)
	local dropped = 0
	for _ = 1, math.min(count, #intact) do
		local tile = table.remove(intact, math.random(#intact))
		dropTile(tile)
		dropped += 1
	end
	return dropped
end

function World.destroyArena(arena: Model?)
	if arena then
		arena:Destroy()
	end
end

return World
