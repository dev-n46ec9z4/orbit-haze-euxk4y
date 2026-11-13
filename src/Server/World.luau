-- Procedural world geometry: sky lobby and the falling-tile arena.
-- Every instance is fully configured before it is parented.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Catalog = require(Shared:WaitForChild("Catalog"))
local Config = require(Shared:WaitForChild("Config"))
local Grid = require(Shared:WaitForChild("Grid"))

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

local function catalogColor(id: string): Color3
	local entry = Catalog.find(Catalog.TileTypes, id)
	return if entry then entry.color else Colors.TileA
end

local CONVEYOR_DIRECTIONS = {
	Vector3.new(1, 0, 0),
	Vector3.new(-1, 0, 0),
	Vector3.new(0, 0, 1),
	Vector3.new(0, 0, -1),
}

-- Non-colliding, non-queryable detail welded to a tile so it falls with it.
local function addDecoration(tile: BasePart, props: { [string]: any })
	local deco = makePart(props)
	deco.Name = "Decoration"
	deco.Anchored = false
	deco.Massless = true
	deco.CanCollide = false
	deco.CanQuery = false
	deco.CanTouch = false
	deco.CastShadow = false
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = tile
	weld.Part1 = deco
	weld.Parent = deco
	deco.Parent = tile
end

