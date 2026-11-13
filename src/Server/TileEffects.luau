-- Per-tick tile behaviours that depend on what a player is standing on:
-- Bounce pads launch players and Crumble tiles start falling when stepped on.
-- Ice and Conveyor tiles are purely physical (see World.styleTile / activateTiles).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local Impulse = require(script.Parent:WaitForChild("Impulse"))
local RoundStats = require(script.Parent:WaitForChild("RoundStats"))
local World = require(script.Parent:WaitForChild("World"))

local TileEffects = {}

local lastBounce: { [Player]: number } = {}

-- Root part is ~3 studs above the floor for standard rigs; look a little further.
local PROBE_DEPTH = 5

local function tileUnder(root: BasePart, params: RaycastParams): BasePart?
	local result = Workspace:Raycast(root.Position, Vector3.new(0, -PROBE_DEPTH, 0), params)
	local hit = result and result.Instance
	if hit and hit:IsA("BasePart") then
		return hit
	end
	return nil
end

function TileEffects.tick(arena: Model?, players: { Player }, now: number)
	local tiles = World.getTilesFolder(arena)
	if not tiles then
		return
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { tiles }

	for _, player in ipairs(players) do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			local tile = tileUnder(root, params)
			if tile and World.isIntact(tile) then
				local tileType = tile:GetAttribute("TileType")
				if tileType == "Bounce" then
					if now - (lastBounce[player] or 0) >= Config.BOUNCE_COOLDOWN then
						lastBounce[player] = now
						RoundStats.note(player, "bounces")
						local flat = root.AssemblyLinearVelocity * Vector3.new(1, 0, 1)
						Impulse.apply(character, flat + Vector3.new(0, Config.BOUNCE_VELOCITY, 0))
					end
				elseif tileType == "Crumble" then
					World.dropTile(tile, Config.CRUMBLE_DELAY)
				end
			end
		end
	end
end

function TileEffects.reset()
	table.clear(lastBounce)
end

function TileEffects.forget(player: Player)
	lastBounce[player] = nil
end

return TileEffects
