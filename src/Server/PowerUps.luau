-- Server-authoritative power-ups: pickups spawn on intact tiles, are collected by
-- proximity (checked on the server), and apply Speed Boost, Super Jump or Rescue Wing.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Catalog = require(Shared:WaitForChild("Catalog"))
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))

local World = require(script.Parent:WaitForChild("World"))

local gameEvent = Net.getGameEvent()

local PowerUps = {}

type Pickup = { id: string, part: BasePart, tile: BasePart }
type Original = { humanoid: Humanoid, walkSpeed: number, jumpPower: number, jumpHeight: number }
type Effects = { Speed: number?, Jump: number?, Wing: boolean? }

local pickups: { Pickup } = {}
local effects: { [Player]: Effects } = {}
local originals: { [Player]: Original } = {}
local currentArena: Model? = nil

local function entry(id: string)
	return Catalog.find(Catalog.PowerUps, id)
end

local function getHumanoid(player: Player): Humanoid?
	local character = player.Character
	return character and character:FindFirstChildOfClass("Humanoid")
end

local function toastAll(text: string, color: Color3?)
	gameEvent:FireAllClients({ kind = "Toast", text = text, color = color, duration = 2.5 })
end

-- Remember stock movement values the first time a buff touches this humanoid.
local function rememberOriginal(player: Player, humanoid: Humanoid): Original
	local original = originals[player]
	if original and original.humanoid == humanoid then
		return original
	end
	local fresh: Original = {
		humanoid = humanoid,
		walkSpeed = humanoid.WalkSpeed,
		jumpPower = humanoid.JumpPower,
		jumpHeight = humanoid.JumpHeight,
	}
	originals[player] = fresh
	return fresh
end

local function restoreStat(player: Player, id: string)
	local original = originals[player]
	if not original or original.humanoid.Parent == nil then
		return
	end
	if id == "Speed" then
		original.humanoid.WalkSpeed = original.walkSpeed
	elseif id == "Jump" then
		original.humanoid.JumpPower = original.jumpPower
		original.humanoid.JumpHeight = original.jumpHeight
	end
end

local function grant(player: Player, id: string)
	local humanoid = getHumanoid(player)
	if not humanoid then
		return
	end
	local mine = effects[player] or {}
	effects[player] = mine
	local duration: number? = nil

	if id == "Speed" then
		local original = rememberOriginal(player, humanoid)
		humanoid.WalkSpeed = original.walkSpeed * Config.SPEED_BOOST_MULTIPLIER
		duration = Config.SPEED_BOOST_TIME
		mine.Speed = os.clock() + Config.SPEED_BOOST_TIME
	elseif id == "Jump" then
		local original = rememberOriginal(player, humanoid)
		-- Jump height scales with the square of jump power.
		humanoid.JumpHeight = original.jumpHeight * Config.JUMP_BOOST_MULTIPLIER
		humanoid.JumpPower = original.jumpPower * math.sqrt(Config.JUMP_BOOST_MULTIPLIER)
		duration = Config.JUMP_BOOST_TIME
		mine.Jump = os.clock() + Config.JUMP_BOOST_TIME
	elseif id == "Wing" then
		mine.Wing = true
	end

	gameEvent:FireClient(player, { kind = "PowerUp", id = id, active = true, duration = duration })
	local info = entry(id)
	toastAll(string.format("%s grabbed %s", player.DisplayName, if info then info.name else id), info and info.color)
end

-- Pickups -----------------------------------------------------------------------

local function removePickup(index: number)
	local pickup = table.remove(pickups, index)
	if pickup and pickup.part.Parent then
		pickup.part:Destroy()
	end
end

function PowerUps.startRound(arena: Model)
	PowerUps.endRound()
	currentArena = arena
end

