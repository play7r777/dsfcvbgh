--!nonstrict
-- ============================================================================
-- MapBuilder — процедурная генерация PvP-арены на старте сервера.
-- Никаких бинарных ассетов: земля и скалы — Terrain, окопы выкапываются
-- Air-заливкой, укрытия/руины/площадки — обычные Part'ы.
--
-- Схема карты (вид сверху, 460x460):
--   - две линии окопов-«зигзага» на x=-70 и x=+70 (запад/восток)
--   - три соединительных траншеи между ними (z=-75, 0, +75)
--   - руины в центре (хардпоинт), мешки с песком вдоль окопов
--   - площадки техники по углам/краям, 8 точек спавна игроков
-- ============================================================================

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared").Config.GameConfig)

local MapBuilder = {}

local GRASS = Enum.Material.Grass
local ROCK = Enum.Material.Rock
local SAND = Enum.Material.Sand
local CONCRETE = Enum.Material.Concrete
local WOOD = Enum.Material.Wood
local AIR = Enum.Material.Air

local function fill(cframe: CFrame, size: Vector3, material: any)
	Workspace.Terrain:FillBlock(cframe, size, material)
end

local function part(name: string, size: Vector3, cframe: CFrame, material: any, color: Color3, parent: Instance?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Material = material
	p.Color = color
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent or Workspace
	return p
end

-- Вырыть прямоугольный сегмент траншеи (ось X или Z)
local function dig(center: Vector3, size: Vector3, depth: number)
	fill(CFrame.new(center - Vector3.new(0, depth / 2, 0)), Vector3.new(size.X, depth, size.Z), AIR)
end

-- Зигзагообразная линия окопов вдоль Z с шагом по X
local function buildZigzag(xBase: number, zStart: number, zEnd: number, segLen: number, amp: number, depth: number, width: number, parent: Folder)
	local points = {}
	local i = 0
	for z = zStart, zEnd, segLen do
		local x = xBase + (i % 2 == 0 and -amp or amp)
		table.insert(points, Vector2.new(x, z))
		i += 1
	end
	-- ломаная с прямыми углами: сначала по X, потом по Z
	for idx = 1, #points - 1 do
		local a = points[idx]
		local b = points[idx + 1]
		-- горизонтальный «зуб»
		if math.abs(a.X - b.X) > 0.1 then
			local midX = (a.X + b.X) / 2
			dig(Vector3.new(midX, 0, a.Y), Vector3.new(math.abs(a.X - b.X) + width, 0, width), depth)
		end
		-- вертикальный прогон
		local midZ = (a.Y + b.Y) / 2
		dig(Vector3.new(b.X, 0, midZ), Vector3.new(width, 0, math.abs(a.Y - b.Y) + width), depth)

		-- мешки с песком на бруствере вертикального прогона
		local z = math.min(a.Y, b.Y) + 5
		while z < math.max(a.Y, b.Y) - 3 do
			local side = (math.floor(z / 10) % 2 == 0) and 1 or -1
			part("Sandbags", Vector3.new(1.4, 1.5, 4.5), CFrame.new(b.X + side * (width / 2 + 1.2), 0.75, z), SAND, Color3.fromRGB(151, 133, 96), parent)
			z += 10
		end
	end
end

local function buildTrenchLines(parent: Folder)
	local depth = GameConfig.TrenchDepth
	local width = GameConfig.TrenchWidth

	-- две противоположные линии фронта
	buildZigzag(-70, -150, 150, 25, 10, depth, width, parent)
	buildZigzag(70, -150, 150, 25, 10, depth, width, parent)

	-- соединительные траншеи (сообщения между линиями)
	for _, z in ipairs({ -75, 0, 75 }) do
		dig(Vector3.new(0, 0, z), Vector3.new(140 + width, 0, width), depth)
	end
end

local function buildRuins(center: Vector3, parent: Folder)
	local walls = {
		-- size, offset (x, y, z), поворот по Y
		{ Vector3.new(30, 12, 2), Vector3.new(0, 6, -20), 0 },
		{ Vector3.new(18, 9, 2), Vector3.new(-21, 4.5, -18), math.rad(28) },
		{ Vector3.new(2, 11, 24), Vector3.new(-15, 5.5, 2), 0 },
		{ Vector3.new(2, 7, 18), Vector3.new(16, 3.5, -4), 0 },
		{ Vector3.new(22, 13, 2), Vector3.new(6, 6.5, 16), math.rad(-12) },
		{ Vector3.new(10, 6, 2), Vector3.new(-18, 3, 14), math.rad(45) },
		{ Vector3.new(2, 5, 12), Vector3.new(24, 2.5, 10), math.rad(15) },
	}
	for i, w in ipairs(walls) do
		part("RuinWall" .. i, w[1], CFrame.new(center + w[2]) * CFrame.Angles(0, w[3], 0), CONCRETE, Color3.fromRGB(120, 116, 108), parent)
	end
	-- пара ящиков внутри
	part("RuinCrate1", Vector3.new(4, 4, 4), CFrame.new(center + Vector3.new(-6, 2, -6)), WOOD, Color3.fromRGB(117, 86, 54), parent)
	part("RuinCrate2", Vector3.new(3, 3, 3), CFrame.new(center + Vector3.new(5, 1.5, 6)), WOOD, Color3.fromRGB(117, 86, 54), parent)
end

local function scatterCover(parent: Folder)
	local rng = Random.new(1337)
	for i = 1, 22 do
		local x = rng:NextNumber(-200, 200)
		local z = rng:NextNumber(-200, 200)
		-- не ставим укрытия на линии окопов и в центре
		local nearTrenchX = (math.abs(x - 70) < 12 or math.abs(x + 70) < 12) and math.abs(z) < 160
		local nearTrenchZ = (math.abs(z) < 8 or math.abs(z - 75) < 8 or math.abs(z + 75) < 8) and math.abs(x) < 80
		if not nearTrenchX and not nearTrenchZ and Vector3.new(x, 0, z).Magnitude > 45 then
			local s = rng:NextNumber(3, 6.5)
			part("Cover" .. i, Vector3.new(s, s * 0.8, s), CFrame.new(x, s * 0.4, z) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0), ROCK, Color3.fromRGB(99, 95, 88), parent)
		end
	end
