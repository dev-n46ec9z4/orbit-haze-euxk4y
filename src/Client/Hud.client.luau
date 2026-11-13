-- Procedural HUD: top-center phase banner with timer, Alive count and current mode,
-- top-right Wins/Coins card bound to leaderstats, active power-up tray, event toasts,
-- and a guide panel (G key or GUIDE button) that explains every mode, tile, hazard and
-- power-up from Shared.Catalog.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Catalog = require(Shared:WaitForChild("Catalog"))
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

local modeLabel = label({
	Name = "Mode",
	Text = "PRESS G FOR THE GUIDE",
	TextColor3 = Color3.fromRGB(200, 195, 210),
	Size = UDim2.new(1, -24, 0, 18),
	Position = UDim2.fromOffset(12, 84),
})

-- Map / environment / modifier for the current or next round.
local roundInfoLabel = label({
	Name = "RoundInfo",
	Text = "",
	TextColor3 = Color3.fromRGB(200, 195, 210),
	Size = UDim2.new(1, -24, 0, 16),
	Position = UDim2.fromOffset(12, 106),
})

local bannerHome = UDim2.new(0.5, 0, 0, 10)
local banner = create("Frame", {
	Name = "PhaseBanner",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = bannerHome,
	Size = UDim2.fromOffset(440, 130),
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
	modeLabel,
	roundInfoLabel,
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

-- Toasts (hazard warnings, pickups, mode intro) stack under the banner.
local toastStack = create("Frame", {
	Name = "Toasts",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 150),
	Size = UDim2.fromOffset(480, 160),
	BackgroundTransparency = 1,
	Parent = screenGui,
}, {
	create("UIListLayout", {
		Padding = UDim.new(0, 6),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
	}),
}) :: Frame

-- Active power-ups, under the stats card.
local powerUpTray = create("Frame", {
	Name = "PowerUps",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -12, 0, 114),
	Size = UDim2.fromOffset(190, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundTransparency = 1,
	Parent = screenGui,
}, {
	create("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }),
}) :: Frame

-- Round preview card (left side): mode, map, environment and modifier with
-- descriptions. Shown during intermission and the grace countdown, hidden in play.
local previewRows: { [string]: { name: TextLabel, description: TextLabel } } = {}
local previewList = create("Frame", {
	Name = "Rows",
	Position = UDim2.fromOffset(12, 40),
	Size = UDim2.new(1, -24, 0, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundTransparency = 1,
}, {
	create("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
}) :: Frame

for index, kind in ipairs({ "Mode", "Map", "Environment", "Modifier" }) do
	local nameLabel = label({
		Name = "Name",
		Text = string.upper(kind) .. ": -",
		Font = FONT_BOLD,
		TextScaled = false,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, 18),
	})
	local descriptionLabel = label({
		Name = "Description",
		Text = "",
		TextScaled = false,
		TextSize = 13,
		TextWrapped = true,
		TextColor3 = Color3.fromRGB(210, 205, 220),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Position = UDim2.fromOffset(0, 20),
	})
	create("Frame", {
		Name = kind,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = index,
		Parent = previewList,
	}, { nameLabel, descriptionLabel })
	previewRows[kind] = { name = nameLabel, description = descriptionLabel }
end

local previewCard = create("Frame", {
	Name = "RoundPreview",
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, 12, 0.5, 0),
	Size = UDim2.fromOffset(270, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundColor3 = PANEL_COLOR,
	BackgroundTransparency = 0.15,
	Visible = false,
	Parent = screenGui,
}, {
	create("UICorner", { CornerRadius = UDim.new(0, 12) }),
	create("UIStroke", { Thickness = 2, Color = Config.Colors.WarmNeon, Transparency = 0.3 }),
	create("UIPadding", { PaddingBottom = UDim.new(0, 12) }),
	label({
		Name = "Title",
		Text = "NEXT ROUND",
		Font = FONT_BOLD,
		TextColor3 = Config.Colors.WarmNeon,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -24, 0, 22),
		Position = UDim2.fromOffset(12, 10),
	}),
	previewList,
}) :: Frame
local previewTitle = previewCard:FindFirstChild("Title") :: TextLabel

-- Guide panel ------------------------------------------------------------------

local guideScale = create("UIScale", { Scale = 1 }) :: UIScale
local guideList = create("ScrollingFrame", {
	Name = "Entries",
	Position = UDim2.fromOffset(16, 52),
	Size = UDim2.new(1, -32, 1, -68),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 6,
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
}, {
	create("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
}) :: ScrollingFrame

local closeButton = create("TextButton", {
	Name = "Close",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -12, 0, 12),
	Size = UDim2.fromOffset(32, 32),
	BackgroundColor3 = Color3.fromRGB(60, 50, 70),
	Text = "X",
	TextColor3 = TEXT_COLOR,
	Font = FONT_BOLD,
	TextSize = 18,
}, {
	create("UICorner", { CornerRadius = UDim.new(0, 8) }),
}) :: TextButton

local guidePanel = create("Frame", {
	Name = "Guide",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.55),
	Size = UDim2.new(0.9, 0, 0.7, 0),
	BackgroundColor3 = PANEL_COLOR,
	BackgroundTransparency = 0.08,
	Visible = false,
	Parent = screenGui,
}, {
	create("UICorner", { CornerRadius = UDim.new(0, 14) }),
	create("UIStroke", { Thickness = 2, Color = Config.Colors.WarmNeon, Transparency = 0.2 }),
	create("UISizeConstraint", { MaxSize = Vector2.new(600, 460) }),
	guideScale,
	label({
		Name = "Title",
		Text = "HOW TO SURVIVE",
		Font = FONT_BOLD,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -80, 0, 30),
		Position = UDim2.fromOffset(16, 12),
	}),
	closeButton,
	guideList,
}) :: Frame

