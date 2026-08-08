--!nonstrict
-- ============================================================================
-- VehicleFactory — процедурная сборка техники из Part'ов.
-- Танк: корпус + башня как ДВЕ независимые сварные сборки:
--   * корпус движется через LinearVelocity + AlignOrientation (аркадный привод)
--   * башня сидит на AlignPosition (погон) и поворачивается AlignOrientation'ом
-- Хитбоксы размечаются тегами CollectionService (см. HitboxTags).
-- ============================================================================

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HitboxTags = require(ReplicatedStorage:WaitForChild("Shared").Combat.HitboxTags)

local VehicleFactory = {}

local OLIVE = Color3.fromRGB(75, 83, 55)
local DARK = Color3.fromRGB(45, 46, 44)
local TRACK = Color3.fromRGB(56, 56, 58)

local function mkPart(name: string, size: Vector3, cframe: CFrame, color: Color3, parent: Instance): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.Anchored = false
	p.CanCollide = true
	p.Massless = true -- массу несёт только корневой блок сборки
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function weld(root: BasePart, p: BasePart)
	local w = Instance.new("WeldConstraint")
	w.Part0 = root
	w.Part1 = p
	w.Parent = root
end

local function tag(p: BasePart, tagName: string?)
	if tagName then
		CollectionService:AddTag(p, tagName)
	end
end

