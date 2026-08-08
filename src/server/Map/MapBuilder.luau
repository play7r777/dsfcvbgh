--!nonstrict
-- ============================================================================
-- MapBuilder — детерминированная генерация большой общевойсковой PvP-арены.
-- Terrain формирует основание, тактические высоты, окопы, воронки и валы;
-- primitives используются для маршрутов, руин, укреплений, ориентиров и укрытий.
-- ============================================================================

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared").Config.GameConfig)
local MapAssets = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("map")

local MapBuilder = {}

local Terrain = Workspace.Terrain
local MAP_SEED = 24051945
local GROUND_Y = GameConfig.GroundTopY
local FRONT_X = 270
local FRONT_Z = 520
local ROAD_WIDTH = 36
local COVER_CELL_SIZE = 118
local MIN_COVER_SPACING = 34

local GRASS = Enum.Material.Grass
local GROUND = Enum.Material.Ground
local MUD = Enum.Material.Mud
local ROCK = Enum.Material.Rock
local SAND = Enum.Material.Sand
local SLATE = Enum.Material.Slate
local CONCRETE = Enum.Material.Concrete
local BRICK = Enum.Material.Brick
local WOOD = Enum.Material.Wood
local METAL = Enum.Material.Metal
local AIR = Enum.Material.Air

local COLORS = {
	Road = Color3.fromRGB(64, 65, 62),
	RoadShoulder = Color3.fromRGB(91, 78, 61),
	RoadMarking = Color3.fromRGB(170, 156, 112),
	Concrete = Color3.fromRGB(111, 111, 105),
	DarkConcrete = Color3.fromRGB(77, 79, 77),
	Brick = Color3.fromRGB(112, 78, 64),
	Wood = Color3.fromRGB(101, 73, 45),
	Metal = Color3.fromRGB(69, 72, 70),
	Rust = Color3.fromRGB(105, 71, 48),
	Sandbag = Color3.fromRGB(151, 133, 96),
	Rock = Color3.fromRGB(91, 88, 82),
	Mud = Color3.fromRGB(87, 70, 51),
	Olive = Color3.fromRGB(73, 82, 57),
	DarkOlive = Color3.fromRGB(49, 57, 42),
	Charred = Color3.fromRGB(49, 45, 40),
	Warning = Color3.fromRGB(170, 126, 48),
}

local function point(x: number, z: number): Vector3
	return Vector3.new(x, GROUND_Y, z)
end

local SPAWN_POINTS = {
	point(-820, -820),
	point(820, 820),
	point(-820, 820),
	point(820, -820),
	point(-820, 0),
	point(820, 0),
	point(0, -820),
	point(0, 820),
}

local TANK_PADS = {
	CFrame.new(-640, GROUND_Y + 0.22, -640) * CFrame.Angles(0, math.rad(45), 0),
	CFrame.new(640, GROUND_Y + 0.22, 640) * CFrame.Angles(0, math.rad(-135), 0),
}

local BIKE_PADS = {
	CFrame.new(0, GROUND_Y + 0.22, -760),
	CFrame.new(0, GROUND_Y + 0.22, 760) * CFrame.Angles(0, math.rad(180), 0),
	CFrame.new(-760, GROUND_Y + 0.22, 120) * CFrame.Angles(0, math.rad(90), 0),
	CFrame.new(760, GROUND_Y + 0.22, -120) * CFrame.Angles(0, math.rad(-90), 0),
}

local CONTAINER_SPAWNS = {
	CFrame.new(48, GROUND_Y + 0.2, -66),
	CFrame.new(-48, GROUND_Y + 0.2, 66),
	CFrame.new(-322, GROUND_Y + 0.2, -365),
	CFrame.new(-322, GROUND_Y + 0.2, 365),
	CFrame.new(322, GROUND_Y + 0.2, 365),
	CFrame.new(322, GROUND_Y + 0.2, -365),
	CFrame.new(-505, GROUND_Y + 0.2, 62),
	CFrame.new(505, GROUND_Y + 0.2, -62),
	CFrame.new(-34, GROUND_Y + 0.2, -360),
	CFrame.new(34, GROUND_Y + 0.2, 360),
	CFrame.new(-540, GROUND_Y + 0.2, -520),
	CFrame.new(540, GROUND_Y + 0.2, 520),
	CFrame.new(34, GROUND_Y + 0.2, -610),
	CFrame.new(-34, GROUND_Y + 0.2, 610),
}

-- Две широкие поперечные дороги пересекают окопы только по мостам. Остальные
-- маршруты подводят технику к ним и образуют объезд вокруг центральных руин.
local VEHICLE_ROADS = {
	{ point(-760, -160), point(-540, -160), point(-300, -160), point(0, -160), point(300, -160), point(540, -160), point(760, -160) },
	{ point(-760, 160), point(-540, 160), point(-300, 160), point(0, 160), point(300, 160), point(540, 160), point(760, 160) },
	{ point(0, -760), point(0, -560), point(0, -360), point(0, -250), point(0, -160) },
	{ point(0, 160), point(0, 250), point(0, 360), point(0, 560), point(0, 760) },
	{ point(-150, -160), point(-150, 0), point(-150, 160) },
	{ point(150, -160), point(150, 0), point(150, 160) },
	{ point(-640, -640), point(-640, -420), point(-640, -160) },
	{ point(640, 640), point(640, 420), point(640, 160) },
	{ point(-760, -160), point(-760, 0), point(-760, 160) },
	{ point(760, -160), point(760, 0), point(760, 160) },
	{ point(-640, -640), point(-455, -640), point(-230, -600), point(0, -560) },
	{ point(640, 640), point(455, 640), point(230, 600), point(0, 560) },
}

local FOOT_PATHS = {
	{ point(-820, -820), point(-750, -735), point(-680, -665) },
	{ point(820, 820), point(750, 735), point(680, 665) },
	{ point(-820, 820), point(-720, 715), point(-590, 610), point(-500, 500) },
	{ point(820, -820), point(720, -715), point(590, -610), point(500, -500) },
	{ point(-820, 0), point(-700, 0), point(-590, 35), point(-480, 55) },
	{ point(820, 0), point(700, 0), point(590, -35), point(480, -55) },
	{ point(0, -820), point(-38, -710), point(-70, -600), point(-95, -500) },
	{ point(0, 820), point(38, 710), point(70, 600), point(95, 500) },
	{ point(-245, -500), point(-170, -420), point(-105, -300), point(-80, -205) },
	{ point(245, 500), point(170, 420), point(105, 300), point(80, 205) },
	{ point(-740, 300), point(-650, 375), point(-565, 455) },
	{ point(740, -300), point(650, -375), point(565, -455) },
	{ point(-420, -560), point(-360, -450), point(-330, -300) },
	{ point(420, 560), point(360, 450), point(330, 300) },
}

