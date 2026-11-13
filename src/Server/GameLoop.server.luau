-- Falling Tiles Survival: round loop, player lifecycle and state broadcasting.
--
-- Phases: Waiting -> Intermission (10s) -> Grace (3s) -> Survive (<=60s) -> Results -> repeat.
--
-- End-of-round rule:
--   * Rounds that start with 2+ players end when 0 or 1 participants remain alive,
--     or when the 60s timer runs out.
--   * Rounds that start with exactly 1 player (solo / Studio testing) only end when
--     that player is eliminated or the 60s timer runs out. Surviving the full minute
--     wins the round; ending at "1 alive" would otherwise finish a solo round instantly.
--
-- Game modes rotate through Config.MODE_ORDER (Classic -> Shrinking Ring -> Hazard
-- Storm). Each mode sets the wave pattern/size, which hazards run and how often, and
-- how often power-ups spawn. Special tiles, hazards and power-ups only act during Survive.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Catalog = require(Shared:WaitForChild("Catalog"))
local Config = require(Shared:WaitForChild("Config"))
local Format = require(Shared:WaitForChild("Format"))
local Grid = require(Shared:WaitForChild("Grid"))
local Net = require(Shared:WaitForChild("Net"))

local Hazards = require(script.Parent:WaitForChild("Hazards"))
local PlayerData = require(script.Parent:WaitForChild("PlayerData"))
local PowerUps = require(script.Parent:WaitForChild("PowerUps"))
local TileEffects = require(script.Parent:WaitForChild("TileEffects"))
local World = require(script.Parent:WaitForChild("World"))

local Phases = Config.Phases
local ALIVE_TAG = Config.ALIVE_TAG

local roundStateEvent = Net.getRoundStateEvent()
local gameEvent = Net.getGameEvent()
-- Server -> client only; drain anything clients send so it never queues.
gameEvent.OnServerEvent:Connect(function() end)

Players.RespawnTime = Config.RESPAWN_TIME
Players.CharacterAutoLoads = true

World.buildLobby()

-- State -----------------------------------------------------------------------

local state = {
	phase = Phases.Waiting,
	banner = "WAITING FOR PLAYERS",
	timeLeft = 0,
	alive = 0,
	total = 0,
	winners = {} :: { string },
	mode = Config.MODE_ORDER[1],
}

local roundActive = false -- true during Grace and Survive
local participants: { [Player]: boolean } = {}
local currentArena: Model? = nil

local function snapshot()
	return {
		phase = state.phase,
		banner = state.banner,
		timeLeft = state.timeLeft,
		alive = state.alive,
		total = state.total,
		players = #Players:GetPlayers(),
		winners = state.winners,
		mode = state.mode,
	}
end

local function broadcast()
	roundStateEvent:FireAllClients(snapshot())
end

local function setState(changes: { [string]: any })
	for key, value in pairs(changes) do
		state[key] = value
	end
	broadcast()
end

local function toast(text: string, color: Color3?, duration: number?)
	gameEvent:FireAllClients({ kind = "Toast", text = text, color = color, duration = duration or 2.5 })
end

-- Alive tracking -------------------------------------------------------------

local function isAlive(player: Player): boolean
	return CollectionService:HasTag(player, ALIVE_TAG)
end

local function getAliveParticipants(): { Player }
	local alive = {}
	for player in pairs(participants) do
		if isAlive(player) and player.Parent == Players then
			table.insert(alive, player)
		end
	end
	return alive
end

local function countAlive(): number
	return #getAliveParticipants()
end

local function setAlive(player: Player, alive: boolean)
	local character = player.Character
	if alive then
		CollectionService:AddTag(player, ALIVE_TAG)
		if character then
			CollectionService:AddTag(character, ALIVE_TAG)
		end
	else
		CollectionService:RemoveTag(player, ALIVE_TAG)
		if character then
			CollectionService:RemoveTag(character, ALIVE_TAG)
		end
	end
	player:SetAttribute("Alive", alive)
end

local function eliminate(player: Player)
	if not isAlive(player) then
		return
	end
	setAlive(player, false)
	PowerUps.clear(player)
	TileEffects.forget(player)
	if roundActive then
		setState({ alive = countAlive() })
	end
end

-- Player lifecycle -----------------------------------------------------------

