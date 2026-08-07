--!nonstrict
-- ============================================================================
-- VehicleControl — серверный цикл управления техникой:
--   * шасси: LinearVelocity + AlignOrientation, следование рельефу рейкастом
--   * танк: поворот башни к цели с ограничением скорости по HP погона
--   * главная пушка танка (APFSDS + фугасный круг), серверная баллистика
-- Иммобилизация: сорванная гусеница или мёртвый двигатель = полный стоп.
-- ============================================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Ballistics = require(Shared.Combat.Ballistics)
local Validation = require(Shared.Util.Validation)

local VehicleControl = {}

local ctx
local aimFlood = Validation.NewFloodCheck(30)
local fireFlood = Validation.NewFloodCheck(4)

local function shortestAngle(a: number): number
	return (a + math.pi) % (2 * math.pi) - math.pi
end

-- ---------------------------------------------------------------------------
-- Пушка танка
-- ---------------------------------------------------------------------------
local function fireCannon(player: Player)
	if not fireFlood(player) then
		return
	end
	local state = ctx.Armor.GetStateByOccupant(player)
	if not state or state.Kind ~= "Tank" or state.Destroyed then
		return
	end
	if not Validation.AliveCharacter(player) then
		return
	end

	local now = os.clock()
	if now < state.CannonReadyAt then
		return
	end
	local cannon = state.Config.Cannon
	state.CannonReadyAt = now + cannon.ReloadTime

	local muzzle = state.Turret.Muzzle.WorldPosition
	local direction = state.AimLook or state.Turret.Root.CFrame.LookVector

	-- Визуал и звук всем клиентам, включая стрелка: локальный эффект танка
	-- появляется только после серверного подтверждения выстрела.
	for _, plr in ipairs(game:GetService("Players"):GetPlayers()) do
		ctx.Remotes.Get("FX_Shot"):FireClient(plr, player.UserId, "TankCannon", muzzle, direction)
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { state.Model }

	local cast = Ballistics.Fire({
		Origin = muzzle,
		Direction = direction,
		Speed = cannon.ProjectileSpeed,
		Gravity = Vector3.new(0, -Workspace.Gravity * cannon.GravityFactor, 0),
		MaxDistance = cannon.MaxRange,
		RaycastParams = params,
	})

	cast.OnHit:Connect(function(result)
		ctx.Explosives.Explode(result.Position, player, {
			DirectPart = result.Instance,
			DirectDamage = cannon.Damage,
			DirectType = cannon.DamageType,
			DirectNormal = result.Normal,
			DirectDirection = direction,
			SplashRadius = cannon.Splash.Radius,
			SplashDamage = cannon.Splash.Damage,
			SplashType = cannon.Splash.Type,
			WeaponId = "TankCannon",
		})
	end)
end

-- ---------------------------------------------------------------------------
-- Кадровый цикл
-- ---------------------------------------------------------------------------
local function stepVehicle(state, dt: number)
	if state.Destroyed then
		return
	end

	local lv = state.DriveLV
	local ao = state.DriveAO
	if not lv or not lv.Parent then
		return
	end

	local humanoid = state.Seat.Occupant
	local cfg = state.Config

	if not humanoid or ctx.Armor.IsImmobilized(state) then
		lv.VectorVelocity = Vector3.zero
	else
		local throttle = state.Seat.ThrottleFloat
		local steer = state.Seat.SteerFloat

		state.Yaw -= steer * math.rad(cfg.TurnDegPerSec) * dt

		local forward = (CFrame.Angles(0, state.Yaw, 0)).LookVector
		local speed = throttle >= 0 and cfg.MoveSpeed or cfg.ReverseSpeed
		local vel = forward * (throttle * speed)

		-- следование рельефу: рейкаст вниз, плавная подстройка высоты
		local vy = -20
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { state.Model }
		local groundHit = Workspace:Raycast(state.Root.Position + Vector3.new(0, 2, 0), Vector3.new(0, -10, 0), params)
		if groundHit then
			local targetY = groundHit.Position.Y + state.GroundClearance
			vy = math.clamp((targetY - state.Root.Position.Y) * 8, -22, 14)
		end

		lv.VectorVelocity = Vector3.new(vel.X, vy, vel.Z)
	end

	ao.CFrame = CFrame.Angles(0, state.Yaw, 0)

	-- Башня: доворот к цели с ограничением угловой скорости
	if state.Turret and state.AimLook and not ctx.Armor.IsTurretJammed(state) then
		local factor = ctx.Armor.TurretTraverseFactor(state)
		local targetYaw = math.atan2(-state.AimLook.X, -state.AimLook.Z)
		local maxStep = math.rad(cfg.TurretTraverseDegPerSec) * factor * dt
		local delta = shortestAngle(targetYaw - state.TurretYaw)
		state.TurretYaw += math.clamp(delta, -maxStep, maxStep)
		state.Turret.Orientation.CFrame = CFrame.Angles(0, state.TurretYaw, 0)
	end
end

function VehicleControl.Init(deps)
	ctx = deps

	ctx.Remotes.Get("Turret_Aim").OnServerEvent:Connect(function(player, lookDir)
		if not aimFlood(player) then
			return
		end
		if not Validation.IsUnitVector(lookDir, 0.1) then
			return
		end
		local state = ctx.Armor.GetStateByOccupant(player)
		if state and state.Kind == "Tank" and not state.Destroyed then
			state.AimLook = lookDir.Unit
		end
	end)

	ctx.Remotes.Get("Tank_Fire").OnServerEvent:Connect(fireCannon)

	RunService.Heartbeat:Connect(function(dt)
		for _, state in pairs(ctx.Armor.GetStates()) do
			stepVehicle(state, dt)
		end
	end)
end

return VehicleControl
