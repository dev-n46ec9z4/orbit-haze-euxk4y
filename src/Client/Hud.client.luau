-- Procedural HUD: top-center phase banner with timer + Alive count,
-- top-right Wins/Coins card bound to leaderstats.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Format = require(Shared:WaitForChild("Format"))
local Net = require(Shared:WaitForChild("Net"))

local Phases = Config.Phases
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local PHASE_COLORS = {
	[Phases.Waiting] = Color3.fromRGB(170, 170, 185),
	[Phases.Intermission] = Color3.fromRGB(255, 170, 70),
	[Phases.Grace] = Color3.fromRGB(255, 225, 90),
	[Phases.Survive] = Color3.fromRGB(255, 80, 80),
	[Phases.Results] = Color3.fromRGB(120, 235, 140),
}

local FONT_BOLD = Enum.Font.GothamBlack
local FONT_BODY = Enum.Font.GothamBold
local PANEL_COLOR = Color3.fromRGB(22, 20, 30)
local TEXT_COLOR = Color3.fromRGB(245, 240, 235)
local FAST = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local SMOOTH = TweenInfo.new(0.45, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

local function create(className: string, props: { [string]: any }, children: { Instance }?): Instance
	local instance = Instance.new(className)
	local parent = props.Parent
	for key, value in pairs(props) do
		if key ~= "Parent" then
			(instance :: any)[key] = value
		end
	end
	if children then
		for _, child in ipairs(children) do
			child.Parent = instance
		end
	end
	-- Parent last, after the instance is fully configured.
	if parent then
		instance.Parent = parent
	end
	return instance
end

local function label(props: { [string]: any }): TextLabel
	local defaults = {
		BackgroundTransparency = 1,
		TextColor3 = TEXT_COLOR,
		Font = FONT_BODY,
		TextScaled = true,
	}
	for key, value in pairs(props) do
		defaults[key] = value
	end
	return create("TextLabel", defaults) :: TextLabel
end

-- Build GUI -------------------------------------------------------------------

local existing = playerGui:FindFirstChild("FallingTilesHud")
if existing then
	existing:Destroy()
end

local screenGui = create("ScreenGui", {
	Name = "FallingTilesHud",
	ResetOnSpawn = false,
	IgnoreGuiInset = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	DisplayOrder = 10,
}) :: ScreenGui

-- Top-center phase banner
local bannerScale = create("UIScale", { Scale = 1 }) :: UIScale
local bannerStroke = create("UIStroke", {
	Thickness = 2,
	Color = PHASE_COLORS[Phases.Waiting],
	Transparency = 0.1,
}) :: UIStroke

local phaseLabel = label({
	Name = "Phase",
	Text = "WAITING FOR PLAYERS",
	Font = FONT_BOLD,
	TextColor3 = PHASE_COLORS[Phases.Waiting],
	Size = UDim2.new(1, -24, 0, 40),
	Position = UDim2.fromOffset(12, 8),
})

local timerLabel = label({
	Name = "Timer",
	Text = "--",
	TextXAlignment = Enum.TextXAlignment.Left,
	Size = UDim2.new(0.5, -18, 0, 24),
	Position = UDim2.new(0, 14, 0, 54),
})

local aliveLabel = label({
	Name = "Alive",
	Text = "ALIVE: 0",
	TextXAlignment = Enum.TextXAlignment.Right,
	Size = UDim2.new(0.5, -18, 0, 24),
	Position = UDim2.new(0.5, 4, 0, 54),
})

local bannerHome = UDim2.new(0.5, 0, 0, 10)
local banner = create("Frame", {
	Name = "PhaseBanner",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = bannerHome,
	Size = UDim2.fromOffset(380, 88),
	BackgroundColor3 = PANEL_COLOR,
	BackgroundTransparency = 0.2,
	Parent = screenGui,
}, {
	create("UICorner", { CornerRadius = UDim.new(0, 14) }),
	bannerStroke,
	bannerScale,
	phaseLabel,
	timerLabel,
	aliveLabel,
}) :: Frame

-- Top-right stats card
local winsValue = label({
	Name = "Wins",
	Text = "WINS  0",
	TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = Color3.fromRGB(255, 214, 110),
	Size = UDim2.new(1, -24, 0, 24),
	Position = UDim2.fromOffset(12, 34),
})
local coinsValue = label({
	Name = "Coins",
	Text = "COINS 0",
	TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = Color3.fromRGB(255, 180, 80),
	Size = UDim2.new(1, -24, 0, 24),
	Position = UDim2.fromOffset(12, 62),
})

create("Frame", {
	Name = "StatsCard",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -12, 0, 10),
	Size = UDim2.fromOffset(190, 96),
	BackgroundColor3 = PANEL_COLOR,
	BackgroundTransparency = 0.2,
	Parent = screenGui,
}, {
	create("UICorner", { CornerRadius = UDim.new(0, 12) }),
	create("UIStroke", { Thickness = 2, Color = Config.Colors.WarmNeon, Transparency = 0.3 }),
	label({
		Name = "Title",
		Text = "YOUR STATS",
		Font = FONT_BOLD,
		TextColor3 = Color3.fromRGB(200, 195, 210),
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -24, 0, 18),
		Position = UDim2.fromOffset(12, 10),
	}),
	winsValue,
	coinsValue,
})

