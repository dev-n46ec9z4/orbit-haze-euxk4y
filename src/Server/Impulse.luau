-- Short server-created velocity pushes on characters (bounce pads, sweeper, meteors).
-- Characters are simulated by their owning client, so setting AssemblyLinearVelocity on
-- the server is unreliable; a LinearVelocity constraint created on the server replicates
-- and is applied by the owner's physics for its short lifetime instead.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local Impulse = {}

local MOVER_NAME = "FallingTilesImpulse"

function Impulse.apply(character: Model?, velocity: Vector3, duration: number?): boolean
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return false
	end

	local previous = root:FindFirstChild(MOVER_NAME)
	if previous then
		previous:Destroy()
	end

	-- The attachment holds the constraint so a single Destroy cleans up both.
	local attachment = Instance.new("Attachment")
	attachment.Name = MOVER_NAME

	local mover = Instance.new("LinearVelocity")
	mover.Attachment0 = attachment
	mover.RelativeTo = Enum.ActuatorRelativeTo.World
	mover.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	mover.VectorVelocity = velocity
	mover.MaxForce = 1e6
	mover.Parent = attachment

	attachment.Parent = root

	task.delay(duration or Config.IMPULSE_DURATION, function()
		attachment:Destroy()
	end)
	return true
end

-- Adds a horizontal push on top of the character's current horizontal velocity while
-- leaving vertical motion (gravity, jumps) alone. Used for Blizzard gusts.
function Impulse.push(character: Model?, horizontal: Vector3, duration: number): boolean
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return false
	end

	local previous = root:FindFirstChild(MOVER_NAME)
	if previous then
		previous:Destroy()
	end

	local current = root.AssemblyLinearVelocity
	local attachment = Instance.new("Attachment")
	attachment.Name = MOVER_NAME

	local mover = Instance.new("LinearVelocity")
	mover.Attachment0 = attachment
	mover.RelativeTo = Enum.ActuatorRelativeTo.World
	mover.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	mover.PrimaryTangentAxis = Vector3.xAxis
	mover.SecondaryTangentAxis = Vector3.zAxis
	mover.PlaneVelocity = Vector2.new(current.X + horizontal.X, current.Z + horizontal.Z)
	mover.MaxForce = 1e5
	mover.Parent = attachment

	attachment.Parent = root

	task.delay(duration, function()
		attachment:Destroy()
	end)
	return true
end

return Impulse