local TERRAIN_RISES = {
	{ Center = point(-470, 300), Size = Vector2.new(185, 138), Height = 16, Levels = 5, Angle = math.rad(14) },
	{ Center = point(470, -300), Size = Vector2.new(185, 138), Height = 16, Levels = 5, Angle = math.rad(-166) },
	{ Center = point(-125, 535), Size = Vector2.new(190, 120), Height = 12, Levels = 4, Angle = math.rad(-10) },
	{ Center = point(125, -535), Size = Vector2.new(190, 120), Height = 12, Levels = 4, Angle = math.rad(170) },
	{ Center = point(-680, 390), Size = Vector2.new(145, 112), Height = 10, Levels = 4, Angle = math.rad(28) },
	{ Center = point(680, -390), Size = Vector2.new(145, 112), Height = 10, Levels = 4, Angle = math.rad(-152) },
	{ Center = point(-430, -330), Size = Vector2.new(140, 102), Height = 8, Levels = 3, Angle = math.rad(-24) },
	{ Center = point(430, 330), Size = Vector2.new(140, 102), Height = 8, Levels = 3, Angle = math.rad(156) },
}

local function zigzagPoints(xBase: number): { Vector3 }
	local points = {}
	local index = 0
	for z = -FRONT_Z, FRONT_Z, 65 do
		local x = xBase + (index % 2 == 0 and -12 or 12)
		table.insert(points, point(x, z))
		index += 1
	end
	if points[#points].Z < FRONT_Z then
		table.insert(points, point(xBase, FRONT_Z))
	end
	return points
end

local WEST_TRENCH = zigzagPoints(-FRONT_X)
local EAST_TRENCH = zigzagPoints(FRONT_X)
local TRENCH_POLYLINES = {
	WEST_TRENCH,
	EAST_TRENCH,
	{ point(-270, -350), point(-380, -374), point(-470, -346), point(-565, -372) },
	{ point(-270, 350), point(-380, 374), point(-470, 346), point(-565, 372) },
	{ point(270, -350), point(380, -374), point(470, -346), point(565, -372) },
	{ point(270, 350), point(380, 374), point(470, 346), point(565, 372) },
}

local function makeFolder(name: string, parent: Instance): Folder
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

local function fill(cframe: CFrame, size: Vector3, material: any)
	Terrain:FillBlock(cframe, size, material)
end

local function part(
	name: string,
	size: Vector3,
	cframe: CFrame,
	material: any,
	color: Color3,
	parent: Instance,
	canCollide: boolean?
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Material = material
	p.Color = color
	p.Anchored = true
	p.CanCollide = canCollide ~= false
	p.CanTouch = false
	p.CanQuery = canCollide ~= false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function segmentPart(
	name: string,
	a: Vector3,
	b: Vector3,
	width: number,
	height: number,
	y: number,
	material: any,
	color: Color3,
	parent: Instance,
	canCollide: boolean?
): Part?
	local flatA = Vector3.new(a.X, y, a.Z)
	local flatB = Vector3.new(b.X, y, b.Z)
	local delta = flatB - flatA
	if delta.Magnitude < 0.01 then
		return nil
	end
	local midpoint = (flatA + flatB) / 2
	local cframe = CFrame.lookAt(midpoint, flatB)
	return part(name, Vector3.new(width, height, delta.Magnitude), cframe, material, color, parent, canCollide)
end

local function distanceToSegmentXZ(position: Vector3, a: Vector3, b: Vector3): number
	local px = position.X
	local pz = position.Z
	local ax = a.X
	local az = a.Z
	local bx = b.X
	local bz = b.Z
	local dx = bx - ax
	local dz = bz - az
	local lengthSquared = dx * dx + dz * dz
	if lengthSquared <= 0.001 then
		return math.sqrt((px - ax) ^ 2 + (pz - az) ^ 2)
	end
	local t = math.clamp(((px - ax) * dx + (pz - az) * dz) / lengthSquared, 0, 1)
	local nearestX = ax + dx * t
	local nearestZ = az + dz * t
	return math.sqrt((px - nearestX) ^ 2 + (pz - nearestZ) ^ 2)
end

local RESERVED_ZONES = {
	{ Position = point(0, 0), Radius = 145 },
	{ Position = point(0, -360), Radius = 62 },
	{ Position = point(0, 360), Radius = 62 },
	{ Position = point(-500, 455), Radius = 72 },
	{ Position = point(500, -455), Radius = 72 },
	{ Position = point(-335, 20), Radius = 44 },
	{ Position = point(335, -20), Radius = 44 },
	{ Position = point(-565, -350), Radius = 58 },
	{ Position = point(565, 350), Radius = 58 },
	{ Position = point(-620, 90), Radius = 55 },
	{ Position = point(620, -90), Radius = 55 },
	{ Position = point(-720, 610), Radius = 30 },
	{ Position = point(720, -610), Radius = 30 },
	{ Position = point(-390, 665), Radius = 18 },
	{ Position = point(390, -665), Radius = 18 },
}

for _, spawnPosition in ipairs(SPAWN_POINTS) do
	table.insert(RESERVED_ZONES, { Position = spawnPosition, Radius = 52 })
end
for _, cframe in ipairs(TANK_PADS) do
	table.insert(RESERVED_ZONES, { Position = cframe.Position, Radius = 42 })
end
for _, cframe in ipairs(BIKE_PADS) do
	table.insert(RESERVED_ZONES, { Position = cframe.Position, Radius = 24 })
end
for _, cframe in ipairs(CONTAINER_SPAWNS) do
	table.insert(RESERVED_ZONES, { Position = cframe.Position, Radius = 9 })
end

local function isReserved(position: Vector3, padding: number): boolean
	local halfX = GameConfig.ArenaSize.X / 2
	local halfZ = GameConfig.ArenaSize.Z / 2
	if math.abs(position.X) > halfX - 62 - padding or math.abs(position.Z) > halfZ - 62 - padding then
		return true
	end

	for _, zone in ipairs(RESERVED_ZONES) do
		local offset = Vector2.new(position.X - zone.Position.X, position.Z - zone.Position.Z)
		if offset.Magnitude < zone.Radius + padding then
			return true
		end
	end

	for _, rise in ipairs(TERRAIN_RISES) do
		local offset = Vector2.new(position.X - rise.Center.X, position.Z - rise.Center.Z)
		if offset.Magnitude < math.max(rise.Size.X, rise.Size.Y) / 2 + padding then
			return true
		end
	end

	for _, polyline in ipairs(VEHICLE_ROADS) do
		for index = 1, #polyline - 1 do
			if distanceToSegmentXZ(position, polyline[index], polyline[index + 1]) < ROAD_WIDTH / 2 + 8 + padding then
				return true
			end
		end
	end

	for _, polyline in ipairs(TRENCH_POLYLINES) do
		for index = 1, #polyline - 1 do
			if distanceToSegmentXZ(position, polyline[index], polyline[index + 1]) < GameConfig.TrenchWidth + 7 + padding then
				return true
			end
		end
	end

	return false
end

local function buildBaseTerrain()
	local size = GameConfig.ArenaSize
	local thickness = GameConfig.GroundThickness

	-- Build() может повторно запускаться в Studio: очищаем только объём этой арены,
	-- чтобы старые возвышенности и окопы не наслаивались на новую генерацию.
	fill(CFrame.new(0, GROUND_Y + 24, 0), Vector3.new(size.X + 48, 68, size.Z + 48), AIR)
	fill(CFrame.new(0, GROUND_Y - thickness / 2, 0), Vector3.new(size.X, thickness, size.Z), GRASS)

	local halfX = size.X / 2
	local halfZ = size.Z / 2
	local height = GameConfig.PerimeterHeight
	fill(CFrame.new(0, GROUND_Y + height / 2 - 4, -halfZ - 5), Vector3.new(size.X + 30, height, 16), ROCK)
	fill(CFrame.new(0, GROUND_Y + height / 2 - 4, halfZ + 5), Vector3.new(size.X + 30, height, 16), ROCK)
	fill(CFrame.new(-halfX - 5, GROUND_Y + height / 2 - 4, 0), Vector3.new(16, height, size.Z + 30), ROCK)
	fill(CFrame.new(halfX + 5, GROUND_Y + height / 2 - 4, 0), Vector3.new(16, height, size.Z + 30), ROCK)

	for _, corner in ipairs({ point(-halfX, -halfZ), point(halfX, -halfZ), point(-halfX, halfZ), point(halfX, halfZ) }) do
		Terrain:FillBall(corner + Vector3.new(0, 4, 0), 28, ROCK)
	end
end

local function buildTerrainVariation(parent: Instance)
	for index, rise in ipairs(TERRAIN_RISES) do
		local levelHeight = rise.Height / rise.Levels
		for level = 1, rise.Levels do
			local height = level * levelHeight
			local insetX = (level - 1) * 17
			local insetZ = (level - 1) * 13
			local width = math.max(34, rise.Size.X - insetX * 2)
			local depth = math.max(28, rise.Size.Y - insetZ * 2)
			local cframe = CFrame.new(rise.Center.X, GROUND_Y + height / 2, rise.Center.Z)
				* CFrame.Angles(0, rise.Angle, 0)
			fill(cframe, Vector3.new(width, height, depth), level <= 2 and GROUND or GRASS)
		end

		-- Каменные выходы читаются издалека и дают локальное укрытие на высоте.
		for outcropIndex, offset in ipairs({
			Vector3.new(rise.Size.X * 0.08, rise.Height, -rise.Size.Y * 0.06),
			Vector3.new(-rise.Size.X * 0.11, rise.Height * 0.55, rise.Size.Y * 0.28),
		}) do
			local rock = part(
				("HillOutcrop_%d_%d"):format(index, outcropIndex),
				outcropIndex == 1 and Vector3.new(11, 6, 8) or Vector3.new(8, 5, 7),
				CFrame.new(rise.Center + offset + Vector3.new(0, 2.2, 0))
					* CFrame.Angles(math.rad(8), rise.Angle + outcropIndex * 0.4, math.rad(-6)),
				ROCK,
				COLORS.Rock,
				parent,
				true
			)
			rock.Shape = Enum.PartType.Ball
		end
	end
end

local function carveCrater(position: Vector3, radius: number, depth: number)
	local sphereRadius = (radius * radius + depth * depth) / (2 * depth)
	local sphereCenterY = GROUND_Y + sphereRadius - depth
	Terrain:FillBall(Vector3.new(position.X, sphereCenterY, position.Z), sphereRadius, AIR)
end

local function buildShellCraters()
	local rng = Random.new(MAP_SEED + 11)
	local built = 0
	for _ = 1, 900 do
		if built >= 38 then
			break
		end
		local position = point(rng:NextNumber(-805, 805), rng:NextNumber(-805, 805))
		local radius = rng:NextNumber(9, 18)
		if not isReserved(position, radius + 5) then
			-- Подповерхностная сфера грязи оставляет естественный тёмный обод после выреза.
			local mudRadius = radius + 2.5
			Terrain:FillBall(position + Vector3.new(0, -mudRadius + 0.65, 0), mudRadius, MUD)
			carveCrater(position, radius, rng:NextNumber(2.1, 3.8))
			built += 1
		end
	end
end

local function fillSegment(a: Vector3, b: Vector3, width: number, height: number, material: any)
	local flatA = Vector3.new(a.X, GROUND_Y + height / 2, a.Z)
	local flatB = Vector3.new(b.X, GROUND_Y + height / 2, b.Z)
	local delta = flatB - flatA
	if delta.Magnitude < 0.01 then
		return
	end
	fill(CFrame.lookAt((flatA + flatB) / 2, flatB), Vector3.new(width, height, delta.Magnitude), material)
end

local function buildEarthBerms()
	local berms = {
		{ point(-610, 255), point(-555, 300) },
		{ point(-555, 300), point(-500, 315) },
		{ point(610, -255), point(555, -300) },
		{ point(555, -300), point(500, -315) },
		{ point(-330, -705), point(-255, -675) },
		{ point(330, 705), point(255, 675) },
		{ point(-720, -350), point(-670, -305) },
		{ point(720, 350), point(670, 305) },
		{ point(-595, -245), point(-535, -215) },
		{ point(595, 245), point(535, 215) },
		{ point(-205, 690), point(-145, 660) },
		{ point(205, -690), point(145, -660) },
	}
	for _, berm in ipairs(berms) do
		fillSegment(berm[1], berm[2], 17, 4.2, GROUND)
		fillSegment(berm[1], berm[2], 9, 5.1, GRASS)
	end
end

local function buildRoadNetwork(parent: Instance)
	for routeIndex, polyline in ipairs(VEHICLE_ROADS) do
		for index = 1, #polyline - 1 do
			segmentPart(
				("RoadShoulder_%d_%d"):format(routeIndex, index),
				polyline[index],
				polyline[index + 1],
				ROAD_WIDTH + 10,
				0.12,
				GROUND_Y + 0.04,
				GROUND,
				COLORS.RoadShoulder,
				parent,
				false
			)
			local road = segmentPart(
				("Road_%d_%d"):format(routeIndex, index),
				polyline[index],
				polyline[index + 1],
				ROAD_WIDTH,
				0.16,
				GROUND_Y + 0.1,
				SLATE,
				COLORS.Road,
				parent,
				true
			)
			if road then
				road.CastShadow = false
			end

			-- Редкая осевая разметка помогает читать главные транспортные оси.
			if routeIndex <= 4 then
				local a = polyline[index]
				local b = polyline[index + 1]
				local delta = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
				if delta.Magnitude > 45 then
					local direction = delta.Unit
					for distance = 24, delta.Magnitude - 12, 52 do
						local center = a + direction * distance
						part(
							"RoadMarking",
							Vector3.new(0.65, 0.04, 14),
							CFrame.lookAt(center + Vector3.new(0, GROUND_Y + 0.21, 0), center + direction),
							CONCRETE,
							COLORS.RoadMarking,
							parent,
							false
						)
					end
				end
			end
		end
	end

	for routeIndex, polyline in ipairs(FOOT_PATHS) do
		for index = 1, #polyline - 1 do
			local path = segmentPart(
				("Footpath_%d_%d"):format(routeIndex, index),
				polyline[index],
				polyline[index + 1],
				7,
				0.08,
				GROUND_Y + 0.05,
				MUD,
				COLORS.Mud,
				parent,
				false
			)
			if path then
				path.CastShadow = false
			end
		end
	end
end

local function buildSandbagLine(a: Vector3, b: Vector3, sideDirection: Vector3, parent: Instance)
	local delta = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
	local length = delta.Magnitude
	if length < 1 then
		return
	end
	local direction = delta.Unit
	local normal = Vector3.new(-direction.Z, 0, direction.X)
	if normal:Dot(sideDirection) < 0 then
		normal = -normal
	end

	local distance = 8
	while distance < length - 4 do
		local position = a + direction * distance + normal * (GameConfig.TrenchWidth / 2 + 1.4)
		local nearBridge = math.abs(math.abs(position.Z) - 160) < 23 and math.abs(math.abs(position.X) - FRONT_X) < 38
		if not nearBridge then
			part(
				"Sandbag",
				Vector3.new(2.1, 1.35, 6.5),
				CFrame.lookAt(Vector3.new(position.X, GROUND_Y + 0.68, position.Z), position + direction),
				SAND,
				COLORS.Sandbag,
				parent,
				true
			)
		end
		distance += 16
	end
end

local function buildTrenchRamp(position: Vector3, outward: Vector3, parent: Instance)
	local depth = GameConfig.TrenchDepth
	local length = 13
	local direction = Vector3.new(outward.X, 0, outward.Z).Unit
	local midpoint = position + direction * (length / 2) + Vector3.new(0, -depth / 2 + 0.25, 0)
	local slope = math.atan(depth / length)
	part(
		"TrenchRamp",
		Vector3.new(GameConfig.TrenchWidth - 0.8, 0.45, length),
		CFrame.lookAt(midpoint, midpoint + direction) * CFrame.Angles(slope, 0, 0),
		WOOD,
		COLORS.Wood,
		parent,
		true
	)
end

local function buildTrenchPolyline(points: { Vector3 }, sandbagSide: Vector3, parent: Instance)
	local depth = GameConfig.TrenchDepth
	local width = GameConfig.TrenchWidth
	for index = 1, #points - 1 do
		local a = points[index]
		local b = points[index + 1]
		local delta = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
		local distance = delta.Magnitude
		local midpoint = (a + b) / 2 - Vector3.new(0, depth / 2, 0)
		
		-- Carve terrain for the trench path
		fill(CFrame.lookAt(midpoint, midpoint + delta), Vector3.new(width, depth, distance + width), AIR)
		
		-- Place 3D Trench models along the line instead of procedural sandbags
		local numTrenches = math.floor(distance / 8)
		for i = 0, numTrenches - 1 do
			local offset = i * 8 + 4
			local tCFrame = CFrame.lookAt(a + delta.Unit * offset, b)
			placeModel("Trench", tCFrame, parent)
		end
	end

	local firstDirection = (points[1] - points[2]).Unit
	local lastDirection = (points[#points] - points[#points - 1]).Unit
	buildTrenchRamp(points[1], firstDirection, parent)
	buildTrenchRamp(points[#points], lastDirection, parent)
end

local function buildTrenches(parent: Instance)
	buildTrenchPolyline(WEST_TRENCH, Vector3.new(1, 0, 0), parent)
	buildTrenchPolyline(EAST_TRENCH, Vector3.new(-1, 0, 0), parent)
	for index = 3, #TRENCH_POLYLINES do
		local side = index <= 4 and Vector3.new(0, 0, index == 3 and -1 or 1)
			or Vector3.new(0, 0, index == 5 and -1 or 1)
		buildTrenchPolyline(TRENCH_POLYLINES[index], side, parent)
	end
end

local function buildBridges(parent: Instance)
	for _, x in ipairs({ -FRONT_X, FRONT_X }) do
		for _, z in ipairs({ -160, 160 }) do
			part(
				"TrenchBridge",
				Vector3.new(54, 0.65, 30),
				CFrame.new(x, GROUND_Y - 0.13, z),
				CONCRETE,
				COLORS.DarkConcrete,
				parent,
				true
			)
			for _, side in ipairs({ -1, 1 }) do
				part(
					"BridgeMarker",
					Vector3.new(1, 2.5, 4),
					CFrame.new(x, GROUND_Y + 1.25, z + side * 16),
					METAL,
					COLORS.Rust,
					parent,
					true
				)
			end
		end
	end
end

local function wallPart(name: string, base: CFrame, size: Vector3, offset: CFrame, material: any, color: Color3, parent: Instance)
	return part(name, size, base * offset, material, color, parent, true)
end

local function buildCommandPost(parent: Instance)
	local base = CFrame.new(0, GROUND_Y, 0)
	part("CommandPostFloor", Vector3.new(124, 0.5, 104), base * CFrame.new(0, 0.25, 0), CONCRETE, COLORS.DarkConcrete, parent, true)

	wallPart("BrokenNorthWall", base, Vector3.new(44, 8, 2), CFrame.new(-38, 4, -51) * CFrame.Angles(0, math.rad(-2), 0), BRICK, COLORS.Brick, parent)
	wallPart("BrokenNorthWall", base, Vector3.new(25, 5, 2), CFrame.new(37, 2.5, -51), BRICK, COLORS.Brick, parent)
	wallPart("BrokenSouthWall", base, Vector3.new(32, 6, 2), CFrame.new(-43, 3, 51), BRICK, COLORS.Brick, parent)
	wallPart("BrokenSouthWall", base, Vector3.new(43, 10, 2), CFrame.new(31, 5, 51) * CFrame.Angles(0, math.rad(3), 0), BRICK, COLORS.Brick, parent)
	wallPart("BrokenWestWall", base, Vector3.new(2, 9, 37), CFrame.new(-61, 4.5, -29), CONCRETE, COLORS.Concrete, parent)
	wallPart("BrokenWestWall", base, Vector3.new(2, 5, 24), CFrame.new(-61, 2.5, 37) * CFrame.Angles(0, math.rad(-4), 0), CONCRETE, COLORS.Concrete, parent)
	wallPart("BrokenEastWall", base, Vector3.new(2, 7, 29), CFrame.new(61, 3.5, -35), CONCRETE, COLORS.Concrete, parent)
	wallPart("BrokenEastWall", base, Vector3.new(2, 11, 34), CFrame.new(61, 5.5, 27) * CFrame.Angles(0, math.rad(3), 0), CONCRETE, COLORS.Concrete, parent)

	wallPart("MapRoomWall", base, Vector3.new(40, 7, 2), CFrame.new(-19, 3.5, -12), CONCRETE, COLORS.Concrete, parent)
	wallPart("MapRoomWall", base, Vector3.new(2, 7, 30), CFrame.new(-39, 3.5, 2), CONCRETE, COLORS.Concrete, parent)
	wallPart("MapRoomWall", base, Vector3.new(20, 4, 2), CFrame.new(-29, 2, 17), CONCRETE, COLORS.Concrete, parent)
	wallPart("CollapsedSlab", base, Vector3.new(27, 1.2, 21), CFrame.new(-23, 8.2, 0) * CFrame.Angles(math.rad(8), 0, math.rad(-10)), CONCRETE, COLORS.DarkConcrete, parent)

	for index, offset in ipairs({ Vector3.new(22, 0, 5), Vector3.new(35, 0, 17), Vector3.new(18, 0, 28) }) do
		part(
			"CommandCrate" .. index,
			Vector3.new(5, 4, 5),
			CFrame.new(offset + Vector3.new(0, GROUND_Y + 2, 0)) * CFrame.Angles(0, math.rad(index * 17), 0),
			WOOD,
			COLORS.Wood,
			parent,
			true
		)
	end

	-- Высокий, но лёгкий по числу деталей ориентир в центре карты.
	local towerCenter = Vector3.new(30, GROUND_Y, -24)
	for _, offset in ipairs({ Vector3.new(-3, 0, -3), Vector3.new(3, 0, -3), Vector3.new(-3, 0, 3), Vector3.new(3, 0, 3) }) do
		part("RadioTowerLeg", Vector3.new(0.7, 24, 0.7), CFrame.new(towerCenter + offset + Vector3.new(0, 12, 0)), METAL, COLORS.Metal, parent, true)
	end
	part("RadioPlatform", Vector3.new(9, 0.7, 9), CFrame.new(towerCenter + Vector3.new(0, 22, 0)), METAL, COLORS.Metal, parent, true)
	part("RadioMast", Vector3.new(0.6, 17, 0.6), CFrame.new(towerCenter + Vector3.new(0, 30.5, 0)), METAL, COLORS.Rust, parent, false)
end

local function placeModel(name: string, cframe: CFrame, parent: Instance)
	local model = MapAssets:FindFirstChild(name)
	if model then
		local clone = model:Clone()
		if clone:IsA("Model") then
			clone:PivotTo(cframe)
		elseif clone:IsA("BasePart") then
			clone.CFrame = cframe
		end
		clone.Parent = parent
	end
end

local function buildRuinedBuilding(center: Vector3, yaw: number, parent: Instance)
	placeModel("House", CFrame.new(center) * CFrame.Angles(0, yaw, 0), parent)
end

local function buildBunker(center: Vector3, facing: Vector3, parent: Instance)
	local base = CFrame.lookAt(center, center + facing)
	wallPart("BunkerFloor", base, Vector3.new(26, 0.5, 20), CFrame.new(0, 0.25, 0), CONCRETE, COLORS.DarkConcrete, parent)
	wallPart("BunkerRoof", base, Vector3.new(29, 1.2, 23), CFrame.new(0, 8.1, 0), CONCRETE, COLORS.DarkConcrete, parent)
	wallPart("BunkerSide", base, Vector3.new(2, 7, 20), CFrame.new(-12, 4, 0), CONCRETE, COLORS.Concrete, parent)
	wallPart("BunkerSide", base, Vector3.new(2, 7, 20), CFrame.new(12, 4, 0), CONCRETE, COLORS.Concrete, parent)
	wallPart("BunkerFrontLow", base, Vector3.new(24, 3.6, 2), CFrame.new(0, 1.8, -9), CONCRETE, COLORS.Concrete, parent)
	wallPart("BunkerFrontTop", base, Vector3.new(24, 2.2, 2), CFrame.new(0, 6.9, -9), CONCRETE, COLORS.Concrete, parent)
	wallPart("BunkerRear", base, Vector3.new(8, 7, 2), CFrame.new(-8, 3.5, 9), CONCRETE, COLORS.Concrete, parent)
	wallPart("BunkerRear", base, Vector3.new(8, 7, 2), CFrame.new(8, 3.5, 9), CONCRETE, COLORS.Concrete, parent)
end

local function buildCheckpoint(z: number, parent: Instance)
	local direction = z < 0 and 1 or -1
	local base = CFrame.new(0, GROUND_Y, z) * CFrame.Angles(0, z < 0 and 0 or math.pi, 0)
	for _, side in ipairs({ -1, 1 }) do
		wallPart("CheckpointBarrier", base, Vector3.new(3, 3.2, 25), CFrame.new(side * 21, 1.6, 0), CONCRETE, COLORS.Concrete, parent)
		wallPart("CheckpointPost", base, Vector3.new(2.5, 9, 2.5), CFrame.new(side * 23, 4.5, -13 * direction), CONCRETE, COLORS.DarkConcrete, parent)
	end
	wallPart("GuardBooth", base, Vector3.new(12, 6, 10), CFrame.new(32, 3, 11), METAL, COLORS.Olive, parent)
	wallPart("GuardBoothRoof", base, Vector3.new(14, 0.6, 12), CFrame.new(32, 6.3, 11), METAL, COLORS.Metal, parent)
	wallPart("CheckpointCrate", base, Vector3.new(5, 4, 5), CFrame.new(-31, 2, 12), WOOD, COLORS.Wood, parent)
end

local function buildSandbagNest(center: Vector3, yaw: number, parent: Instance)
	local base = CFrame.new(center) * CFrame.Angles(0, yaw, 0)
	for _, offset in ipairs({ Vector3.new(-8, 0, -5), Vector3.new(0, 0, -7), Vector3.new(8, 0, -5) }) do
		part(
			"SandbagNest",
			Vector3.new(6.5, 1.5, 2.2),
			base * CFrame.new(offset + Vector3.new(0, 0.75, 0)),
			SAND,
			COLORS.Sandbag,
			parent,
			true
		)
	end
end

local function buildGunEmplacement(center: Vector3, facing: Vector3, parent: Instance)
	local base = CFrame.lookAt(center, center + facing)
	wallPart("GunPitFloor", base, Vector3.new(34, 0.4, 29), CFrame.new(0, 0.2, 0), CONCRETE, COLORS.DarkConcrete, parent)
	wallPart("GunPitRear", base, Vector3.new(34, 4.5, 2.5), CFrame.new(0, 2.25, 13), CONCRETE, COLORS.Concrete, parent)
	wallPart("GunPitSide", base, Vector3.new(2.5, 4, 24), CFrame.new(-15.75, 2, 1), CONCRETE, COLORS.Concrete, parent)
	wallPart("GunPitSide", base, Vector3.new(2.5, 4, 24), CFrame.new(15.75, 2, 1), CONCRETE, COLORS.Concrete, parent)
	wallPart("GunShield", base, Vector3.new(12, 4.5, 1), CFrame.new(0, 3, -5), METAL, COLORS.Olive, parent)

	local carriage = part("BrokenGunCarriage", Vector3.new(7, 2.2, 6), base * CFrame.new(0, 1.3, 1), METAL, COLORS.DarkOlive, parent, true)
	carriage.Shape = Enum.PartType.Cylinder
	local barrel = part("BrokenGunBarrel", Vector3.new(14, 1.1, 1.1), base * CFrame.new(0, 4.2, -9) * CFrame.Angles(0, math.rad(90), math.rad(-8)), METAL, COLORS.Charred, parent, true)
	barrel.Shape = Enum.PartType.Cylinder
end

local function buildFortifiedDepot(center: Vector3, yaw: number, parent: Instance)
	local base = CFrame.new(center) * CFrame.Angles(0, yaw, 0)
	wallPart("DepotFloor", base, Vector3.new(78, 0.45, 50), CFrame.new(0, 0.225, 0), CONCRETE, COLORS.DarkConcrete, parent)
	wallPart("DepotRearWall", base, Vector3.new(78, 7, 2), CFrame.new(0, 3.5, 24), BRICK, COLORS.Brick, parent)
	wallPart("DepotSideWall", base, Vector3.new(2, 7, 50), CFrame.new(-38, 3.5, 0), BRICK, COLORS.Brick, parent)
	wallPart("DepotSideWall", base, Vector3.new(2, 5, 31), CFrame.new(38, 2.5, 8), CONCRETE, COLORS.Concrete, parent)
	wallPart("DepotFrontWall", base, Vector3.new(25, 5, 2), CFrame.new(-25.5, 2.5, -24), CONCRETE, COLORS.Concrete, parent)
	wallPart("DepotFrontWall", base, Vector3.new(22, 8, 2), CFrame.new(28, 4, -24), BRICK, COLORS.Brick, parent)
	wallPart("DepotRoofSlab", base, Vector3.new(29, 1, 24), CFrame.new(-21, 8.3, 8) * CFrame.Angles(math.rad(5), 0, math.rad(-7)), CONCRETE, COLORS.DarkConcrete, parent)

	for index, offset in ipairs({
		Vector3.new(-21, 0, -10),
		Vector3.new(-14, 0, -10),
		Vector3.new(14, 0, 8),
		Vector3.new(20, 0, 11),
		Vector3.new(14, 0, 15),
	}) do
		part(
			"DepotCrate" .. index,
			Vector3.new(5.5, 4, 5.5),
			base * CFrame.new(offset + Vector3.new(0, 2, 0)) * CFrame.Angles(0, math.rad(index * 9), 0),
			WOOD,
			COLORS.Wood,
			parent,
			true
		)
	end
end

local function buildObservationTower(center: Vector3, yaw: number, parent: Instance)
	local base = CFrame.new(center) * CFrame.Angles(0, yaw, 0)
	wallPart("TowerFoundation", base, Vector3.new(19, 0.6, 19), CFrame.new(0, 0.3, 0), CONCRETE, COLORS.DarkConcrete, parent)
	for _, offset in ipairs({ Vector3.new(-6, 0, -6), Vector3.new(6, 0, -6), Vector3.new(-6, 0, 6), Vector3.new(6, 0, 6) }) do
		wallPart("TowerLeg", base, Vector3.new(0.9, 8.5, 0.9), CFrame.new(offset + Vector3.new(0, 4.55, 0)), METAL, COLORS.Metal, parent)
	end
	wallPart("TowerPlatform", base, Vector3.new(15, 0.7, 15), CFrame.new(0, 8.8, 0), WOOD, COLORS.Wood, parent)
	wallPart("TowerRoof", base, Vector3.new(17, 0.6, 17), CFrame.new(0, 13, 0), METAL, COLORS.DarkOlive, parent)
	for _, offset in ipairs({ Vector3.new(-6, 0, -6), Vector3.new(6, 0, -6), Vector3.new(-6, 0, 6), Vector3.new(6, 0, 6) }) do
		wallPart("TowerRoofPost", base, Vector3.new(0.45, 4, 0.45), CFrame.new(offset + Vector3.new(0, 10.9, 0)), METAL, COLORS.Metal, parent)
	end
	wallPart("TowerBack", base, Vector3.new(15, 2.8, 0.7), CFrame.new(0, 10.2, 7), WOOD, COLORS.Wood, parent)
	wallPart("TowerSide", base, Vector3.new(0.7, 2.8, 9), CFrame.new(-7, 10.2, 2.5), WOOD, COLORS.Wood, parent)
	wallPart("TowerSide", base, Vector3.new(0.7, 2.8, 9), CFrame.new(7, 10.2, 2.5), WOOD, COLORS.Wood, parent)

	-- Широкая лестница делает ориентир игровой позицией, а не декорацией.
	for stepIndex = 1, 12 do
		wallPart(
			"TowerStep",
			base,
			Vector3.new(6, 0.7, 1.8),
			CFrame.new(0, 0.35 + stepIndex * 0.68, -18 + stepIndex * 1.05),
			WOOD,
			COLORS.Wood,
			parent
		)
	end
end

local function buildStructures(parent: Instance)
	buildCommandPost(parent)
	buildRuinedBuilding(point(-500, 455), math.rad(18), parent)
	buildRuinedBuilding(point(500, -455), math.rad(-162), parent)
	buildBunker(point(-335, 20), Vector3.new(1, 0, 0), parent)
	buildBunker(point(335, -20), Vector3.new(-1, 0, 0), parent)
	buildCheckpoint(-360, parent)
	buildCheckpoint(360, parent)
	buildGunEmplacement(point(-565, -350), Vector3.new(1, 0, 0), parent)
	buildGunEmplacement(point(565, 350), Vector3.new(-1, 0, 0), parent)
	buildFortifiedDepot(point(-620, 90), math.rad(90), parent)
	buildFortifiedDepot(point(620, -90), math.rad(-90), parent)
	buildObservationTower(point(-720, 610), math.rad(35), parent)
	buildObservationTower(point(720, -610), math.rad(-145), parent)
	buildSandbagNest(point(-455, -70), math.rad(90), parent)
	buildSandbagNest(point(455, 70), math.rad(-90), parent)
	buildSandbagNest(point(-95, 430), math.rad(180), parent)
	buildSandbagNest(point(95, -430), 0, parent)
end

local function buildHedgehog(position: Vector3, yaw: number, parent: Instance)
	local center = position + Vector3.new(0, 2.5, 0)
	part("Hedgehog", Vector3.new(7, 0.75, 0.75), CFrame.new(center) * CFrame.Angles(0, yaw, math.rad(45)), METAL, COLORS.Rust, parent, true)
	part("Hedgehog", Vector3.new(7, 0.75, 0.75), CFrame.new(center) * CFrame.Angles(0, yaw + math.pi / 2, math.rad(-45)), METAL, COLORS.Rust, parent, true)
	part("Hedgehog", Vector3.new(6, 0.75, 0.75), CFrame.new(center) * CFrame.Angles(math.rad(35), yaw + math.rad(45), 0), METAL, COLORS.Rust, parent, true)
end

local function buildDeadTree(position: Vector3, yaw: number, parent: Instance)
	placeModel("Tree", CFrame.new(position) * CFrame.Angles(0, yaw, 0), parent)
end

local function buildCrateStack(position: Vector3, yaw: number, parent: Instance)
	local base = CFrame.new(position) * CFrame.Angles(0, yaw, 0)
	part("FieldCrate", Vector3.new(5, 3.5, 5), base * CFrame.new(-2.7, 1.75, 0), WOOD, COLORS.Wood, parent, true)
	part("FieldCrate", Vector3.new(5, 3.5, 5), base * CFrame.new(2.7, 1.75, 0), WOOD, COLORS.Wood, parent, true)
	part("FieldCrate", Vector3.new(4.5, 3.2, 4.5), base * CFrame.new(0, 5.1, 0) * CFrame.Angles(0, math.rad(8), 0), WOOD, COLORS.Wood, parent, true)
end

local function scatterBattlefieldCover(parent: Instance)
	local rng = Random.new(MAP_SEED)
	local placedPositions = {}

	-- Ячейки гарантируют заполнение всех секторов, а seeded jitter убирает вид сетки.
	for x = -790, 790, COVER_CELL_SIZE do
		for z = -790, 790, COVER_CELL_SIZE do
			local position = point(x + rng:NextNumber(-31, 31), z + rng:NextNumber(-31, 31))
			local farEnough = true
			for _, placedPosition in ipairs(placedPositions) do
				if (Vector2.new(position.X, position.Z) - Vector2.new(placedPosition.X, placedPosition.Z)).Magnitude < MIN_COVER_SPACING then
					farEnough = false
					break
				end
			end

			if rng:NextNumber() < 0.72 and farEnough and not isReserved(position, 8) then
				local yaw = rng:NextNumber(0, math.pi * 2)
				local coverType = rng:NextInteger(1, 7)
				if coverType == 1 then
					for _ = 1, rng:NextInteger(2, 3) do
						local size = rng:NextNumber(4, 7.5)
						local offset = Vector3.new(rng:NextNumber(-4, 4), size * 0.38, rng:NextNumber(-4, 4))
						local rock = part(
							"RockCover",
							Vector3.new(size, size * rng:NextNumber(0.65, 0.95), size * rng:NextNumber(0.75, 1.1)),
							CFrame.new(position + offset) * CFrame.Angles(rng:NextNumber(-0.25, 0.25), yaw, rng:NextNumber(-0.2, 0.2)),
							ROCK,
							COLORS.Rock,
							parent,
							true
						)
						rock.Shape = Enum.PartType.Ball
					end
				elseif coverType == 2 then
					part("ConcreteCover", Vector3.new(rng:NextNumber(9, 14), 3.4, 2.4), CFrame.new(position + Vector3.new(0, 1.7, 0)) * CFrame.Angles(0, yaw, 0), CONCRETE, COLORS.Concrete, parent, true)
				elseif coverType == 3 then
					for logIndex = 1, 2 do
						local log = part("LogCover", Vector3.new(10, 2.1, 2.1), CFrame.new(position + Vector3.new(0, 1.05 + (logIndex - 1) * 1.3, 0)) * CFrame.Angles(0, yaw + (logIndex - 1) * 0.08, 0), WOOD, COLORS.Wood, parent, true)
						log.Shape = Enum.PartType.Cylinder
					end
				elseif coverType == 4 then
					buildSandbagNest(position, yaw, parent)
				elseif coverType == 5 then
					buildHedgehog(position, yaw, parent)
				elseif coverType == 6 then
					buildCrateStack(position, yaw, parent)
				else
					local subType = rng:NextInteger(1, 2)
					if subType == 1 then
						buildDeadTree(position, yaw, parent)
					else
						placeModel("Bush", CFrame.new(position) * CFrame.Angles(0, yaw, 0), parent)
					end
				end
				table.insert(placedPositions, position)
			end
		end
	end
end

local function buildDestroyedVehicle(position: Vector3, yaw: number, parent: Instance)
	local base = CFrame.new(position) * CFrame.Angles(0, yaw, 0)
	wallPart("VehicleWreck", base, Vector3.new(11, 2.4, 6), CFrame.new(0, 1.5, 0) * CFrame.Angles(math.rad(5), 0, math.rad(8)), METAL, COLORS.Charred, parent)
	wallPart("VehicleWreckCab", base, Vector3.new(5, 3, 5), CFrame.new(-2, 3.2, 0) * CFrame.Angles(0, math.rad(-5), 0), METAL, COLORS.Rust, parent)
	for _, offset in ipairs({ Vector3.new(-4, 1.3, -3.2), Vector3.new(4, 1.3, -3.2), Vector3.new(-4, 1.3, 3.2), Vector3.new(4, 1.3, 3.2) }) do
		local wheel = wallPart("WreckWheel", base, Vector3.new(1.2, 3.2, 3.2), CFrame.new(offset), METAL, COLORS.Charred, parent)
		wheel.Shape = Enum.PartType.Cylinder
	end
end

local function buildWireObstacle(a: Vector3, b: Vector3, parent: Instance)
	for _, position in ipairs({ a, (a + b) / 2, b }) do
		part("WirePost", Vector3.new(0.35, 3.5, 0.35), CFrame.new(position + Vector3.new(0, 1.75, 0)), METAL, COLORS.Rust, parent, false)
	end
	for _, height in ipairs({ 0.8, 1.65, 2.5 }) do
		segmentPart("BarbedWire", a, b, 0.12, 0.12, GROUND_Y + height, METAL, COLORS.Metal, parent, false)
	end
end

local function buildBattlefieldDetails(parent: Instance)
	buildDestroyedVehicle(point(-390, 665), math.rad(28), parent)
	buildDestroyedVehicle(point(390, -665), math.rad(-152), parent)

	for _, line in ipairs({
		{ point(-520, -105), point(-425, -105) },
		{ point(520, 105), point(425, 105) },
		{ point(-205, 610), point(-125, 635) },
		{ point(205, -610), point(125, -635) },
		{ point(-690, -250), point(-620, -215) },
		{ point(690, 250), point(620, 215) },
	}) do
		buildWireObstacle(line[1], line[2], parent)
	end

	local poleLines = {
		{ point(-115, -720), point(-115, -600), point(-115, -480) },
		{ point(115, 720), point(115, 600), point(115, 480) },
	}
	for _, poleLine in ipairs(poleLines) do
		for _, polePosition in ipairs(poleLine) do
			part("UtilityPole", Vector3.new(0.9, 13, 0.9), CFrame.new(polePosition + Vector3.new(0, 6.5, 0)), WOOD, COLORS.Charred, parent, false)
			part("UtilityCrossarm", Vector3.new(7, 0.55, 0.55), CFrame.new(polePosition + Vector3.new(0, 11.5, 0)), WOOD, COLORS.Charred, parent, false)
		end
		for index = 1, #poleLine - 1 do
			segmentPart("UtilityWire", poleLine[index], poleLine[index + 1], 0.12, 0.12, GROUND_Y + 11.5, METAL, COLORS.Metal, parent, false)
		end
	end
end

local function buildVehiclePads(parent: Instance)
	for index, cframe in ipairs(TANK_PADS) do
		local orientation = cframe - cframe.Position
		part("TankPad" .. index, Vector3.new(30, 0.18, 38), CFrame.new(cframe.Position.X, GROUND_Y + 0.09, cframe.Position.Z) * orientation, CONCRETE, COLORS.DarkConcrete, parent, true)
		part("TankPadStripe" .. index, Vector3.new(1.2, 0.05, 32), CFrame.new(cframe.Position.X, GROUND_Y + 0.205, cframe.Position.Z) * orientation, METAL, COLORS.Sandbag, parent, false)
	end
	for index, cframe in ipairs(BIKE_PADS) do
		local orientation = cframe - cframe.Position
		part("BikePad" .. index, Vector3.new(12, 0.18, 16), CFrame.new(cframe.Position.X, GROUND_Y + 0.09, cframe.Position.Z) * orientation, CONCRETE, COLORS.DarkConcrete, parent, true)
	end
end

local function buildSupplyPads(parent: Instance)
	for index, cframe in ipairs(CONTAINER_SPAWNS) do
		part("SupplyPad" .. index, Vector3.new(7, 0.18, 7), CFrame.new(cframe.Position.X, GROUND_Y + 0.09, cframe.Position.Z), CONCRETE, COLORS.DarkConcrete, parent, true)
	end
end

local function buildSpawnShelter(position: Vector3, parent: Instance)
	local inward = Vector3.new(-position.X, 0, -position.Z).Unit
	local right = Vector3.new(-inward.Z, 0, inward.X)
	local rearCenter = position - inward * 17
	local rearA = rearCenter - right * 16
	local rearB = rearCenter + right * 16
	segmentPart("SpawnBlastWall", rearA, rearB, 2.5, 5, GROUND_Y + 2.5, CONCRETE, COLORS.Concrete, parent, true)

	for _, side in ipairs({ -1, 1 }) do
		local sideCenter = position - inward * 5 + right * side * 15
		segmentPart("SpawnBlastWall", sideCenter - inward * 12, sideCenter + inward * 12, 2.5, 4, GROUND_Y + 2, CONCRETE, COLORS.Concrete, parent, true)
	end
end

local function buildSpawnLocations(parent: Instance)
	for index, position in ipairs(SPAWN_POINTS) do
		buildSpawnShelter(position, parent)
		local spawn = Instance.new("SpawnLocation")
		spawn.Name = "Spawn" .. index
		spawn.Size = Vector3.new(7, 1, 7)
		spawn.CFrame = CFrame.new(position + Vector3.new(0, 0.5, 0))
		spawn.Anchored = true
		spawn.Neutral = true
		spawn.Duration = 0
		spawn.Material = SLATE
		spawn.Color = Color3.fromRGB(70, 84, 66)
		spawn.TopSurface = Enum.SurfaceType.Smooth
		spawn.BottomSurface = Enum.SurfaceType.Smooth
		spawn.Parent = parent
	end
end

function MapBuilder.Build()
	local previousMap = Workspace:FindFirstChild("ArenaMap")
	if previousMap then
		previousMap:Destroy()
	end

	local mapFolder = makeFolder("ArenaMap", Workspace)
	mapFolder:SetAttribute("GeneratorSeed", MAP_SEED)
	mapFolder:SetAttribute("GeneratorVersion", 2)
	local roadsFolder = makeFolder("Roads", mapFolder)
	local trenchesFolder = makeFolder("Trenches", mapFolder)
	local structuresFolder = makeFolder("Structures", mapFolder)
	local coverFolder = makeFolder("BattlefieldCover", mapFolder)
	local detailsFolder = makeFolder("BattlefieldDetails", mapFolder)
	local gameplayFolder = makeFolder("Gameplay", mapFolder)

	buildBaseTerrain()
	buildTerrainVariation(coverFolder)
	buildEarthBerms()
	buildShellCraters()
	buildTrenches(trenchesFolder)
	buildRoadNetwork(roadsFolder)
	buildBridges(roadsFolder)
	buildStructures(structuresFolder)
	buildBattlefieldDetails(detailsFolder)
	scatterBattlefieldCover(coverFolder)
	buildVehiclePads(gameplayFolder)
	buildSupplyPads(gameplayFolder)
	buildSpawnLocations(gameplayFolder)

	return {
		ContainerSpawns = CONTAINER_SPAWNS,
		TankPads = TANK_PADS,
		BikePads = BIKE_PADS,
	}
end

return MapBuilder