screenGui.Parent = playerGui

-- The stats card replaces the default top-right player list, which would overlap it.
task.spawn(function()
	for _ = 1, 10 do
		local ok = pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
		end)
		if ok then
			return
		end
		task.wait(0.5)
	end
end)

-- Animations ----------------------------------------------------------------

local function pulse(target: TextLabel)
	local scale = target:FindFirstChildOfClass("UIScale")
	if not scale then
		scale = create("UIScale", { Scale = 1, Parent = target }) :: UIScale
	end
	scale.Scale = 1.2
	TweenService:Create(scale, FAST, { Scale = 1 }):Play()
end

local function transitionTo(phase: string)
	local color = PHASE_COLORS[phase] or TEXT_COLOR

	-- Drop in from above and settle with a slight pop.
	banner.Position = bannerHome - UDim2.fromOffset(0, 24)
	bannerScale.Scale = 0.9
	phaseLabel.TextTransparency = 0.6
	banner.BackgroundTransparency = 0.5

	TweenService:Create(banner, SMOOTH, { Position = bannerHome, BackgroundTransparency = 0.2 }):Play()
	TweenService:Create(bannerScale, SMOOTH, { Scale = 1 }):Play()
	TweenService:Create(phaseLabel, SMOOTH, { TextTransparency = 0, TextColor3 = color }):Play()
	TweenService:Create(bannerStroke, SMOOTH, { Color = color }):Play()
end

-- Round state -----------------------------------------------------------------

local currentPhase: string? = nil
local lastTimeLeft: number? = nil

local function applyState(data: any)
	if type(data) ~= "table" then
		return
	end

	local phase = tostring(data.phase or Phases.Waiting)
	local timeLeft = tonumber(data.timeLeft) or 0
	local alive = tonumber(data.alive) or 0
	local total = tonumber(data.total) or 0
	local playerCount = tonumber(data.players) or #Players:GetPlayers()

	phaseLabel.Text = tostring(data.banner or string.upper(phase))

	if phase == Phases.Waiting then
		timerLabel.Text = "--"
	elseif phase == Phases.Results then
		timerLabel.Text = string.format("NEXT: %ds", timeLeft)
	else
		timerLabel.Text = "TIME " .. Format.clock(timeLeft)
	end

	if phase == Phases.Grace or phase == Phases.Survive or phase == Phases.Results then
		aliveLabel.Text = string.format("ALIVE: %d/%d", alive, total)
	else
		aliveLabel.Text = string.format("PLAYERS: %d", playerCount)
	end

	if phase ~= currentPhase then
		currentPhase = phase
		transitionTo(phase)
	elseif timeLeft ~= lastTimeLeft and timeLeft <= 3 and phase ~= Phases.Results then
		pulse(timerLabel)
	end
	lastTimeLeft = timeLeft
end

local roundStateEvent = Net.getRoundStateEvent()
roundStateEvent.OnClientEvent:Connect(applyState)
roundStateEvent:FireServer() -- request a snapshot (late join / HUD restart)

-- Leaderstats -----------------------------------------------------------------

local function bindStat(leaderstats: Instance, statName: string, target: TextLabel, prefix: string)
	local function bind(stat: Instance)
		if not stat:IsA("IntValue") then
			return
		end
		target.Text = prefix .. tostring(stat.Value)
		stat.Changed:Connect(function(value)
			target.Text = prefix .. tostring(value)
			pulse(target)
		end)
	end

	local stat = leaderstats:FindFirstChild(statName)
	if stat then
		bind(stat)
		return
	end
	local connection
	connection = leaderstats.ChildAdded:Connect(function(child)
		if child.Name == statName then
			connection:Disconnect()
			bind(child)
		end
	end)
end

task.spawn(function()
	local leaderstats = player:WaitForChild("leaderstats", 60)
	if not leaderstats then
		warn("[Hud] leaderstats not found; stats card will stay at defaults")
		return
	end
	bindStat(leaderstats, "Wins", winsValue, "WINS  ")
	bindStat(leaderstats, "Coins", coinsValue, "COINS ")
end)
