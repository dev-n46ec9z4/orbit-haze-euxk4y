-- Player-facing names, colours and descriptions for modes, tile types, hazards and
-- power-ups. The server uses the colours for world visuals; the HUD guide renders
-- everything here, so every gameplay feature is explained in-game.
-- Ids must match Config (TILE_TYPE_WEIGHTS, Modes, Maps, Environments, Modifiers and their
-- *_ORDER lists); tests/catalog.test.luau checks this.

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

Catalog.Maps = {
	{
		id = "Square",
		name = "Square",
		color = Color3.fromRGB(88, 170, 255),
		description = "The full 10x10 floor.",
	},
	{
		id = "Donut",
		name = "Donut",
		color = Color3.fromRGB(255, 160, 200),
		description = "The middle is a hole. Don't get pushed in.",
	},
	{
		id = "Cross",
		name = "Cross",
		color = Color3.fromRGB(120, 220, 255),
		description = "Two wide bridges crossing in the middle, with no corners.",
	},
	{
		id = "Islands",
		name = "Islands",
		color = Color3.fromRGB(110, 230, 170),
		description = "Nine islands with one-tile gaps between them. Jump across before yours sinks.",
	},
	{
		id = "Pyramid",
		name = "Pyramid",
		color = Color3.fromRGB(240, 200, 110),
		description = "Each ring sits higher than the last. Jump up the steps to the peak. No sweepers here.",
	},
} :: { Entry }

Catalog.Environments = {
	{
		id = "Clear",
		name = "Clear Sky",
		color = Color3.fromRGB(150, 210, 255),
		description = "Normal gravity and lighting.",
	},
	{
		id = "LowGravity",
		name = "Low Gravity",
		color = Color3.fromRGB(170, 140, 255),
		description = "Night sky, less than half gravity. Longer jumps, slower falls.",
	},
	{
		id = "Blizzard",
		name = "Blizzard",
		color = Color3.fromRGB(225, 240, 255),
		description = "Thick fog. A white wind front sweeps across, then a gust shoves everyone its way.",
	},
	{
		id = "Volcano",
		name = "Volcano",
		color = Color3.fromRGB(255, 110, 50),
		description = "Lava rises under the arena all round. Falling into it is instant elimination.",
	},
} :: { Entry }

Catalog.Modifiers = {
	{
		id = "None",
		name = "No Modifier",
		color = Color3.fromRGB(200, 195, 210),
		description = "Standard rules.",
	},
	{
		id = "Overdrive",
		name = "Overdrive",
		color = Color3.fromRGB(255, 120, 60),
		description = "Waves come 35% faster. Survivors get +10 bonus Coins.",
	},
	{
		id = "PowerSurge",
		name = "Power Surge",
		color = Color3.fromRGB(120, 255, 230),
		description = "Power-ups spawn twice as often, up to 4 at once.",
	},
	{
		id = "Regrowth",
		name = "Regrowth",
		color = Color3.fromRGB(140, 255, 120),
		description = "Every 4s a fallen tile grows back (ghosted at first, then solid).",
	},
	{
		id = "IceAge",
		name = "Ice Age",
		color = Color3.fromRGB(190, 240, 255),
		description = "Every normal tile is ice. Survivors get +5 bonus Coins.",
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
