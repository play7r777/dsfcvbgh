--!nonstrict
-- ============================================================================
-- VehicleConfig — баланс бронетехники и зон уязвимости (раздел 3 ТЗ).
-- Классы: "Tank" (тяжёлая броня) и "Light" (лёгкая техника/мотоцикл).
-- ============================================================================

local DamageTypes = require(script.Parent.Parent.Combat.DamageTypes)

local VehicleConfig = {
	Tank = {
		Class = "Tank",
		DisplayName = "ОБТ «Кабан»",

		-- Пул здоровья и узлы (3.1)
		HullHP = 2000,
		Modules = {
			TrackL = 350, -- гусеница левая
			TrackR = 350, -- гусеница правая
			Engine = 450, -- двигатель (кормовая решётка)
			Turret = 600, -- погон башни
			AmmoRack = 300, -- боеукладка
		},

		CookoffChance = 0.35, -- шанс детонации БК при попадании HEAT/AP
		CookoffChanceDead = 0.6, -- шанс, если БК уже разрушена
		EngineFireDPS = 25, -- пожар: урон корпусу в секунду
		TurretDegradedAt = 0.5, -- ниже 50% HP погона...
		TurretDegradedFactor = 0.4, -- ...скорость поворота падает на 60% (остаётся 40%)
		TurretTraverseDegPerSec = 32,

		-- Множители урона по зонам хитбоксов (3.3)
		ZoneMultipliers = {
			Armor_Front = 0.5,
			Armor_Side = 1.0,
			Armor_Rear = 1.5,
			Armor_Turret = 1.0,
			Hitbox_Engine = 2.0,
			Hitbox_AmmoRack = 2.5,
			Hitbox_Track_L = 1.0,
			Hitbox_Track_R = 1.0,
		},

		-- Кинетика: геометрия попадания
		RicochetCos = 0.25, -- cos угла падения ниже — рикошет (без урона)
		MinPenetrationCos = 0.3, -- минимальный фактор пробития

		-- Фугас бонусно срывает гусеницы
		HETrackBonus = 1.5,

		-- Динамика (аркадный привод через LinearVelocity; карта x4 -> быстрее)
		MoveSpeed = 26, -- studs/s вперёд
		ReverseSpeed = 10,
		TurnDegPerSec = 45,

		-- Главная пушка (APFSDS, кинетика) + лёгкий фугасный круг
		Cannon = {
			Damage = 520,
			DamageType = DamageTypes.Kinetic,
			ProjectileSpeed = 1000,
			GravityFactor = 0.15,
			ReloadTime = 4.0,
			MaxRange = 1800,
			Splash = { Radius = 10, Damage = 130, Type = DamageTypes.HE },
		},
	},

	Bike = {
		Class = "Light",
		DisplayName = "Мотоцикл разведки",
		HullHP = 150, -- нулевая броня: мина/ПКМ/автомат быстро решают
		Modules = {},
		ZoneMultipliers = {},
		MoveSpeed = 64,
		ReverseSpeed = 16,
		TurnDegPerSec = 95,
	},
}

return VehicleConfig
