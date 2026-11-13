-- Mid-round hazards: Meteor, Sweeper and Row Collapse.
-- Every visual is parented under the arena, so destroying the arena removes it; each
-- hazard also stops as soon as ctx.isActive() returns false.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Catalog = require(Shared:WaitForChild("Catalog"))
local Config = require(Shared:WaitForChild("Config"))
local Grid = require(Shared:WaitForChild("Grid"))

local Impulse = require(script.Parent:WaitForChild("Impulse"))
local World = require(script.Parent:WaitForChild("World"))

export type Context = {
	arena: Model,
	isActive: () -> boolean,
	alivePlayers: () -> { Player },
	notify: (text: string, color: Color3?) -> (),
}

local Hazards = {}

local function hazardColor(id: string): Color3
	local entry = Catalog.find(Catalog.Hazards, id)
	return if entry then entry.color else Config.Colors.HazardMarker
end

local function effectPart(props: { [string]: any }): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	for key, value in pairs(props) do
		(part :: any)[key] = value
	end
	return part
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

-- Meteor ----------------------------------------------------------------------

local function meteorStrike(ctx: Context, target: BasePart)
	local impact = target.Position
	local surfaceY = World.getTileTop(target) -- raised tiles on the Pyramid map

	local marker = effectPart({
		Name = "MeteorMarker",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.2, Config.METEOR_SMASH_RADIUS * 2, Config.METEOR_SMASH_RADIUS * 2),
		CFrame = CFrame.new(impact.X, surfaceY + 0.15, impact.Z) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Config.Colors.HazardMarker,
		Transparency = 0.45,
	})
	marker.Parent = ctx.arena

	local meteor = effectPart({
		Name = "Meteor",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(5, 5, 5),
		CFrame = CFrame.new(impact + Vector3.new(0, 90, 0)),
		Color = Config.Colors.Meteor,
	})
	local fire = Instance.new("PointLight")
	fire.Color = Config.Colors.Meteor
	fire.Range = 20
	fire.Brightness = 3
	fire.Parent = meteor
	meteor.Parent = ctx.arena

	local fall = TweenService:Create(
		meteor,
		TweenInfo.new(Config.METEOR_WARN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ CFrame = CFrame.new(impact.X, surfaceY + 2, impact.Z) }
	)
	fall:Play()
	task.wait(Config.METEOR_WARN_TIME)
	meteor:Destroy()
	marker:Destroy()
	if not ctx.isActive() then
		return
	end

	-- Smash tiles in range (reinforced tiles included) and knock nearby players away.
	for _, tile in ipairs(World.getIntactTiles(ctx.arena)) do
		local offset = (tile.Position - impact) * Vector3.new(1, 0, 1)
		if offset.Magnitude <= Config.METEOR_SMASH_RADIUS then
			World.dropTile(tile, 0.15)
		end
	end
	for _, player in ipairs(ctx.alivePlayers()) do
		local root = rootOf(player)
		if root then
			local offset = (root.Position - impact) * Vector3.new(1, 0, 1)
			if offset.Magnitude <= Config.METEOR_SMASH_RADIUS + 2 and math.abs(root.Position.Y - surfaceY) < 10 then
				local away = if offset.Magnitude > 0.1 then offset.Unit else Vector3.xAxis
				Impulse.apply(player.Character, away * Config.METEOR_KNOCKBACK + Vector3.new(0, 35, 0))
			end
		end
	end

	local blast = effectPart({
		Name = "MeteorBlast",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(2, 2, 2),
		CFrame = CFrame.new(impact.X, surfaceY + 1, impact.Z),
		Color = Config.Colors.Meteor,
		Transparency = 0.2,
	})
	blast.Parent = ctx.arena
	local grow = Config.METEOR_SMASH_RADIUS * 2
	TweenService:Create(blast, TweenInfo.new(0.4), { Size = Vector3.new(grow, grow, grow), Transparency = 1 }):Play()
	task.delay(0.45, function()
		blast:Destroy()
	end)
end

