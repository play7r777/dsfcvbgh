--!nonstrict
-- ============================================================================
-- WeaponVisualService — видимое оружие в ПРАВОЙ руке персонажа.
-- Процедурные low-poly модели (Part'ы), сваренные к кисти Weld'ом.
-- Если в WeaponConfig.MeshIds задан asset id (после импорта FBX) —
-- используется MeshPart вместо процедурной модели.
--
-- Модели строятся в «grip space»: ствол смотрит на -Z, вверх +Y,
-- начало — в точке хвата. CanQuery=false, чтобы пули не цеплялись за ствол.
-- ============================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local WeaponConfig = require(Shared.Config.WeaponConfig)

local WeaponVisualService = {}

local GUNMETAL = Color3.fromRGB(42, 44, 46)
local DARK = Color3.fromRGB(26, 27, 28)
local OLIVE = Color3.fromRGB(74, 82, 56)
local WOODC = Color3.fromRGB(110, 80, 50)
local TAN = Color3.fromRGB(140, 126, 90)

-- Смещение хвата (C0 сварки), по типу рига
local GRIP = {
	R15 = CFrame.new(0.12, -0.55, -0.35),
	R6 = CFrame.new(0.12, -1.1, -0.35),
}

local active = {} -- [Player] = { [weaponId] = Model }

-- ---------------------------------------------------------------------------
-- Строительные блоки (координаты в grip space)
-- ---------------------------------------------------------------------------
local function box(parent: Model, name: string, size: Vector3, cf: CFrame, color: Color3): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.Anchored = false
	p.CanCollide = false
	p.CanQuery = false
	p.Massless = true
	p.CastShadow = false
	p.Parent = parent
	return p
end

local function cyl(parent: Model, name: string, diameter: number, length: number, cf: CFrame, color: Color3): Part
	local p = box(parent, name, Vector3.new(length, diameter, diameter), cf * CFrame.Angles(0, math.rad(90), 0), color)
	p.Shape = Enum.PartType.Cylinder -- ось цилиндра вдоль локального X -> после поворота вдоль -Z
	return p
end

-- ---------------------------------------------------------------------------
-- Модели оружия (ствол в -Z, рукоять у начала координат)
-- ---------------------------------------------------------------------------
local BUILDERS = {}

function BUILDERS.AssaultRifle(model: Model): Part
	local grip = box(model, "Handle", Vector3.new(0.07, 0.22, 0.1), CFrame.new(0, -0.05, 0.02), DARK)
	box(model, "Receiver", Vector3.new(0.09, 0.13, 0.55), CFrame.new(0, 0.09, -0.28), GUNMETAL)
	box(model, "Handguard", Vector3.new(0.1, 0.11, 0.32), CFrame.new(0, 0.1, -0.62), OLIVE)
	cyl(model, "Barrel", 0.045, 0.42, CFrame.new(0, 0.1, -0.95), DARK)
	box(model, "Magazine", Vector3.new(0.08, 0.24, 0.14), CFrame.new(0, -0.06, -0.32) * CFrame.Angles(math.rad(-12), 0, 0), GUNMETAL)
	box(model, "Stock", Vector3.new(0.08, 0.12, 0.3), CFrame.new(0, 0.07, 0.18), OLIVE)
	box(model, "Sight", Vector3.new(0.03, 0.05, 0.05), CFrame.new(0, 0.18, -0.5), DARK)
	return grip
end

function BUILDERS.Pistol(model: Model): Part
	local grip = box(model, "Handle", Vector3.new(0.06, 0.18, 0.09), CFrame.new(0, -0.06, 0.02) * CFrame.Angles(math.rad(-12), 0, 0), DARK)
	box(model, "Slide", Vector3.new(0.07, 0.07, 0.3), CFrame.new(0, 0.06, -0.1), GUNMETAL)
	box(model, "Frame", Vector3.new(0.06, 0.06, 0.26), CFrame.new(0, 0.0, -0.08), DARK)
	cyl(model, "Muzzle", 0.035, 0.05, CFrame.new(0, 0.06, -0.27), DARK)
	return grip
end

function BUILDERS.SniperRifle(model: Model): Part
	local grip = box(model, "Handle", Vector3.new(0.07, 0.2, 0.1), CFrame.new(0, -0.06, 0.05) * CFrame.Angles(math.rad(-14), 0, 0), DARK)
	box(model, "Receiver", Vector3.new(0.1, 0.13, 0.7), CFrame.new(0, 0.08, -0.35), GUNMETAL)
	cyl(model, "Barrel", 0.04, 0.85, CFrame.new(0, 0.09, -1.1), DARK)
	box(model, "Stock", Vector3.new(0.09, 0.16, 0.45), CFrame.new(0, 0.06, 0.32), OLIVE)
	cyl(model, "Scope", 0.06, 0.3, CFrame.new(0, 0.2, -0.25), DARK)
	cyl(model, "Bolt", 0.03, 0.12, CFrame.new(0.09, 0.1, -0.15) * CFrame.Angles(0, 0, math.rad(90)), GUNMETAL)
	box(model, "Magazine", Vector3.new(0.07, 0.14, 0.16), CFrame.new(0, -0.03, -0.3), DARK)
	return grip
end

function BUILDERS.LMG(model: Model): Part
	local grip = box(model, "Handle", Vector3.new(0.07, 0.2, 0.1), CFrame.new(0, -0.06, 0.05), DARK)
	box(model, "Receiver", Vector3.new(0.13, 0.17, 0.75), CFrame.new(0, 0.1, -0.35), GUNMETAL)
	cyl(model, "Barrel", 0.05, 0.7, CFrame.new(0, 0.11, -1.05), DARK)
	cyl(model, "Shroud", 0.09, 0.3, CFrame.new(0, 0.11, -0.75), OLIVE)
	box(model, "AmmoBox", Vector3.new(0.14, 0.2, 0.26), CFrame.new(0, -0.06, -0.3), OLIVE)
	box(model, "Stock", Vector3.new(0.1, 0.14, 0.32), CFrame.new(0, 0.08, 0.26), DARK)
	box(model, "BipodL", Vector3.new(0.02, 0.22, 0.02), CFrame.new(0.08, -0.06, -0.95) * CFrame.Angles(math.rad(20), 0, math.rad(12)), DARK)
	box(model, "BipodR", Vector3.new(0.02, 0.22, 0.02), CFrame.new(-0.08, -0.06, -0.95) * CFrame.Angles(math.rad(20), 0, math.rad(-12)), DARK)
	return grip
end

function BUILDERS.RPG(model: Model): Part
	local grip = box(model, "Handle", Vector3.new(0.07, 0.22, 0.1), CFrame.new(0, -0.08, 0.0), DARK)
	cyl(model, "Tube", 0.09, 1.5, CFrame.new(0, 0.12, -0.35), OLIVE)
	cyl(model, "RearCone", 0.13, 0.2, CFrame.new(0, 0.12, 0.45), DARK)
	cyl(model, "Warhead", 0.14, 0.3, CFrame.new(0, 0.12, -1.2), TAN)
	box(model, "Sight", Vector3.new(0.04, 0.12, 0.06), CFrame.new(0, 0.24, -0.1), DARK)
	return grip
end

function BUILDERS.C4Charge(model: Model): Part
	local grip = box(model, "Handle", Vector3.new(0.22, 0.07, 0.15), CFrame.new(0, -0.04, -0.02), TAN)
	box(model, "Stripe", Vector3.new(0.22, 0.02, 0.04), CFrame.new(0, 0.005, -0.02), Color3.fromRGB(200, 60, 40))
	return grip
end

function BUILDERS.Detonator(model: Model): Part
	local grip = box(model, "Handle", Vector3.new(0.09, 0.05, 0.16), CFrame.new(0, -0.02, 0), DARK)
	cyl(model, "Antenna", 0.015, 0.22, CFrame.new(0.03, 0.12, -0.05) * CFrame.Angles(0, 0, 0), GUNMETAL)
	box(model, "Button", Vector3.new(0.04, 0.02, 0.04), CFrame.new(0, 0.005, -0.02), Color3.fromRGB(200, 50, 40))
	return grip
end

function BUILDERS.Landmine(model: Model): Part
	local grip = cyl(model, "Handle", 0.34, 0.09, CFrame.new(0, -0.04, 0) * CFrame.Angles(0, 0, math.rad(90)), OLIVE)
	box(model, "Cap", Vector3.new(0.12, 0.04, 0.12), CFrame.new(0, 0.03, 0), DARK)
	return grip
end

function BUILDERS.DroneTablet(model: Model): Part
	local grip = box(model, "Handle", Vector3.new(0.3, 0.02, 0.2), CFrame.new(0, -0.02, 0) * CFrame.Angles(math.rad(-30), 0, 0), DARK)
	box(model, "Screen", Vector3.new(0.26, 0.012, 0.16), CFrame.new(0, -0.005, 0) * CFrame.Angles(math.rad(-30), 0, 0), Color3.fromRGB(70, 160, 200))
	return grip
end

-- ---------------------------------------------------------------------------
-- API
-- ---------------------------------------------------------------------------
local function findHand(character: Model): (BasePart?, string?)
	local hand = character:FindFirstChild("RightHand") -- R15
	if hand and hand:IsA("BasePart") then
		return hand, "R15"
	end
	hand = character:FindFirstChild("Right Arm") -- R6
	if hand and hand:IsA("BasePart") then
		return hand, "R6"
	end
	return nil, nil
end

function WeaponVisualService.Attach(player: Player, weaponId: string)
	WeaponVisualService.Detach(player, weaponId)

	local character = player.Character
	if not character then
		return
	end
	local hand, rig = findHand(character)
	if not hand then
		return
	end

	local builder = BUILDERS[weaponId]
	if not builder then
		return
	end

	local model = Instance.new("Model")
	model.Name = "Wep_" .. weaponId

	local handle
	local meshId = WeaponConfig.MeshIds[weaponId]
	if meshId and meshId ~= 0 then
		-- импортированный FBX (после заливки ассета в Roblox)
		local mp = Instance.new("MeshPart")
		mp.Name = "Handle"
		mp.MeshId = "rbxassetid://" .. meshId
		mp.Size = Vector3.new(0.5, 0.5, 1.2)
		mp.Color = GUNMETAL
		mp.Anchored = false
		mp.CanCollide = false
		mp.CanQuery = false
		mp.Massless = true
		mp.CastShadow = false
		mp.Parent = model
		handle = mp
	else
		handle = builder(model)
	end

	model.PrimaryPart = handle

	-- сварка деталей между собой
	for _, p in ipairs(model:GetChildren()) do
		if p:IsA("BasePart") and p ~= handle then
			local w = Instance.new("WeldConstraint")
			w.Part0 = handle
			w.Part1 = p
			w.Parent = handle
		end
	end

	-- крепление к руке
	local weld = Instance.new("Weld")
	weld.Name = "GripWeld"
	weld.Part0 = hand
	weld.Part1 = handle
	weld.C0 = GRIP[rig] or GRIP.R15
	weld.Parent = handle

	model.Parent = character

	active[player] = active[player] or {}
	active[player][weaponId] = model
end

function WeaponVisualService.Detach(player: Player, weaponId: string)
	local per = active[player]
	if per and per[weaponId] then
		per[weaponId]:Destroy()
		per[weaponId] = nil
	end
end

function WeaponVisualService.Init(_ctx)
	Players.PlayerRemoving:Connect(function(player)
		active[player] = nil
	end)
end

return WeaponVisualService
