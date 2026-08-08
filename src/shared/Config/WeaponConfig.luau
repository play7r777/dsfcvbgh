--!nonstrict
-- ============================================================================
-- WeaponConfig — характеристики стрелкового оружия и боеприпасов.
-- Клиент использует для визуала/предикции, сервер — как авторитетный источник.
--
-- GravityFactor — множитель гравитации workspace для траектории снаряда
-- (падение пули). 1 = полная гравитация, 0 = прямой выстрел.
-- VehicleDamage — множитель урона по классам техники { Light, Tank }.
-- Bloom — детерминированный ADS/hipfire-разброс с ростом очереди.
-- Recoil — клиентский профиль управляемой отдачи камеры (в градусах).
-- ============================================================================

local DamageTypes = require(script.Parent.Parent.Combat.DamageTypes)

local Weapons = {
	-- 1. ШТУРМОВАЯ ВИНТОВКА ---------------------------------------------------
	AssaultRifle = {
		Id = "AssaultRifle",
		DisplayName = "АК-12",
		FireMode = "Auto",
		RPM = 650,
		Damage = 32, -- средний урон 30-35
		HeadshotMultiplier = 1.4,
		DamageType = DamageTypes.Kinetic,
		ProjectileSpeed = 760,
		GravityFactor = 1.0, -- заметное падение пули на дальности
		MaxRange = 900,
		MagSize = 30,
		ReserveAmmo = 210,
		ReloadTime = 2.3,
		Bloom = {
			Base = 0.12,
			PerShot = 0.075,
			Max = 0.72,
			HipBase = 1.35,
			HipPerShot = 0.22,
			HipMax = 4.2,
			Movement = 0.85,
			ADSMovement = 0.28,
			Airborne = 1.8,
			RecoveryDelay = 0.12,
			RecoveryPerSecond = 8.5,
			ResetTime = 0.38,
		}, -- градусы
		Recoil = {
			VerticalMin = 0.58,
			VerticalMax = 0.82,
			Horizontal = 0.28,
			GrowthPerShot = 0.055,
			MaxGrowth = 1.75,
			Pattern = { -0.45, -0.15, 0.3, 0.65, 0.2, -0.55, -0.8, -0.25, 0.5, 0.85, 0.35, -0.4 },
			HorizontalJitter = 0.32,
			PatternChangeChance = 0.18,
			ADSMultiplier = 0.74,
			HipMultiplier = 1.08,
			MovementMultiplier = 1.12,
			AirborneMultiplier = 1.22,
			MaxVertical = 13.5,
			MaxHorizontal = 4.25,
			RecoveryDelay = 0.14,
			RecoverySpeed = 7.5,
			SpringFrequency = 18,
			SpringDamping = 0.92,
			CameraKick = 0.24,
		},
		VehicleDamage = { Light = 1.0, Tank = 0.0 }, -- танк пулям не по зубам
		SoundId = 151997375, -- доступный в исходниках винтовочный выстрел
		Sound = { Volume = 0.82, VolumeVariation = 0.045, PlaybackSpeedMin = 0.97, PlaybackSpeedMax = 1.04, RollOffMinDistance = 18, RollOffMaxDistance = 720, Lifetime = 6 },
	},

	-- 2. ПИСТОЛЕТ --------------------------------------------------------------
	Pistol = {
		Id = "Pistol",
		DisplayName = "МП-443",
		FireMode = "Semi",
		RPM = 480, -- высокий темп по кликам (кап)
		Damage = 23, -- малый урон 20-25
		HeadshotMultiplier = 1.5,
		DamageType = DamageTypes.Kinetic,
		ProjectileSpeed = 620,
		GravityFactor = 1.0,
		MaxRange = 500,
		MagSize = 12,
		ReserveAmmo = 96,
		ReloadTime = 1.7,
		Bloom = {
			Base = 0.16,
			PerShot = 0.11,
			Max = 0.75,
			HipBase = 1.05,
			HipPerShot = 0.18,
			HipMax = 2.7,
			Movement = 0.7,
			ADSMovement = 0.25,
			Airborne = 1.4,
			RecoveryDelay = 0.1,
			RecoveryPerSecond = 11,
			ResetTime = 0.32,
		},
		Recoil = {
			VerticalMin = 0.9,
			VerticalMax = 1.2,
			Horizontal = 0.34,
			GrowthPerShot = 0.04,
			MaxGrowth = 1.35,
			Pattern = { -0.35, 0.55, -0.2, 0.7, -0.6, 0.25 },
			HorizontalJitter = 0.42,
			PatternChangeChance = 0.3,
			ADSMultiplier = 0.78,
			HipMultiplier = 1.08,
			MovementMultiplier = 1.08,
			AirborneMultiplier = 1.18,
			MaxVertical = 7.5,
			MaxHorizontal = 2.8,
			RecoveryDelay = 0.12,
			RecoverySpeed = 9,
			SpringFrequency = 21,
			SpringDamping = 0.9,
			CameraKick = 0.32,
		},
		VehicleDamage = { Light = 0.5, Tank = 0.0 },
		SoundId = 800000246, -- доступный в исходниках пистолетный выстрел
		Sound = { Volume = 0.78, VolumeVariation = 0.05, PlaybackSpeedMin = 0.98, PlaybackSpeedMax = 1.045, RollOffMinDistance = 12, RollOffMaxDistance = 480, Lifetime = 5 },
	},

	-- 3. СНАЙПЕРСКАЯ ВИНТОВКА (контейнерный лут) ------------------------------
	SniperRifle = {
		Id = "SniperRifle",
		DisplayName = "СВ-98",
		FireMode = "Semi",
		RPM = 42,
		Damage = 96, -- 90-100 в туловище
		HeadshotMultiplier = 1.6, -- 96*1.6 = 153.6 => 150+ в голову
		DamageType = DamageTypes.Kinetic,
		ProjectileSpeed = 980, -- снаряд летит заметное время — задержка выстрела
		GravityFactor = 0.45, -- баллистическая траектория
		MaxRange = 1600,
		MagSize = 5,
		ReserveAmmo = 35,
		ReloadTime = 3.4,
		Bloom = {
			Base = 0.035,
			PerShot = 0,
			Max = 0.035,
			HipBase = 4.8,
			HipPerShot = 0,
			HipMax = 4.8,
			Movement = 2.2,
			ADSMovement = 0.95,
			Airborne = 3.0,
			RecoveryDelay = 0.18,
			RecoveryPerSecond = 12,
			ResetTime = 0.5,
		}, -- в оптике точная только из устойчивого положения
		HipBloom = 4.8, -- fallback для старых вызовов ComputeBloom
		ScopeFOV = 12, -- оптический прицел
		Recoil = {
			VerticalMin = 4.4,
			VerticalMax = 5.2,
			Horizontal = 0.72,
			GrowthPerShot = 0,
			MaxGrowth = 1,
			Pattern = { -0.25, 0.4 },
			HorizontalJitter = 0.55,
			PatternChangeChance = 0.5,
			ADSMultiplier = 0.86,
			HipMultiplier = 1.12,
			MovementMultiplier = 1.08,
			AirborneMultiplier = 1.16,
			MaxVertical = 6.5,
			MaxHorizontal = 2.2,
			RecoveryDelay = 0.28,
			RecoverySpeed = 5.5,
			SpringFrequency = 15,
			SpringDamping = 0.86,
			CameraKick = 0.48,
		},
		VehicleDamage = { Light = 1.0, Tank = 0.05 },
		SoundId = 151483854, -- доступный в исходниках мощный винтовочный выстрел
		Sound = { Volume = 1.0, VolumeVariation = 0.035, PlaybackSpeedMin = 0.985, PlaybackSpeedMax = 1.02, RollOffMinDistance = 28, RollOffMaxDistance = 1200, Lifetime = 8 },
	},

	-- 4. РУЧНОЙ ПУЛЕМЁТ (контейнерный лут) ------------------------------------
	LMG = {
		Id = "LMG",
		DisplayName = "ПКМ",
		FireMode = "Auto",
		RPM = 620,
		Damage = 26,
		HeadshotMultiplier = 1.3,
		DamageType = DamageTypes.Kinetic,
		ProjectileSpeed = 780,
		GravityFactor = 1.0,
		MaxRange = 1000,
		MagSize = 100,
		ReserveAmmo = 200,
		ReloadTime = 5.2,
		Bloom = {
			Base = 0.18,
			PerShot = 0.09,
			Max = 1.15,
			HipBase = 1.8,
			HipPerShot = 0.2,
			HipMax = 5.2,
			Movement = 1.15,
			ADSMovement = 0.42,
			Airborne = 2.2,
			RecoveryDelay = 0.13,
			RecoveryPerSecond = 7,
			ResetTime = 0.42,
		},
		Recoil = {
			VerticalMin = 0.5,
			VerticalMax = 0.72,
			Horizontal = 0.4,
			GrowthPerShot = 0.065,
			MaxGrowth = 2.05,
			Pattern = { -0.6, -0.35, 0.05, 0.5, 0.8, 0.4, -0.2, -0.75, -0.45, 0.2, 0.65, 0.15 },
			HorizontalJitter = 0.38,
			PatternChangeChance = 0.14,
			ADSMultiplier = 0.7,
			HipMultiplier = 1.12,
			MovementMultiplier = 1.16,
			AirborneMultiplier = 1.3,
			MaxVertical = 17.5,
			MaxHorizontal = 5.5,
			RecoveryDelay = 0.16,
			RecoverySpeed = 6.3,
			SpringFrequency = 17,
			SpringDamping = 0.94,
			CameraKick = 0.22,
		},
		-- Перегрев ствола: 100 единиц шкалы
		Overheat = { PerShot = 2.2, CoolPerSec = 16, VentTime = 3.5 },
		SuppressionRadius = 9, -- эффект подавления рядом с трассой
		VehicleDamage = { Light = 1.0, Tank = 0.05 }, -- бьёт лёгкую технику/мотоциклы
		SoundId = 150544849, -- доступный в исходниках пулемётный выстрел
		Sound = { Volume = 0.9, VolumeVariation = 0.04, PlaybackSpeedMin = 0.96, PlaybackSpeedMax = 1.03, RollOffMinDistance = 24, RollOffMaxDistance = 900, Lifetime = 7 },
	},

	-- 5. РПГ / ПТ-ГРАНАТОМЁТ ---------------------------------------------------
	RPG = {
		Id = "RPG",
		DisplayName = "РПГ-7",
		FireMode = "Single",
		RPM = 30,
		Damage = 400, -- прямое попадание (кумулятивная БЧ)
		DamageType = DamageTypes.HEAT,
		Projectile = true, -- физический снаряд, не «быстрая» пуля
		ProjectileSpeed = 135,
		GravityFactor = 1.0, -- тяжёлая траектория
		MaxRange = 700,
		MagSize = 1,
		ReserveAmmo = 4,
		ReloadTime = 3.8,
		Bloom = {
			Base = 0.16,
			PerShot = 0,
			Max = 0.16,
			HipBase = 1.1,
			HipPerShot = 0,
			HipMax = 1.1,
			Movement = 0.7,
			ADSMovement = 0.3,
			Airborne = 1.4,
			RecoveryDelay = 0.2,
			RecoveryPerSecond = 8,
			ResetTime = 0.6,
		},
		Recoil = {
			VerticalMin = 2.7,
			VerticalMax = 3.35,
			Horizontal = 0.5,
			GrowthPerShot = 0,
			MaxGrowth = 1,
			Pattern = { -0.35, 0.35 },
			HorizontalJitter = 0.45,
			PatternChangeChance = 0.5,
			ADSMultiplier = 0.82,
			HipMultiplier = 1.12,
			MovementMultiplier = 1.08,
			AirborneMultiplier = 1.14,
			MaxVertical = 4.5,
			MaxHorizontal = 1.8,
			RecoveryDelay = 0.24,
			RecoverySpeed = 5,
			SpringFrequency = 14,
			SpringDamping = 0.9,
			CameraKick = 0.38,
		},
		Splash = { Radius = 14, Damage = 140, Type = DamageTypes.HE }, -- фугасный осколочный круг
		VehicleDamage = { Light = 1.0, Tank = 1.0 },
		SoundId = 153230666, -- доступный в исходниках запуск РПГ
		Sound = { Volume = 1.0, VolumeVariation = 0.025, PlaybackSpeedMin = 0.985, PlaybackSpeedMax = 1.015, RollOffMinDistance = 32, RollOffMaxDistance = 1250, Lifetime = 8 },
	},
}