-- Spawns one random pickup on a free intact tile. Returns true if one was placed.
function PowerUps.spawnPickup(): boolean
	local arena = currentArena
	if not arena or not arena.Parent or #pickups >= Config.POWERUP_MAX_ACTIVE then
		return false
	end

	local taken: { [BasePart]: boolean } = {}
	for _, pickup in ipairs(pickups) do
		taken[pickup.tile] = true
	end
	local free = {}
	for _, tile in ipairs(World.getIntactTiles(arena)) do
		if not taken[tile] then
			table.insert(free, tile)
		end
	end
	if #free == 0 then
		return false
	end

	local tile = free[math.random(#free)]
	local info = Catalog.PowerUps[math.random(#Catalog.PowerUps)]
	local base = Vector3.new(tile.Position.X, World.getSurfaceY() + 2.5, tile.Position.Z)

	local part = Instance.new("Part")
	part.Name = "PowerUp_" .. info.id
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(2.5, 2.5, 2.5)
	part.CFrame = CFrame.new(base)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Material = Enum.Material.Neon
	part.Color = info.color
	part:SetAttribute("PowerUp", info.id)

	local light = Instance.new("PointLight")
	light.Color = info.color
	light.Range = 10
	light.Parent = part

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(140, 28)
	billboard.StudsOffset = Vector3.new(0, 2.5, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 150
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Text = string.upper(info.name)
	text.TextColor3 = info.color
	text.TextStrokeTransparency = 0.3
	text.Font = Enum.Font.GothamBlack
	text.TextScaled = true
	text.Parent = billboard
	billboard.Parent = part

	part.Parent = arena

	TweenService:Create(
		part,
		TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ CFrame = CFrame.new(base + Vector3.new(0, 1, 0)) }
	):Play()

	table.insert(pickups, { id = info.id, part = part, tile = tile })
	return true
end

-- Collects pickups, removes ones whose tile fell, expires timed buffs.
function PowerUps.tick(players: { Player }, now: number)
	for index = #pickups, 1, -1 do
		local pickup = pickups[index]
		if not pickup.part.Parent or not World.isIntact(pickup.tile) then
			removePickup(index)
		else
			for _, player in ipairs(players) do
				local character = player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart")
				if
					root
					and root:IsA("BasePart")
					and (root.Position - pickup.part.Position).Magnitude <= Config.POWERUP_PICKUP_RADIUS
				then
					local id = pickup.id
					removePickup(index)
					grant(player, id)
					break
				end
			end
		end
	end

	for player, mine in pairs(effects) do
		for _, id in ipairs({ "Speed", "Jump" }) do
			local expires = (mine :: any)[id]
			if expires and now >= expires then
				(mine :: any)[id] = nil
				restoreStat(player, id)
				gameEvent:FireClient(player, { kind = "PowerUp", id = id, active = false })
			end
		end
	end
end

-- Rescue Wing: called every Heartbeat for alive players during a round. Returns true
-- if the player was rescued (so the kill plane should leave them alone).
function PowerUps.tryRescue(player: Player): boolean
	local mine = effects[player]
	local arena = currentArena
	if not mine or not mine.Wing or not arena then
		return false
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return false
	end
	if root.Position.Y > Config.ARENA_CENTER.Y - Config.RESCUE_DROP_DEPTH then
		return false
	end
	if World.countIntactTiles(arena) == 0 then
		return false
	end

	mine.Wing = nil
	root.AssemblyLinearVelocity = Vector3.zero
	character:PivotTo(World.getSpawnCFrames(arena, 1)[1])
	gameEvent:FireClient(player, { kind = "PowerUp", id = "Wing", active = false })
	local info = entry("Wing")
	toastAll(player.DisplayName .. " was saved by a Rescue Wing!", info and info.color)
	return true
end

-- Removes every buff from a player (elimination, leaving, or round end).
function PowerUps.clear(player: Player)
	if effects[player] then
		restoreStat(player, "Speed")
		restoreStat(player, "Jump")
		effects[player] = nil
		if player.Parent == Players then
			gameEvent:FireClient(player, { kind = "PowerUpClear" })
		end
	end
	originals[player] = nil
end

function PowerUps.endRound()
	for index = #pickups, 1, -1 do
		removePickup(index)
	end
	local affected = {}
	for player in pairs(effects) do
		table.insert(affected, player)
	end
	for _, player in ipairs(affected) do
		PowerUps.clear(player)
	end
	table.clear(originals)
	currentArena = nil
end

return PowerUps
