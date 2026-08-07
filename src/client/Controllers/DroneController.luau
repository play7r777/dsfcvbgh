--!nonstrict
-- ============================================================================
-- DroneController — клиент FPV-дрона:
--   * планшет -> Drone_Request; сервер подтверждает Drone_State{Active=true}
--   * камера переключается на дрон, курсор заперт, WASD+Shift/Space
--   * yaw/pitch от мыши (Acro-стиль), сглаженная отдача на сервер
--   * батарея (60 с) и помехи видеоканала при отдалении от оператора
-- Q или повторный клик по планшету — выход (дрон теряется)
-- ============================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)

local DroneController = {}

local ctx
local player = Players.LocalPlayer

local active = false
local yaw = 0
local pitch = 0
local mouseDelta = Vector2.zero
local lastSend = 0
local lastPos = nil
local battery = 0
local conn = nil

local function currentHumanoid()
	local char = player.Character
	return char and char:FindFirstChildOfClass("Humanoid")
end

-- ---------------------------------------------------------------------------
local function sendInput(force: boolean)
	if not active then
		return
	end
	local now = os.clock()
	if not force and now - lastSend < 0.1 then
		return
	end
	lastSend = now

	local axes = Vector3.zero
	if UserInputService:IsKeyDown(Enum.KeyCode.W) then
		axes += Vector3.new(0, 0, 1)
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.S) then
		axes -= Vector3.new(0, 0, 1)
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.D) then
		axes += Vector3.new(1, 0, 0)
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.A) then
		axes -= Vector3.new(1, 0, 0)
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
		axes += Vector3.new(0, 1, 0)
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then
		axes -= Vector3.new(0, 1, 0)
	end

	ctx.Remotes.Get("Drone_Input"):FireServer(yaw, pitch, axes)
end

-- ---------------------------------------------------------------------------
local function exitMode(reason: string?)
	if not active then
		return
	end
	active = false
	if conn then
		conn:Disconnect()
		conn = nil
	end
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default

	local cam = Workspace.CurrentCamera
	if cam then
		cam.CameraType = Enum.CameraType.Custom
		local humanoid = currentHumanoid()
		if humanoid then
			cam.CameraSubject = humanoid
		end
	end

	ctx.HUD.SetDroneVisible(false)
	ctx.HUD.SetSignal(0)
	ctx.HUD.SetCrosshairVisible(true)
	if reason then
		local text = reason == "battery" and "Дрон: батарея разряжена"
			or reason == "signal_lost" and "Дрон: потеря сигнала"
			or reason == "shotdown" and "Дрон сбит!"
			or reason == "exit" and "Связь с дроном разорвана"
			or "Дрон потерян"
		ctx.HUD.Killfeed(text)
	end
end

local function enterMode()
	active = true
	yaw = 0
	pitch = 0
	mouseDelta = Vector2.zero
	lastPos = nil

	local cam = Workspace.CurrentCamera
	if cam then
		cam.CameraType = Enum.CameraType.Scriptable
	end
	UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	ctx.HUD.SetDroneVisible(true)
	ctx.HUD.SetCrosshairVisible(false)

	conn = RunService.RenderStepped:Connect(function()
		-- инерционное сглаживание поворота (кинематографичный Acro)
		local yawDelta = mouseDelta.X * 0.0032
		local pitchDelta = mouseDelta.Y * 0.0032
		mouseDelta = Vector2.zero

		yaw -= yawDelta
		pitch = math.clamp(pitch - pitchDelta, -1.25, 1.25)

		local cam2 = Workspace.CurrentCamera
		if cam2 and lastPos then
			cam2.CFrame = CFrame.new(lastPos) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0)
		end

		sendInput(false)

		-- помехи при отдалении от оператора
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if root then
			local level = (lastPos and (lastPos - root.Position).Magnitude or 0) / GameConfig.Drone.MaxRange
			ctx.HUD.SetSignal(math.clamp(level, 0, 1))
		end
	end)
end

-- ---------------------------------------------------------------------------
function DroneController.Init(deps)
	ctx = deps

	-- ввод мыши
	UserInputService.InputChanged:Connect(function(input)
		if active and input.UserInputType == Enum.UserInputType.MouseMovement then
			mouseDelta += input.Delta
		end
	end)

	-- выход по Q
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed or not active then
			return
		end
		if input.KeyCode == Enum.KeyCode.Q then
			ctx.Remotes.Get("Drone_Exit"):FireServer()
		end
	end)

	-- телеметрия сервера
	ctx.Remotes.Get("Drone_State").OnClientEvent:Connect(function(state)
		if state.Active then
			battery = state.Battery
			lastPos = state.Position
			if not active then
				enterMode()
			end
		else
			if active then
				exitMode(state.Reason)
			end
		end
		ctx.HUD.SetBattery(math.clamp(battery / GameConfig.Drone.BatterySeconds, 0, 1))
	end)

	-- планшет: запуск/выход
	local function bindTablet(tool: Tool)
		if tool:GetAttribute("WeaponId") ~= "DroneTablet" then
			return
		end
		tool.Activated:Connect(function()
			if active then
				ctx.Remotes.Get("Drone_Exit"):FireServer()
			else
				ctx.Remotes.Get("Drone_Request"):FireServer()
			end
		end)
	end

	player.Backpack.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then
			bindTablet(child)
		end
	end)
	player.CharacterAdded:Connect(function(char)
		char.ChildAdded:Connect(function(child)
			if child:IsA("Tool") then
				bindTablet(child)
			end
		end)
		-- после смерти выходим из режима дрона
		exitMode("exit")
		for _, tool in ipairs(char:GetChildren()) do
			if tool:IsA("Tool") then
				bindTablet(tool)
			end
		end
	end)
	if player.Character then
		for _, tool in ipairs(player.Character:GetChildren()) do
			if tool:IsA("Tool") then
				bindTablet(tool)
			end
		end
	end
	for _, tool in ipairs(player.Backpack:GetChildren()) do
		if tool:IsA("Tool") then
			bindTablet(tool)
		end
	end
end

return DroneController