-- ============================================================================
-- ТАНК
-- ============================================================================
function VehicleFactory.BuildTank(spawnCFrame: CFrame)
	local model = Instance.new("Model")
	model.Name = "Tank"
	model:SetAttribute("VehicleType", "Tank")

	-- Корневая деталь корпуса (единственная немассолесс деталь сборки)
	local rootCF = spawnCFrame * CFrame.new(0, 3.0, 0)
	local hull = mkPart("Hull", Vector3.new(10, 3.5, 16), rootCF, OLIVE, model)
	hull.Massless = false
	hull.CustomPhysicalProperties = PhysicalProperties.new(0.9, 0.4, 0.2)
	model.PrimaryPart = hull

	-- Бронелисты и узлы (offsets относительно корпуса)
	local glacis = mkPart("Glacis", Vector3.new(10, 3.2, 1.2), rootCF * CFrame.new(0, 0, -7.6), OLIVE, model)
	tag(glacis, HitboxTags.ArmorFront)
	local rear = mkPart("RearPlate", Vector3.new(10, 3.2, 1.2), rootCF * CFrame.new(0, 0, 7.6), OLIVE, model)
	tag(rear, HitboxTags.ArmorRear)
	local skirtL = mkPart("SkirtL", Vector3.new(0.6, 2.2, 15), rootCF * CFrame.new(5.35, 0.4, 0), OLIVE, model)
	tag(skirtL, HitboxTags.ArmorSide)
	local skirtR = mkPart("SkirtR", Vector3.new(0.6, 2.2, 15), rootCF * CFrame.new(-5.35, 0.4, 0), OLIVE, model)
	tag(skirtR, HitboxTags.ArmorSide)

	-- Гусеницы (уязвимые узлы)
	local trackL = mkPart("TrackL", Vector3.new(2.2, 2.8, 16.6), rootCF * CFrame.new(5.05, -1.4, 0), TRACK, model)
	tag(trackL, HitboxTags.TrackL)
	local trackR = mkPart("TrackR", Vector3.new(2.2, 2.8, 16.6), rootCF * CFrame.new(-5.05, -1.4, 0), TRACK, model)
	tag(trackR, HitboxTags.TrackR)

	-- Опорные катки (декор, внутри гусениц)
	for _, sx in ipairs({ -5.05, 5.05 }) do
		for _, z in ipairs({ -6, -2, 2, 6 }) do
			local wheel = mkPart("Wheel", Vector3.new(0.9, 2.6, 2.6), rootCF * CFrame.new(sx, -1.55, z), DARK, model)
			wheel.Shape = Enum.PartType.Cylinder
			wheel.CanCollide = false
		end
	end

	-- Кормовая решётка двигателя
	local deck = mkPart("EngineDeck", Vector3.new(6, 0.6, 4.5), rootCF * CFrame.new(0, 1.9, 5.3), DARK, model)
	tag(deck, HitboxTags.Engine)

	-- Место водителя
	local seat = Instance.new("VehicleSeat")
	seat.Name = "DriverSeat"
	seat.Size = Vector3.new(2, 0.8, 2)
	seat.CFrame = rootCF * CFrame.new(0, 0.4, -1.5)
	seat.Color = DARK
	seat.Anchored = false
	seat.CanCollide = false
	seat.Parent = model

	-- Привод корпуса
	local rootAtt = Instance.new("Attachment")
	rootAtt.Name = "RootAttachment"
	rootAtt.Parent = hull

	local lv = Instance.new("LinearVelocity")
	lv.Name = "DriveLV"
	lv.Attachment0 = rootAtt
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.ForceLimitsEnabled = false
	lv.MaxForce = 1e7
	lv.VectorVelocity = Vector3.zero
	lv.Parent = hull

	local ao = Instance.new("AlignOrientation")
	ao.Name = "DriveAO"
	ao.Mode = Enum.OrientationAlignmentMode.OneAttachment
	ao.Attachment0 = rootAtt
	ao.MaxTorque = 1e7
	ao.Responsiveness = 18
	ao.CFrame = CFrame.new()
	ao.Parent = hull

	-- Сварка корпуса
	for _, p in ipairs(model:GetChildren()) do
		if p:IsA("BasePart") and p ~= hull then
			weld(hull, p)
		end
	end

	-- Кольцо погона на корпусе
	local hullRingAtt = Instance.new("Attachment")
	hullRingAtt.Name = "RingAtt"
	hullRingAtt.CFrame = CFrame.new(0, 1.85, 0.5)
	hullRingAtt.Parent = hull

	-- ------------------------------ БАШНЯ -----------------------------------
	local turretModel = Instance.new("Model")
	turretModel.Name = "Turret"
	turretModel.Parent = model

	local turretRootCF = rootCF * CFrame.new(0, 2.9, 0.5)
	local turretRoot = mkPart("TurretRoot", Vector3.new(6.5, 2.2, 7.5), turretRootCF, OLIVE, turretModel)
	turretRoot.Massless = false
	turretRoot.CustomPhysicalProperties = PhysicalProperties.new(0.6, 0.4, 0.2)
	tag(turretRoot, HitboxTags.ArmorTurret)
	turretModel.PrimaryPart = turretRoot

	local mantlet = mkPart("Mantlet", Vector3.new(4.5, 2, 1.4), turretRootCF * CFrame.new(0, 0.1, -4.2), DARK, turretModel)
	tag(mantlet, HitboxTags.ArmorFront)

	local barrel = mkPart("Barrel", Vector3.new(9, 0.9, 0.9), turretRootCF * CFrame.new(0, 0.3, -9.4) * CFrame.Angles(0, math.rad(90), 0), DARK, turretModel)
	barrel.Shape = Enum.PartType.Cylinder
	tag(barrel, HitboxTags.ArmorTurret)

	-- Боеукладка в кормовой нише башни
	local bustle = mkPart("AmmoBustle", Vector3.new(4, 1.6, 2), turretRootCF * CFrame.new(0, 0.2, 4.4), OLIVE, turretModel)
	tag(bustle, HitboxTags.AmmoRack)

	for _, p in ipairs(turretModel:GetChildren()) do
		if p:IsA("BasePart") and p ~= turretRoot then
			weld(turretRoot, p)
		end
	end

	local turretRingAtt = Instance.new("Attachment")
	turretRingAtt.Name = "RingAtt"
	turretRingAtt.CFrame = CFrame.new(0, -1.1, 0)
	turretRingAtt.Parent = turretRoot

	-- Погон: позиция удерживается, ориентацией управляет сервер
	local ap = Instance.new("AlignPosition")
	ap.Name = "RingAP"
	ap.Mode = Enum.PositionAlignmentMode.TwoAttachment
	ap.Attachment0 = turretRingAtt
	ap.Attachment1 = hullRingAtt
	ap.MaxForce = 1e7
	ap.Responsiveness = 40
	ap.Parent = turretRoot

	local turretAO = Instance.new("AlignOrientation")
	turretAO.Name = "TurretAO"
	turretAO.Mode = Enum.OrientationAlignmentMode.OneAttachment
	turretAO.Attachment0 = turretRingAtt
	turretAO.MaxTorque = 1e6
	turretAO.Responsiveness = 22
	turretAO.CFrame = turretRootCF - turretRootCF.Position -- только ориентация
	turretAO.Parent = turretRoot

	-- Дуло (точка выстрела пушки)
	local muzzle = Instance.new("Attachment")
	muzzle.Name = "Muzzle"
	muzzle.CFrame = CFrame.new(4.6, 0, 0) -- локальный +X ствола смотрит вперёд
	muzzle.Parent = barrel

	model.Parent = workspace

	return {
		Kind = "Tank",
		Model = model,
		Root = hull,
		Seat = seat,
		DriveLV = lv,
		DriveAO = ao,
		GroundClearance = 3.0,
		Turret = {
			Root = turretRoot,
			Orientation = turretAO,
			Muzzle = muzzle,
		},
	}
