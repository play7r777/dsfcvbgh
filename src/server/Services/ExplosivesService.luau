--!nonstrict
-- ============================================================================
-- ExplosivesService — C4 (липучка + детонатор), противотанковые мины и
-- единая функция взрыва Explode() для РПГ / пушки танка / дрона.
--
-- C4:   сервер валидирует рейкаст клиента (<= 5.5 studs), варп-заряд
--       приваривается WeldConstraint'ом к конкретной детали (в т.ч. танка).
--       800 HEAT; на Hitbox_Engine / Hitbox_AmmoRack — мгновенный вывод
--       модуля / подрыв боеукладки (InstantModuleKill).
-- Мины: ставит инженер; сервер опрашивает Spatial Query; наезд техники =
--       650 HE + гарантированный срыв гусениц. Лёгкая техника гибнет сразу.
-- ============================================================================

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local DamageTypes = require(Shared.Combat.DamageTypes)
local GameConfig = require(Shared.Config.GameConfig)
local HitboxTags = require(Shared.Combat.HitboxTags)
local Validation = require(Shared.Util.Validation)
local WeaponConfig = require(Shared.Config.WeaponConfig)

local ExplosivesService = {}

local ctx
local charges = {} -- [Player] = { C4 = n, Mine = n }
local activeC4 = {} -- [Player] = { Part, ... }
local mines = {} -- { Part, ... }
local placeFlood = Validation.NewFloodCheck(4)

-- ---------------------------------------------------------------------------
-- Утилиты
-- ---------------------------------------------------------------------------

-- Humanoid по попавшей детали (или nil)
function ExplosivesService.FindHumanoid(part: Instance): Humanoid?
	if not part then
		return nil
	end
	local model = part:FindFirstAncestorOfClass("Model")
	if not model then
		return nil
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		return humanoid
	end
	return nil
end

local function isFiniteCFrame(cf): boolean
	if typeof(cf) ~= "CFrame" then
		return false
	end
	local p = cf.Position
	return Validation.IsFiniteVector(p) and Validation.IsFiniteVector(cf.LookVector)
end

-- ---------------------------------------------------------------------------
-- Единый взрыв
-- spec: { DirectPart?, DirectDamage?, DirectType?, DirectNormal?, DirectDirection?,
--         InstantModuleKill?, SplashRadius?, SplashDamage?, SplashType?, WeaponId? }
-- ---------------------------------------------------------------------------
function ExplosivesService.Explode(position: Vector3, attacker: Player?, spec)
	-- визуал и физический толчок (урон — наш кастомный)
	local explosion = Instance.new("Explosion")
	explosion.Position = position
	explosion.BlastRadius = spec.SplashRadius or 8
	explosion.BlastPressure = 250000
	explosion.DestroyJointRadiusPercent = 0
	explosion.ExplosionType = Enum.ExplosionType.NoCraters
	explosion.Parent = Workspace

	-- прямое попадание
	local directHumanoid = nil
	local directState = nil
	if spec.DirectPart and spec.DirectPart.Parent then
		directState = ctx.Armor.GetStateFromPart(spec.DirectPart)
		if directState then
			ctx.Armor.ApplyHit(directState, spec.DirectPart, spec.DirectDamage or 0, spec.DirectType or DamageTypes.HE, attacker, {
				Normal = spec.DirectNormal,
				Direction = spec.DirectDirection,
				InstantModuleKill = spec.InstantModuleKill,
			})
		else
			directHumanoid = ExplosivesService.FindHumanoid(spec.DirectPart)
			if directHumanoid then
				ctx.Damage.Damage(attacker, directHumanoid, spec.DirectDamage or 0, { WeaponId = spec.WeaponId or "Explosion" })
			end
		end
	end

	-- фугасный круг
	local radius = spec.SplashRadius
	if not radius or radius <= 0 then
		return
	end

	local parts = Workspace:GetPartBoundsInRadius(position, radius, nil)
	local humanoids = {}
	local vehicles = {} -- state -> { part, dist }
	for _, p in ipairs(parts) do
		local state = ctx.Armor.GetStateFromPart(p)
		if state then
			local d = (p.Position - position).Magnitude
			local cur = vehicles[state]
			if not cur or d < cur.dist then
				vehicles[state] = { part = p, dist = d }
			end
		else
			local humanoid = ExplosivesService.FindHumanoid(p)
			if humanoid and humanoid ~= directHumanoid then
				humanoids[humanoid] = true
			end
		end
	end

	-- урон по пехоте с проверкой линии видимости (укрытия работают)
	for humanoid in pairs(humanoids) do
		local root = humanoid.Parent and humanoid.Parent:FindFirstChild("HumanoidRootPart")
		if root then
			local offset = root.Position - position
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			params.FilterDescendantsInstances = { humanoid.Parent }
			local blocked = Workspace:Raycast(position, offset, params)
			if not blocked then
				local falloff = 1 - 0.7 * math.clamp(offset.Magnitude / radius, 0, 1)
				ctx.Damage.Damage(attacker, humanoid, (spec.SplashDamage or 0) * falloff, { WeaponId = spec.WeaponId or "Explosion" })
			end
		end
	end

	-- урон по технике (одна ближайшая деталь на машину)
	for state, info in pairs(vehicles) do
		if state ~= directState then
			local falloff = 1 - 0.7 * math.clamp(info.dist / radius, 0, 1)
			ctx.Armor.ApplyHit(state, info.part, (spec.SplashDamage or 0) * falloff, spec.SplashType or DamageTypes.HE, attacker, nil)
		end
	end
