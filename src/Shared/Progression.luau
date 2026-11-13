-- Pure progression rules: profile schema + migration, XP and levels, daily quests,
-- achievements, login and win streaks. No Roblox services, so the server (PlayerData),
-- the HUD and tests/progression.test.luau all use the same rules.
--
-- Profiles are plain tables that are saved as-is. Version history:
--   v1 (no Version field): { Wins, Coins }
--   v2: everything in Progression.defaultProfile()

local Config = require(script.Parent:WaitForChild("Config"))

local Progression = {}

Progression.SCHEMA_VERSION = 2

export type Stats = {
	RoundsPlayed: number,
	SecondsSurvived: number,
	PowerUps: number,
	Bounces: number,
	Rescues: number,
	FullRounds: number,
	BestSurvival: number,
	BestWinStreak: number,
	CurrentWinStreak: number,
	MapWins: { [string]: number },
	EnvWins: { [string]: number },
}

export type Quest = { id: string, progress: number, done: boolean }

export type Profile = {
	Version: number,
	Wins: number,
	Coins: number,
	XP: number,
	Stats: Stats,
	Achievements: { [string]: boolean },
	Quests: { Day: number, List: { Quest } },
	LoginDay: number,
	LoginStreak: number,
	LastRoundId: string,
}

export type RoundSummary = {
	roundId: string,
	won: boolean,
	seconds: number,
	powerUps: number,
	bounces: number,
	rescues: number,
	fullRound: boolean,
	map: string,
	environment: string,
	modifier: string,
	bonusCoins: number,
}

export type XpPart = { label: string, amount: number }

export type RoundResult = {
	duplicate: boolean,
	xp: number,
	xpParts: { XpPart },
	coins: number,
	levelsGained: { number },
	quests: { string },
	achievements: { string },
}

local STAT_KEYS = {
	"RoundsPlayed",
	"SecondsSurvived",
	"PowerUps",
	"Bounces",
	"Rescues",
	"FullRounds",
	"BestSurvival",
	"BestWinStreak",
	"CurrentWinStreak",
}

-- Non-negative whole number, or 0 for anything invalid (nil, NaN, inf, strings, negatives).
local function count(value: any): number
	local n = tonumber(value)
	if not n or n ~= n or n == math.huge or n < 0 then
		return 0
	end
	return math.floor(n)
end
Progression.count = count

local function findById(list: { any }, id: string?): any
	for _, entry in ipairs(list) do
		if entry.id == id then
			return entry
		end
	end
	return nil
end

function Progression.questTemplate(id: string?)
	return findById(Config.QUEST_POOL, id)
end

function Progression.achievementDef(id: string?)
	return findById(Config.ACHIEVEMENTS, id)
end

function Progression.defaultProfile(): Profile
	return {
		Version = Progression.SCHEMA_VERSION,
		Wins = 0,
		Coins = 0,
		XP = 0,
		Stats = {
			RoundsPlayed = 0,
			SecondsSurvived = 0,
			PowerUps = 0,
			Bounces = 0,
			Rescues = 0,
			FullRounds = 0,
			BestSurvival = 0,
			BestWinStreak = 0,
			CurrentWinStreak = 0,
			MapWins = {},
			EnvWins = {},
		},
		Achievements = {},
		Quests = { Day = 0, List = {} },
		LoginDay = 0,
		LoginStreak = 0,
		LastRoundId = "",
	}
end

local function countMap(raw: any): { [string]: number }
	local result = {}
	if type(raw) == "table" then
		for key, value in pairs(raw) do
			if type(key) == "string" and count(value) > 0 then
				result[key] = count(value)
			end
		end
	end
	return result
end

