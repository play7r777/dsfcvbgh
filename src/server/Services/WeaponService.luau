--!nonstrict
-- ============================================================================
-- WeaponService — серверная сторона стрелкового оружия.
--
-- Схема FastCast / Server-Validated Ballistics (раздел 2 ТЗ):
--   * клиент мгновенно рисует трассер/звук (отзывчивость)
--   * клиент шлёт (weaponId, origin, aimDir, seed, timestamp, scoped)
--   * сервер проверяет: темп огня, магазин, перезарядку, перегрев, задержку
--     (timestamp по серверным часам), положение origin рядом с головой,
--     единичность вектора; разброс восстанавливает детерминированно по seed
--   * сервер прогоняет СВОЮ баллистику и наносит урон через DamageService /
--     ArmorService; остальным клиентам рассылает трассер (FX_Shot)
-- ============================================================================

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Ballistics = require(Shared.Combat.Ballistics)
local HitboxTags = require(Shared.Combat.HitboxTags)
local Validation = require(Shared.Util.Validation)
local WeaponConfig = require(Shared.Config.WeaponConfig)

local WeaponService = {}

local ctx
local states = {} -- [Player] = state
local fireFlood = Validation.NewFloodCheck(40)
local reloadFlood = Validation.NewFloodCheck(6)

local function newState()
	return {
		Ammo = {}, -- [weaponId] = { Mag, Reserve }
		Heat = 0,
		VentUntil = 0,
		ReloadEnd = 0,
		ReloadWeapon = nil,
		Burst = 0,
		BurstLast = 0,
		Equipped = nil,
		LastFireAt = 0,
	}
end

-- ---------------------------------------------------------------------------
-- Синхронизация состояния с клиентом (боеприпасы/перегрев/перезарядка)
-- ---------------------------------------------------------------------------
local function pushSync(player: Player)
	local st = states[player]
	if not st then
		return
	end
	local now = os.clock()
	local ammoOut = {}
	for id, a in pairs(st.Ammo) do
		ammoOut[id] = { Mag = a.Mag, Reserve = a.Reserve }
	end
	ctx.Remotes.Get("Weapon_Sync"):FireClient(player, {
		Ammo = ammoOut,
		Heat = st.Heat,
		VentIn = math.max(0, st.VentUntil - now),
		ReloadIn = math.max(0, st.ReloadEnd - now),
		ReloadWeapon = st.ReloadWeapon,
	})
end

-- ---------------------------------------------------------------------------
-- Выдача и сброс
-- ---------------------------------------------------------------------------
function WeaponService.ResetLoadout(player: Player)
	local st = states[player] or newState()
	st.Ammo = {}
	st.Heat = 0
	st.VentUntil = 0
	st.ReloadEnd = 0
	st.ReloadWeapon = nil
	st.Equipped = nil
	st.Burst = 0
	st.BurstLast = 0
	for _, id in ipairs(require(Shared.Config.GameConfig).Loadout) do
		local cfg = WeaponConfig.Get(id)
		if cfg then
			st.Ammo[id] = { Mag = cfg.MagSize, Reserve = cfg.ReserveAmmo }
		end
	end
	states[player] = st
	pushSync(player)
end

-- Выдать контейнерное оружие (ПКМ/СВД). Повтор — просто пополнение запаса.
function WeaponService.GiveWeapon(player: Player, weaponId: string)
	local cfg = WeaponConfig.Get(weaponId)
	if not cfg then
		return
	end
	local st = states[player]
	if not st then
		return
	end

	local hasTool = false
	if player.Backpack then
		for _, tool in ipairs(player.Backpack:GetChildren()) do
			if tool:IsA("Tool") and tool:GetAttribute("WeaponId") == weaponId then
				hasTool = true
			end
		end
	end
	if player.Character then
		for _, tool in ipairs(player.Character:GetChildren()) do
			if tool:IsA("Tool") and tool:GetAttribute("WeaponId") == weaponId then
				hasTool = true
			end
		end
	end

	if hasTool then
		local ammo = st.Ammo[weaponId]
		if ammo then
			ammo.Reserve = cfg.ReserveAmmo
		end
	else
		st.Ammo[weaponId] = { Mag = cfg.MagSize, Reserve = cfg.ReserveAmmo }
		ctx.Loadout.MakeTool(player, weaponId)
	end
	pushSync(player)
end

function WeaponService.RefillReserve(player: Player)
	local st = states[player]
	if not st then
		return
	end
	for id, a in pairs(st.Ammo) do
		local cfg = WeaponConfig.Get(id)
		if cfg then
			a.Reserve = cfg.ReserveAmmo
		end
	end
	pushSync(player)