local guideButton = create("TextButton", {
	Name = "GuideButton",
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -12, 1, -12),
	Size = UDim2.fromOffset(140, 38),
	BackgroundColor3 = PANEL_COLOR,
	BackgroundTransparency = 0.15,
	Text = "GUIDE [G]",
	TextColor3 = Config.Colors.WarmNeon,
	Font = FONT_BOLD,
	TextSize = 18,
	Parent = screenGui,
}, {
	create("UICorner", { CornerRadius = UDim.new(0, 10) }),
	create("UIStroke", { Thickness = 2, Color = Config.Colors.WarmNeon, Transparency = 0.3 }),
}) :: TextButton

do
	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end

	local function addText(props: { [string]: any })
		props.TextScaled = false
		props.TextXAlignment = Enum.TextXAlignment.Left
		props.LayoutOrder = nextOrder()
		props.Parent = guideList
		label(props)
	end

	local function addHeading(text: string)
		addText({
			Name = "Heading",
			Text = text,
			Font = FONT_BOLD,
			TextSize = 18,
			TextColor3 = Config.Colors.WarmNeon,
			Size = UDim2.new(1, -8, 0, 26),
		})
	end

	local function addEntry(entry: Catalog.Entry)
		create("Frame", {
			Name = entry.id,
			Size = UDim2.new(1, -8, 0, 40),
			BackgroundTransparency = 1,
			LayoutOrder = nextOrder(),
			Parent = guideList,
		}, {
			create("Frame", {
				Name = "Swatch",
				Size = UDim2.fromOffset(16, 16),
				Position = UDim2.fromOffset(2, 4),
				BackgroundColor3 = entry.color,
			}, { create("UICorner", { CornerRadius = UDim.new(0, 4) }) }),
			label({
				Name = "Name",
				Text = entry.name,
				Font = FONT_BOLD,
				TextScaled = false,
				TextSize = 15,
				TextColor3 = entry.color,
				TextXAlignment = Enum.TextXAlignment.Left,
				Size = UDim2.new(0, 130, 0, 24),
				Position = UDim2.fromOffset(26, 0),
			}),
			label({
				Name = "Description",
				Text = entry.description,
				TextScaled = false,
				TextSize = 14,
				TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Top,
				Size = UDim2.new(1, -164, 1, 0),
				Position = UDim2.fromOffset(160, 3),
			}),
		})
	end

	addHeading("GOAL")
	addText({
		Name = "Goal",
		Text = string.format(
			"Stay on the arena until the timer ends or you're the last one standing. "
				.. "Survivors earn +%d Win and +%d Coins. Tiles flash red before they fall.",
			Config.WIN_REWARD,
			Config.COIN_REWARD
		),
		TextSize = 14,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		Size = UDim2.new(1, -8, 0, 40),
	})
	for _, section in ipairs({
		{ "GAME MODES (one per round, in rotation)", Catalog.Modes },
		{ "TILES", Catalog.TileTypes },
		{ "HAZARDS", Catalog.Hazards },
		{ "MAPS (random each round)", Catalog.Maps },
		{ "ENVIRONMENTS (random each round)", Catalog.Environments },
		{ "ROUND MODIFIERS (one per round)", Catalog.Modifiers },
		{ "POWER-UPS (touch the glowing orbs)", Catalog.PowerUps },
	}) do
		addHeading(section[1] :: string)
		for _, entry in ipairs(section[2] :: { Catalog.Entry }) do
			addEntry(entry)
		end
	end