end

-- ============================================================================
-- МОТОЦИКЛ
-- ============================================================================
function VehicleFactory.BuildBike(spawnCFrame: CFrame)
	local model = Instance.new("Model")
	model.Name = "Bike"
	model:SetAttribute("VehicleType", "Bike")

	local rootCF = spawnCFrame * CFrame.new(0, 1.6, 0)
	local frame = mkPart("Frame", Vector3.new(1.4, 1.2, 5), rootCF, Color3.fromRGB(60, 68, 52), model)
	frame.Massless = false
	frame.CustomPhysicalProperties = PhysicalProperties.new(0.5, 0.5, 0.3)
	model.PrimaryPart = frame

	local wheelF = mkPart("WheelF", Vector3.new(0.8, 2.4, 2.4), rootCF * CFrame.new(0, -0.4, -1.9), DARK, model)
	wheelF.Shape = Enum.PartType.Cylinder
	wheelF.CanCollide = false
	local wheelR = mkPart("WheelR", Vector3.new(0.8, 2.4, 2.4), rootCF * CFrame.new(0, -0.4, 1.9), DARK, model)
	wheelR.Shape = Enum.PartType.Cylinder
	wheelR.CanCollide = false

	mkPart("Handlebar", Vector3.new(1.8, 0.25, 0.25), rootCF * CFrame.new(0, 1.4, -1.6), DARK, model)

	local seat = Instance.new("VehicleSeat")
	seat.Name = "DriverSeat"
	seat.Size = Vector3.new(1.4, 0.5, 1.6)
	seat.CFrame = rootCF * CFrame.new(0, 0.8, 0.4)
	seat.Color = DARK
	seat.Anchored = false
	seat.CanCollide = false
	seat.Parent = model

	local rootAtt = Instance.new("Attachment")
	rootAtt.Name = "RootAttachment"
	rootAtt.Parent = frame

	local lv = Instance.new("LinearVelocity")
	lv.Name = "DriveLV"
	lv.Attachment0 = rootAtt
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.ForceLimitsEnabled = false
	lv.MaxForce = 1e7
	lv.VectorVelocity = Vector3.zero
	lv.Parent = frame

	local ao = Instance.new("AlignOrientation")
	ao.Name = "DriveAO"
	ao.Mode = Enum.OrientationAlignmentMode.OneAttachment
	ao.Attachment0 = rootAtt
	ao.MaxTorque = 1e7
	ao.Responsiveness = 22
	ao.CFrame = CFrame.new()
	ao.Parent = frame

	for _, p in ipairs(model:GetChildren()) do
		if p:IsA("BasePart") and p ~= frame then
			weld(frame, p)
		end
	end

	model.Parent = workspace

	return {
		Kind = "Bike",
		Model = model,
		Root = frame,
		Seat = seat,
		DriveLV = lv,
		DriveAO = ao,
		GroundClearance = 1.6,
		Turret = nil,
	}
end

return VehicleFactory
