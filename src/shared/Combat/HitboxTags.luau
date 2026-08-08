--!nonstrict
-- ============================================================================
-- HitboxTags — разметка зон брони через CollectionService (раздел 3.3 ТЗ).
-- Теги вешаются на BasePart'ы техники в VehicleFactory.
-- ============================================================================

local CollectionService = game:GetService("CollectionService")

local HitboxTags = {
	-- Зоны брони танка
	ArmorFront = "Armor_Front", -- 0.5x
	ArmorSide = "Armor_Side", -- 1.0x
	ArmorRear = "Armor_Rear", -- 1.5x
	ArmorTurret = "Armor_Turret", -- 1.0x (погон/башня)
	Engine = "Hitbox_Engine", -- 2.0x + шанс поджога
	TrackL = "Hitbox_Track_L", -- срыв гусеницы
	TrackR = "Hitbox_Track_R",
	AmmoRack = "Hitbox_AmmoRack", -- 2.5x + шанс детонации БК

	-- Прочие теги мира
	Landmine = "Landmine",
	SupplyContainer = "SupplyContainer",
}

-- Порядок важен: сначала критические узлы, потом общая броня.
local ZONE_PRIORITY = {
	HitboxTags.Engine,
	HitboxTags.AmmoRack,
	HitboxTags.TrackL,
	HitboxTags.TrackR,
	HitboxTags.ArmorFront,
	HitboxTags.ArmorSide,
	HitboxTags.ArmorRear,
	HitboxTags.ArmorTurret,
}

-- Тег зоны -> модуль танка (ключ VehicleConfig.Tank.Modules)
local ZONE_TO_MODULE = {
	[HitboxTags.Engine] = "Engine",
	[HitboxTags.AmmoRack] = "AmmoRack",
	[HitboxTags.TrackL] = "TrackL",
	[HitboxTags.TrackR] = "TrackR",
	[HitboxTags.ArmorTurret] = "Turret",
}

function HitboxTags.GetZone(part: BasePart): string?
	for _, tag in ipairs(ZONE_PRIORITY) do
		if CollectionService:HasTag(part, tag) then
			return tag
		end
	end
	return nil
end

function HitboxTags.ZoneToModule(zone: string?): string?
	if not zone then
		return nil
	end
	return ZONE_TO_MODULE[zone]
end

return HitboxTags
