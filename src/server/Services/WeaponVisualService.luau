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
local MeshLibrary = require(Shared.Util.MeshLibrary)

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

	local template = ReplicatedStorage:WaitForChild("Assets"):FindFirstChild(weaponId)
	if not template then
		warn("Missing weapon model:", weaponId)
		return
	end

	local model
	if template:IsA("Model") then
		model = template:Clone()
	else
		model = Instance.new("Model")
		local clone = template:Clone()
		clone.Parent = model
	end
	
	model.Name = "Wep_" .. weaponId

	-- Красим по именам материалов OBJ (как в DWAS MeshLibrary)
	MeshLibrary.ApplyFallbackColors(model)

	local handle = model.PrimaryPart or model:FindFirstChild("Handle") or model:FindFirstChildWhichIsA("BasePart")
	if not handle then
		warn("Weapon model has no basepart:", weaponId)
		model:Destroy()
		return
	end
	model.PrimaryPart = handle

	-- сварка деталей между собой (для импортированных FBX)
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") then
			p.Anchored = false
			p.CanCollide = false
			p.CanQuery = false
			p.Massless = true
			if p ~= handle then
				local w = Instance.new("WeldConstraint")
				w.Part0 = handle
				w.Part1 = p
				w.Parent = handle
			end
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
