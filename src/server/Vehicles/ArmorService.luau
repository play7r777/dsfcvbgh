--!nonstrict
-- ============================================================================
-- ArmorService — многокомпонентная модель повреждений бронетехники (разд. 3).
--
-- У каждой машины: общий Hull HP + модули (гусеницы, двигатель, погон башни,
-- боеукладка). Урон зависит от типа (Kinetic/HEAT/HE), зоны попадания
-- (теги CollectionService) и угла встречи с бронёй (кинетика).
--
-- Эффекты:
--   Track 0 HP        -> полная иммобилизация
--   Engine 0 HP       -> потеря хода + пожар (25 HP/сек корпусу)
--   Turret < 50% HP   -> скорость поворота башни x0.4; 0 HP -> заклинивание
--   AmmoRack + HEAT/AP-> 35% шанс мгновенного подрыва (cook-off)
-- ============================================================================

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local DamageTypes = require(Shared.Combat.DamageTypes)
local HitboxTags = require(Shared.Combat.HitboxTags)
local VehicleConfig = require(Shared.Config.VehicleConfig)

local ArmorService = {}

local ctx
local states = {} -- [id] = state
local rng = Random.new()

-- ---------------------------------------------------------------------------
-- Регистрация / поиск
-- ---------------------------------------------------------------------------

local function assignPartIds(model: Model, id: string)
	for _, inst in ipairs(model:GetDescendants()) do
		if inst:IsA("BasePart") then
			inst:SetAttribute("VehicleId", id)
		end
	end
end

function ArmorService.RegisterVehicle(factoryData)
	local id = HttpService:GenerateGUID(false):sub(1, 8)
	local cfg = VehicleConfig[factoryData.Kind]

	local modules = {}
	for name, hp in pairs(cfg.Modules) do
		modules[name] = { HP = hp, Max = hp }
	end

	local state = {
		Id = id,
		Kind = factoryData.Kind,
		Config = cfg,
		Model = factoryData.Model,
		Root = factoryData.Root,
		Seat = factoryData.Seat,
		DriveLV = factoryData.DriveLV,
		DriveAO = factoryData.DriveAO,
		GroundClearance = factoryData.GroundClearance,
		Turret = factoryData.Turret,

		HullHP = cfg.HullHP,
		Modules = modules,
		Burning = false,
		Destroyed = false,

		Yaw = 0,
		TurretYaw = 0,
		AimLook = nil,
		CannonReadyAt = 0,
		Occupant = nil, -- Player водителя
		LastAttacker = nil,
	}

	-- начальный курс по ориентации спавна
	local look = factoryData.Root.CFrame.LookVector
	state.Yaw = math.atan2(-look.X, -look.Z)
	state.TurretYaw = state.Yaw

	assignPartIds(factoryData.Model, id)
	factoryData.Model:SetAttribute("VehicleId", id)
	states[id] = state

	factoryData.Seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		local humanoid = factoryData.Seat.Occupant
		if humanoid then
			state.Occupant = Players:GetPlayerFromCharacter(humanoid.Parent)
		else
			state.Occupant = nil
		end
	end)

	return state
end

function ArmorService.GetStates()
	return states
end

function ArmorService.GetStateFromPart(inst: Instance?)
	if not inst or not inst:IsA("BasePart") then
		return nil
	end
	local id = inst:GetAttribute("VehicleId")
	if not id then
		return nil
	end
	local state = states[id]
	if state and not state.Destroyed then
		return state
	end
	return nil
end

function ArmorService.GetStateByOccupant(player: Player)
	for _, state in pairs(states) do
		if not state.Destroyed and state.Occupant == player then
			return state
		end
	end
	return nil
end

-- ---------------------------------------------------------------------------
-- Снапшот состояния для HUD водителя
-- ---------------------------------------------------------------------------
function ArmorService.Snapshot(state)
	local mods = {}
	for name, m in pairs(state.Modules) do
		mods[name] = m.HP / m.Max
	end
	return {
		Hull = state.HullHP / state.Config.HullHP,
		Modules = mods,
		Burning = state.Burning,
		Immobilized = ArmorService.IsImmobilized(state),
		TurretJammed = ArmorService.IsTurretJammed(state),
		Name = state.Config.DisplayName,
	}
