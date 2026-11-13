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

-- Server -> client: round snapshot { phase, banner, timeLeft, alive, total, players, winners }.
-- Client -> server: no payload, requests a fresh snapshot (used on join / late join).
function Net.getRoundStateEvent(): RemoteEvent
	if RunService:IsServer() then
		local folder = getOrCreateFolder()
		local event = folder:FindFirstChild(Net.ROUND_STATE)
		if not event then
			event = Instance.new("RemoteEvent")
			event.Name = Net.ROUND_STATE
			event.Parent = folder
		end
		return event
	end

	return ReplicatedStorage:WaitForChild(Net.FOLDER_NAME):WaitForChild(Net.ROUND_STATE)
end

return Net