end

local function setGuideOpen(open: boolean)
	if open then
		guidePanel.Visible = true
		guideScale.Scale = 0.85
		TweenService:Create(guideScale, SMOOTH, { Scale = 1 }):Play()
	else
		guidePanel.Visible = false
	end
end

guideButton.Activated:Connect(function()
	setGuideOpen(not guidePanel.Visible)
end)
closeButton.Activated:Connect(function()
	setGuideOpen(false)
end)
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.KeyCode == Enum.KeyCode.G then
		setGuideOpen(not guidePanel.Visible)
	end
end)

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

-- Toasts ------------------------------------------------------------------------

local MAX_TOASTS = 4
local toastOrder = 0

local function showToast(text: string, color: Color3?, duration: number?)
	toastOrder += 1
	local accent = color or TEXT_COLOR
	local textLabel = label({
		Name = "Text",
		Text = text,
		Font = FONT_BOLD,
		TextColor3 = accent,
		TextTransparency = 1,
		Size = UDim2.new(1, -20, 1, -8),
		Position = UDim2.fromOffset(10, 4),
	})
	local stroke = create("UIStroke", { Thickness = 1.5, Color = accent, Transparency = 1 }) :: UIStroke
	local frame = create("Frame", {
		Name = "Toast",
		Size = UDim2.fromOffset(480, 32),
		BackgroundColor3 = PANEL_COLOR,
		BackgroundTransparency = 1,
		LayoutOrder = toastOrder,
		Parent = toastStack,
	}, {
		create("UICorner", { CornerRadius = UDim.new(0, 8) }),
		stroke,
		textLabel,
	}) :: Frame

	-- Keep only the newest few.
	local toasts = {}
	for _, child in ipairs(toastStack:GetChildren()) do
		if child:IsA("Frame") then
			table.insert(toasts, child)
		end
	end
	if #toasts > MAX_TOASTS then
		table.sort(toasts, function(a, b)
			return a.LayoutOrder < b.LayoutOrder
		end)
		for i = 1, #toasts - MAX_TOASTS do
			toasts[i]:Destroy()
		end
	end

	TweenService:Create(frame, FAST, { BackgroundTransparency = 0.25 }):Play()
	TweenService:Create(textLabel, FAST, { TextTransparency = 0 }):Play()
	TweenService:Create(stroke, FAST, { Transparency = 0.2 }):Play()
	task.delay(duration or 2.5, function()
		if not frame.Parent then
			return
		end
		TweenService:Create(frame, SMOOTH, { BackgroundTransparency = 1 }):Play()
		TweenService:Create(textLabel, SMOOTH, { TextTransparency = 1 }):Play()
		TweenService:Create(stroke, SMOOTH, { Transparency = 1 }):Play()
		task.wait(0.5)
		frame:Destroy()
	end)
end

-- Power-up tray -----------------------------------------------------------------

local activePowerUps: { [string]: { row: TextLabel, expires: number? } } = {}

local function removePowerUp(id: string)
	local active = activePowerUps[id]
	if active then
		active.row:Destroy()
		activePowerUps[id] = nil
	end
end

local function powerUpText(id: string, expires: number?): string
	local info = Catalog.find(Catalog.PowerUps, id)
	local name = string.upper(if info then info.name else id)
	if expires then
		return string.format("%s  %ds", name, math.max(0, math.ceil(expires - os.clock())))
	end
	return name .. "  READY"