end

function ArmorService.IsImmobilized(state): boolean
	local tL = state.Modules.TrackL
	local tR = state.Modules.TrackR
	local eng = state.Modules.Engine
	if eng and eng.HP <= 0 then
		return true
	end
	return (tL and tL.HP <= 0) or (tR and tR.HP <= 0) or false
end

function ArmorService.IsTurretJammed(state): boolean
	local t = state.Modules.Turret
	return t ~= nil and t.HP <= 0
end

function ArmorService.TurretTraverseFactor(state): number
	local t = state.Modules.Turret
	if not t then
		return 1
	end
	if t.HP <= 0 then
		return 0
	end
	if t.HP / t.Max <= state.Config.TurretDegradedAt then
		return state.Config.TurretDegradedFactor
	end
	return 1
end

-- ---------------------------------------------------------------------------
-- Нанесение урона
-- ---------------------------------------------------------------------------

local function pushStateToOccupant(state)
	if state.Occupant then
		ctx.Remotes.Get("Vehicle_Event"):FireClient(state.Occupant, "State", state.Id, ArmorService.Snapshot(state))
	end
end

local function hitmarker(attacker: Player?, kind: string)
	if attacker then
		ctx.Remotes.Get("FX_Hitmarker"):FireClient(attacker, kind)
	end
end

-- Главная точка входа. opts: { Normal?, Direction?, InstantModuleKill? }
function ArmorService.ApplyHit(state, part: BasePart, baseDamage: number, damageType: string, attacker: Player?, opts): number
	if state.Destroyed or baseDamage <= 0 then
		return 0
	end
	opts = opts or {}

	local cfg = state.Config
	local zone = HitboxTags.GetZone(part)
	local mult = (cfg.ZoneMultipliers and cfg.ZoneMultipliers[zone]) or 1
	local damage = baseDamage * mult

	-- Кинетика: толщина/угол брони
	if damageType == DamageTypes.Kinetic and opts.Normal and opts.Direction then
		local cos = -opts.Direction.Unit:Dot(opts.Normal.Unit)
		if cos < (cfg.RicochetCos or 0) then
			hitmarker(attacker, "ricochet")
			return 0
		end
		damage *= math.clamp(cos, cfg.MinPenetrationCos or 0.3, 1)
	end

	-- Фугас бонусно срывает гусеницы
	if
		damageType == DamageTypes.HE
		and cfg.HETrackBonus
		and (zone == HitboxTags.TrackL or zone == HitboxTags.TrackR)
	then
		damage *= cfg.HETrackBonus
	end

	-- Урон модулю
	local moduleName = HitboxTags.ZoneToModule(zone)
	local module = moduleName and state.Modules[moduleName]
	if module then
		if opts.InstantModuleKill then
			module.HP = 0
		else
			module.HP = math.max(0, module.HP - damage)
		end

		if moduleName == "Engine" and module.HP <= 0 and not state.Burning then
			state.Burning = true
			ArmorService._ignite(state)
		end

		-- Детонация боеукладки: кумулятив/кинетика по БК
		if moduleName == "AmmoRack" and (damageType == DamageTypes.HEAT or damageType == DamageTypes.Kinetic) then
			local chance = module.HP <= 0 and cfg.CookoffChanceDead or cfg.CookoffChance
			if opts.InstantModuleKill or rng:NextNumber() < chance then
				state.LastAttacker = attacker
				ArmorService.Destroy(state, attacker, "cookoff")
				hitmarker(attacker, "cookoff")
				return damage
			end
		end
	end

	-- Урон корпусу
	state.HullHP = math.max(0, state.HullHP - damage)
	state.LastAttacker = attacker

	if state.HullHP <= 0 then
		ArmorService.Destroy(state, attacker, "destroyed")
	else
		pushStateToOccupant(state)
		hitmarker(attacker, "vehicle")
	end
	return damage
