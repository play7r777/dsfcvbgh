--!nonstrict
-- ============================================================================
-- WeaponConfig — характеристики стрелкового оружия и боеприпасов.
-- Клиент использует для визуала/предикции, сервер — как авторитетный источник.
--
-- GravityFactor — множитель гравитации workspace для траектории снаряда
-- (падение пули). 1 = полная гравитация, 0 = прямой выстрел.
-- VehicleDamage — множитель урона по классам техники { Light, Tank }.
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
		Bloom = { Base = 0.5, PerShot = 0.35, Max = 4.0, Recovery = 7 }, -- градусы
		VehicleDamage = { Light = 1.0, Tank = 0.0 }, -- танк пулям не по зубам
		SoundId = 0, -- TODO: rbxassetid выстрела
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
		Bloom = { Base = 0.4, PerShot = 0.25, Max = 2.2, Recovery = 10 },
		VehicleDamage = { Light = 0.5, Tank = 0.0 },
		SoundId = 0,
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
		Bloom = { Base = 0.05, PerShot = 0.0, Max = 0.05, Recovery = 20 }, -- в прицеле
		HipBloom = 5.0, -- от бедра снайперка почти бесполезна
		ScopeFOV = 12, -- оптический прицел
		VehicleDamage = { Light = 1.0, Tank = 0.05 },
		SoundId = 0,
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
		Bloom = { Base = 0.9, PerShot = 0.3, Max = 5.5, Recovery = 5 },
		-- Перегрев ствола: 100 единиц шкалы
		Overheat = { PerShot = 2.2, CoolPerSec = 16, VentTime = 3.5 },
		SuppressionRadius = 9, -- эффект подавления рядом с трассой
		VehicleDamage = { Light = 1.0, Tank = 0.05 }, -- бьёт лёгкую технику/мотоциклы
		SoundId = 0,
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
		Bloom = { Base = 0.3, PerShot = 0, Max = 0.3, Recovery = 5 },
		Splash = { Radius = 14, Damage = 140, Type = DamageTypes.HE }, -- фугасный осколочный круг
		VehicleDamage = { Light = 1.0, Tank = 1.0 },
		SoundId = 0,
	},
}

-- Боеприпасы/заряды спец-механик (C4, мина, FPV-дрон, пушка танка) ----------
local Charges = {
	C4 = { DirectDamage = 800, DirectType = DamageTypes.HEAT, SplashRadius = 8, SplashDamage = 150, SplashType = DamageTypes.HE },
	Mine = { DirectDamage = 650, DirectType = DamageTypes.HE, SplashRadius = 9, SplashDamage = 220, SplashType = DamageTypes.HE },
	DroneWarhead = { DirectDamage = 750, DirectType = DamageTypes.HEAT, SplashRadius = 9, SplashDamage = 160, SplashType = DamageTypes.HE },
}

local WeaponConfig = {}

WeaponConfig.Weapons = Weapons
WeaponConfig.Charges = Charges

function WeaponConfig.Get(id: string)
	return Weapons[id]
end

-- Разброс текущего выстрела в градусах по длине очереди (burst >= 1)
function WeaponConfig.ComputeBloom(cfg, burst: number): number
	local b = cfg.Bloom
	if not b then
		return 0
	end
	return math.min(b.Max, b.Base + b.PerShot * math.max(burst - 1, 0))
end

-- Детерминированный разброс: один и тот же seed даёт одинаковое отклонение
-- на клиенте (визуал) и сервере (авторитетная проверка).
function WeaponConfig.ApplySpread(aimDirection: Vector3, seed: number, bloomDegrees: number): Vector3
	if bloomDegrees <= 0 then
		return aimDirection.Unit
	end
	local rng = Random.new(seed)
	local pitch = math.rad(rng:NextNumber(-bloomDegrees, bloomDegrees))
	local yaw = math.rad(rng:NextNumber(-bloomDegrees, bloomDegrees))
	local cf = CFrame.lookAt(Vector3.zero, aimDirection.Unit) * CFrame.Angles(pitch, yaw, 0)
	return cf.LookVector
end

return WeaponConfig
