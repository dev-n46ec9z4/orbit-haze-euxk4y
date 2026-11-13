-- leaderstats (Wins / Coins) with optional DataStore persistence.
-- Every DataStore call is wrapped in pcall; if DataStores are unavailable
-- (e.g. Studio without API access) stats simply live for the session.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local PlayerData = {}

local store: DataStore? = nil
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Config.DATASTORE_NAME)
	end)
	if ok and result then
		store = result
	else
		warn("[PlayerData] DataStore unavailable; stats are session-only:", result)
	end
end

-- Only players whose load succeeded get saved, so a failed load never wipes saved data.
local loadedPlayers: { [Player]: boolean } = {}

local function dataKey(player: Player): string
	return "player_" .. player.UserId
end

local function getStat(player: Player, statName: string): IntValue?
	local leaderstats = player:FindFirstChild("leaderstats")
	local stat = leaderstats and leaderstats:FindFirstChild(statName)
	if stat and stat:IsA("IntValue") then
		return stat
	end
	return nil
end

function PlayerData.setup(player: Player)
	if player:FindFirstChild("leaderstats") then
		return
	end

	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"

	local wins = Instance.new("IntValue")
	wins.Name = "Wins"
	wins.Value = 0
	wins.Parent = leaderstats

	local coins = Instance.new("IntValue")
	coins.Name = "Coins"
	coins.Value = 0
	coins.Parent = leaderstats

	leaderstats.Parent = player

	-- Test-server players in Studio have non-positive UserIds; skip persistence for them.
	if not store or player.UserId <= 0 then
		return
	end

	task.spawn(function()
		local ok, data = pcall(function()
			return (store :: DataStore):GetAsync(dataKey(player))
		end)
		if player.Parent ~= Players then
			return
		end
		if not ok then
			warn(string.format("[PlayerData] Load failed for %s; using session stats: %s", player.Name, tostring(data)))
			return
		end
		if type(data) == "table" then
			-- Add on top of anything earned while the load was in flight.
			wins.Value += tonumber(data.Wins) or 0
			coins.Value += tonumber(data.Coins) or 0
		end
		loadedPlayers[player] = true
	end)
end

function PlayerData.save(player: Player)
	if not store or not loadedPlayers[player] then
		return
	end
	local wins = getStat(player, "Wins")
	local coins = getStat(player, "Coins")
	if not wins or not coins then
		return
	end
	local payload = { Wins = wins.Value, Coins = coins.Value }
	local ok, err = pcall(function()
		(store :: DataStore):SetAsync(dataKey(player), payload)
	end)
	if not ok then
		warn(string.format("[PlayerData] Save failed for %s: %s", player.Name, tostring(err)))
	end
end

function PlayerData.award(player: Player, wins: number, coins: number)
	local winsStat = getStat(player, "Wins")
	local coinsStat = getStat(player, "Coins")
	if winsStat then
		winsStat.Value += wins
	end
	if coinsStat then
		coinsStat.Value += coins
	end
	task.spawn(PlayerData.save, player)
end

function PlayerData.release(player: Player)
	PlayerData.save(player)
	loadedPlayers[player] = nil
end

function PlayerData.saveAll(timeout: number)
	local pending = 0
	for _, player in ipairs(Players:GetPlayers()) do
		pending += 1
		task.spawn(function()
			PlayerData.save(player)
			pending -= 1
		end)
	end
	local deadline = os.clock() + timeout
	while pending > 0 and os.clock() < deadline do
		task.wait(0.1)
	end
end

return PlayerData
