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

local VehicleController = {}

local ctx
local player = Players.LocalPlayer

local currentVehicleId = nil -- id техники, в которой сидим
local turretConn = nil
local lastAimSend = 0

local function clearDriving()
	currentVehicleId = nil
	if turretConn then
		turretConn:Disconnect()
		turretConn = nil
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
	local isTank = model:GetAttribute("VehicleType") == "Tank"

	if turretConn then
		turretConn:Disconnect()
		turretConn = nil
	end

	-- Танк: башня следует за камерой, ЛКМ/F — выстрел
	if isTank then
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

		UserInputService.InputBegan:Connect(function(input, gameProcessed)
			if gameProcessed or currentVehicleId ~= vehicleId then
				return
			end
			if
				input.UserInputType == Enum.UserInputType.MouseButton1
				or input.KeyCode == Enum.KeyCode.F
			then
				ctx.Remotes.Get("Tank_Fire"):FireServer()
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
