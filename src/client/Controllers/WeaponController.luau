--!nonstrict
-- ============================================================================
-- WeaponController — клиентская сторона оружия.
--   * мгновенный локальный трассер/звук (отзывчивость), сервер всё валидирует
--   * детерминированный разброс по seed (клиент и сервер считают одинаково)
--   * динамический прицел: зазор = разброс
--   * оптический прицел СВД (FOV-зум + маска), перегрев ПКМ (локальное зеркало)
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
local burst = 0
local burstLast = 0

-- ---------------------------------------------------------------------------
-- Звук (placeholder: SoundId == 0 => тишина)
-- ---------------------------------------------------------------------------
local function playSound(weaponId: string, position: Vector3)
	local cfg = WeaponConfig.Get(weaponId)
	if not cfg or not cfg.SoundId or cfg.SoundId == 0 then
		return
	end
	local holder = Instance.new("Part")
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.Transparency = 1
	holder.CFrame = CFrame.new(position)
	holder.Parent = Workspace
	local sound = Instance.new("Sound")
	sound.SoundId = "rbxassetid://" .. cfg.SoundId
	sound.Volume = 0.7
	sound.RollOffMaxDistance = 500
	sound.Parent = holder
	sound:Play()
	task.delay(3, function()
		if holder.Parent then
			holder:Destroy()
		end
	end)
end

-- ---------------------------------------------------------------------------
-- Прицеливание (ПКМ)
-- ---------------------------------------------------------------------------
local function setZoom(fov: number)
	if not cam then
		cam = Workspace.CurrentCamera
	end
	local tween = TweenService:Create(cam, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { FieldOfView = fov })
	tween:Play()
end

local function updateAim()
	if not current then
		return
	end
	local cfg = current.Cfg
	if not cfg.ScopeFOV then
		return
	end
	local scoped = current.Scoped
	if scoped then
		setZoom(cfg.ScopeFOV)
		ctx.HUD.SetScope(true)
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

	if not cam then
		cam = Workspace.CurrentCamera
	end

	-- разброс (те же правила, что на сервере)
	if now - burstLast > 0.4 then
		burst = 0
	end
	burst += 1
	burstLast = now

	local bloom = WeaponConfig.ComputeBloom(cfg, burst)
	if cfg.HipBloom and not current.Scoped then
		bloom = cfg.HipBloom
	end
	local seed = rng:NextInteger(1, 2 ^ 31 - 1)
	local aimDir = cam.CFrame.LookVector
	local finalDir = WeaponConfig.ApplySpread(aimDir, seed, bloom)

	ammo.Mag -= 1
	ctx.HUD.SetAmmo(ammo.Mag, ammo.Reserve)
	ctx.HUD.SetCrosshairGap(6 + bloom * 3.2)

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
	playSound(current.Id, origin)

	-- лёгкая отдача камеры
	if cfg.FireMode == "Auto" then
		cam.CFrame = cam.CFrame * CFrame.Angles(-0.0025, 0, 0)
	elseif cfg.Id == "SniperRifle" then
		cam.CFrame = cam.CFrame * CFrame.Angles(-0.015, 0, 0)
	else
		cam.CFrame = cam.CFrame * CFrame.Angles(-0.004, 0, 0)
	end

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
	ctx.Remotes.Get("Weapon_Fire"):FireServer(current.Id, origin, aimDir, seed, Workspace:GetServerTimeNow(), current.Scoped == true)
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
			ctx.HUD.SetCrosshairGap(8)
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
			updateAim()
			ctx.HUD.SetScope(false)
			ctx.HUD.SetCrosshairVisible(false)
			ctx.HUD.SetHeat(nil)
			ctx.HUD.SetAmmo(nil)
			current = nil
		end
	end)

	bindTool(tool)
end

-- ---------------------------------------------------------------------------
function WeaponController.Init(deps)
	ctx = deps

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
		if payload.ReloadIn and payload.ReloadIn > 0 then
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

	-- прицеливание (ПКМ)
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed or not current then
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

	-- цикл автоматического огня
	RunService.Heartbeat:Connect(function()
		if firing then
			tryFire()
		end
		-- охлаждение ствола (зеркало)
		if current and current.Cfg and current.Cfg.Overheat and current.Heat > 0 and os.clock() > (current.VentUntil or 0) then
			current.Heat = math.max(0, current.Heat - current.Cfg.Overheat.CoolPerSec / 60)
			ctx.HUD.SetHeat(current.Heat / 100)
		end
	end)
end

return WeaponController
