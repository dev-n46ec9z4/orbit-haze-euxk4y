-- Per-player tracking for the current round, turned into a Progression.RoundSummary
-- exactly once per player: when they are eliminated (lost) or when the round ends
-- (survivors won). Players who leave mid-round are forgotten and forfeit the round.

local RoundStats = {}

type Entry = {
	powerUps: number,
	bounces: number,
	rescues: number,
	finalized: boolean,
}

type Plan = { map: string, environment: string, modifier: string, bonusCoins: number }

local roundId = ""
local plan: Plan? = nil
local surviveStart: number? = nil
local roundLength = 0
local entries: { [Player]: Entry } = {}

function RoundStats.begin(id: string, roundPlan: Plan, players: { Player }, length: number)
	table.clear(entries)
	roundId = id
	plan = roundPlan
	surviveStart = nil
	roundLength = length
	for _, player in ipairs(players) do
		entries[player] = { powerUps = 0, bounces = 0, rescues = 0, finalized = false }
	end
end

-- Survival time counts from the start of Survive; grace-period deaths survive 0s.
function RoundStats.markSurviveStart(now: number)
	surviveStart = now
end

-- key: "powerUps" | "bounces" | "rescues". Ignored for untracked/finalized players.
function RoundStats.note(player: Player, key: string)
	local entry = entries[player]
	if entry and not entry.finalized then
		(entry :: any)[key] += 1
	end
end

-- Returns the summary the first time it's called for a tracked player, nil afterwards.
function RoundStats.finalize(player: Player, won: boolean, now: number)
	local entry = entries[player]
	if not entry or entry.finalized or not plan then
		return nil
	end
	entry.finalized = true
	local seconds = if surviveStart then math.max(0, now - surviveStart) else 0
	return {
		roundId = roundId,
		won = won,
		seconds = math.floor(seconds),
		powerUps = entry.powerUps,
		bounces = entry.bounces,
		rescues = entry.rescues,
		fullRound = won and seconds >= roundLength - 1,
		map = plan.map,
		environment = plan.environment,
		modifier = plan.modifier,
		bonusCoins = if won then plan.bonusCoins else 0,
	}
end

function RoundStats.forget(player: Player)
	entries[player] = nil
end

function RoundStats.clear()
	table.clear(entries)
	plan = nil
	surviveStart = nil
end

return RoundStats