local function onCharacterAdded(player: Player, character: Model)
	-- A fresh character means the old one is gone (death, reset or reload): out of the round.
	if isAlive(player) then
		eliminate(player)
	end

	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid or not humanoid:IsA("Humanoid") then
		return
	end
	humanoid.Died:Connect(function()
		if player.Character == character then
			eliminate(player)
		end
	end)
end

local function onPlayerAdded(player: Player)
	PlayerData.setup(player)
	player:SetAttribute("Alive", false)

	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
	if player.Character then
		task.spawn(onCharacterAdded, player, player.Character)
	end

	-- Late joiners spawn in the lobby automatically; refresh everyone's player count.
	broadcast()
end

local function onPlayerRemoving(player: Player)
	eliminate(player)
	participants[player] = nil
	PlayerData.release(player)
	task.defer(function()
		if roundActive then
			setState({ alive = countAlive() })
		else
			broadcast()
		end
	end)
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, player)
end

game:BindToClose(function()
	PlayerData.saveAll(if RunService:IsStudio() then 3 else 20)
end)

-- Clients ask for a snapshot when their HUD starts (covers late joins).
local lastRequest: { [Player]: number } = {}
roundStateEvent.OnServerEvent:Connect(function(player)
	local now = os.clock()
	if lastRequest[player] and now - lastRequest[player] < 0.5 then
		return
	end
	lastRequest[player] = now
	roundStateEvent:FireClient(player, snapshot())
end)
Players.PlayerRemoving:Connect(function(player)
	lastRequest[player] = nil
end)

-- Rescue Wings fire first (they trigger well above the kill plane); then anything
-- below KILL_PLANE_Y dies and is eliminated.
RunService.Heartbeat:Connect(function()
	if roundActive then
		for _, player in ipairs(getAliveParticipants()) do
			PowerUps.tryRescue(player)
		end
	end
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") and root.Position.Y < Config.KILL_PLANE_Y then
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 then
				humanoid.Health = 0
			end
			eliminate(player)
		end
	end
end)

-- Round flow -----------------------------------------------------------------

local function hasEnoughPlayers(): boolean
	return #Players:GetPlayers() >= Config.MIN_PLAYERS
end

local function getEligiblePlayers(): { Player }
	local eligible = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if humanoid and root and humanoid.Health > 0 then
			table.insert(eligible, player)
		end
	end
	return eligible
end

local function shouldEndRound(total: number): boolean
	local alive = countAlive()
	if alive == 0 then
		return true
	end
	-- Solo rounds (total == 1) keep going until death or timeout; see header comment.
	return total >= 2 and alive <= 1
end

local function waitForPlayers()
	if hasEnoughPlayers() then
		return
	end
	setState({
		phase = Phases.Waiting,
		banner = "WAITING FOR PLAYERS",
		timeLeft = 0,
		alive = 0,
		total = 0,
		winners = {},
	})
	while not hasEnoughPlayers() do
		task.wait(0.5)
	end
end

-- Returns false if the player count dropped below the minimum mid-countdown.
local modeIndex = 0

