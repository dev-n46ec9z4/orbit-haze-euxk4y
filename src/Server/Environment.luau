-- Round environments: lighting, gravity, Blizzard wind gusts and Volcano rising lava.
-- Lighting and gravity are saved before a round and restored in Environment.clear(),
-- so the lobby returns to normal between rounds. Gusts and lava only run during
-- Survive (Environment.startSurvive); the grace period only gets the look and gravity.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Catalog = require(Shared:WaitForChild("Catalog"))
local Config = require(Shared:WaitForChild("Config"))

local Impulse = require(script.Parent:WaitForChild("Impulse"))
local World = require(script.Parent:WaitForChild("World"))

export type SurviveContext = {
	arena: Model,
	isActive: () -> boolean,
	alivePlayers: () -> { Player },
	notify: (text: string, color: Color3?) -> (),
}

local Environment = {}

local LIGHTING_KEYS = { "ClockTime", "Brightness", "Ambient", "OutdoorAmbient", "FogColor", "FogStart", "FogEnd" }

local saved: { [string]: any }? = nil
local savedGravity: number? = nil
local currentId = "Clear"
local lava: BasePart? = nil
local killY = Config.KILL_PLANE_Y

local function settingsFor(id: string)
	return Config.Environments[id] or Config.Environments.Clear
end

local function envColor(id: string): Color3?
	local entry = Catalog.find(Catalog.Environments, id)
	return entry and entry.color
end

-- Y below which players are eliminated: the fixed kill plane, or the lava surface.
function Environment.getKillY(): number
	return killY
end

function Environment.getCurrent(): string
	return currentId
end

-- Applies look + gravity for a round. Call before the grace period.
function Environment.apply(id: string, arena: Model)
	Environment.clear()
	local settings = settingsFor(id)
	currentId = if Config.Environments[id] then id else "Clear"

	saved = {}
	for _, key in ipairs(LIGHTING_KEYS) do
		(saved :: any)[key] = (Lighting :: any)[key]
	end
	savedGravity = Workspace.Gravity

	for key, value in pairs(settings.lighting) do
		(Lighting :: any)[key] = value
	end
	Workspace.Gravity = Config.DEFAULT_GRAVITY * settings.gravityScale

	if settings.lava then
		local part = Instance.new("Part")
		part.Name = "Lava"
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Material = Enum.Material.Neon
		part.Color = Color3.fromRGB(255, 90, 20)
		part.Transparency = 0.15
		part.Size = Vector3.new(220, 2, 220)
		part.CFrame = CFrame.new(Config.ARENA_CENTER.X, Config.KILL_PLANE_Y - 1, Config.ARENA_CENTER.Z)
		local glow = Instance.new("PointLight")
		glow.Color = part.Color
		glow.Range = 40
		glow.Brightness = 2
		glow.Parent = part
		part.Parent = arena
		lava = part
	end
end

local function runLava(ctx: SurviveContext)
	local part = lava
	if not part then
		return
	end
	ctx.notify("THE LAVA IS RISING", envColor("Volcano"))
	local bottomY = Config.KILL_PLANE_Y
	local topY = World.getSurfaceY() - Config.LAVA_MAX_BELOW_SURFACE
	local startTime = os.clock()
	while ctx.isActive() and part.Parent do
		local alpha = math.clamp((os.clock() - startTime) / Config.ROUND_TIME, 0, 1)
		local surface = bottomY + (topY - bottomY) * alpha
		part.CFrame = CFrame.new(Config.ARENA_CENTER.X, surface - part.Size.Y / 2, Config.ARENA_CENTER.Z)
		killY = surface
		task.wait(0.1)
	end
end

local DIRECTIONS = {
	Vector3.new(1, 0, 0),
	Vector3.new(-1, 0, 0),
	Vector3.new(0, 0, 1),
	Vector3.new(0, 0, -1),
}

local function runGust(ctx: SurviveContext, direction: Vector3)
	ctx.notify("WIND GUST! Watch the white front", envColor("Blizzard"))

	-- Telegraph: a translucent wall sweeps across the arena in the gust direction.
	local span = Config.GRID_SIZE * (Config.TILE_SIZE.X + Config.TILE_GAP) + 10
	local half = span / 2
	local center = Vector3.new(Config.ARENA_CENTER.X, World.getSurfaceY() + 6, Config.ARENA_CENTER.Z)
	local front = Instance.new("Part")
	front.Name = "GustFront"
	front.Anchored = true
	front.CanCollide = false
	front.CanQuery = false
	front.CanTouch = false
	front.CastShadow = false
	front.Material = Enum.Material.Neon
	front.Color = Color3.fromRGB(240, 248, 255)
	front.Transparency = 0.8
	front.Size = if direction.X ~= 0 then Vector3.new(1, 12, span) else Vector3.new(span, 12, 1)
	front.CFrame = CFrame.new(center - direction * half)
	front.Parent = ctx.arena
	TweenService:Create(front, TweenInfo.new(Config.GUST_WARN_TIME, Enum.EasingStyle.Linear), {
		CFrame = CFrame.new(center + direction * half),
	}):Play()
	task.wait(Config.GUST_WARN_TIME)
	front:Destroy()
	if not ctx.isActive() then
		return
	end
	for _, player in ipairs(ctx.alivePlayers()) do
		Impulse.push(player.Character, direction * Config.GUST_SPEED, Config.GUST_DURATION)
	end
end

local function runGusts(ctx: SurviveContext, interval: number)
	task.wait(interval / 2)
	while ctx.isActive() do
		runGust(ctx, DIRECTIONS[math.random(#DIRECTIONS)])
		task.wait(interval)
	end
end

-- Starts Survive-only effects (lava, gusts) in their own threads.
function Environment.startSurvive(ctx: SurviveContext)
	local settings = settingsFor(currentId)
	local function guarded(fn: (...any) -> (), ...)
		local args = table.pack(...)
		task.spawn(function()
			local ok, err = pcall(fn, table.unpack(args, 1, args.n))
			if not ok then
				warn("[Environment]", currentId, "failed:", err)
			end
		end)
	end
	if settings.lava then
		guarded(runLava, ctx)
	end
	if settings.gustInterval > 0 then
		guarded(runGusts, ctx, settings.gustInterval)
	end
end

-- Restores lighting and gravity and resets the kill height. Safe to call repeatedly.
function Environment.clear()
	if saved then
		for key, value in pairs(saved) do
			(Lighting :: any)[key] = value
		end
		saved = nil
	end
	if savedGravity then
		Workspace.Gravity = savedGravity
		savedGravity = nil
	end
	if lava and lava.Parent then
		lava:Destroy()
	end
	lava = nil
	killY = Config.KILL_PLANE_Y
	currentId = "Clear"
end

return Environment
