-- Player profiles (Wins, Coins, XP/levels, stats, quests, achievements, streaks) with
-- optional DataStore persistence. leaderstats (Wins / Coins / Level) mirror the profile.
--
-- Safety rules:
--   * Every DataStore call is wrapped in pcall. If DataStores are unavailable (e.g.
--     Studio without API access) profiles simply live for the session.
--   * Only profiles that loaded successfully are ever saved, so a failed load never
--     overwrites stored data. Data from a newer schema version is never saved over.
--   * Saves use UpdateAsync and refuse to replace data written by a newer schema.
--   * Round results that arrive while the profile is still loading are queued and
--     applied after the load, so nothing is added on top of unloaded data twice.
--   * The same DataStore name/key as v1 is kept; v1 { Wins, Coins } data migrates.

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Catalog = require(Shared:WaitForChild("Catalog"))
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local Progression = require(Shared:WaitForChild("Progression"))

local gameEvent = Net.getGameEvent()

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

local profiles: { [Player]: Progression.Profile } = {}
local persist: { [Player]: boolean } = {} -- true only after a successful, current-schema load
local pending: { [Player]: { Progression.RoundSummary } } = {} -- results queued during load
local applied: { [Player]: { [string]: boolean } } = {} -- round ids applied this session

local function dataKey(player: Player): string
	return "player_" .. player.UserId
end

local function today(): number
	return Progression.dayNumber(os.time())
end

local function toast(player: Player, text: string, color: Color3?, duration: number?)
	if player.Parent == Players then
		gameEvent:FireClient(player, { kind = "Toast", text = text, color = color, duration = duration or 3.5 })
	end
end

local function newStat(name: string, parent: Instance)
	local value = Instance.new("IntValue")
	value.Name = name
	value.Value = 0
	value.Parent = parent
end

-- Mirrors the profile into leaderstats and the "Progress" attribute read by the HUD.
local function publish(player: Player)
	local profile = profiles[player]
	local leaderstats = player:FindFirstChild("leaderstats")
	if not profile or not leaderstats then
		return
	end
	local view = Progression.clientView(profile)
	for name, value in pairs({ Wins = profile.Wins, Coins = profile.Coins, Level = view.level }) do
		local stat = leaderstats:FindFirstChild(name)
		if stat and stat:IsA("IntValue") then
			stat.Value = value
		end
	end
	local ok, json = pcall(function()
		return HttpService:JSONEncode(view)
	end)
	if ok then
		player:SetAttribute("Progress", json)
	end
end

local function catalogName(list: { Catalog.Entry }, id: string): string
	local entry = Catalog.find(list, id)
	return if entry then entry.name else id
end

local function announce(player: Player, result: Progression.RoundResult)
	local parts = {}
	for _, part in ipairs(result.xpParts) do
		table.insert(parts, string.format("%s %d", part.label, part.amount))
	end
	toast(player, string.format("+%d XP  (%s)", result.xp, table.concat(parts, ", ")), Config.Colors.WarmNeon, 5)
	for _, level in ipairs(result.levelsGained) do
		toast(
			player,
			string.format("LEVEL UP! Level %d  +%d Coins", level, Progression.levelReward(level)),
			Color3.fromRGB(255, 214, 110),
			5
		)
	end
	for _, id in ipairs(result.quests) do
		local template = Progression.questTemplate(id)
		toast(
			player,
			string.format(
				"Quest complete: %s  +%d Coins",
				catalogName(Catalog.Quests, id),
				if template then template.coins else 0
			),
			Color3.fromRGB(120, 235, 140),
			5
		)
	end
	for _, id in ipairs(result.achievements) do
		local def = Progression.achievementDef(id)
		toast(
			player,
			string.format(
				"Achievement unlocked: %s  +%d Coins",
				catalogName(Catalog.Achievements, id),
				if def then def.coins else 0
			),
			Color3.fromRGB(255, 214, 110),
			6
		)
	end
end

