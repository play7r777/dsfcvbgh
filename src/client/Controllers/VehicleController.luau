--!nonstrict
-- ============================================================================
-- VehicleController — клиент техники:
--   * сидя в танке: наведение башни мышью (Turret_Aim), выстрел пушки (ЛКМ/F)
--   * панель модулей водителя обновляется с сервера (Vehicle_Event)
-- ============================================================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local VehicleConfig = require(Shared.Config.VehicleConfig)

local VehicleController = {}

local ctx
local player = Players.LocalPlayer

local currentVehicleId = nil -- id техники, в которой сидим
local currentVehicleModel = nil
local currentIsTank = false
local turretConn = nil
local visibilityConn = nil
local lastAimSend = 0
local nextCannonAt = 0

local function clearDriving()
	currentVehicleId = nil
	currentIsTank = false
	if turretConn then
		turretConn:Disconnect()
		turretConn = nil
	end
	if visibilityConn then
		visibilityConn:Disconnect()
		visibilityConn = nil
	end
	if currentVehicleModel then
		for _, descendant in ipairs(currentVehicleModel:GetDescendants()) do
			if descendant:IsA("BasePart") then
				descendant.LocalTransparencyModifier = 0
			end
		end
		currentVehicleModel = nil
	end
	ctx.HUD.SetVehicle(nil)
end

local function onSeated(active: boolean, seat: VehicleSeat?)
	if not active or not seat then
		clearDriving()
		return
	end
	local model = seat:FindFirstAncestorOfClass("Model")
	if not model then
		return
	end
	local vehicleId = model:GetAttribute("VehicleId")
	if not vehicleId then
		return
	end

	currentVehicleId = vehicleId
	currentVehicleModel = model
	currentIsTank = model:GetAttribute("VehicleType") == "Tank"
	nextCannonAt = 0

	-- LockFirstPerson остаётся привязан к Humanoid. Локально скрываем только те
	-- детали техники, внутри которых находится камера, чтобы башня/корпус не
	-- перекрывали обзор, не делая всю машину невидимой.
	visibilityConn = RunService.RenderStepped:Connect(function()
		local camera = Workspace.CurrentCamera
		if not camera or currentVehicleModel ~= model then
			return
		end
		local cameraPosition = camera.CFrame.Position
		for _, descendant in ipairs(model:GetDescendants()) do
			if descendant:IsA("BasePart") then
				local localPosition = descendant.CFrame:PointToObjectSpace(cameraPosition)
				local halfSize = descendant.Size / 2 + Vector3.new(0.35, 0.35, 0.35)
				local inside = math.abs(localPosition.X) <= halfSize.X
					and math.abs(localPosition.Y) <= halfSize.Y
					and math.abs(localPosition.Z) <= halfSize.Z
				descendant.LocalTransparencyModifier = inside and 1 or 0
			end
		end
	end)

	if turretConn then
		turretConn:Disconnect()
		turretConn = nil
	end

	-- Танк: башня следует за камерой, ЛКМ/F — выстрел
	if currentIsTank then
		turretConn = RunService.RenderStepped:Connect(function()
			local cam = Workspace.CurrentCamera
			if not cam then
				return
			end
			local now = os.clock()
			if now - lastAimSend > 0.06 then
				lastAimSend = now
				ctx.Remotes.Get("Turret_Aim"):FireServer(cam.CFrame.LookVector)
			end
		end)

	end
end

local function onHumanoidSpawned(humanoid: Humanoid)
	humanoid.Seated:Connect(onSeated)
end

-- ---------------------------------------------------------------------------
function VehicleController.Init(deps)
	ctx = deps

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed or not currentIsTank or not currentVehicleModel then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.KeyCode ~= Enum.KeyCode.F then
			return
		end
		local now = os.clock()
		if now < nextCannonAt then
			return
		end
		nextCannonAt = now + VehicleConfig.Tank.Cannon.ReloadTime
		ctx.Remotes.Get("Tank_Fire"):FireServer()
	end)

	-- события техники: HUD-снапшоты и уничтожения
	ctx.Remotes.Get("Vehicle_Event").OnClientEvent:Connect(function(kind, vehicleId, payload, label)
		if kind == "State" then
			if currentVehicleId == vehicleId then
				ctx.HUD.SetVehicle(payload)
			end
		elseif kind == "Destroyed" then
			local attackerName = payload or "???"
			ctx.HUD.Killfeed(("%s  »  уничтожена техника: %s"):format(attackerName, tostring(label)))
			if currentVehicleId == vehicleId then
				clearDriving()
			end
		end
	end)

	player.CharacterAdded:Connect(function(char)
		local humanoid = char:WaitForChild("Humanoid", 10)
		if humanoid then
			onHumanoidSpawned(humanoid)
		end
	end)
	if player.Character then
		local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			onHumanoidSpawned(humanoid)
		end
	end
end

return VehicleController
