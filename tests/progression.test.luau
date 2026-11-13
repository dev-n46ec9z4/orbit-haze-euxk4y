-- Run: node tests/run.mjs
local Config = require("./Config")
local Progression = require("./Progression")

local failures = 0
local function check(name: string, ok: boolean)
	if not ok then
		failures += 1
		print("FAIL " .. name)
	end
end

local function summary(overrides)
	local s = {
		roundId = "r1",
		won = false,
		seconds = 0,
		powerUps = 0,
		bounces = 0,
		rescues = 0,
		fullRound = false,
		map = "Square",
		environment = "Clear",
		modifier = "None",
		bonusCoins = 0,
	}
	for k, v in pairs(overrides or {}) do
		s[k] = v
	end
	return s
end

-- Migration ---------------------------------------------------------------------
local fresh, future = Progression.migrate(nil)
check("nil migrates to default", fresh.Wins == 0 and fresh.XP == 0 and not future)
check("default version", fresh.Version == Progression.SCHEMA_VERSION)

local v1 = Progression.migrate({ Wins = 12, Coins = 340 })
check("v1 keeps wins/coins", v1.Wins == 12 and v1.Coins == 340)
check("v1 gets defaults", v1.XP == 0 and v1.Stats.RoundsPlayed == 0 and next(v1.Achievements) == nil)