end

local function buildSpawnLocations(parent: Folder)
	local spots = {
		Vector3.new(-200, 0, -200), Vector3.new(200, 0, 200),
		Vector3.new(-200, 0, 200), Vector3.new(200, 0, -200),
		Vector3.new(-200, 0, 0), Vector3.new(200, 0, 0),
		Vector3.new(0, 0, -200), Vector3.new(0, 0, 200),
	}
	for i, pos in ipairs(spots) do
		local sp = Instance.new("SpawnLocation")
		sp.Name = "Spawn" .. i
		sp.Size = Vector3.new(6, 1, 6)
		sp.CFrame = CFrame.new(pos + Vector3.new(0, 0.5, 0))
		sp.Anchored = true
		sp.Neutral = true
		sp.Duration = 0 -- своя спавн-протекция в DamageService
		sp.Material = Enum.Material.Slate
		sp.Color = Color3.fromRGB(70, 84, 66)
		sp.TopSurface = Enum.SurfaceType.Smooth
		sp.Parent = parent
	end
end

local function buildPad(name: string, cframe: CFrame, size: Vector3, parent: Folder)
	part(name, size, cframe + Vector3.new(0, 0.25, 0), CONCRETE, Color3.fromRGB(88, 90, 92), parent)
end

function MapBuilder.Build()
	local folderMap = Instance.new("Folder")
	folderMap.Name = "ArenaMap"
	folderMap.Parent = Workspace

	-- Земля и периметр
	local size = GameConfig.ArenaSize
	local thick = GameConfig.GroundThickness
	fill(CFrame.new(0, -thick / 2, 0), Vector3.new(size.X, thick, size.Z), GRASS)

	local h = GameConfig.PerimeterHeight
	local half = size.X / 2
	fill(CFrame.new(0, h / 2 - 4, -half - 5), Vector3.new(size.X + 30, h, 16), ROCK)
	fill(CFrame.new(0, h / 2 - 4, half + 5), Vector3.new(size.X + 30, h, 16), ROCK)
	fill(CFrame.new(-half - 5, h / 2 - 4, 0), Vector3.new(16, h, size.Z + 30), ROCK)
	fill(CFrame.new(half + 5, h / 2 - 4, 0), Vector3.new(16, h, size.Z + 30), ROCK)

	-- Окопы, руины, укрытия
	buildTrenchLines(folderMap)
	buildRuins(Vector3.new(0, 0, 0), folderMap)
	scatterCover(folderMap)
	buildSpawnLocations(folderMap)

	-- Площадки техники
	local tankPads = {
		CFrame.new(-160, 0, -160) * CFrame.Angles(0, math.rad(45), 0),
		CFrame.new(160, 0, 160) * CFrame.Angles(0, math.rad(-135), 0),
	}
	local bikePads = {
		CFrame.new(0, 0, -190),
		CFrame.new(0, 0, 190) * CFrame.Angles(0, math.rad(180), 0),
		CFrame.new(-190, 0, 30) * CFrame.Angles(0, math.rad(90), 0),
	}
	for i, cf in ipairs(tankPads) do
		buildPad("TankPad" .. i, cf, Vector3.new(16, 0.5, 22), folderMap)
	end
	for i, cf in ipairs(bikePads) do
		buildPad("BikePad" .. i, cf, Vector3.new(6, 0.5, 8), folderMap)
	end

	-- Точки контейнеров снабжения (ПКМ/СВД/мины/C4/боеприпасы)
	local containerSpawns = {
		CFrame.new(4, 0, -12), -- центр, руины
		CFrame.new(-10, 0, 8), -- центр, руины
		CFrame.new(-70, 0, -80), -- западные окопы, север
		CFrame.new(-70, 0, 90), -- западные окопы, юг
		CFrame.new(70, 0, 80), -- восточные окопы, север
		CFrame.new(70, 0, -90), -- восточные окопы, юг
		CFrame.new(0, 0, -75), -- траншея сообщения
		CFrame.new(0, 0, 75), -- траншея сообщения
		CFrame.new(-140, 0, 0), -- середина, запад
		CFrame.new(140, 0, 0), -- середина, восток
	}

	return {
		ContainerSpawns = containerSpawns,
		TankPads = tankPads,
		BikePads = bikePads,
	}
end

return MapBuilder