end

function WeaponService.OnToolEquipped(player: Player, weaponId: string)
	local st = states[player]
	if st then
		if st.Equipped ~= weaponId then
			st.Burst = 0
			st.BurstLast = 0
		end
		st.Equipped = weaponId
	end
end

function WeaponService.OnToolUnequipped(player: Player, weaponId: string)
	local st = states[player]
	if st and st.Equipped == weaponId then
		st.Equipped = nil
	end
end

-- ---------------------------------------------------------------------------
-- Попадание серверного снаряда
-- ---------------------------------------------------------------------------
local function onCastHit(player: Player, weaponId: string, cfg, result: RaycastResult, direction: Vector3)
	local inst = result.Instance

	-- Подбитая мина детонирует
	if CollectionService:HasTag(inst, HitboxTags.Landmine) then
		ctx.Explosives.DetonateMinePart(inst, player)
		return
	end

	-- Сбитие FPV-дрона
	local droneId = inst:GetAttribute("DroneId")
	if droneId and ctx.Drone then
		ctx.Drone.OnDroneShot(droneId, player)
		return
	end

	-- Физический снаряд (РПГ): взрыв в точке контакта — прямой урон + фугас
	if cfg.Projectile then
		local state = ctx.Armor.GetStateFromPart(inst)
		local mult = 1
		if state then
			mult = (cfg.VehicleDamage and cfg.VehicleDamage[state.Config.Class]) or 1
		end
		ctx.Explosives.Explode(result.Position, player, {
			DirectPart = inst,
			DirectDamage = cfg.Damage * mult,
			DirectType = cfg.DamageType,
			DirectNormal = result.Normal,
			DirectDirection = direction,
			SplashRadius = cfg.Splash and cfg.Splash.Radius,
			SplashDamage = cfg.Splash and cfg.Splash.Damage,
			SplashType = cfg.Splash and cfg.Splash.Type,
			WeaponId = weaponId,
		})
		return
	end

	-- Бронетехника
	local state = ctx.Armor.GetStateFromPart(inst)
	if state then
		local vehMult = (cfg.VehicleDamage and cfg.VehicleDamage[state.Config.Class]) or 0
		if vehMult <= 0 then
			ctx.Remotes.Get("FX_Hitmarker"):FireClient(player, "ricochet")
			return
		end
		ctx.Armor.ApplyHit(state, inst, cfg.Damage * vehMult, cfg.DamageType, player, {
			Normal = result.Normal,
			Direction = direction,
		})
		return
	end

	-- Пехота
	local humanoid = ctx.Explosives.FindHumanoid(inst)
	if humanoid then
		local char = player.Character
		if humanoid.Parent ~= char then
			local damage = cfg.Damage
			if inst.Name == "Head" then
				damage *= cfg.HeadshotMultiplier
			end
			ctx.Damage.Damage(player, humanoid, damage, { WeaponId = weaponId })
		end
		return
	end
end

