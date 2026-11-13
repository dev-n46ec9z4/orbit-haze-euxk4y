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

-- Hazards
Config.KILL_PLANE_Y = -20

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
}

return Config
