--!nonstrict
-- ============================================================================
-- GameConfig — общие настройки арены Frontline (PvP, FFA)
-- Все игровые константы собраны здесь, чтобы баланс правился в одном месте.
-- ============================================================================

local GameConfig = {
	-- Размеры арены (карта генерируется процедурно на старте сервера)
	ArenaSize = Vector3.new(460, 0, 460), -- игровое поле по X/Z
	GroundTopY = 0, -- верх плиты земли
	GroundThickness = 10,
	PerimeterHeight = 24, -- скалы по периметру

	-- Окопы
	TrenchDepth = 5,
	TrenchWidth = 6,

	-- Игроки
	RespawnTime = 4,
	SpawnProtection = 3, -- секунды неуязвимости после спавна
	WalkSpeed = 16,

	-- Стартовый набор пехоты (выдаётся при каждом спавне)
	-- Пистолет, автомат, C4 + детонатор и мины — всегда с собой.
	-- ПКМ и СВД лежат в контейнерах на карте.
	Loadout = { "AssaultRifle", "Pistol", "C4Charge", "Detonator", "Landmine", "DroneTablet" },
	C4ChargesPerLife = 2,
	MineChargesPerLife = 2,
	MaxActiveC4 = 4, -- сколько зарядов одновременно может держать один игрок

	-- Контейнеры снабжения (бесконечный респавн лута)
	PickupRespawnMin = 45, -- сек
	PickupRespawnMax = 90,

	-- Техника (бесконечный респавн после уничтожения)
	TankRespawn = 150,
	BikeRespawn = 60,

	-- FPV дрон-камикадзе
	Drone = {
		BatterySeconds = 60, -- заряд батареи
		MaxRange = 340, -- радиус уверенного видеоканала (дальше — потеря связи)
		MaxSpeed = 58, -- studs/s
		Acceleration = 9, -- плавность разгона (damp-фактор)
		ExplodeSpeed = 24, -- скорость столкновения для подрыва боевой части
		RespawnCooldown = 25, -- кулдаун планшета после потери дрона
	},
}

return GameConfig