-- Builds a valid current-schema profile from whatever was stored (nil, v1, v2, or
-- garbage). Unknown fields are dropped and invalid numbers become 0. The second
-- return value is true if the data came from a newer schema than this server knows;
-- the caller must then not save, so a newer server's data is never downgraded.
function Progression.migrate(raw: any): (Profile, boolean)
	local profile = Progression.defaultProfile()
	if type(raw) ~= "table" then
		return profile, false
	end
	local version = tonumber(raw.Version) or 1
	local isFuture = version > Progression.SCHEMA_VERSION

	-- Present since v1.
	profile.Wins = count(raw.Wins)
	profile.Coins = count(raw.Coins)
	if version < 2 then
		return profile, isFuture
	end

	profile.XP = count(raw.XP)
	local stats = if type(raw.Stats) == "table" then raw.Stats else {}
	for _, key in ipairs(STAT_KEYS) do
		(profile.Stats :: any)[key] = count(stats[key])
	end
	profile.Stats.MapWins = countMap(stats.MapWins)
	profile.Stats.EnvWins = countMap(stats.EnvWins)

	if type(raw.Achievements) == "table" then
		for id, unlocked in pairs(raw.Achievements) do
			if unlocked == true and Progression.achievementDef(id) then
				profile.Achievements[id] = true
			end
		end
	end

	if type(raw.Quests) == "table" and type(raw.Quests.List) == "table" then
		profile.Quests.Day = count(raw.Quests.Day)
		for _, quest in ipairs(raw.Quests.List) do
			local template = type(quest) == "table" and Progression.questTemplate(quest.id)
			if template then
				table.insert(profile.Quests.List, {
					id = template.id,
					progress = math.min(count(quest.progress), template.goal),
					done = quest.done == true,
				})
			end
		end
	end

	profile.LoginDay = count(raw.LoginDay)
	profile.LoginStreak = count(raw.LoginStreak)
	profile.LastRoundId = if type(raw.LastRoundId) == "string" then raw.LastRoundId else ""
	return profile, isFuture
end

-- Levels ----------------------------------------------------------------------

function Progression.xpToNext(level: number): number
	return Config.XP_LEVEL_BASE + Config.XP_LEVEL_STEP * (level - 1)
end

-- Returns level, XP into that level, and XP needed for the next (0 at max level).
function Progression.levelInfo(xp: number): (number, number, number)
	local level = 1
	local remaining = count(xp)
	while level < Config.MAX_LEVEL and remaining >= Progression.xpToNext(level) do
		remaining -= Progression.xpToNext(level)
		level += 1
	end
	if level >= Config.MAX_LEVEL then
		return Config.MAX_LEVEL, remaining, 0
	end
	return level, remaining, Progression.xpToNext(level)
end

function Progression.levelReward(level: number): number
	local coins = Config.LEVEL_REWARD_COINS * level
	if level % Config.LEVEL_MILESTONE_EVERY == 0 then
		coins += Config.LEVEL_MILESTONE_COINS
	end
	return coins
end

-- Daily quests ------------------------------------------------------------------

-- UTC day number for a unix time.
function Progression.dayNumber(unixTime: number): number
	return math.floor(unixTime / 86400)
end

