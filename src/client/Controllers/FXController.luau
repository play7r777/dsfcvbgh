--!nonstrict
-- ============================================================================
-- FXController — визуальные эффекты боя:
--   * трассеры других игроков (серверный FX_Shot) с падением пули
--   * подавление: трасса ПКМ рядом с камерой -> вспышка по краям экрана
--   * искры от попаданий, вспышки
--   * пространственные звуки локальных и удалённых выстрелов из WeaponConfig
-- ============================================================================

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Ballistics = require(Shared.Combat.Ballistics)
local VehicleConfig = require(Shared.Config.VehicleConfig)
local WeaponConfig = require(Shared.Config.WeaponConfig)

local FXController = {}

local ctx
local soundRng = Random.new()

-- Стили трассеров: цвет и толщина (RPG — толстый дымный след)
local TRACER_STYLE = {
	AssaultRifle = { Color = Color3.fromRGB(255, 205, 100), Size = 0.28 },
	Pistol = { Color = Color3.fromRGB(255, 235, 190), Size = 0.22 },
	SniperRifle = { Color = Color3.fromRGB(190, 225, 255), Size = 0.3 },
	LMG = { Color = Color3.fromRGB(255, 160, 70), Size = 0.34 },
	RPG = { Color = Color3.fromRGB(220, 170, 90), Size = 0.7 },
	TankCannon = { Color = Color3.fromRGB(255, 255, 240), Size = 0.8 },
}

local function tracerStyle(weaponId: string)
	return TRACER_STYLE[weaponId] or { Color = Color3.fromRGB(255, 230, 160), Size = 0.28 }
end

local function toAssetUri(assetId): string?
	if type(assetId) == "number" and assetId > 0 then
		return "rbxassetid://" .. tostring(math.floor(assetId))
	end
	if type(assetId) == "string" then
		if assetId:match("^rbxassetid://%d+$") then
			return assetId
		end
		if assetId:match("^%d+$") then
			return "rbxassetid://" .. assetId
		end
	end
	return nil
end

