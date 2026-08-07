--!nonstrict
-- ============================================================================
-- WeaponController — клиентская сторона оружия.
--   * мгновенный локальный трассер/звук (отзывчивость), сервер всё валидирует
--   * детерминированный разброс по seed (клиент и сервер считают одинаково)
--   * накопительная PUBG-подобная отдача: вертикальный рост, горизонтальный
--     паттерн с вариацией и пружинный camera kick с плавным возвратом
--   * прицеливание: СВД — оптика (FOV-зум + маска), прочее — AimFOV из настроек
--   * прицел: статичный/динамический, зазор и цвет — из настроек (Settings)
--   * инструменты: C4 (рейкаст до 4 м), детонатор, ПТ-мины
-- ============================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Ballistics = require(Shared.Combat.Ballistics)
local WeaponConfig = require(Shared.Config.WeaponConfig)

local WeaponController = {}

local ctx
local player = Players.LocalPlayer
local rng = Random.new()

local cam = Workspace.CurrentCamera
local baseFOV = 70

local current = nil -- активный инструмент: { Id, Cfg, ... }
local firing = false
local ammoCache = {} -- [weaponId] = { Mag, Reserve } (авторитет от сервера)
local nextShotAt = 0
local burst = 0 -- накопленные «выстрелы» bloom; может быть дробным при восстановлении
local burstLast = 0

-- Отдача хранится как угловой offset камеры в радианах. На камеру применяется
-- только дельта offset'а: это позволяет игроку тянуть мышь вниз и контролировать
-- очередь, а не перезаписывает ввод абсолютным CFrame каждый кадр.
local recoilTargetP, recoilTargetY = 0, 0
local recoilP, recoilY = 0, 0
local recoilVelP, recoilVelY = 0, 0
local recoilAppliedP, recoilAppliedY = 0, 0
local recoilShot = 0
local recoilLast = 0
local recoilPatternSign = 1
local recoilProfile = nil
local recoilCamera = cam


-- ---------------------------------------------------------------------------
-- Прицеливание (ПКМ)
-- ---------------------------------------------------------------------------
local function setZoom(fov: number)
	if not cam then
		cam = Workspace.CurrentCamera
	end
	if not cam then
		return
	end
	local tween = TweenService:Create(cam, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { FieldOfView = fov })
	tween:Play()
end

local function aimFOV(): number
	if ctx.Settings then
		return ctx.Settings.Get("AimFOV")
	end
	return 58
end

-- Безопасно для нестрелковых инструментов (C4/детонатор/мина/планшет):
-- у них нет Cfg, прицеливание просто отключается.
local function updateAim()
	local cfg = current and current.Cfg
	local scoped = current ~= nil and current.Scoped == true

	if cfg and cfg.ScopeFOV and scoped then
		setZoom(cfg.ScopeFOV)
		ctx.HUD.SetScope(true)
	elseif cfg and scoped then
		setZoom(aimFOV())
		ctx.HUD.SetScope(false)
	else
		setZoom(baseFOV)
		ctx.HUD.SetScope(false)
	end
end

-- ---------------------------------------------------------------------------
-- Перезарядка
-- ---------------------------------------------------------------------------
local startReload

