--!nonstrict
-- ============================================================================
-- DroneService — FPV дрон-камикадзе (раздел 4.3 ТЗ).
--   * оператор остаётся неподвижен и уязвим (WalkSpeed/JumpPower = 0)
--   * дрон летит по инерциальной модели с damp-разгоном, кренами (Acro-стиль)
--   * батарея 60 сек, радиус видеоканала; за пределами — потеря связи
--   * столкновение на скорости >= ExplodeSpeed: 750 HEAT в конкретный хитбокс
--   * дрон можно сбить стрелковым оружием
-- ============================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Validation = require(Shared.Util.Validation)
local WeaponConfig = require(Shared.Config.WeaponConfig)

local DroneService = {}

local ctx
local drones = {} -- [Player] = droneState
local cooldowns = {} -- [Player] = os.clock()
local requestFlood = Validation.NewFloodCheck(2)
local inputFlood = Validation.NewFloodCheck(30)

local DRONE_CFG = GameConfig.Drone

-- ---------------------------------------------------------------------------
-- Модель дрона (все детали Anchored — двигаем PivotTo, столкновения ловим сами)
-- ---------------------------------------------------------------------------
local droneCounter = 0

local function buildDroneModel(spawnCF: CFrame): Model
	droneCounter += 1
	local id = "Drone" .. droneCounter

	local model = Instance.new("Model")
	model.Name = "FPVDrone"

	local function dpart(name: string, size: Vector3, offset: CFrame, color: Color3): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.CFrame = spawnCF * offset
		p.Color = color
		p.Material = Enum.Material.SmoothPlastic
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = true -- пули могут сбить дрон
		p:SetAttribute("DroneId", id)
		p.Parent = model
		return p
	end

	local body = dpart("Body", Vector3.new(1.4, 0.5, 1.4), CFrame.new(), Color3.fromRGB(40, 40, 42))
	dpart("Eye", Vector3.new(0.4, 0.3, 0.2), CFrame.new(0, 0, -0.75), Color3.fromRGB(255, 80, 60))
	for i, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			dpart("Arm", Vector3.new(1.6, 0.12, 0.22), CFrame.new(sx * 0.8, 0.1, sz * 0.8) * CFrame.Angles(0, sx * sz * math.rad(45), 0), Color3.fromRGB(55, 55, 58))
			local rotor = dpart("Rotor", Vector3.new(0.06, 1.3, 1.3), CFrame.new(sx * 1.25, 0.32, sz * 1.25), Color3.fromRGB(25, 25, 26))
			rotor.Shape = Enum.PartType.Cylinder
		end
	end

	model.PrimaryPart = body
	model:SetAttribute("DroneId", id)
	model.Parent = Workspace
	return model
end

-- ---------------------------------------------------------------------------
-- Завершение полёта
-- ---------------------------------------------------------------------------
local function restoreOperator(player: Player)
	local char = player.Character
	if char then
		char:SetAttribute("OperatingDrone", nil)
		local humanoid = char:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.WalkSpeed = GameConfig.WalkSpeed
			humanoid.JumpPower = 50
		end
	end
end

local function cleanup(player: Player, reason: string, explodePos: Vector3?, hitResult: RaycastResult?)
	local d = drones[player]
	if not d then
		return
	end
	drones[player] = nil
	cooldowns[player] = os.clock() + DRONE_CFG.RespawnCooldown

	if d.DiedConn then
		d.DiedConn:Disconnect()
	end

	-- подрыв боевой части
	if explodePos then
		local spec = WeaponConfig.Charges.DroneWarhead
		ctx.Explosives.Explode(explodePos, player, {
			DirectPart = hitResult and hitResult.Instance or nil,
			DirectDamage = spec.DirectDamage,
			DirectType = spec.DirectType,
			DirectNormal = hitResult and hitResult.Normal or nil,
			DirectDirection = hitResult and d.Velocity.Unit or nil,
			SplashRadius = spec.SplashRadius,
			SplashDamage = spec.SplashDamage,
			SplashType = spec.SplashType,
			WeaponId = "FPVDrone",
		})
		d.Model:Destroy()
	else
		-- мягкая потеря: дрон падает и пропадает
		for _, p in ipairs(d.Model:GetDescendants()) do
			if p:IsA("BasePart") then
				p.Anchored = false
				p.CanCollide = true
			end
		end
		task.delay(4, function()
			if d.Model and d.Model.Parent then
				d.Model:Destroy()
			end
		end)
	end

	restoreOperator(player)
	ctx.Remotes.Get("Drone_State"):FireClient(player, { Active = false, Reason = reason })
end

-- Сбитие дрона стрелковым огнём (вызывается из WeaponService)
function DroneService.OnDroneShot(droneId: string, shooter: Player?)
	for player, d in pairs(drones) do
		if d.Id == droneId then
			cleanup(player, "shotdown")
			return
		end
	end
end