end

-- ---------------------------------------------------------------------------
-- Заряды игрока
-- ---------------------------------------------------------------------------
function ExplosivesService.ResetCharges(player: Player)
	charges[player] = {
		C4 = GameConfig.C4ChargesPerLife,
		Mine = GameConfig.MineChargesPerLife,
	}
end

function ExplosivesService.AddCharges(player: Player, kind: string, amount: number)
	local c = charges[player]
	if c and c[kind] then
		c[kind] = math.min(6, c[kind] + amount)
	end
end

function ExplosivesService.GetCharges(player: Player, kind: string): number
	local c = charges[player]
	return (c and c[kind]) or 0
end

-- ---------------------------------------------------------------------------
-- C4
-- ---------------------------------------------------------------------------
local function onC4Place(player: Player, hitPart: Instance, hitCFrame: CFrame)
	if not placeFlood(player) then
		return
	end
	local char, _, root = Validation.AliveCharacter(player)
	if not char then
		return
	end

	-- в руках должна быть именно C4
	local tool = char:FindFirstChildOfClass("Tool")
	if not tool or tool:GetAttribute("WeaponId") ~= "C4Charge" then
		return
	end
	if ExplosivesService.GetCharges(player, "C4") <= 0 then
		return
	end

	-- цель: реальная деталь мира/техники, не персонаж
	if typeof(hitPart) ~= "Instance" or not hitPart:IsA("BasePart") or not hitPart:IsDescendantOf(Workspace) then
		return
	end
	if ExplosivesService.FindHumanoid(hitPart) then
		return
	end
	if not isFiniteCFrame(hitCFrame) then
		return
	end
	if (root.Position - hitCFrame.Position).Magnitude > 5.5 then
		return -- клиентский рейкаст на 4 м + допуск на лаг
	end

	charges[player].C4 -= 1

	local charge = Instance.new("Part")
	charge.Name = "C4Charge"
	charge.Size = Vector3.new(1.2, 0.5, 0.8)
	charge.CFrame = hitCFrame
	charge.Color = Color3.fromRGB(86, 76, 56)
	charge.Material = Enum.Material.SmoothPlastic
	charge.Anchored = false
	charge.CanCollide = false
	charge.Massless = true
	charge:SetAttribute("OwnerUserId", player.UserId)
	charge.Parent = Workspace

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = charge
	weld.Part1 = hitPart
	weld.Parent = charge

	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 60, 40)
	light.Range = 4
	light.Brightness = 1.5
	light.Parent = charge

	activeC4[player] = activeC4[player] or {}
	table.insert(activeC4[player], charge)

	-- лимит одновременно активных зарядов: самый старый обезвреживается
	if #activeC4[player] > GameConfig.MaxActiveC4 then
		local oldest = table.remove(activeC4[player], 1)
		if oldest and oldest.Parent then
			oldest:Destroy()
		end
	end
end

local function onC4Detonate(player: Player)
	local list = activeC4[player]
	if not list or #list == 0 then
		return
	end
	activeC4[player] = {}

	local spec = WeaponConfig.Charges.C4
	for i, charge in ipairs(list) do
		task.delay(0.12 * (i - 1), function()
			if charge and charge.Parent then
				local weld = charge:FindFirstChildOfClass("WeldConstraint")
				local target = weld and weld.Part1
				ExplosivesService.Explode(charge.Position, player, {
					DirectPart = target,
					DirectDamage = spec.DirectDamage,
					DirectType = spec.DirectType,
					InstantModuleKill = true, -- мгновенный вывод модуля / подрыв БК
					SplashRadius = spec.SplashRadius,
					SplashDamage = spec.SplashDamage,
					SplashType = spec.SplashType,
					WeaponId = "C4",
				})
				charge:Destroy()
			end
		end)
	end