-- Публичная точка воспроизведения нужна и локальному оружию, и FX_Shot.
-- SoundId сохраняется как совместимый fallback; общий fallback используется,
-- если конкретный профиль не указал пригодный asset id.
function FXController.PlayWeaponSound(weaponId: string, position: Vector3)
	if typeof(position) ~= "Vector3" then
		return
	end

	local cfg = WeaponConfig.Get(weaponId)
	local soundConfig
	local assetId
	if cfg then
		soundConfig = cfg.Sound or {}
		assetId = cfg.SoundId
	elseif weaponId == "TankCannon" then
		soundConfig = VehicleConfig.Tank.Cannon.Sound or {}
		assetId = VehicleConfig.Tank.Cannon.SoundId
	else
		return
	end
	if type(soundConfig.Ids) == "table" and #soundConfig.Ids > 0 then
		assetId = soundConfig.Ids[soundRng:NextInteger(1, #soundConfig.Ids)]
	elseif soundConfig.Id ~= nil then
		assetId = soundConfig.Id
	end
	local assetUri = toAssetUri(assetId) or toAssetUri(WeaponConfig.DefaultSoundId)
	if not assetUri then
		return
	end

	local listenerCamera = Workspace.CurrentCamera
	if listenerCamera and (listenerCamera.CFrame.Position - position).Magnitude > (soundConfig.RollOffMaxDistance or 650) then
		return
	end

	local holder = Instance.new("Part")
	holder.Name = "WeaponSoundEmitter"
	holder.Size = Vector3.one
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.Transparency = 1
	holder.CFrame = CFrame.new(position)
	holder.Parent = Workspace

	local speedMin = soundConfig.PlaybackSpeedMin or 0.98
	local speedMax = math.max(soundConfig.PlaybackSpeedMax or 1.02, speedMin)
	local volumeVariation = math.clamp(soundConfig.VolumeVariation or 0.04, 0, 0.2)
	local sound = Instance.new("Sound")
	sound.Name = weaponId .. "Shot"
	sound.SoundId = assetUri
	sound.Volume = (soundConfig.Volume or 0.8) * soundRng:NextNumber(1 - volumeVariation, 1 + volumeVariation)
	sound.PlaybackSpeed = soundRng:NextNumber(speedMin, speedMax)
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = soundConfig.RollOffMinDistance or 15
	sound.RollOffMaxDistance = soundConfig.RollOffMaxDistance or 650
	sound.Parent = holder
	sound.Ended:Once(function()
		if holder.Parent then
			holder:Destroy()
		end
	end)
	sound:Play()
	Debris:AddItem(holder, soundConfig.Lifetime or 6)
end

-- ---------------------------------------------------------------------------
-- Локальный трассер на уже созданный каст
-- ---------------------------------------------------------------------------
function FXController.AttachTracer(cast, color: Color3, thickness: number)
	local sphere = Instance.new("Part")
	sphere.Shape = Enum.PartType.Ball
	sphere.Size = Vector3.one * thickness
	sphere.Color = color
	sphere.Material = Enum.Material.Neon
	sphere.Anchored = true
	sphere.CanCollide = false
	sphere.CanQuery = false
	sphere.CastShadow = false
	sphere.Parent = Workspace

	local trail = Instance.new("Trail")
	trail.Transparency = NumberSequence.new(0.35, 1)
	trail.Color = ColorSequence.new(color)
	trail.Lifetime = 0.18
	trail.WidthScale = NumberSequence.new(1, 0.2)
	trail.FaceCamera = true
	trail.Parent = sphere

	local alive = true
	cast.OnStep:Connect(function(_, position)
		if alive then
			sphere.CFrame = CFrame.new(position)
		end
	end)
	local function kill()
		if not alive then
			return
		end
		alive = false
		sphere.CanCollide = false
		task.delay(0.25, function()
			if sphere.Parent then
				sphere:Destroy()
			end
		end)
	end
	cast.OnTerminating:Connect(kill)
	cast.OnHit:Connect(function(result)
		FXController.Impact(result.Position, result.Normal)
		kill()
	end)
end

-- ---------------------------------------------------------------------------
-- Искры от попадания
-- ---------------------------------------------------------------------------
function FXController.Impact(position: Vector3, normal: Vector3?)
	local p = Instance.new("Part")
	p.Size = Vector3.one
	p.Transparency = 1
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CFrame = CFrame.new(position)
	p.Parent = Workspace

	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(Color3.fromRGB(255, 220, 140), Color3.fromRGB(120, 90, 50))
	emitter.Lifetime = NumberRange.new(0.08, 0.2)
	emitter.Speed = NumberRange.new(8, 22)
	emitter.SpreadAngle = Vector2.new(45, 45)
	emitter.Rate = 0
	emitter.Parent = p
	emitter:Emit(10)

	task.delay(0.6, function()
		if p.Parent then
			p:Destroy()
		end
	end)
end

-- ---------------------------------------------------------------------------
-- Трасса чужого выстрела + подавление
-- ---------------------------------------------------------------------------
local function onRemoteShot(userId: number, weaponId, origin: Vector3, direction: Vector3)
	if typeof(origin) ~= "Vector3" or typeof(direction) ~= "Vector3" then
		return
	end
	local style = tracerStyle(weaponId)
	FXController.PlayWeaponSound(weaponId, origin)

	local localChar = Players.LocalPlayer.Character
	local localHead = localChar and localChar:FindFirstChild("Head")

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	if localChar then
		params.FilterDescendantsInstances = { localChar }
	end

	local speed, gravityFactor, maxRange = 800, 1, 1000
	local cfg = WeaponConfig.Get(weaponId)
	if weaponId == "TankCannon" then
		local cannon = VehicleConfig.Tank.Cannon
		speed, gravityFactor, maxRange = cannon.ProjectileSpeed, cannon.GravityFactor, cannon.MaxRange
	elseif cfg then
		speed, gravityFactor, maxRange = cfg.ProjectileSpeed, cfg.GravityFactor, cfg.MaxRange
	end
	local cast = Ballistics.Fire({
		Origin = origin,
		Direction = direction,
		Speed = speed,
		Gravity = Vector3.new(0, -Workspace.Gravity * gravityFactor, 0),
		MaxDistance = maxRange,
		RaycastParams = params,
	})
	FXController.AttachTracer(cast, style.Color, style.Size)

	-- подавление: трасса ближе SuppressionRadius к голове игрока
	local suppRadius = (cfg and cfg.SuppressionRadius) or 0
	if suppRadius > 0 and localHead then
		local pulsed = false
		cast.OnStep:Connect(function(last, pos)
			if pulsed then
				return
			end
			-- расстояние от головы до отрезка [last, pos]
			local ab = pos - last
			local t = math.clamp((localHead.Position - last):Dot(ab) / math.max(ab.Magnitude ^ 2, 1e-6), 0, 1)
			local closest = last + ab * t
			if (localHead.Position - closest).Magnitude < suppRadius then
				pulsed = true
				ctx.HUD.SuppressionPulse()
			end
		end)
	end
end

-- ---------------------------------------------------------------------------
function FXController.Init(deps)
	ctx = deps

	ctx.Remotes.Get("FX_Shot").OnClientEvent:Connect(onRemoteShot)
end

return FXController