-- ---------------------------------------------------------------------------
-- Обработчик выстрела
-- payload: weaponId, origin, aimDir, seed, timestamp, scoped
-- ---------------------------------------------------------------------------
local function onFire(player: Player, weaponId, origin, aimDir, seed, timestamp, scoped)
	if not fireFlood(player) then
		return
	end
	if type(weaponId) ~= "string" then
		return
	end
	local cfg = WeaponConfig.Get(weaponId)
	if not cfg then
		return
	end
	local st = states[player]
	if not st or st.Equipped ~= weaponId then
		return
	end

	local char, humanoid = Validation.AliveCharacter(player)
	if not char then
		return
	end
	if char:GetAttribute("OperatingDrone") then
		return -- оператор дрона занят планшетом
	end
	if humanoid.SeatPart then
		return -- из техники личное оружие не стреляет
	end

	local now = os.clock()

	-- темп огня (допуск 15% на сетевой джиттер)
	local minInterval = (60 / cfg.RPM) * 0.85
	if now - st.LastFireAt < minInterval then
		return
	end
	-- перезарядка / продувка ствола
	if now < st.ReloadEnd or now < st.VentUntil then
		return
	end
	local ammo = st.Ammo[weaponId]
	if not ammo or ammo.Mag <= 0 then
		return
	end

	-- метка времени клиента (защита от replay-атак)
	if not Validation.IsFiniteNumber(timestamp) or math.abs(Workspace:GetServerTimeNow() - timestamp) > 1.0 then
		return
	end
	-- origin рядом с головой персонажа
	local head = char:FindFirstChild("Head")
	if not Validation.IsFiniteVector(origin) or not head then
		return
	end
	if (origin - head.Position).Magnitude > 8 then
		return
	end
	if not Validation.IsUnitVector(aimDir, 0.08) then
		return
	end
	if type(seed) ~= "number" then
		return
	end

	-- Сервер авторитетно восстанавливает очередь по синхронизированному времени
	-- ввода и сам рассчитывает штрафы движения/прыжка. Состояние изменяется только
	-- после всех проверок, поэтому отклонённый пакет не влияет на следующий выстрел.
	local recoveredBurst = WeaponConfig.RecoverBloom(cfg, st.Burst, now - st.BurstLast)
	local movementAlpha = math.clamp(humanoid.MoveDirection.Magnitude, 0, 1)
	local airborne = humanoid.FloorMaterial == Enum.Material.Air
	local bloom = WeaponConfig.ComputeBloom(cfg, recoveredBurst + 1, scoped == true, movementAlpha, airborne)
	local finalDir = WeaponConfig.ApplySpread(aimDir, seed, bloom)
	st.LastFireAt = now
	st.Burst = recoveredBurst + 1
	st.BurstLast = now

	ammo.Mag -= 1

	if cfg.Overheat then
		st.Heat = math.min(100, st.Heat + cfg.Overheat.PerShot)
		if st.Heat >= 100 then
			st.VentUntil = now + cfg.Overheat.VentTime -- принудительная продувка
		end
	end
	pushSync(player)

	-- трассер для остальных клиентов
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr ~= player then
			ctx.Remotes.Get("FX_Shot"):FireClient(plr, player.UserId, weaponId, origin, finalDir)
		end
	end

	-- авторитетная серверная баллистика
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { char }

	local cast = Ballistics.Fire({
		Origin = origin,
		Direction = finalDir,
		Speed = cfg.ProjectileSpeed,
		Gravity = Vector3.new(0, -Workspace.Gravity * cfg.GravityFactor, 0),
		MaxDistance = cfg.MaxRange,
		RaycastParams = params,
	})
	cast.OnHit:Connect(function(result)
		onCastHit(player, weaponId, cfg, result, finalDir)
	end)
end

-- ---------------------------------------------------------------------------
-- Перезарядка
-- ---------------------------------------------------------------------------
local function onReload(player: Player, weaponId)
	if not reloadFlood(player) then
		return
	end
	if type(weaponId) ~= "string" then
		return
	end
	local cfg = WeaponConfig.Get(weaponId)
	local st = states[player]
	if not cfg or not st or st.Equipped ~= weaponId then
		return
	end
	local ammo = st.Ammo[weaponId]
	if not ammo or ammo.Mag >= cfg.MagSize or ammo.Reserve <= 0 then
		return
	end
	local now = os.clock()
	if now < st.ReloadEnd then
		return
	end

	st.ReloadEnd = now + cfg.ReloadTime
	st.ReloadWeapon = weaponId
	pushSync(player)

	task.delay(cfg.ReloadTime, function()
		local cur = states[player]
		if not cur or cur.ReloadWeapon ~= weaponId then
			return
		end
		local a = cur.Ammo[weaponId]
		if not a then
			return
		end
		local need = cfg.MagSize - a.Mag
		local take = math.min(need, a.Reserve)
		a.Mag += take
		a.Reserve -= take
		cur.ReloadEnd = 0
		cur.ReloadWeapon = nil
		pushSync(player)
	end)
end

-- ---------------------------------------------------------------------------
function WeaponService.Init(deps)
	ctx = deps

	ctx.Remotes.Get("Weapon_Fire").OnServerEvent:Connect(onFire)
	ctx.Remotes.Get("Weapon_Reload").OnServerEvent:Connect(onReload)

	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
	end)

	-- охлаждение стволов
	RunService.Heartbeat:Connect(function(dt)
		local now = os.clock()
		for player, st in pairs(states) do
			if st.Heat > 0 then
				local cfg = st.Equipped and WeaponConfig.Get(st.Equipped)
				local cool = (cfg and cfg.Overheat and cfg.Overheat.CoolPerSec) or 16
				if now < st.VentUntil then
					cool *= 2 -- продувка охлаждает вдвое быстрее
				end
				st.Heat = math.max(0, st.Heat - cool * dt)
				if (st._heatPush or 0) < now - 0.25 then
					st._heatPush = now
					pushSync(player)
				end
			end
		end
	end)
end

return WeaponService