-- Index into Config.MODE_ORDER of the mode the next round will use. Only advances
-- once a round actually starts, so an aborted intermission doesn't skip a mode.
local function peekNextMode(): number
	return (modeIndex % #Config.MODE_ORDER) + 1
end

local function runIntermission(nextMode: string): boolean
	for remaining = Config.INTERMISSION_TIME, 1, -1 do
		if not hasEnoughPlayers() then
			return false
		end
		setState({
			phase = Phases.Intermission,
			banner = string.format("INTERMISSION: %ds", remaining),
			timeLeft = remaining,
			alive = 0,
			total = 0,
			winners = {},
			mode = nextMode,
		})
		task.wait(1)
	end
	return hasEnoughPlayers()
end

local function cleanupRound()
	roundActive = false
	PowerUps.endRound()
	TileEffects.reset()
	for player in pairs(participants) do
		setAlive(player, false)
	end
	table.clear(participants)
	World.destroyArena(currentArena)
	currentArena = nil
end

local function runRound(modeId: string)
	local mode = Config.Modes[modeId] or Config.Modes.Classic
	local modeInfo = Catalog.find(Catalog.Modes, modeId)
	currentArena = World.buildArena()
	local arena = currentArena :: Model

	local players = getEligiblePlayers()
	if #players == 0 then
		-- Everyone is mid-respawn; try again next cycle.
		cleanupRound()
		return
	end

	local spawns = World.getSpawnCFrames(arena, #players)
	for index, player in ipairs(players) do
		local character = player.Character
		if character then
			participants[player] = true
			setAlive(player, true)
			character:PivotTo(spawns[index])
		end
	end

	local total = countAlive()
	roundActive = true

	-- Grace period: no tiles fall yet.
	for remaining = Config.GRACE_TIME, 1, -1 do
		setState({
			phase = Phases.Grace,
			banner = string.format("GET READY: %d", remaining),
			timeLeft = remaining,
			alive = countAlive(),
			total = total,
			winners = {},
		})
		task.wait(1)
		if shouldEndRound(total) then
			break
		end
	end

	-- Survive phase: waves accelerate from WAVE_INTERVAL_START to WAVE_INTERVAL_END.
	local hazardContext: Hazards.Context = {
		arena = arena,
		isActive = function()
			return roundActive and currentArena == arena and arena.Parent ~= nil
		end,
		alivePlayers = getAliveParticipants,
		notify = function(text, color)
			toast(text, color)
		end,
	}
	World.activateTiles(arena)
	PowerUps.startRound(arena)
	if modeInfo then
		toast(string.upper(modeInfo.name) .. ": " .. modeInfo.description, modeInfo.color, 4)
	end

	local startTime = os.clock()
	local nextWaveAt = startTime
	local nextHazardAt = startTime + mode.firstHazardAt
	local nextPowerUpAt = startTime + mode.powerUpInterval / 2
	local lastShown = -1
	while not shouldEndRound(total) do
		local now = os.clock()
		local elapsed = now - startTime
		if elapsed >= Config.ROUND_TIME then
			break
		end

		if now >= nextWaveAt then
			World.dropWave(arena, math.random(mode.waveMin, mode.waveMax), mode.pattern)
			nextWaveAt = now
				+ Grid.waveInterval(elapsed, Config.ROUND_TIME, Config.WAVE_INTERVAL_START, Config.WAVE_INTERVAL_END)
		end

		if now >= nextHazardAt and #mode.hazards > 0 then
			Hazards.start(mode.hazards[math.random(#mode.hazards)], hazardContext)
			nextHazardAt = now + mode.hazardInterval
		end

		if now >= nextPowerUpAt then
			PowerUps.spawnPickup()
			nextPowerUpAt = now + mode.powerUpInterval
		end

		local alivePlayers = getAliveParticipants()
		TileEffects.tick(arena, alivePlayers, now)
		PowerUps.tick(alivePlayers, now)

		local timeLeft = math.max(0, math.ceil(Config.ROUND_TIME - elapsed))
		if timeLeft ~= lastShown then
			lastShown = timeLeft
			setState({
				phase = Phases.Survive,
				banner = "SURVIVE!",
				timeLeft = timeLeft,
				alive = countAlive(),
				total = total,
			})
		end

		task.wait(0.1)
	end

	-- Results: everyone still alive (and still in the server) wins.
	roundActive = false
	local winners: { Player } = {}
	for player in pairs(participants) do
		if isAlive(player) and player.Parent == Players then
			table.insert(winners, player)
		end
	end

	local winnerNames = {}
	for _, player in ipairs(winners) do
		PlayerData.award(player, Config.WIN_REWARD, Config.COIN_REWARD)
		table.insert(winnerNames, player.DisplayName)
	end

	local banner
	if #winners == 0 then
		banner = "NO SURVIVORS"
	elseif #winners == 1 then
		banner = "WINNER: " .. winnerNames[1]
	else
		banner = "WINNERS: " .. Format.joinNames(winnerNames)
	end

	-- Bring survivors back to the lobby before the arena is removed.
	for _, player in ipairs(winners) do
		local character = player.Character
		if character then
			character:PivotTo(World.getLobbyCFrame())
		end
	end
	cleanupRound()

	for remaining = Config.RESULTS_TIME, 1, -1 do
		setState({
			phase = Phases.Results,
			banner = banner,
			timeLeft = remaining,
			alive = #winners,
			total = total,
			winners = winnerNames,
		})
		task.wait(1)
	end
end

-- Main loop ------------------------------------------------------------------

task.spawn(function()
	while true do
		waitForPlayers()
		local nextIndex = peekNextMode()
		local modeId = Config.MODE_ORDER[nextIndex]
		if runIntermission(modeId) then
			modeIndex = nextIndex
			local ok, err = pcall(runRound, modeId)
			if not ok then
				warn("[GameLoop] Round error:", err)
				cleanupRound()
				task.wait(1)
			end
		end
	end
end)