local function apply(player: Player, summary: Progression.RoundSummary)
	local profile = profiles[player]
	local seen = applied[player]
	if not profile or not seen or seen[summary.roundId] then
		return
	end
	seen[summary.roundId] = true
	local result = Progression.recordRound(profile, summary, today(), player.UserId)
	if result.duplicate then
		return
	end
	publish(player)
	announce(player, result)
	task.spawn(PlayerData.save, player)
end

-- Called once the profile is known (loaded, defaulted or failed).
local function resolve(player: Player, profile: Progression.Profile, shouldPersist: boolean, grantLogin: boolean)
	profiles[player] = profile
	persist[player] = shouldPersist
	Progression.refreshQuests(profile, today(), player.UserId)

	if grantLogin then
		local reward, streak = Progression.checkIn(profile, today())
		if reward > 0 then
			toast(player, string.format("Daily streak: day %d  +%d Coins", streak, reward), Config.Colors.WarmNeon, 6)
		end
	end
	-- Achievements can already be met by migrated v1 data (e.g. First Victory).
	local unlocked = Progression.checkAchievements(profile)
	for _, id in ipairs(unlocked) do
		toast(player, "Achievement unlocked: " .. catalogName(Catalog.Achievements, id), Color3.fromRGB(255, 214, 110), 6)
	end
	publish(player)

	local queued = pending[player] or {}
	pending[player] = nil
	for _, summary in ipairs(queued) do
		apply(player, summary)
	end
end

function PlayerData.setup(player: Player)
	if player:FindFirstChild("leaderstats") then
		return
	end

	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	newStat("Wins", leaderstats)
	newStat("Coins", leaderstats)
	newStat("Level", leaderstats)
	leaderstats.Parent = player

	applied[player] = {}
	pending[player] = {}

	-- Test-server players in Studio have non-positive UserIds; skip persistence for them.
	if not store or player.UserId <= 0 then
		resolve(player, Progression.defaultProfile(), false, true)
		return
	end

	task.spawn(function()
		local ok, data = pcall(function()
			return (store :: DataStore):GetAsync(dataKey(player))
		end)
		-- Left (and was released) while loading: drop the result.
		if player.Parent ~= Players or not applied[player] then
			return
		end
		if not ok then
			warn(string.format("[PlayerData] Load failed for %s; using session stats: %s", player.Name, tostring(data)))
			-- No login reward: it could never be saved, and rejoining would re-grant it.
			resolve(player, Progression.defaultProfile(), false, false)
			return
		end
		local profile, isFuture = Progression.migrate(data)
		if isFuture then
			warn(string.format("[PlayerData] %s has data from a newer schema; not saving this session", player.Name))
		end
		resolve(player, profile, not isFuture, not isFuture)
	end)
end

function PlayerData.save(player: Player)
	local profile = profiles[player]
	if not store or not profile or not persist[player] then
		return
	end
	local payload = table.clone(profile)
	payload.Version = Progression.SCHEMA_VERSION
	local ok, err = pcall(function()
		(store :: DataStore):UpdateAsync(dataKey(player), function(old)
			if type(old) == "table" and (tonumber(old.Version) or 1) > Progression.SCHEMA_VERSION then
				return nil -- cancel: never downgrade newer data
			end
			return payload
		end)
	end)
	if not ok then
		warn(string.format("[PlayerData] Save failed for %s: %s", player.Name, tostring(err)))
	end
end

-- Applies a finished round (from RoundStats.finalize). Safe to call more than once
-- with the same summary; queued if the profile is still loading.
function PlayerData.recordRound(player: Player, summary: Progression.RoundSummary)
	if player.Parent ~= Players then
		return
	end
	if profiles[player] then
		apply(player, summary)
	elseif pending[player] then
		table.insert(pending[player], summary)
	end
end

function PlayerData.release(player: Player)
	PlayerData.save(player)
	profiles[player] = nil
	persist[player] = nil
	pending[player] = nil
	applied[player] = nil
end

function PlayerData.saveAll(timeout: number)
	local count = 0
	for _, player in ipairs(Players:GetPlayers()) do
		count += 1
		task.spawn(function()
			PlayerData.save(player)
			count -= 1
		end)
	end
	local deadline = os.clock() + timeout
	while count > 0 and os.clock() < deadline do
		task.wait(0.1)
	end
end

return PlayerData
