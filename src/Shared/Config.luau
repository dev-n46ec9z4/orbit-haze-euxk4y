-- Shared tunables for Falling Tiles Survival.
-- Required by both server and client via ReplicatedStorage.Shared.Config.

local Config = {}

-- Round flow
Config.MIN_PLAYERS = 1 -- 1 so a single player can test solo in Studio
Config.INTERMISSION_TIME = 10
Config.GRACE_TIME = 3
Config.ROUND_TIME = 60
Config.RESULTS_TIME = 5
Config.RESPAWN_TIME = 3

-- Lobby (sky platform)
Config.LOBBY_POSITION = Vector3.new(0, 60, 0)
Config.LOBBY_SIZE = Vector3.new(48, 2, 48)
Config.LOBBY_BARRIER_HEIGHT = 14

-- Arena
Config.ARENA_CENTER = Vector3.new(0, 10, 0)
Config.GRID_SIZE = 10
Config.TILE_SIZE = Vector3.new(6, 1, 6)
Config.TILE_GAP = 1

-- Tile waves
Config.WAVE_MIN_TILES = 3
Config.WAVE_MAX_TILES = 5
Config.WAVE_INTERVAL_START = 1.2
Config.WAVE_INTERVAL_END = 0.5
Config.TILE_FLASH_TIME = 0.6
Config.TILE_DESTROY_DELAY = 2

-- Kill plane
Config.KILL_PLANE_Y = -20

-- Special tiles (weights are relative; see Catalog.TileTypes for names/descriptions)
Config.TILE_TYPE_WEIGHTS = {
	{ id = "Normal", weight = 60 },
	{ id = "Ice", weight = 8 },
	{ id = "Crumble", weight = 8 },
	{ id = "Reinforced", weight = 10 },
	{ id = "Bounce", weight = 7 },
	{ id = "Conveyor", weight = 7 },
}
Config.BOUNCE_VELOCITY = 70 -- upward studs/s applied briefly
Config.BOUNCE_COOLDOWN = 0.8
Config.CONVEYOR_SPEED = 10
Config.CRUMBLE_DELAY = 0.9 -- warning time after a player steps on a crumble tile
Config.ICE_FRICTION = 0.02
Config.IMPULSE_DURATION = 0.18

-- Hazards (scheduled per mode, see Config.Modes)
Config.METEOR_WARN_TIME = 1.5
Config.METEOR_SMASH_RADIUS = 7.5 -- studs; 7 = one tile pitch, so target + 4 neighbours
Config.METEOR_KNOCKBACK = 45
Config.SWEEPER_WARN_TIME = 1.5
Config.SWEEPER_DURATION = 8
Config.SWEEPER_SPEED = 1.1 -- radians per second
Config.SWEEPER_HIT_RADIUS = 2
Config.SWEEPER_HIT_HEIGHT = 4.2 -- root height above the tile top that still counts as a hit
Config.SWEEPER_KNOCKBACK = 55
Config.ROW_COLLAPSE_WARN_TIME = 1.4

-- Power-ups
Config.POWERUP_MAX_ACTIVE = 2 -- pickups on the arena at once
Config.POWERUP_PICKUP_RADIUS = 4.5
Config.SPEED_BOOST_MULTIPLIER = 1.5
Config.SPEED_BOOST_TIME = 6
Config.JUMP_BOOST_MULTIPLIER = 1.8 -- applied to JumpHeight (or JumpPower via sqrt)
Config.JUMP_BOOST_TIME = 6
Config.RESCUE_DROP_DEPTH = 10 -- studs below the arena that trigger a Rescue Wing

-- Game modes, rotated in MODE_ORDER. Text lives in Catalog.Modes.
Config.MODE_ORDER = { "Classic", "ShrinkingRing", "HazardStorm" }
Config.Modes = {
	Classic = {
		pattern = "Random",
		waveMin = Config.WAVE_MIN_TILES,
		waveMax = Config.WAVE_MAX_TILES,
		hazards = { "Meteor", "Sweeper", "RowCollapse" },
		firstHazardAt = 12,
		hazardInterval = 14,
		powerUpInterval = 9,
	},
	ShrinkingRing = {
		pattern = "OuterFirst",
		waveMin = 3,
		waveMax = 5,
		hazards = { "Meteor" },
		firstHazardAt = 15,
		hazardInterval = 18,
		powerUpInterval = 9,
	},
	HazardStorm = {
		pattern = "Random",
		waveMin = 2,
		waveMax = 3,
		hazards = { "Meteor", "Sweeper", "RowCollapse" },
		firstHazardAt = 5,
		hazardInterval = 6,
		powerUpInterval = 7,
	},
}

-- Rewards
Config.WIN_REWARD = 1
Config.COIN_REWARD = 25

-- Tags / data
Config.ALIVE_TAG = "Alive"
Config.DATASTORE_NAME = "FallingTilesStats_v1"

Config.Phases = {
	Waiting = "Waiting",
	Intermission = "Intermission",
	Grace = "Grace",
	Survive = "Survive",
	Results = "Results",
}

Config.Colors = {
	LobbyFloor = Color3.fromRGB(58, 52, 70),
	LobbyBarrier = Color3.fromRGB(255, 226, 190),
	WarmNeon = Color3.fromRGB(255, 150, 60),
	SpawnPad = Color3.fromRGB(255, 196, 90),
	TileA = Color3.fromRGB(88, 170, 255),
	TileB = Color3.fromRGB(64, 132, 220),
	TileWarn = Color3.fromRGB(255, 40, 40),
	TileWarnDim = Color3.fromRGB(150, 20, 20),
	TileCracked = Color3.fromRGB(95, 90, 100),
	Meteor = Color3.fromRGB(255, 120, 40),
	HazardMarker = Color3.fromRGB(255, 50, 50),
	Sweeper = Color3.fromRGB(255, 70, 200),
}

return Config