-- Боеприпасы/заряды спец-механик (C4, мина, FPV-дрон, пушка танка) ----------
local Charges = {
	C4 = { DirectDamage = 800, DirectType = DamageTypes.HEAT, SplashRadius = 8, SplashDamage = 150, SplashType = DamageTypes.HE },
	Mine = { DirectDamage = 650, DirectType = DamageTypes.HE, SplashRadius = 9, SplashDamage = 220, SplashType = DamageTypes.HE },
	DroneWarhead = { DirectDamage = 750, DirectType = DamageTypes.HEAT, SplashRadius = 9, SplashDamage = 160, SplashType = DamageTypes.HE },
}

-- Mesh-ассеты (FBX из tools/blender/build_assets.py). После импорта в Roblox
-- впишите сюда asset id — WeaponVisualService подставит MeshPart вместо
-- процедурной модели. 0 = использовать процедурную модель из кода.
local MeshIds = {
	AssaultRifle = 0,
	Pistol = 0,
	SniperRifle = 0,
	LMG = 0,
	RPG = 0,
	C4Charge = 0,
	Detonator = 0,
	Landmine = 0,
	DroneTablet = 0,
}

local WeaponConfig = {}

WeaponConfig.Weapons = Weapons
WeaponConfig.Charges = Charges
WeaponConfig.MeshIds = MeshIds
WeaponConfig.DefaultSoundId = 2811598570 -- Gun Shot, public-domain fallback audio