-- ---------------------------------------------------------------------------
-- Отдача
-- ---------------------------------------------------------------------------
local function addRecoil(cfg, humanoid: Humanoid, now: number)
	local profile = cfg.Recoil
	if not profile then
		return
	end

	if now - recoilLast > (profile.RecoveryDelay or 0.15) then
		recoilShot = 0
		recoilPatternSign = rng:NextNumber() < 0.5 and -1 or 1
	end
	recoilShot += 1
	if recoilShot > 1 and rng:NextNumber() < (profile.PatternChangeChance or 0) then
		recoilPatternSign *= -1
	end

	local growth = math.min(1 + (recoilShot - 1) * (profile.GrowthPerShot or 0), profile.MaxGrowth or 1)
	local stanceMultiplier = current and current.Scoped and (profile.ADSMultiplier or 1) or (profile.HipMultiplier or 1)
	local movementAlpha = math.clamp(humanoid.MoveDirection.Magnitude, 0, 1)
	local movementMultiplier = 1 + ((profile.MovementMultiplier or 1) - 1) * movementAlpha
	local airborneMultiplier = humanoid.FloorMaterial == Enum.Material.Air and (profile.AirborneMultiplier or 1) or 1
	local multiplier = growth * stanceMultiplier * movementMultiplier * airborneMultiplier

	local vertical = rng:NextNumber(profile.VerticalMin or 0.5, profile.VerticalMax or profile.VerticalMin or 0.8) * multiplier
	local patternValue = 0
	local pattern = profile.Pattern
	if type(pattern) == "table" and #pattern > 0 then
		patternValue = pattern[((recoilShot - 1) % #pattern) + 1] * recoilPatternSign
	else
		patternValue = rng:NextNumber(-1, 1)
	end
	local jitter = rng:NextNumber(-1, 1) * (profile.HorizontalJitter or 0.3)
	local horizontal = (patternValue + jitter) * (profile.Horizontal or 0.2) * multiplier

	recoilTargetP = math.clamp(recoilTargetP + math.rad(vertical), 0, math.rad(profile.MaxVertical or 15))
	recoilTargetY = math.clamp(recoilTargetY + math.rad(horizontal), -math.rad(profile.MaxHorizontal or 5), math.rad(profile.MaxHorizontal or 5))

	-- Небольшой импульс поверх накопленной цели создаёт резкий camera kick,
	-- после которого пружина стабилизируется на новом уровне отдачи.
	local frequency = profile.SpringFrequency or 18
	local kick = profile.CameraKick or 0.25
	recoilVelP += math.rad(vertical) * frequency * kick
	recoilVelY += math.rad(horizontal) * frequency * kick * 0.75
	recoilLast = now
	recoilProfile = profile
end

-- ---------------------------------------------------------------------------
-- Выстрел
-- ---------------------------------------------------------------------------
local function tryFire()
	if not current then
		return
	end
	local cfg = current.Cfg
	local char = player.Character
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end
	if humanoid.SeatPart then
		return -- из техники не стреляем
	end
	if char:GetAttribute("OperatingDrone") then
		return
	end

	local now = os.clock()
	local shotTimestamp = Workspace:GetServerTimeNow()
	local ammo = ammoCache[current.Id]
	if not ammo then
		ammo = { Mag = cfg.MagSize, Reserve = cfg.ReserveAmmo }
		ammoCache[current.Id] = ammo
	end

	if ammo.Mag <= 0 then
		if ammo.Reserve > 0 and now > (current.ReloadEnd or 0) then
			startReload()
		end
		return
	end
	if now < (current.ReloadEnd or 0) or now < (current.VentUntil or 0) then
		return
	end
	if now < nextShotAt then
		return
	end
	nextShotAt = now + 60 / cfg.RPM

	cam = Workspace.CurrentCamera
	if not cam then
		return
	end

	-- Разброс восстанавливается плавно после короткой паузы. Сервер считает
	-- то же состояние по времени принятых выстрелов и остаётся авторитетным.
	burst = WeaponConfig.RecoverBloom(cfg, burst, shotTimestamp - burstLast)
	local movementAlpha = math.clamp(humanoid.MoveDirection.Magnitude, 0, 1)
	local airborne = humanoid.FloorMaterial == Enum.Material.Air
	local bloom = WeaponConfig.ComputeBloom(cfg, burst + 1, current.Scoped == true, movementAlpha, airborne)
	burst += 1
	burstLast = shotTimestamp
	local seed = rng:NextInteger(1, 2 ^ 31 - 1)
	local aimDir = cam.CFrame.LookVector
	local finalDir = WeaponConfig.ApplySpread(aimDir, seed, bloom)

	ammo.Mag -= 1
	ctx.HUD.SetAmmo(ammo.Mag, ammo.Reserve)

	-- динамический прицел (только если включён в настройках)
	if ctx.Settings and ctx.Settings.Get("CrosshairDynamic") then
		ctx.HUD.SetCrosshairTarget(ctx.Settings.Get("CrosshairGap") + bloom * 3.2)
	end

	-- локальный трассер + звук (визуал)
	local origin = cam.CFrame.Position
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
	local style = cfg.Id == "RPG" and Color3.fromRGB(220, 170, 90) or Color3.fromRGB(255, 205, 100)
	ctx.FX.AttachTracer(cast, style, cfg.Id == "RPG" and 0.7 or 0.28)
	cast.OnHit:Connect(function(result)
		ctx.FX.Impact(result.Position, result.Normal)
	end)
	ctx.FX.PlayWeaponSound(current.Id, origin)

	addRecoil(cfg, humanoid, now)

	-- перегрев ПКМ (зеркало; сервер поправит)
	if cfg.Overheat then
		current.Heat = math.min(100, (current.Heat or 0) + cfg.Overheat.PerShot)
		if current.Heat >= 100 then
			current.VentUntil = now + cfg.Overheat.VentTime
			ctx.HUD.SetVenting(true)
			task.delay(cfg.Overheat.VentTime, function()
				if current then
					ctx.HUD.SetVenting(false)
				end
			end)
		end
		ctx.HUD.SetHeat(current.Heat / 100)
	end

	-- серверу: вектор + timestamp + seed
	ctx.Remotes.Get("Weapon_Fire"):FireServer(current.Id, origin, aimDir, seed, shotTimestamp, current.Scoped == true)
end

-- ---------------------------------------------------------------------------
-- Перезарядка
-- ---------------------------------------------------------------------------
startReload = function()
	if not current then
		return
	end
	local cfg = current.Cfg
	local ammo = ammoCache[current.Id]
	if not ammo then
		return
	end
	local now = os.clock()
	if ammo.Mag >= cfg.MagSize or ammo.Reserve <= 0 or now < (current.ReloadEnd or 0) then
		return
	end
	current.ReloadEnd = now + cfg.ReloadTime
	ctx.HUD.SetReloading(true)
	ctx.Remotes.Get("Weapon_Reload"):FireServer(current.Id)
	task.delay(cfg.ReloadTime, function()
		if current and current.Id == current.Id then
			ctx.HUD.SetReloading(false)
		end
	end)
end

-- ---------------------------------------------------------------------------
-- Инструменты (C4 / детонатор / мины)
-- ---------------------------------------------------------------------------
local function placeC4()
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root or not cam then
		return
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { char }
	local result = Workspace:Raycast(cam.CFrame.Position, cam.CFrame.LookVector * 4.5, params)
	if result then
		local normal = result.Normal
		local hitPos = result.Position
		ctx.Remotes.Get("C4_Place"):FireServer(result.Instance, CFrame.new(hitPos + normal * 0.3))
		ctx.HUD.Notify("C4 установлена")
	else
		ctx.HUD.Notify("Слишком далеко (4 м)")
	end
end

local function placeMine()
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local position = (root.CFrame * CFrame.new(0, 0, -3)).Position
	ctx.Remotes.Get("Mine_Place"):FireServer(position)
	ctx.HUD.Notify("Мина установлена (взведётся через 2.5 с)")
end

-- ---------------------------------------------------------------------------
-- Привязка инструментов
-- ---------------------------------------------------------------------------
local function bindTool(tool: Tool)
	local id = tool:GetAttribute("WeaponId")
	if not id then
		return
	end
	local cfg = WeaponConfig.Get(id)

	if cfg then
		tool.Activated:Connect(function()
			if cfg.FireMode == "Auto" then
				firing = true
			else
				tryFire()
			end
		end)
		tool.Deactivated:Connect(function()
			firing = false
		end)
	elseif id == "C4Charge" then
		tool.Activated:Connect(placeC4)
	elseif id == "Detonator" then
		tool.Activated:Connect(function()
			ctx.Remotes.Get("C4_Detonate"):FireServer()
		end)
	elseif id == "Landmine" then
		tool.Activated:Connect(placeMine)
	end
	-- DroneTablet обрабатывает DroneController
end

local function trackTool(tool: Tool)
	local id = tool:GetAttribute("WeaponId")
	if not id then
		return
	end

	tool.Equipped:Connect(function()
		burst = 0
		burstLast = 0
		recoilShot = 0
		recoilLast = 0
		current = {
			Id = id,
			Cfg = WeaponConfig.Get(id),
			Scoped = false,
			Heat = 0,
			ReloadEnd = 0,
			VentUntil = 0,
		}
		if current.Cfg then
			ctx.HUD.SetWeapon(current.Cfg.DisplayName)
			local ammo = ammoCache[id]
			ctx.HUD.SetAmmo(ammo and ammo.Mag, ammo and ammo.Reserve)
			ctx.HUD.SetCrosshairVisible(true)
			ctx.HUD.SetHeat(current.Cfg.Overheat and 0 or nil)
		else
			ctx.HUD.SetWeapon(id)
			ctx.HUD.SetAmmo(nil)
			ctx.HUD.SetCrosshairVisible(true)
			ctx.HUD.SetHeat(nil)
		end
	end)

	tool.Unequipped:Connect(function()
		if current and current.Id == id then
			firing = false
			current.Scoped = false
			current = nil
			updateAim()
			ctx.HUD.SetScope(false)
			ctx.HUD.SetCrosshairVisible(false)
			ctx.HUD.SetHeat(nil)
			ctx.HUD.SetAmmo(nil)
		end
	end)

	bindTool(tool)
end

-- ---------------------------------------------------------------------------
function WeaponController.Init(deps)
	ctx = deps

	-- Отдача применяется ПОСЛЕ стандартного камер-скрипта (иначе он её затирает).
	RunService:BindToRenderStep("ArenaRecoil", Enum.RenderPriority.Camera.Value + 1, function(dt)
		local profile = recoilProfile
		if not profile then
			return
		end
		dt = math.min(dt, 1 / 30)

		if os.clock() - recoilLast > (profile.RecoveryDelay or 0.15) then
			local returnAlpha = 1 - math.exp(-(profile.RecoverySpeed or 7) * dt)
			recoilTargetP += (0 - recoilTargetP) * returnAlpha
			recoilTargetY += (0 - recoilTargetY) * returnAlpha
		end

		local frequency = profile.SpringFrequency or 18
		local damping = profile.SpringDamping or 0.92
		local stiffness = frequency * frequency
		local drag = 2 * damping * frequency
		recoilVelP += (stiffness * (recoilTargetP - recoilP) - drag * recoilVelP) * dt
		recoilVelY += (stiffness * (recoilTargetY - recoilY) - drag * recoilVelY) * dt
		recoilP += recoilVelP * dt
		recoilY += recoilVelY * dt

		if math.abs(recoilTargetP) < 1e-5 and math.abs(recoilP) < 1e-5 and math.abs(recoilVelP) < 1e-4 then
			recoilTargetP, recoilP, recoilVelP = 0, 0, 0
		end
		if math.abs(recoilTargetY) < 1e-5 and math.abs(recoilY) < 1e-5 and math.abs(recoilVelY) < 1e-4 then
			recoilTargetY, recoilY, recoilVelY = 0, 0, 0
		end

		local camera = Workspace.CurrentCamera
		if not camera then
			return
		end
		if camera ~= recoilCamera then
			recoilCamera = camera
			recoilAppliedP, recoilAppliedY = 0, 0
		end
		local deltaP = recoilP - recoilAppliedP
		local deltaY = recoilY - recoilAppliedY
		if deltaP ~= 0 or deltaY ~= 0 then
			camera.CFrame = camera.CFrame * CFrame.Angles(deltaP, deltaY, 0)
			recoilAppliedP, recoilAppliedY = recoilP, recoilY
		end
	end)

	-- синхронизация с сервером (боеприпасы/перегрев/перезарядка)
	ctx.Remotes.Get("Weapon_Sync").OnClientEvent:Connect(function(payload)
		if payload.Ammo then
			for id, a in pairs(payload.Ammo) do
				ammoCache[id] = { Mag = a.Mag, Reserve = a.Reserve }
				if current and current.Id == id then
					ctx.HUD.SetAmmo(a.Mag, a.Reserve)
				end
			end
		end
		if current and current.Cfg and current.Cfg.Overheat then
			if payload.Heat ~= nil then
				current.Heat = payload.Heat
				ctx.HUD.SetHeat(current.Heat / 100)
			end
			if payload.VentIn and payload.VentIn > 0 then
				current.VentUntil = os.clock() + payload.VentIn
				ctx.HUD.SetVenting(true)
				task.delay(payload.VentIn, function()
					if current then
						ctx.HUD.SetVenting(false)
					end
				end)
			end
		end
		if payload.ReloadIn and payload.ReloadIn > 0 and current then
			current.ReloadEnd = os.clock() + payload.ReloadIn
			ctx.HUD.SetReloading(true)
			task.delay(payload.ReloadIn, function()
				ctx.HUD.SetReloading(false)
			end)
		end
	end)

	-- хитмаркеры
	ctx.Remotes.Get("FX_Hitmarker").OnClientEvent:Connect(function(kind)
		ctx.HUD.Hitmarker(kind)
	end)

	-- киллфид
	ctx.Remotes.Get("Killfeed").OnClientEvent:Connect(function(attackerName, victimLabel, weaponId)
		local weaponName = (WeaponConfig.Get(weaponId) and WeaponConfig.Get(weaponId).DisplayName) or weaponId or ""
		local left = attackerName or "???"
		ctx.HUD.Killfeed(("%s  »  %s  [%s]"):format(left, tostring(victimLabel), weaponName))
	end)

	-- отслеживание инструментов (рюкзак и персонаж)
	local function scan(container: Instance)
		for _, tool in ipairs(container:GetChildren()) do
			if tool:IsA("Tool") then
				trackTool(tool)
			end
		end
	end
	player.Backpack.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then
			trackTool(child)
		end
	end)
	player.CharacterAdded:Connect(function(char)
		char.ChildAdded:Connect(function(child)
			if child:IsA("Tool") then
				trackTool(child)
			end
		end)
		scan(char)
	end)
	if player.Character then
		scan(player.Character)
	end
	scan(player.Backpack)

	-- горячая клавиша R
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end
		if input.KeyCode == Enum.KeyCode.R then
			startReload()
		end
	end)

	-- прицеливание (ПКМ) — только для оружия с Cfg
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed or not current or not current.Cfg then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			current.Scoped = true
			updateAim()
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton2 and current then
			current.Scoped = false
			updateAim()
		end
	end)

	-- цикл автоматического огня + охлаждение ствола (зеркало)
	RunService.Heartbeat:Connect(function(dt)
		if firing then
			tryFire()
		end
		if current and current.Cfg and current.Cfg.Overheat and current.Heat > 0 and os.clock() > (current.VentUntil or 0) then
			current.Heat = math.max(0, current.Heat - current.Cfg.Overheat.CoolPerSec * dt)
			ctx.HUD.SetHeat(current.Heat / 100)
		end
	end)
end

return WeaponController
