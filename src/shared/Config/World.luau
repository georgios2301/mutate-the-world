-- World layout constants shared by the server world builder and client helpers.
local World = {}

World.GroundY = 50 -- top surface height of hub, islands and biomes

World.HubCenter = Vector3.new(0, World.GroundY, 0)
World.HubRadius = 85

World.MaxIslands = 8
World.IslandRingRadius = 300
World.IslandHalfSize = 48 -- base platform is 96 x 96
World.IslandZoneRadius = 95 -- "on this island" check (includes expansion wings)

-- Distinct identity color per island slot.
World.IslandColors = {
	Color3.fromRGB(162, 92, 255), -- violet
	Color3.fromRGB(62, 230, 255), -- cyan
	Color3.fromRGB(124, 255, 79), -- toxic green
	Color3.fromRGB(255, 154, 60), -- orange
	Color3.fromRGB(255, 80, 160), -- pink
	Color3.fromRGB(255, 230, 80), -- yellow
	Color3.fromRGB(80, 140, 255), -- blue
	Color3.fromRGB(255, 90, 90), -- red
}
World.IslandColorNames = { "Violet", "Cyan", "Lime", "Orange", "Pink", "Gold", "Azure", "Crimson" }

World.BiomeRingRadius = 640
World.BiomeHalfSize = 110
World.BiomeAngles = {
	frozen_peaks = 22.5,
	toxic_swamp = 112.5,
	plasma_rift = 202.5,
	cosmic_void = 292.5,
}

function World.islandPosition(index: number): Vector3
	local angle = math.rad((index - 1) * (360 / World.MaxIslands))
	return Vector3.new(math.cos(angle) * World.IslandRingRadius, World.GroundY, math.sin(angle) * World.IslandRingRadius)
end

-- Island local frame: origin at the top surface center, -Z (LookVector) faces the hub.
function World.islandCFrame(index: number): CFrame
	local pos = World.islandPosition(index)
	return CFrame.lookAt(pos, Vector3.new(World.HubCenter.X, pos.Y, World.HubCenter.Z))
end

function World.biomePosition(biomeId: string): Vector3
	local angle = math.rad(World.BiomeAngles[biomeId] or 0)
	return Vector3.new(math.cos(angle) * World.BiomeRingRadius, World.GroundY, math.sin(angle) * World.BiomeRingRadius)
end

function World.biomeCFrame(biomeId: string): CFrame
	local pos = World.biomePosition(biomeId)
	return CFrame.lookAt(pos, Vector3.new(World.HubCenter.X, pos.Y, World.HubCenter.Z))
end

-- Island layout in island-local studs (x right, z back/away from hub, y up).
World.IslandLayout = {
	vaultMin = Vector3.new(-30, 0, -2),
	vaultMax = Vector3.new(30, 12, 38),
	doorHalfWidth = 6,
	padColumns = { -22, -11, 0, 11, 22 },
	padRows = { 12, 22, 32 },
	ownerSpawn = Vector3.new(0, 3, 4),
	dock = Vector3.new(0, 3, -40),
	chamber = Vector3.new(-39, 0, 14),
	collector = Vector3.new(39, 0, 14),
	upgradeTerminal = Vector3.new(24, 0, -22),
	securityConsole = Vector3.new(-24, 0, -22),
	hubPad = Vector3.new(0, 0, -34),
}

function World.padLocalPosition(slot: number): Vector3
	local cols = #World.IslandLayout.padColumns
	local row = math.floor((slot - 1) / cols) + 1
	local col = (slot - 1) % cols + 1
	return Vector3.new(World.IslandLayout.padColumns[col], 0, World.IslandLayout.padRows[row] or 32)
end

World.MaxPadPositions = #World.IslandLayout.padColumns * #World.IslandLayout.padRows

return World