local junk = Progression.migrate({
	Version = 2,
	Wins = -5,
	Coins = "lots",
	XP = 0 / 0,
	Stats = { RoundsPlayed = math.huge, PowerUps = 3.7, MapWins = { Square = 2, Bad = -1 } },
	Achievements = { FirstWin = true, NotReal = true, TenWins = "yes" },
	Quests = { Day = 5, List = { { id = "WinRound", progress = 99, done = false }, { id = "Nope" }, "x" } },
	LastRoundId = 42,
	Extra = "dropped",
})
check("junk numbers sanitised", junk.Wins == 0 and junk.Coins == 0 and junk.XP == 0)
check("junk stats sanitised", junk.Stats.RoundsPlayed == 0 and junk.Stats.PowerUps == 3)
check("junk map wins filtered", junk.Stats.MapWins.Square == 2 and junk.Stats.MapWins.Bad == nil)
check("junk achievements filtered", junk.Achievements.FirstWin and not junk.Achievements.NotReal and not junk.Achievements.TenWins)
check("junk quests filtered + capped", #junk.Quests.List == 1 and junk.Quests.List[1].progress == 1)
check("junk round id", junk.LastRoundId == "")
check("junk extra dropped", (junk :: any).Extra == nil)

local _, isFuture = Progression.migrate({ Version = 99, Wins = 1 })
check("future version flagged", isFuture)

-- Round trip: a migrated v2 profile survives migrate() unchanged.
local roundTrip = Progression.defaultProfile()
roundTrip.Wins = 3
roundTrip.XP = 250
roundTrip.Stats.MapWins.Donut = 1
roundTrip.Achievements.FirstWin = true
Progression.refreshQuests(roundTrip, 100, 1)
local again = Progression.migrate(roundTrip)
check("round trip", again.Wins == 3 and again.XP == 250 and again.Stats.MapWins.Donut == 1
	and again.Achievements.FirstWin and #again.Quests.List == Config.QUESTS_PER_DAY and again.Quests.Day == 100)

-- Levels --------------------------------------------------------------------------
local level, into, nextXp = Progression.levelInfo(0)
check("level 1 at 0 xp", level == 1 and into == 0 and nextXp == Config.XP_LEVEL_BASE)
level, into = Progression.levelInfo(Config.XP_LEVEL_BASE)
check("level 2 at base xp", level == 2 and into == 0)
level, into = Progression.levelInfo(Config.XP_LEVEL_BASE + Config.XP_LEVEL_BASE + Config.XP_LEVEL_STEP + 5)
check("level 3 plus 5", level == 3 and into == 5)
level, _, nextXp = Progression.levelInfo(10 ^ 9)
check("max level capped", level == Config.MAX_LEVEL and nextXp == 0)
check("milestone reward", Progression.levelReward(5) == 5 * Config.LEVEL_REWARD_COINS + Config.LEVEL_MILESTONE_COINS)
check("plain reward", Progression.levelReward(4) == 4 * Config.LEVEL_REWARD_COINS)

-- Daily quests ------------------------------------------------------------------
local a = Progression.questsFor(20000, 12345)
local b = Progression.questsFor(20000, 12345)
check("quests deterministic", table.concat(a, ",") == table.concat(b, ","))
check("quest count", #a == Config.QUESTS_PER_DAY)
local unique = {}
for _, id in ipairs(a) do
	unique[id] = true
end
local uniqueCount = 0
for _ in pairs(unique) do
	uniqueCount += 1
end
check("quests distinct", uniqueCount == #a)
local differs = false
for day = 20001, 20010 do
	if table.concat(Progression.questsFor(day, 12345), ",") ~= table.concat(a, ",") then
		differs = true
	end
end
check("quests change across days", differs)
check("negative studio ids ok", #Progression.questsFor(20000, -1) == Config.QUESTS_PER_DAY)

local questProfile = Progression.defaultProfile()
check("refresh fills", Progression.refreshQuests(questProfile, 7, 1) and #questProfile.Quests.List == Config.QUESTS_PER_DAY)
check("refresh same day no-op", not Progression.refreshQuests(questProfile, 7, 1))
questProfile.Quests.List[1].progress = 1
check("refresh new day resets", Progression.refreshQuests(questProfile, 8, 1) and questProfile.Quests.List[1].progress == 0)

-- Login streak ------------------------------------------------------------------
local login = Progression.defaultProfile()
local reward, streak = Progression.checkIn(login, 100)
check("first login", reward == Config.LOGIN_STREAK_REWARDS[1] and streak == 1 and login.Coins == reward)
reward = Progression.checkIn(login, 100)
check("same day no double reward", reward == 0 and login.Coins == Config.LOGIN_STREAK_REWARDS[1])
reward, streak = Progression.checkIn(login, 101)
check("next day streak", streak == 2 and reward == Config.LOGIN_STREAK_REWARDS[2])
for day = 102, 110 do
	reward, streak = Progression.checkIn(login, day)
end
check("streak reward caps", streak == 11 and reward == Config.LOGIN_STREAK_REWARDS[#Config.LOGIN_STREAK_REWARDS])
reward, streak = Progression.checkIn(login, 115)
check("missed day resets", streak == 1 and reward == Config.LOGIN_STREAK_REWARDS[1])

-- Rounds ----------------------------------------------------------------------------
local p = Progression.defaultProfile()
-- Pin quests so the test knows what completes.
p.Quests = { Day = 1, List = { { id = "WinRound", progress = 0, done = false }, { id = "PlayRounds", progress = 0, done = false } } }
local result = Progression.recordRound(p, summary({ roundId = "a", won = true, seconds = 60, fullRound = true, powerUps = 2, bonusCoins = 10 }), 1, 1)
check("win counted", p.Wins == 1 and p.Stats.RoundsPlayed == 1 and p.Stats.FullRounds == 1)
check("win map/env", p.Stats.MapWins.Square == 1 and p.Stats.EnvWins.Clear == 1)
local expectedXp = Config.XP_PARTICIPATION + 6 * Config.XP_PER_10_SECONDS + Config.XP_WIN + 2 * Config.XP_PER_POWERUP
	+ Progression.questTemplate("WinRound").xp
check("round xp incl. quest", result.xp == expectedXp and p.XP == expectedXp)
check("quest completed once", #result.quests == 1 and result.quests[1] == "WinRound" and p.Quests.List[1].done)
local unlocked = {}
for _, id in ipairs(result.achievements) do
	unlocked[id] = true
end
check("first win + untouchable unlocked", unlocked.FirstWin and unlocked.Untouchable)
local expectedCoins = Config.COIN_REWARD + 10 + Progression.questTemplate("WinRound").coins
for _, levelGained in ipairs(result.levelsGained) do
	expectedCoins += Progression.levelReward(levelGained)
end
expectedCoins += Progression.achievementDef("FirstWin").coins + Progression.achievementDef("Untouchable").coins
check("coins total", p.Coins == expectedCoins and result.coins == expectedCoins)
check("levelled up", #result.levelsGained >= 1 and result.levelsGained[1] == 2)

-- Same round again is rejected and changes nothing.
local coinsBefore, xpBefore = p.Coins, p.XP
local dup = Progression.recordRound(p, summary({ roundId = "a", won = true, seconds = 60 }), 1, 1)
check("duplicate rejected", dup.duplicate and p.Coins == coinsBefore and p.XP == xpBefore and p.Wins == 1)

-- Achievement isn't granted twice.
local second = Progression.recordRound(p, summary({ roundId = "b", won = true, seconds = 30 }), 1, 1)
for _, id in ipairs(second.achievements) do
	check("no repeat achievement " .. id, id ~= "FirstWin" and id ~= "Untouchable")
end
check("win streak 2", p.Stats.CurrentWinStreak == 2)
local streakPart = false
for _, part in ipairs(second.xpParts) do
	streakPart = streakPart or (part.label == "Streak x2" and part.amount == Config.XP_STREAK_STEP)
end
check("streak xp", streakPart)
check("quest stays done", p.Quests.List[1].done and #second.quests == 0)

local loss = Progression.recordRound(p, summary({ roundId = "c", won = false, seconds = 12 }), 1, 1)
check("loss resets streak", p.Stats.CurrentWinStreak == 0 and p.Stats.BestWinStreak == 2)
check("loss gives participation + survival", loss.xp >= Config.XP_PARTICIPATION + Config.XP_PER_10_SECONDS)
check("loss no win", p.Wins == 2)
check("play quest done after 3 rounds", p.Quests.List[2].done)

-- New day in the middle of a session: quests roll over before counting.
Progression.recordRound(p, summary({ roundId = "d" }), 2, 1)
check("quests rolled to day 2", p.Quests.Day == 2)

-- World Tour needs a win on every map.
local tour = Progression.defaultProfile()
for i, map in ipairs(Config.MAP_ORDER) do
	local r = Progression.recordRound(tour, summary({ roundId = "t" .. i, won = true, map = map }), 1, 1)
	local got = false
	for _, id in ipairs(r.achievements) do
		got = got or id == "WorldTour"
	end
	check("world tour only on last map " .. map, got == (i == #Config.MAP_ORDER))
end

-- Migrated v1 data meets achievements immediately (checked on load).
local veteran = Progression.migrate({ Wins = 15, Coins = 0 })
local ids, coins = Progression.checkAchievements(veteran)
check("v1 wins unlock", #ids == 2 and coins == Progression.achievementDef("FirstWin").coins + Progression.achievementDef("TenWins").coins)
check("checkAchievements idempotent", #(Progression.checkAchievements(veteran)) == 0)

-- Client view is complete.
local view = Progression.clientView(p)
check("view quests", #view.quests == Config.QUESTS_PER_DAY and view.quests[1].goal ~= nil)
check("view achievements", #view.achievements == #Config.ACHIEVEMENTS)
check("view level", view.level >= 2 and view.xpNext > 0)

if failures > 0 then
	error(failures .. " progression test(s) failed")
end
print("progression tests passed")