end

-- Гарантированный срыв обеих гусениц (противотанковая мина)
function ArmorService.BreakTracks(state, attacker: Player?)
	if state.Destroyed then
		return
	end
	for _, name in ipairs({ "TrackL", "TrackR" }) do
		local m = state.Modules[name]
		if m then
			m.HP = 0
		end
	end
	pushStateToOccupant(state)
end

-- Пожар двигателя: дым + DoT по корпусу (цикл в Heartbeat ниже)
function ArmorService._ignite(state)
	local deck = state.Model:FindFirstChild("EngineDeck")
	if deck then
		local fire = Instance.new("ParticleEmitter")
		fire.Name = "EngineFire"
		fire.Rate = 24
		fire.Lifetime = NumberRange.new(0.4, 0.8)
		fire.Speed = NumberRange.new(4, 7)
		fire.Color = ColorSequence.new(Color3.fromRGB(255, 120, 40), Color3.fromRGB(60, 60, 60))
		fire.Size = NumberSequence.new(1.6)
		fire.Parent = deck
	end
	pushStateToOccupant(state)
end

-- ---------------------------------------------------------------------------
-- Уничтожение машины
-- ---------------------------------------------------------------------------
function ArmorService.Destroy(state, attacker: Player?, cause: string)
	if state.Destroyed then
		return
	end
	state.Destroyed = true
	state.Burning = false

	local position = state.Root.Position

	-- взрыв корпуса
	local explosion = Instance.new("Explosion")
	explosion.Position = position
	explosion.BlastRadius = 18
	explosion.BlastPressure = 400000
	explosion.DestroyJointRadiusPercent = 0
	explosion.ExplosionType = Enum.ExplosionType.NoCraters
	explosion.Parent = workspace

	-- экипаж погибает
	local humanoid = state.Seat and state.Seat.Occupant
	if humanoid and ctx and ctx.Damage then
		ctx.Damage.ForceKill(humanoid, attacker, "VehicleExplosion")
	end

	-- оповещения
	local attackerName = attacker and attacker.Name or nil
	ctx.Remotes.Get("Vehicle_Event"):FireAllClients("Destroyed", state.Id, attackerName, state.Config.DisplayName)
	if attackerName then
		ctx.Remotes.Get("Killfeed"):FireAllClients(attackerName, state.Config.DisplayName, cause or "destroyed")
	end

	-- каркас остаётся укрытием на некоторое время
	for _, inst in ipairs(state.Model:GetDescendants()) do
		if inst:IsA("BasePart") then
			inst:SetAttribute("VehicleId", nil)
			inst.Color = Color3.fromRGB(45, 43, 40)
			inst.Material = Enum.Material.CorrodedMetal
		end
	end
	if state.Turret then
		state.Turret.Orientation:Destroy()
	end
	state.DriveLV:Destroy()
	state.DriveAO:Destroy()

	task.delay(25, function()
		if state.Model and state.Model.Parent then
			state.Model:Destroy()
		end
	end)

	states[state.Id] = nil

	if ctx.Spawner then
		ctx.Spawner.OnVehicleDestroyed(state)
	end
end

-- ---------------------------------------------------------------------------
-- Цикл: пожары и пуш-уведомления
-- ---------------------------------------------------------------------------
function ArmorService.Init(deps)
	ctx = deps

	RunService.Heartbeat:Connect(function(dt)
		for _, state in pairs(states) do
			if state.Burning and not state.Destroyed then
				state.HullHP = math.max(0, state.HullHP - state.Config.EngineFireDPS * dt)
				if state.HullHP <= 0 then
					ArmorService.Destroy(state, state.LastAttacker, "fire")
				elseif state.Occupant and (state._lastPush or 0) < os.clock() - 1 then
					state._lastPush = os.clock()
					pushStateToOccupant(state)
				end
			end
		end
	end)
end

return ArmorService