local function styleTile(tile: BasePart, tileType: string, checkerColor: Color3)
	tile:SetAttribute("TileType", tileType)
	local top = tile.Position.Y + tile.Size.Y / 2

	if tileType == "Normal" then
		tile.Color = checkerColor
	elseif tileType == "Ice" then
		tile.Material = Enum.Material.Ice
		tile.Color = catalogColor("Ice")
		tile.Reflectance = 0.15
		tile.CustomPhysicalProperties = PhysicalProperties.new(0.9, Config.ICE_FRICTION, 0, 100, 1)
	elseif tileType == "Crumble" then
		tile.Material = Enum.Material.Sand
		tile.Color = catalogColor("Crumble")
	elseif tileType == "Reinforced" then
		tile.Material = Enum.Material.DiamondPlate
		tile.Color = catalogColor("Reinforced")
	elseif tileType == "Bounce" then
		tile.Color = catalogColor("Bounce")
		addDecoration(tile, {
			Size = Vector3.new(3.5, 0.2, 3.5),
			CFrame = CFrame.new(tile.Position.X, top + 0.1, tile.Position.Z),
			Material = Enum.Material.Neon,
			Color = Color3.fromRGB(200, 255, 210),
		})
	elseif tileType == "Conveyor" then
		local direction = CONVEYOR_DIRECTIONS[math.random(#CONVEYOR_DIRECTIONS)]
		tile.Color = catalogColor("Conveyor")
		tile:SetAttribute("ConveyorDirection", direction)
		-- Glowing strip on the edge the conveyor pushes toward.
		local edge = tile.Position + direction * (tile.Size.X / 2 - 0.5)
		addDecoration(tile, {
			Size = if direction.X ~= 0 then Vector3.new(1, 0.2, tile.Size.Z) else Vector3.new(tile.Size.X, 0.2, 1),
			CFrame = CFrame.new(edge.X, top + 0.1, edge.Z),
			Material = Enum.Material.Neon,
			Color = Color3.fromRGB(255, 240, 170),
		})
	end
end

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
			local checker = if (x + z) % 2 == 0 then Colors.TileA else Colors.TileB
			local tile = makePart({
				Name = string.format("Tile_%d_%d", x, z),
				Size = tileSize,
				CFrame = CFrame.new(
					center.X + (x - centerOffset) * pitch,
					center.Y,
					center.Z + (z - centerOffset) * pitch
				),
				Material = Enum.Material.SmoothPlastic,
				Color = checker,
			})
			tile:SetAttribute("State", TILE_INTACT)
			tile:SetAttribute("GridX", x)
			tile:SetAttribute("GridZ", z)
			styleTile(tile, Grid.weightedPick(Config.TILE_TYPE_WEIGHTS, math.random()), checker)
			tile.Parent = tiles
		end
	end

	model.Parent = Workspace
	return model
end

function World.getTilesFolder(arena: Model?): Folder?
	local folder = arena and arena:FindFirstChild("Tiles")
	return if folder and folder:IsA("Folder") then folder else nil
end

local function getIntactTiles(arena: Model): { BasePart }
	local result = {}
	local tiles = World.getTilesFolder(arena)
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
World.getIntactTiles = getIntactTiles

function World.isIntact(tile: Instance?): boolean
	return tile ~= nil and tile.Parent ~= nil and tile:GetAttribute("State") == TILE_INTACT
end

function World.countIntactTiles(arena: Model?): number
	if not arena then
		return 0
	end
	return #getIntactTiles(arena)
end

-- Y of the tile tops (arena surface).
function World.getSurfaceY(): number
	return Config.ARENA_CENTER.Y + Config.TILE_SIZE.Y / 2
end

-- Returns `count` spawn CFrames above random distinct intact tiles (cycling if needed).
-- Normal tiles are preferred so nobody starts on ice, a bounce pad or a crumble tile.
function World.getSpawnCFrames(arena: Model, count: number): { CFrame }
	local all = getIntactTiles(arena)
	local result = {}
	if #all == 0 then
		for _ = 1, count do
			table.insert(result, CFrame.new(Config.ARENA_CENTER + Vector3.new(0, 4, 0)))
		end
		return result
	end

	local normal = {}
	for _, tile in ipairs(all) do
		if tile:GetAttribute("TileType") == "Normal" then
			table.insert(normal, tile)
		end
	end
	local tiles = if #normal >= count then normal else all
	Grid.shuffle(tiles, math.random)

	local lift = Config.TILE_SIZE.Y / 2 + 3
	for i = 1, count do
		local tile = tiles[((i - 1) % #tiles) + 1]
		table.insert(result, CFrame.new(tile.Position + Vector3.new(0, lift, 0)))
	end
	return result
end

-- Starts tile behaviours that should not run during the grace period (conveyors).
function World.activateTiles(arena: Model?)
	if not arena then
		return
	end
	for _, tile in ipairs(getIntactTiles(arena)) do
		local direction = tile:GetAttribute("ConveyorDirection")
		if typeof(direction) == "Vector3" then
			-- An anchored part with velocity moves whatever stands on it.
			tile.AssemblyLinearVelocity = direction * Config.CONVEYOR_SPEED
		end
	end
end

-- Flashes a tile red for `flashTime` seconds, then drops it. Safe to call on any tile;
-- tiles that are already falling are ignored.
function World.dropTile(tile: BasePart, flashTime: number?)
	if not World.isIntact(tile) then
		return
	end
	tile:SetAttribute("State", TILE_FALLING)
	local warnTime = flashTime or Config.TILE_FLASH_TIME

	task.spawn(function()
		local flashes = math.max(1, math.round(warnTime / 0.2))
		local step = warnTime / (flashes * 2)
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
		tile.AssemblyLinearVelocity = Vector3.zero
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

-- A wave picking a tile: reinforced tiles crack first and only fall the second time.
local function hitByWave(tile: BasePart)
	if tile:GetAttribute("TileType") == "Reinforced" and not tile:GetAttribute("Cracked") then
		tile:SetAttribute("Cracked", true)
		tile.Material = Enum.Material.CrackedLava
		tile.Color = Colors.TileCracked
		return
	end
	World.dropTile(tile)
end

-- Picks up to `count` intact tiles. pattern "OuterFirst" takes the outermost ring first.
-- Returns how many tiles were hit.
function World.dropWave(arena: Model?, count: number, pattern: string?): number
	if not arena or not arena.Parent then
		return 0
	end
	local intact = getIntactTiles(arena)
	local chosen
	if pattern == "OuterFirst" then
		chosen = Grid.pickOuterFirst(intact, count, function(tile: BasePart)
			local x = tonumber(tile:GetAttribute("GridX")) or 0
			local z = tonumber(tile:GetAttribute("GridZ")) or 0
			return Grid.ringIndex(x, z, Config.GRID_SIZE)
		end, math.random)
	else
		chosen = table.move(Grid.shuffle(intact, math.random), 1, math.min(count, #intact), 1, {})
	end
	for _, tile in ipairs(chosen) do
		hitByWave(tile)
	end
	return #chosen
end

-- Intact tiles in one grid row ("X" = fixed GridX) or column ("Z" = fixed GridZ).
function World.getLine(arena: Model, axis: string, index: number): { BasePart }
	local result = {}
	local attribute = if axis == "X" then "GridX" else "GridZ"
	for _, tile in ipairs(getIntactTiles(arena)) do
		if tile:GetAttribute(attribute) == index then
			table.insert(result, tile)
		end
	end
	return result
end

function World.destroyArena(arena: Model?)
	if arena then
		arena:Destroy()
	end
end

return World