local function runMeteor(ctx: Context)
	local intact = World.getIntactTiles(ctx.arena)
	if #intact == 0 then
		return
	end
	ctx.notify("METEOR STRIKE! Leave the red circles", hazardColor("Meteor"))
	Grid.shuffle(intact, math.random)
	for i = 1, math.min(math.random(1, 3), #intact) do
		task.spawn(meteorStrike, ctx, intact[i])
	end
end

-- Sweeper ---------------------------------------------------------------------

local function runSweeper(ctx: Context)
	ctx.notify("SWEEPER! Jump over the beam", hazardColor("Sweeper"))

	local center = Config.ARENA_CENTER
	local surfaceY = World.getSurfaceY()
	local pitch = Config.TILE_SIZE.X + Config.TILE_GAP
	local length = Config.GRID_SIZE * pitch + 4
	local halfLength = length / 2
	local beamY = surfaceY + 1
	local angle = math.random() * math.pi * 2

	local beam = effectPart({
		Name = "Sweeper",
		Size = Vector3.new(length, 1, 1),
		CFrame = CFrame.new(center.X, beamY, center.Z) * CFrame.Angles(0, angle, 0),
		Color = hazardColor("Sweeper"),
		Transparency = 0.8,
	})
	beam.Parent = ctx.arena

	-- Telegraph: fade in before it becomes dangerous.
	TweenService:Create(beam, TweenInfo.new(Config.SWEEPER_WARN_TIME), { Transparency = 0.1 }):Play()
	task.wait(Config.SWEEPER_WARN_TIME)

	local lastHit: { [Player]: number } = {}
	local startTime = os.clock()
	local lastTime = startTime
	local direction = if math.random() < 0.5 then 1 else -1
	while ctx.isActive() and os.clock() - startTime < Config.SWEEPER_DURATION do
		local now = os.clock()
		angle += direction * Config.SWEEPER_SPEED * (now - lastTime)
		lastTime = now
		beam.CFrame = CFrame.new(center.X, beamY, center.Z) * CFrame.Angles(0, angle, 0)

		local axis = beam.CFrame.RightVector
		for _, player in ipairs(ctx.alivePlayers()) do
			local root = rootOf(player)
			if root and now - (lastHit[player] or 0) > 1 then
				local height = root.Position.Y - surfaceY
				local distance, awayX, awayZ =
					Grid.beamDistance(root.Position.X, root.Position.Z, center.X, center.Z, axis.X, axis.Z, halfLength)
				if distance < Config.SWEEPER_HIT_RADIUS and height > -1 and height < Config.SWEEPER_HIT_HEIGHT then
					lastHit[player] = now
					local away = Vector3.new(awayX, 0, awayZ)
					Impulse.apply(player.Character, away * Config.SWEEPER_KNOCKBACK + Vector3.new(0, 30, 0))
				end
			end
		end
		task.wait()
	end
	if beam.Parent then
		beam:Destroy()
	end
end

-- Row collapse ----------------------------------------------------------------

local function runRowCollapse(ctx: Context)
	local candidates = {}
	for _, axis in ipairs({ "X", "Z" }) do
		for index = 0, Config.GRID_SIZE - 1 do
			local line = World.getLine(ctx.arena, axis, index)
			if #line > 0 then
				table.insert(candidates, line)
			end
		end
	end
	if #candidates == 0 then
		return
	end
	ctx.notify("ROW COLLAPSE! Get off the flashing line", hazardColor("RowCollapse"))
	for _, tile in ipairs(candidates[math.random(#candidates)]) do
		World.dropTile(tile, Config.ROW_COLLAPSE_WARN_TIME)
	end
end

-- Public ------------------------------------------------------------------------

local RUNNERS: { [string]: (Context) -> () } = {
	Meteor = runMeteor,
	Sweeper = runSweeper,
	RowCollapse = runRowCollapse,
}

-- Starts a hazard in its own thread. Unknown ids are ignored with a warning.
function Hazards.start(id: string, ctx: Context)
	local runner = RUNNERS[id]
	if not runner then
		warn("[Hazards] Unknown hazard:", id)
		return
	end
	task.spawn(function()
		local ok, err = pcall(runner, ctx)
		if not ok then
			warn("[Hazards]", id, "failed:", err)
		end
	end)
end

function Hazards.has(id: string): boolean
	return RUNNERS[id] ~= nil
end

return Hazards