end

local function addPowerUp(id: string, duration: number?)
	removePowerUp(id)
	local info = Catalog.find(Catalog.PowerUps, id)
	local color = if info then info.color else TEXT_COLOR
	local expires = if duration then os.clock() + duration else nil
	local row = label({
		Name = id,
		Text = powerUpText(id, expires),
		Font = FONT_BOLD,
		TextColor3 = color,
		BackgroundColor3 = PANEL_COLOR,
		BackgroundTransparency = 0.2,
		Size = UDim2.new(1, 0, 0, 28),
	})
	create("UICorner", { CornerRadius = UDim.new(0, 8), Parent = row })
	create("UIStroke", { Thickness = 1.5, Color = color, Transparency = 0.3, Parent = row })
	row.Parent = powerUpTray
	activePowerUps[id] = { row = row, expires = expires }
	pulse(row)
end

task.spawn(function()
	while true do
		for id, active in pairs(activePowerUps) do
			if active.expires then
				active.row.Text = powerUpText(id, active.expires)
			end
		end
		task.wait(0.25)
	end
end)

local function onGameEvent(data: any)
	if type(data) ~= "table" then
		return
	end
	if data.kind == "Toast" and type(data.text) == "string" then
		showToast(data.text, if typeof(data.color) == "Color3" then data.color else nil, tonumber(data.duration))
	elseif data.kind == "PowerUp" and type(data.id) == "string" then
		if data.active then
			addPowerUp(data.id, tonumber(data.duration))
		else
			removePowerUp(data.id)
		end
	elseif data.kind == "PowerUpClear" then
		for id in pairs(activePowerUps) do
			removePowerUp(id)
		end
	end
end

Net.getGameEvent().OnClientEvent:Connect(onGameEvent)

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

	local modeInfo = Catalog.find(Catalog.Modes, data.mode)
	if not modeInfo or phase == Phases.Waiting then
		modeLabel.Text = "PRESS G FOR THE GUIDE"
		modeLabel.TextColor3 = Color3.fromRGB(200, 195, 210)
	else
		local prefix = if phase == Phases.Intermission then "NEXT MODE: " else "MODE: "
		modeLabel.Text = prefix .. string.upper(modeInfo.name) .. "  |  G FOR GUIDE"
		modeLabel.TextColor3 = modeInfo.color
	end

	-- Round plan: compact line on the banner, full preview card before play starts.
	local plan = {
		Mode = Catalog.find(Catalog.Modes, data.mode),
		Map = Catalog.find(Catalog.Maps, data.map),
		Environment = Catalog.find(Catalog.Environments, data.environment),
		Modifier = Catalog.find(Catalog.Modifiers, data.modifier),
	}
	if phase == Phases.Waiting or not plan.Map or not plan.Environment or not plan.Modifier then
		roundInfoLabel.Text = ""
	else
		roundInfoLabel.Text = string.format(
			"MAP: %s  |  %s  |  %s",
			string.upper(plan.Map.name),
			string.upper(plan.Environment.name),
			string.upper(plan.Modifier.name)
		)
	end
	for kind, row in pairs(previewRows) do
		local info = (plan :: any)[kind]
		row.name.Text = string.upper(kind) .. ": " .. (if info then string.upper(info.name) else "-")
		row.name.TextColor3 = if info then info.color else TEXT_COLOR
		row.description.Text = if info then info.description else ""
	end
	local showPreview = phase == Phases.Intermission or phase == Phases.Grace
	previewTitle.Text = if phase == Phases.Grace then "THIS ROUND" else "NEXT ROUND"
	if showPreview and not previewCard.Visible then
		previewCard.Visible = true
		previewCard.Position = UDim2.new(0, -280, 0.5, 0)
		TweenService:Create(previewCard, SMOOTH, { Position = UDim2.new(0, 12, 0.5, 0) }):Play()
	elseif not showPreview then
		previewCard.Visible = false
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

showToast("Welcome! Press G or click GUIDE to learn the tiles, hazards and power-ups.", Config.Colors.WarmNeon, 6)

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
