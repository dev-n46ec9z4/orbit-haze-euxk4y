-- Player-facing names, colours and descriptions for modes, tile types, hazards and
-- power-ups. The server uses the colours for world visuals; the HUD guide renders
-- everything here, so every gameplay feature is explained in-game.
-- Ids must match Config (TILE_TYPE_WEIGHTS, Modes, MODE_ORDER); tests/catalog.test.luau checks this.

export type Entry = {
	id: string,
	name: string,
	color: Color3,
	description: string,
}

local Catalog = {}

Catalog.Modes = {
	{
		id = "Classic",
		name = "Classic",
		color = Color3.fromRGB(88, 170, 255),
		description = "Random tiles fall in speeding waves. Occasional meteors, sweepers and row collapses.",
	},
	{
		id = "ShrinkingRing",
		name = "Shrinking Ring",
		color = Color3.fromRGB(150, 110, 255),
		description = "Tiles fall from the outer edge inward. Head for the middle, but it won't last.",
	},
	{
		id = "HazardStorm",
		name = "Hazard Storm",
		color = Color3.fromRGB(255, 90, 90),
		description = "Smaller tile waves, but a hazard hits every few seconds.",
	},
} :: { Entry }

Catalog.TileTypes = {
	{
		id = "Normal",
		name = "Normal",
		color = Color3.fromRGB(88, 170, 255),
		description = "Falls when a wave picks it.",
	},
	{
		id = "Ice",
		name = "Ice",
		color = Color3.fromRGB(190, 240, 255),
		description = "Almost no friction. You'll slide.",
	},
	{
		id = "Crumble",
		name = "Crumble",
		color = Color3.fromRGB(215, 175, 110),
		description = "Starts falling a moment after someone steps on it.",
	},
	{
		id = "Reinforced",
		name = "Reinforced",
		color = Color3.fromRGB(160, 165, 175),
		description = "Survives the first wave that picks it (it cracks), falls on the second.",
	},
	{
		id = "Bounce",
		name = "Bounce Pad",
		color = Color3.fromRGB(90, 230, 120),
		description = "Launches you into the air. Use it to reach other tiles.",
	},
	{
		id = "Conveyor",
		name = "Conveyor",
		color = Color3.fromRGB(255, 205, 70),
		description = "Pushes you toward its glowing edge once the round starts.",
	},
} :: { Entry }

Catalog.Hazards = {
	{
		id = "Meteor",
		name = "Meteor",
		color = Color3.fromRGB(255, 120, 40),
		description = "Red circles mark impact points. The meteor smashes the tile and its neighbours.",
	},
	{
		id = "Sweeper",
		name = "Sweeper",
		color = Color3.fromRGB(255, 70, 200),
		description = "A low spinning beam knocks you away. Jump over it.",
	},
	{
		id = "RowCollapse",
		name = "Row Collapse",
		color = Color3.fromRGB(255, 60, 60),
		description = "A whole row or column flashes, then drops.",
	},
} :: { Entry }

Catalog.PowerUps = {
	{
		id = "Speed",
		name = "Speed Boost",
		color = Color3.fromRGB(80, 220, 255),
		description = "Run 50% faster for 6s.",
	},
	{
		id = "Jump",
		name = "Super Jump",
		color = Color3.fromRGB(130, 255, 120),
		description = "Jump much higher for 6s.",
	},
	{
		id = "Wing",
		name = "Rescue Wing",
		color = Color3.fromRGB(255, 230, 120),
		description = "If you fall, you're carried back onto a tile once. Lasts until used or the round ends.",
	},
} :: { Entry }

-- Lookup by id within one of the lists above.
function Catalog.find(list: { Entry }, id: string?): Entry?
	for _, entry in ipairs(list) do
		if entry.id == id then
			return entry
		end
	end
	return nil
end

return Catalog