-- Deterministic quest ids for a player and day (same on every server).
function Progression.questsFor(day: number, userId: number): { string }
	-- MINSTD generator: products stay below 2^53 so the sequence is exact.
	local seed = (count(day) * 7919 + math.abs(math.floor(userId)) % 1000003 * 31 + 17) % 2147483647
	if seed == 0 then
		seed = 1
	end
	local function nextInt(n: number): number
		seed = (seed * 48271) % 2147483647
		return seed % n + 1
	end

	local ids = {}
	for _, template in ipairs(Config.QUEST_POOL) do
		table.insert(ids, template.id)
	end
	for i = #ids, 2, -1 do
		local j = nextInt(i)
		ids[i], ids[j] = ids[j], ids[i]
	end
	return table.move(ids, 1, math.min(Config.QUESTS_PER_DAY, #ids), 1, {})
end

-- Replaces the quest list when the UTC day changes. Returns true if it changed.
function Progression.refreshQuests(profile: Profile, day: number, userId: number): boolean
	if profile.Quests.Day == day and #profile.Quests.List > 0 then
		return false
	end
	local list = {}
	for _, id in ipairs(Progression.questsFor(day, userId)) do
		table.insert(list, { id = id, progress = 0, done = false })
	end
	profile.Quests = { Day = day, List = list }
	return true
end

-- How much one round counts toward a quest metric.
function Progression.questMetric(metric: string, summary: RoundSummary): number
	if metric == "RoundsPlayed" then
		return 1
	elseif metric == "RoundsWon" then
		return if summary.won then 1 else 0
	elseif metric == "SecondsSurvived" then
		return count(summary.seconds)
	elseif metric == "PowerUps" then
		return count(summary.powerUps)
	elseif metric == "Bounces" then
		return count(summary.bounces)
	elseif metric == "Rescues" then
		return count(summary.rescues)
	elseif metric == "FullRounds" then
		return if summary.fullRound then 1 else 0
	elseif metric == "ModifierRounds" then
		return if summary.modifier ~= "None" then 1 else 0
	end
	return 0
end

-- Login streak --------------------------------------------------------------------

-- Call once per session after the profile loads. Returns the coin reward (0 if this
-- UTC day was already claimed) and the current streak.
function Progression.checkIn(profile: Profile, day: number): (number, number)
	if profile.LoginDay == day then
		return 0, profile.LoginStreak
	end
	if profile.LoginDay == day - 1 then
		profile.LoginStreak += 1
	else
		profile.LoginStreak = 1
	end
	profile.LoginDay = day
	local rewards = Config.LOGIN_STREAK_REWARDS
	local reward = rewards[math.min(profile.LoginStreak, #rewards)]
	profile.Coins += reward
	return reward, profile.LoginStreak
end

-- Achievements --------------------------------------------------------------------

-- Current value and goal for an achievement.
function Progression.achievementProgress(profile: Profile, def: any): (number, number)
	if def.kind == "allMaps" or def.kind == "allEnvironments" then
		local order = if def.kind == "allMaps" then Config.MAP_ORDER else Config.ENVIRONMENT_ORDER
		local wins = if def.kind == "allMaps" then profile.Stats.MapWins else profile.Stats.EnvWins
		local done = 0
		for _, id in ipairs(order) do
			if count(wins[id]) > 0 then
				done += 1
			end
		end
		return done, #order
	elseif def.kind == "level" then
		return (Progression.levelInfo(profile.XP)), def.goal
	end
	local value = if def.stat == "Wins" then profile.Wins else (profile.Stats :: any)[def.stat]
	return count(value), def.goal
end

-- Unlocks every newly met achievement. Returns their ids and the coins granted.
function Progression.checkAchievements(profile: Profile): ({ string }, number)
	local unlocked, coins = {}, 0
	for _, def in ipairs(Config.ACHIEVEMENTS) do
		if not profile.Achievements[def.id] then
			local value, goal = Progression.achievementProgress(profile, def)
			if value >= goal then
				profile.Achievements[def.id] = true
				table.insert(unlocked, def.id)
				coins += def.coins
			end
		end
	end
	profile.Coins += coins
	return unlocked, coins
end

-- Rounds --------------------------------------------------------------------------

function Progression.roundXp(summary: RoundSummary, winStreak: number): { XpPart }
	local parts = { { label = "Played", amount = Config.XP_PARTICIPATION } }
	local survived = math.floor(count(summary.seconds) / 10) * Config.XP_PER_10_SECONDS
	if survived > 0 then
		table.insert(parts, { label = "Survived", amount = survived })
	end
	if summary.won then
		table.insert(parts, { label = "Win", amount = Config.XP_WIN })
		if winStreak > 1 then
			local streakXp = math.min(Config.XP_STREAK_MAX, (winStreak - 1) * Config.XP_STREAK_STEP)
			table.insert(parts, { label = "Streak x" .. winStreak, amount = streakXp })
		end
	end
	local powerUps = count(summary.powerUps) * Config.XP_PER_POWERUP
	if powerUps > 0 then
		table.insert(parts, { label = "Power-ups", amount = powerUps })
	end
	local rescues = count(summary.rescues) * Config.XP_PER_RESCUE
	if rescues > 0 then
		table.insert(parts, { label = "Rescues", amount = rescues })
	end
	return parts
end

-- Applies one finished round to a profile: stats, Wins/Coins, XP + level rewards, daily
-- quests and achievements. A round id that was already applied is rejected, so a
-- repeated callback can't grant anything twice.
function Progression.recordRound(profile: Profile, summary: RoundSummary, day: number, userId: number): RoundResult
	local result: RoundResult = {
		duplicate = false,
		xp = 0,
		xpParts = {},
		coins = 0,
		levelsGained = {},
		quests = {},
		achievements = {},
	}
	if summary.roundId ~= "" and summary.roundId == profile.LastRoundId then
		result.duplicate = true
		return result
	end
	profile.LastRoundId = summary.roundId
	Progression.refreshQuests(profile, day, userId)

	local stats = profile.Stats
	local seconds = count(summary.seconds)
	stats.RoundsPlayed += 1
	stats.SecondsSurvived += seconds
	stats.BestSurvival = math.max(stats.BestSurvival, seconds)
	stats.PowerUps += count(summary.powerUps)
	stats.Bounces += count(summary.bounces)
	stats.Rescues += count(summary.rescues)

	local coins = 0
	if summary.won then
		profile.Wins += Config.WIN_REWARD
		coins += Config.COIN_REWARD + count(summary.bonusCoins)
		stats.CurrentWinStreak += 1
		stats.BestWinStreak = math.max(stats.BestWinStreak, stats.CurrentWinStreak)
		stats.MapWins[summary.map] = count(stats.MapWins[summary.map]) + 1
		stats.EnvWins[summary.environment] = count(stats.EnvWins[summary.environment]) + 1
		if summary.fullRound then
			stats.FullRounds += 1
		end
	else
		stats.CurrentWinStreak = 0
	end

	result.xpParts = Progression.roundXp(summary, stats.CurrentWinStreak)

	for _, quest in ipairs(profile.Quests.List) do
		local template = Progression.questTemplate(quest.id)
		if template and not quest.done then
			quest.progress = math.min(template.goal, quest.progress + Progression.questMetric(template.metric, summary))
			if quest.progress >= template.goal then
				quest.done = true
				coins += template.coins
				table.insert(result.xpParts, { label = "Quest", amount = template.xp })
				table.insert(result.quests, quest.id)
			end
		end
	end

	local xp = 0
	for _, part in ipairs(result.xpParts) do
		xp += part.amount
	end
	local levelBefore = Progression.levelInfo(profile.XP)
	profile.XP += xp
	local levelAfter = Progression.levelInfo(profile.XP)
	for level = levelBefore + 1, levelAfter do
		coins += Progression.levelReward(level)
		table.insert(result.levelsGained, level)
	end
	profile.Coins += coins

	local unlocked, achievementCoins = Progression.checkAchievements(profile)
	result.achievements = unlocked
	result.xp = xp
	result.coins = coins + achievementCoins
	return result
end

-- What the HUD needs (sent as JSON in the player's "Progress" attribute).
function Progression.clientView(profile: Profile)
	local level, into, nextXp = Progression.levelInfo(profile.XP)
	local quests = {}
	for _, quest in ipairs(profile.Quests.List) do
		local template = Progression.questTemplate(quest.id)
		if template then
			table.insert(quests, {
				id = quest.id,
				progress = quest.progress,
				goal = template.goal,
				done = quest.done,
				coins = template.coins,
				xp = template.xp,
			})
		end
	end
	local achievements = {}
	for _, def in ipairs(Config.ACHIEVEMENTS) do
		local value, goal = Progression.achievementProgress(profile, def)
		table.insert(achievements, {
			id = def.id,
			unlocked = profile.Achievements[def.id] == true,
			progress = math.min(value, goal),
			goal = goal,
			coins = def.coins,
		})
	end
	local stats = profile.Stats
	return {
		level = level,
		xp = profile.XP,
		xpInto = into,
		xpNext = nextXp,
		wins = profile.Wins,
		coins = profile.Coins,
		loginStreak = profile.LoginStreak,
		questDay = profile.Quests.Day,
		quests = quests,
		achievements = achievements,
		stats = {
			RoundsPlayed = stats.RoundsPlayed,
			SecondsSurvived = stats.SecondsSurvived,
			BestSurvival = stats.BestSurvival,
			PowerUps = stats.PowerUps,
			Rescues = stats.Rescues,
			FullRounds = stats.FullRounds,
			BestWinStreak = stats.BestWinStreak,
			CurrentWinStreak = stats.CurrentWinStreak,
		},
	}
end

return Progression
