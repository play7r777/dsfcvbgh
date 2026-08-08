--!nonstrict
-- ============================================================================
-- MeshLibrary — поиск и окраска импортированных OBJ-мешей.
--
-- Когда Roblox Studio импортирует OBJ-файл с несколькими материалами,
-- каждый подмеш становится отдельным MeshPart с именем = имя материала из MTL.
-- Но цвет/текстуру из .mtl Studio НЕ читает (Kd игнорируется).
-- Поэтому ApplyFallbackColors вручную красит парты по имени материала.
--
-- Поиск идёт в трёх местах (по приоритету):
--   1) ReplicatedStorage/<folderName>
--   2) ReplicatedStorage/Assets
--   3) прямо в ReplicatedStorage
-- ============================================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MeshLibrary = {}

-- ---------------------------------------------------------------------------
-- Палитра: ключ — подстрока имени материала (lowercase), значение — Color3.
-- Имена берутся из Blender-материалов в generate_map_assets.py и build_assets.py.
-- ---------------------------------------------------------------------------
local FALLBACK_COLORS = {
	-- Карта (generate_map_assets.py)
	{ "map_wood",      Color3.fromRGB(89,  64,  38)  },
	{ "map_leaves",    Color3.fromRGB(38,  102, 38)  },
	{ "map_dirt",      Color3.fromRGB(102, 77,  51)  },
	{ "map_stone",     Color3.fromRGB(128, 128, 128) },
	{ "map_sandbag",   Color3.fromRGB(153, 140, 115) },
	{ "map_concrete",  Color3.fromRGB(179, 179, 179) },
	{ "map_roof",      Color3.fromRGB(153, 51,  51)  },
	{ "map_window",    Color3.fromRGB(128, 204, 230) },
	{ "map_ground",    Color3.fromRGB(51,  77,  38)  },

	-- Оружие (build_assets.py)
	{ "gunmetal",      Color3.fromRGB(41,  44,  48)  },
	{ "dark",          Color3.fromRGB(23,  26,  26)  },
	{ "olive",         Color3.fromRGB(74,  82,  56)  },
	{ "wood",          Color3.fromRGB(97,  69,  41)  },
	{ "tan",           Color3.fromRGB(140, 125, 89)  },
	{ "brass",         Color3.fromRGB(184, 140, 64)  },
	{ "steeltip",      Color3.fromRGB(115, 120, 128) },
	{ "screen",        Color3.fromRGB(64,  158, 199) },
	{ "signalred",     Color3.fromRGB(191, 51,  36)  },

	-- Общие запасные
	{ "metal",         Color3.fromRGB(69,  72,  70)  },
	{ "rubber",        Color3.fromRGB(30,  30,  30)  },
	{ "glass",         Color3.fromRGB(173, 216, 230) },
}

local function paletteColor(name: string): Color3?
	name = string.lower(name)
	for _, entry in ipairs(FALLBACK_COLORS) do
		if string.find(name, entry[1], 1, true) then
			return entry[2]
		end
	end
	return nil
end

-- ---------------------------------------------------------------------------
-- Поиск инстанса по имени (без учёта регистра) в контейнере.
-- ---------------------------------------------------------------------------
local function findIn(container: Instance?, name: string): Instance?
	if not container then return nil end
	local direct = container:FindFirstChild(name)
	if direct then return direct end
	-- нечувствительный к регистру
	local nameLow = string.lower(name)
	for _, child in ipairs(container:GetChildren()) do
		if string.lower(child.Name) == nameLow then
			return child
		end
	end
	return nil
end

-- ---------------------------------------------------------------------------
-- Найти модель/меш в ReplicatedStorage.
-- folderName — опциональная папка (например "Assets")
-- ---------------------------------------------------------------------------
function MeshLibrary.Find(folderName: string?, name: string): Instance?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local inst = findIn(assets and assets:FindFirstChild(folderName or "") or nil, name)
	if inst then return inst end
	inst = findIn(assets, name)
	if inst then return inst end
	return findIn(ReplicatedStorage, name)
end

-- ---------------------------------------------------------------------------
-- Применить запасные цвета к клонированному OBJ-мешу.
-- Вызывается после клонирования, до родительства.
-- ---------------------------------------------------------------------------
function MeshLibrary.ApplyFallbackColors(root: Instance)
	local function paint(part: Instance)
		if not part:IsA("BasePart") then return end
		-- если уже есть текстурная карта — не трогаем
		if part:IsA("MeshPart") and part.TextureID ~= "" then return end
		local sa = part:FindFirstChildOfClass("SurfaceAppearance")
		if sa and (sa.ColorMap ~= "" or sa.NormalMap ~= "") then return end

		local color = paletteColor(part.Name)
		if color then
			part.Color = color
			part.Material = Enum.Material.SmoothPlastic
			-- убираем лишние SurfaceAppearance без текстур
			if sa then sa:Destroy() end
		end
	end

	if root:IsA("BasePart") then
		paint(root)
	else
		for _, desc in ipairs(root:GetDescendants()) do
			paint(desc)
		end
	end
end

return MeshLibrary