-- ---------------------------------------------------------------------------
-- Запуск и ввод
-- ---------------------------------------------------------------------------
local function onDroneRequest(player: Player)
	if not requestFlood(player) then
		return
	end
	if drones[player] then
		return
	end
	if (cooldowns[player] or 0) > os.clock() then
		return
	end

	local char, humanoid, root = Validation.AliveCharacter(player)
	if not char then
		return
	end
	local tool = char:FindFirstChildOfClass("Tool")
	if not tool or tool:GetAttribute("WeaponId") ~= "DroneTablet" then
		return -- планшет должен быть в руках
	end
	if humanoid.SeatPart then
		return
	end

	-- оператор замирает и уязвим
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	char:SetAttribute("OperatingDrone", true)

	local spawnCF = CFrame.new(root.Position + root.CFrame.LookVector * 4 + Vector3.new(0, 3, 0))
	local model = buildDroneModel(spawnCF)

	local look = root.CFrame.LookVector
	local d = {
		Id = model:GetAttribute("DroneId"),
		Model = model,
		Position = spawnCF.Position,
		Velocity = Vector3.zero,
		Yaw = math.atan2(-look.X, -look.Z),
		Pitch = 0,
		Axes = Vector3.zero,
		Battery = DRONE_CFG.BatterySeconds,
		PushAt = 0,
		DiedConn = humanoid.Died:Connect(function()
			cleanup(player, "operator_dead")
		end),
	}
	drones[player] = d

	ctx.Remotes.Get("Drone_State"):FireClient(player, {
		Active = true,
		Battery = d.Battery,
		Position = d.Position,
	})
end

local function onDroneInput(player: Player, yaw, pitch, axes)
	if not inputFlood(player) then
		return
	end
	local d = drones[player]
	if not d then
		return
	end
	if not Validation.IsFiniteNumber(yaw) or not Validation.IsFiniteNumber(pitch) then
		return
	end
	if not Validation.IsFiniteVector(axes) then
		return
	end
	d.Yaw = yaw
	d.Pitch = math.clamp(pitch, -1.35, 1.35)
	d.Axes = Vector3.new(
		math.clamp(axes.X, -1, 1),
		math.clamp(axes.Y, -1, 1),
		math.clamp(axes.Z, -1, 1)
	)
end

-- ---------------------------------------------------------------------------
-- Полётный цикл
-- ---------------------------------------------------------------------------
local function stepDrone(player: Player, d, dt: number)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then
		cleanup(player, "operator_dead")
		return
	end

	-- целевая скорость в системе дрона (yaw+pitch), вертикаль — мировая
	local orientCF = CFrame.Angles(0, d.Yaw, 0) * CFrame.Angles(d.Pitch, 0, 0)
	local targetVel = orientCF * Vector3.new(d.Axes.X, 0, -d.Axes.Z) * DRONE_CFG.MaxSpeed
		+ Vector3.new(0, d.Axes.Y * DRONE_CFG.MaxSpeed * 0.7, 0)

	-- инерция (damp)
	local alpha = math.min(1, DRONE_CFG.Acceleration * dt)
	d.Velocity = d.Velocity + (targetVel - d.Velocity) * alpha

	-- столкновения: рейкаст по вектору движения
	local newPos = d.Position + d.Velocity * dt
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { d.Model, char }

	local travel = newPos - d.Position
	if travel.Magnitude > 1e-4 then
		local hit = Workspace:Raycast(d.Position, travel, params)
		if hit then
			if d.Velocity.Magnitude >= DRONE_CFG.ExplodeSpeed then
				cleanup(player, "detonated", hit.Position, hit) -- КАМИКАДЗЕ: 750 HEAT в хитбокс
				return
			end
			-- мягкий отскок на малой скорости
			local n = hit.Normal
			d.Velocity = (d.Velocity - 2 * d.Velocity:Dot(n) * n) * 0.35
			newPos = hit.Position + n * 0.6
		end
	end
	d.Position = newPos

	-- батарея и радиус видеоканала
	d.Battery -= dt
	if d.Battery <= 0 then
		cleanup(player, "battery")
		return
	end
	if (d.Position - root.Position).Magnitude > DRONE_CFG.MaxRange then
		cleanup(player, "signal_lost")
		return
	end

	-- визуальные крены (Acro-стиль): тангаж по продольной скорости, крен по боковой
	local localVel = orientCF:VectorToObjectSpace(d.Velocity)
	local fwdTilt = math.clamp(-localVel.Z / DRONE_CFG.MaxSpeed, -1, 1) * math.rad(-22)
	local rollTilt = math.clamp(localVel.X / DRONE_CFG.MaxSpeed, -1, 1) * math.rad(-18)
	local visualCF = CFrame.new(d.Position)
		* CFrame.Angles(0, d.Yaw, 0)
		* CFrame.Angles(d.Pitch + fwdTilt, 0, rollTilt)
	d.Model:PivotTo(visualCF)

	-- телеметрия оператору
	if os.clock() > d.PushAt then
		d.PushAt = os.clock() + 0.05
		ctx.Remotes.Get("Drone_State"):FireClient(player, {
			Active = true,
			Battery = d.Battery,
			Position = d.Position,
		})
	end
end

-- ---------------------------------------------------------------------------
function DroneService.Init(deps)
	ctx = deps

	ctx.Remotes.Get("Drone_Request").OnServerEvent:Connect(onDroneRequest)
	ctx.Remotes.Get("Drone_Input").OnServerEvent:Connect(onDroneInput)
	ctx.Remotes.Get("Drone_Exit").OnServerEvent:Connect(function(player)
		if drones[player] then
			cleanup(player, "exit")
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		if drones[player] then
			cleanup(player, "exit")
		end
		cooldowns[player] = nil
	end)

	RunService.Heartbeat:Connect(function(dt)
		for player, d in pairs(drones) do
			stepDrone(player, d, dt)
		end
	end)
end

return DroneService
