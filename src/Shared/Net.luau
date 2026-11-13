-- Networking helpers. The server creates the remotes at runtime; clients wait for them.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = {}

Net.FOLDER_NAME = "FallingTilesRemotes"
Net.ROUND_STATE = "RoundState"

local function getOrCreateFolder(): Folder
	local folder = ReplicatedStorage:FindFirstChild(Net.FOLDER_NAME)
	if folder then
		return folder
	end
	folder = Instance.new("Folder")
	folder.Name = Net.FOLDER_NAME
	folder.Parent = ReplicatedStorage
	return folder
end

Net.GAME_EVENT = "GameEvent"

local function getEvent(name: string): RemoteEvent
	if RunService:IsServer() then
		local folder = getOrCreateFolder()
		local event = folder:FindFirstChild(name)
		if not event then
			event = Instance.new("RemoteEvent")
			event.Name = name
			event.Parent = folder
		end
		return event
	end

	return ReplicatedStorage:WaitForChild(Net.FOLDER_NAME):WaitForChild(name)
end

-- Server -> client: round snapshot { phase, banner, timeLeft, alive, total, players, winners, mode }.
-- Client -> server: no payload, requests a fresh snapshot (used on join / late join).
function Net.getRoundStateEvent(): RemoteEvent
	return getEvent(Net.ROUND_STATE)
end

-- Server -> client only. Payloads:
--   { kind = "Toast", text, color, duration }            announcements (hazards, pickups)
--   { kind = "PowerUp", id, active, duration }           local player's buff started/ended
--   { kind = "PowerUpClear" }                            all local buffs removed
-- The server ignores anything clients send on this event.
function Net.getGameEvent(): RemoteEvent
	return getEvent(Net.GAME_EVENT)
end

return Net