end

-- ---------------------------------------------------------------------------
-- Противотанковые мины
-- ---------------------------------------------------------------------------
local function onMinePlace(player: Player, position: Vector3)
	if not placeFlood(player) then
		return
	end
	local char, _, root = Validation.AliveCharacter(player)
	if not char then
		return
	end
	local tool = char:FindFirstChildOfClass("Tool")
	if not tool or tool:GetAttribute("WeaponId") ~= "Landmine" then
		return
	end
	if ExplosivesService.GetCharges(player, "Mine") <= 0 then
		return
	end
	if not Validation.IsFiniteVector(position) then
		return
	end
	if (root.Position - position).Magnitude > 8 then
		return
	end

	-- мина должна встать на землю
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { char }
	local ground = Workspace:Raycast(position + Vector3.new(0, 2.5, 0), Vector3.new(0, -8, 0), params)
	if not ground then
		return
	end

	charges[player].Mine -= 1

	local mine = Instance.new("Part")
	mine.Name = "Landmine"
	mine.Shape = Enum.PartType.Cylinder
	mine.Size = Vector3.new(0.5, 1.8, 1.8)
	mine.CFrame = CFrame.new(ground.Position + Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, 0, math.rad(90))
	mine.Color = Color3.fromRGB(64, 66, 58)
	mine.Material = Enum.Material.Metal
	mine.Anchored = true
	mine.CanCollide = false -- техника наезжает, а не упирается
	mine.CanQuery = true -- но пули мину находят
	mine:SetAttribute("Armed", false)
	mine:SetAttribute("OwnerUserId", player.UserId)
	CollectionService:AddTag(mine, HitboxTags.Landmine)
	mine.Parent = Workspace

	table.insert(mines, mine)

	-- взвод через 2.5 секунды
	task.delay(2.5, function()
		if mine.Parent then
			mine:SetAttribute("Armed", true)
			mine.Color = Color3.fromRGB(120, 50, 40)
		end
	end)
end

local function removeMine(mine: Part)
	local idx = table.find(mines, mine)
	if idx then
		table.remove(mines, idx)
	end
	if mine.Parent then
		mine:Destroy()
	end
end

-- Подрыв мины. triggerPart/state — наехавшая техника; shooter — кто прострелил.
function ExplosivesService.DetonateMinePart(mine: Part, shooter: Player?, triggerPart: BasePart?, state)
	if not mine.Parent then
		return
	end
	local ownerId = mine:GetAttribute("OwnerUserId")
	local attacker = shooter or (ownerId and Players:GetPlayerByUserId(ownerId)) or nil

	if state and state.Config.Class == "Tank" then
		ctx.Armor.BreakTracks(state, attacker) -- гарантированный срыв гусениц
	end

	local spec = WeaponConfig.Charges.Mine
	ExplosivesService.Explode(mine.Position, attacker, {
		DirectPart = triggerPart,
		DirectDamage = spec.DirectDamage,
		DirectType = spec.DirectType,
		SplashRadius = spec.SplashRadius,
		SplashDamage = spec.SplashDamage,
		SplashType = spec.SplashType,
		WeaponId = "Landmine",
	})
	removeMine(mine)
end

-- Сканер наездов: 8-9 раз в секунду
local scanAccumulator = 0
local function mineScanner(dt: number)
	scanAccumulator += dt
	if scanAccumulator < 0.12 then
		return
	end
	scanAccumulator = 0

	for i = #mines, 1, -1 do
		local mine = mines[i]
		if not mine.Parent then
			table.remove(mines, i)
		elseif mine:GetAttribute("Armed") then
			local found = Workspace:GetPartBoundsInBox(CFrame.new(mine.Position + Vector3.new(0, 1.2, 0)), Vector3.new(5, 3, 5), nil)
			for _, p in ipairs(found) do
				local state = ctx.Armor.GetStateFromPart(p)
				if state then
					ExplosivesService.DetonateMinePart(mine, nil, p, state)
					break
				end
			end
		end
	end
end

-- ---------------------------------------------------------------------------
function ExplosivesService.Init(deps)
	ctx = deps

	ctx.Remotes.Get("C4_Place").OnServerEvent:Connect(onC4Place)
	ctx.Remotes.Get("C4_Detonate").OnServerEvent:Connect(onC4Detonate)
	ctx.Remotes.Get("Mine_Place").OnServerEvent:Connect(onMinePlace)

	RunService.Heartbeat:Connect(mineScanner)

	Players.PlayerRemoving:Connect(function(player)
		charges[player] = nil
		activeC4[player] = nil
	end)
end

return ExplosivesService