function WeaponConfig.Get(id: string)
	return Weapons[id]
end

-- Разброс текущего выстрела в градусах. Клиент и сервер передают одинаковые
-- scoped/movement/airborne условия; старые вызовы с двумя аргументами остаются ADS.
function WeaponConfig.RecoverBloom(cfg, bloomShots: number, elapsed: number): number
	local b = cfg.Bloom
	if not b or bloomShots <= 0 then
		return 0
	end

	local recoveryDelay = b.RecoveryDelay
	local recoveryPerSecond = b.RecoveryPerSecond
	if recoveryDelay and recoveryPerSecond then
		local recoveryTime = math.max(elapsed - recoveryDelay, 0)
		return math.max(0, bloomShots - recoveryTime * recoveryPerSecond)
	end

	-- Совместимость со старыми профилями: после ResetTime bloom сбрасывается.
	if elapsed > (b.ResetTime or 0.4) then
		return 0
	end
	return bloomShots
end

function WeaponConfig.ComputeBloom(cfg, burst: number, scoped: boolean?, movementAlpha: number?, airborne: boolean?): number
	local b = cfg.Bloom
	if not b then
		return 0
	end

	local shotIndex = math.max(burst - 1, 0)
	local isADS = scoped ~= false
	local base = isADS and b.Base or (b.HipBase or cfg.HipBloom or b.Base)
	local perShot = isADS and b.PerShot or (b.HipPerShot or b.PerShot)
	local maximum = isADS and b.Max or (b.HipMax or b.Max)
	local bloom = math.min(maximum, base + perShot * shotIndex)

	local movement = math.clamp(movementAlpha or 0, 0, 1)
	local movementPenalty = isADS and (b.ADSMovement or b.Movement or 0) or (b.Movement or 0)
	bloom += movementPenalty * movement
	if airborne then
		bloom += b.Airborne or 0
	end

	return bloom
end

-- Детерминированный равномерный круговой разброс: один seed даёт одинаковое
-- направление у локального предикта и авторитетной серверной баллистики.
function WeaponConfig.ApplySpread(aimDirection: Vector3, seed: number, bloomDegrees: number): Vector3
	if bloomDegrees <= 0 then
		return aimDirection.Unit
	end
	local spreadRng = Random.new(seed)
	local radius = math.rad(bloomDegrees) * math.sqrt(spreadRng:NextNumber())
	local angle = spreadRng:NextNumber(0, math.pi * 2)
	local pitch = math.sin(angle) * radius
	local yaw = math.cos(angle) * radius
	local cf = CFrame.lookAt(Vector3.zero, aimDirection.Unit) * CFrame.Angles(pitch, yaw, 0)
	return cf.LookVector
end

return WeaponConfig
