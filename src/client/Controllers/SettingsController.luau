--!nonstrict
-- ============================================================================
-- SettingsController — внутриигровые настройки (шестерёнка слева сверху):
--   * зазор прицела (по умолчанию 4 px — маленький статичный крестик)
--   * динамический прицел (расширяется при стрельбе) — ВЫКЛ по умолчанию
--   * цвет прицела: белый / зелёный / жёлтый / красный
--   * FOV прицеливания (ПКМ) для оружия без оптики
-- Сохранение: Settings_Save -> серверный DataStore (с фолбэком на сессию).
-- ============================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SettingsController = {}

local ctx
local player = Players.LocalPlayer

local DEFAULTS = {
	CrosshairGap = 4,
	CrosshairDynamic = false,
	CrosshairColor = "White",
	AimFOV = 58,
}

local COLORS = {
	White = Color3.fromRGB(235, 235, 230),
	Green = Color3.fromRGB(120, 255, 140),
	Yellow = Color3.fromRGB(255, 230, 90),
	Red = Color3.fromRGB(255, 90, 80),
}
local COLOR_ORDER = { "White", "Green", "Yellow", "Red" }

local data = table.clone(DEFAULTS)
local saveAt = 0
local refs: any = {}

function SettingsController.Get(key: string)
	return data[key]
end

local function applyCrosshair()
	ctx.HUD.SetCrosshairStyle({
		Gap = data.CrosshairGap,
		Color = COLORS[data.CrosshairColor] or COLORS.White,
		Dynamic = data.CrosshairDynamic,
	})
end

-- ---------------------------------------------------------------------------
-- GUI
-- ---------------------------------------------------------------------------
local function button(parent, props): TextButton
	local b = Instance.new("TextButton")
	b.Font = Enum.Font.GothamBold
	b.TextColor3 = Color3.fromRGB(235, 235, 230)
	b.BackgroundColor3 = Color3.fromRGB(45, 50, 45)
	b.BorderSizePixel = 0
	for k, v in pairs(props) do
		(b :: any)[k] = v
	end
	b.Parent = parent
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
	return b
end

