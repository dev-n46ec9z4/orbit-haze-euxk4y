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

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Format = require(Shared:WaitForChild("Format"))
local Net = require(Shared:WaitForChild("Net"))

local PlayerData = require(script.Parent:WaitForChild("PlayerData"))
local World = require(script.Parent:WaitForChild("World"))

local Phases = Config.Phases
local ALIVE_TAG = Config.ALIVE_TAG

local roundStateEvent = Net.getRoundStateEvent()

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

-- Alive tracking -------------------------------------------------------------

local function isAlive(player: Player): boolean
	return CollectionService:HasTag(player, ALIVE_TAG)
end

local function countAlive(): number
	local count = 0
	for player in pairs(participants) do
		if isAlive(player) and player.Parent == Players then
			count += 1
		end
	end
	return count
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

-- Kill plane: anything below KILL_PLANE_Y dies and is eliminated.
RunService.Heartbeat:Connect(function()
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
local function runIntermission(): boolean
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
		})
		task.wait(1)
	end
	return hasEnoughPlayers()
end

local function cleanupRound()
	roundActive = false
	for player in pairs(participants) do
		setAlive(player, false)
	end
	table.clear(participants)
	World.destroyArena(currentArena)
	currentArena = nil
end

local function runRound()
	currentArena = World.buildArena()

	local players = getEligiblePlayers()
	if #players == 0 then
		-- Everyone is mid-respawn; try again next cycle.
		cleanupRound()
		return
	end

	local spawns = World.getSpawnCFrames(currentArena :: Model, #players)
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
	local startTime = os.clock()
	local nextWaveAt = startTime
	local lastShown = -1
	while not shouldEndRound(total) do
		local now = os.clock()
		local elapsed = now - startTime
		if elapsed >= Config.ROUND_TIME then
			break
		end

		if now >= nextWaveAt then
			World.dropWave(currentArena, math.random(Config.WAVE_MIN_TILES, Config.WAVE_MAX_TILES))
			local alpha = math.clamp(elapsed / Config.ROUND_TIME, 0, 1)
			local interval = Config.WAVE_INTERVAL_START
				+ (Config.WAVE_INTERVAL_END - Config.WAVE_INTERVAL_START) * alpha
			nextWaveAt = now + interval
		end

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
		if runIntermission() then
			local ok, err = pcall(runRound)
			if not ok then
				warn("[GameLoop] Round error:", err)
				cleanupRound()
				task.wait(1)
			end
		end
	end
end)