local function buildGui()
	local playerGui = player:WaitForChild("PlayerGui")

	local gui = Instance.new("ScreenGui")
	gui.Name = "ArenaSettings"
	gui.ResetOnSpawn = false
	gui.Parent = playerGui

	local open = button(gui, {
		Name = "OpenSettings",
		Position = UDim2.new(0, 16, 0, 16),
		Size = UDim2.fromOffset(150, 34),
		Text = "⚙  НАСТРОЙКИ",
		TextSize = 13,
	})

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.Position = UDim2.new(0, 16, 0, 58)
	panel.Size = UDim2.fromOffset(300, 240)
	panel.BackgroundColor3 = Color3.fromRGB(14, 17, 14)
	panel.BackgroundTransparency = 0.15
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Parent = gui
	Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 10)

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Position = UDim2.new(0, 14, 0, 8)
	title.Size = UDim2.new(1, -28, 0, 22)
	title.Font = Enum.Font.GothamBold
	title.TextSize = 15
	title.TextColor3 = Color3.fromRGB(255, 190, 80)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = "НАСТРОЙКИ ПРИЦЕЛА"
	title.Parent = panel

	local function rowLabel(text, y)
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Position = UDim2.new(0, 14, 0, y)
		l.Size = UDim2.fromOffset(150, 22)
		l.Font = Enum.Font.Gotham
		l.TextSize = 13
		l.TextColor3 = Color3.fromRGB(220, 220, 215)
		l.TextXAlignment = Enum.TextXAlignment.Left
		l.Text = text
		l.Parent = panel
	end

	-- Зазор прицела
	rowLabel("Зазор прицела", 40)
	refs.GapValue = button(panel, { Position = UDim2.new(0, 196, 0, 40), Size = UDim2.fromOffset(40, 22), Text = tostring(data.CrosshairGap), TextSize = 13 })
	button(panel, { Position = UDim2.new(0, 164, 0, 40), Size = UDim2.fromOffset(26, 22), Text = "–", TextSize = 14 }).MouseButton1Click:Connect(function()
		SettingsController.Set("CrosshairGap", math.max(0, data.CrosshairGap - 1))
	end)
	button(panel, { Position = UDim2.new(0, 242, 0, 40), Size = UDim2.fromOffset(26, 22), Text = "+", TextSize = 14 }).MouseButton1Click:Connect(function()
		SettingsController.Set("CrosshairGap", math.min(24, data.CrosshairGap + 1))
	end)

	-- Динамический прицел
	rowLabel("Динамический прицел", 74)
	refs.Dynamic = button(panel, { Position = UDim2.new(0, 196, 0, 74), Size = UDim2.fromOffset(72, 22), Text = "ВЫКЛ", TextSize = 12 })
	refs.Dynamic.MouseButton1Click:Connect(function()
		SettingsController.Set("CrosshairDynamic", not data.CrosshairDynamic)
	end)

	-- Цвет прицела
	rowLabel("Цвет прицела", 108)
	refs.ColorButtons = {}
	for i, name in ipairs(COLOR_ORDER) do
		local sw = button(panel, {
			Position = UDim2.new(0, 150 + (i - 1) * 32, 0, 108),
			Size = UDim2.fromOffset(26, 22),
			Text = "",
		})
		sw.BackgroundColor3 = COLORS[name]
		sw.MouseButton1Click:Connect(function()
			SettingsController.Set("CrosshairColor", name)
		end)
		refs.ColorButtons[name] = sw
	end

	-- FOV прицеливания
	rowLabel("FOV прицеливания", 142)
	refs.FovValue = button(panel, { Position = UDim2.new(0, 196, 0, 142), Size = UDim2.fromOffset(40, 22), Text = tostring(data.AimFOV), TextSize = 13 })
	button(panel, { Position = UDim2.new(0, 164, 0, 142), Size = UDim2.fromOffset(26, 22), Text = "–", TextSize = 14 }).MouseButton1Click:Connect(function()
		SettingsController.Set("AimFOV", math.max(45, data.AimFOV - 1))
	end)
	button(panel, { Position = UDim2.new(0, 242, 0, 142), Size = UDim2.fromOffset(26, 22), Text = "+", TextSize = 14 }).MouseButton1Click:Connect(function()
		SettingsController.Set("AimFOV", math.min(80, data.AimFOV + 1))
	end)

	-- подсказка
	local hint = Instance.new("TextLabel")
	hint.BackgroundTransparency = 1
	hint.Position = UDim2.new(0, 14, 1, -44)
	hint.Size = UDim2.new(1, -28, 0, 34)
	hint.Font = Enum.Font.Gotham
	hint.TextSize = 11
	hint.TextWrapped = true
	hint.TextColor3 = Color3.fromRGB(150, 155, 150)
	hint.TextXAlignment = Enum.TextXAlignment.Left
	hint.Text = "Сохраняется автоматически (DataStore). Статичный прицел — классический крестик."
	hint.Parent = panel

	open.MouseButton1Click:Connect(function()
		panel.Visible = not panel.Visible
	end)
end

local function refreshGui()
	refs.GapValue.Text = tostring(data.CrosshairGap)
	refs.Dynamic.Text = data.CrosshairDynamic and "ВКЛ" or "ВЫКЛ"
	refs.FovValue.Text = tostring(data.AimFOV)
	for name, sw in pairs(refs.ColorButtons) do
		sw.BackgroundTransparency = (name == data.CrosshairColor) and 0 or 0.55
	end
end

function SettingsController.Set(key: string, value)
	if DEFAULTS[key] == nil then
		return
	end
	data[key] = value
	applyCrosshair()
	refreshGui()

	-- отложенное сохранение (2 сек тишины)
	saveAt = os.clock() + 2
	task.delay(2.05, function()
		if os.clock() >= saveAt then
			ctx.Remotes.Get("Settings_Save"):FireServer(table.clone(data))
		end
	end)
end

-- ---------------------------------------------------------------------------
function SettingsController.Init(deps)
	ctx = deps

	buildGui()
	applyCrosshair()
	refreshGui()

	-- загрузка сохранённых настроек
	ctx.Remotes.Get("Settings_Load").OnClientEvent:Connect(function(saved)
		if type(saved) ~= "table" then
			return
		end
		for key in pairs(DEFAULTS) do
			if saved[key] ~= nil then
				data[key] = saved[key]
			end
		end
		if not COLORS[data.CrosshairColor] then
			data.CrosshairColor = "White"
		end
		applyCrosshair()
		refreshGui()
	end)
	ctx.Remotes.Get("Settings_Request"):FireServer()
end

return SettingsController
