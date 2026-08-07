--!nonstrict
-- ============================================================================
-- HUD — весь интерфейс арены, построенный кодом (без ассетов):
-- прицел с динамическим разбросом, хитмаркер, боеприпасы, перегрев ПКМ,
-- батарея/сигнал FPV-дрона, киллфид, панель модулей техники, снайперская
-- оптика (чёрная маска с круглым окуляром), подавление.
-- ============================================================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local HUD = {}
HUD._signalLevel = 0

local gui: ScreenGui
local refs = {}

local ACCENT = Color3.fromRGB(255, 190, 80)
local PANEL = Color3.fromRGB(14, 17, 14)
local WHITE = Color3.fromRGB(235, 235, 230)

local function frame(parent, props): Frame
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	for k, v in pairs(props) do
		(f :: any)[k] = v
	end
	f.Parent = parent
	return f
end

local function label(parent, props): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBold
	l.TextColor3 = WHITE
	l.TextStrokeTransparency = 0.6
	for k, v in pairs(props) do
		(l :: any)[k] = v
	end
	l.Parent = parent
	return l
end

-- ---------------------------------------------------------------------------
-- Построение
-- ---------------------------------------------------------------------------
local function build()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	gui = Instance.new("ScreenGui")
	gui.Name = "ArenaHUD"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = playerGui

	-- ПРИЦЕЛ (4 риски, зазор зависит от разброса)
	local cross = {}
	for i = 1, 4 do
		cross[i] = frame(gui, {
			Name = "Cross" .. i,
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = WHITE,
			Size = UDim2.fromOffset(2, 10),
		})
	end
	refs.Cross = cross
	refs.CrossGap = 8

	-- ХИТМАРКЕР
	local hit = {}
	for i = 1, 4 do
		hit[i] = frame(gui, {
			Name = "Hit" .. i,
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = WHITE,
			Size = UDim2.fromOffset(2, 12),
			Visible = false,
			Rotation = 45 + (i - 1) * 90,
		})
	end
	refs.Hit = hit

	-- БОЕПРИПАСЫ (правый нижний угол)
	local ammoPanel = frame(gui, {
		Name = "AmmoPanel",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -24, 1, -24),
		Size = UDim2.fromOffset(220, 86),
		BackgroundColor3 = PANEL,
		BackgroundTransparency = 0.35,
	})
	Instance.new("UICorner", ammoPanel).CornerRadius = UDim.new(0, 8)

	refs.WeaponName = label(ammoPanel, {
		Name = "WeaponName",
		Position = UDim2.new(0, 12, 0, 6),
		Size = UDim2.new(1, -24, 0, 20),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = 14,
		TextColor3 = ACCENT,
		Text = "",
	})
	refs.Ammo = label(ammoPanel, {
		Name = "AmmoCount",
		Position = UDim2.new(0, 12, 0, 24),
		Size = UDim2.new(1, -24, 0, 34),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = 28,
		Text = "",
	})
	refs.Reload = label(ammoPanel, {
		Name = "Reload",
		Position = UDim2.new(0, 12, 0, 60),
		Size = UDim2.new(1, -24, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = 12,
		TextColor3 = Color3.fromRGB(255, 120, 90),
		Text = "",
	})

	-- ПЕРЕГРЕВ ПКМ
	local heatBG = frame(ammoPanel, {
		Name = "HeatBG",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 12, 1, -8),
		Size = UDim2.new(1, -24, 0, 6),
		BackgroundColor3 = Color3.fromRGB(50, 50, 48),
		Visible = false,
	})
	refs.HeatBG = heatBG
	refs.HeatFill = frame(heatBG, {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Color3.fromRGB(255, 120, 50),
	})

	-- FPV: батарея + сигнал (низ по центру)
	local dronePanel = frame(gui, {
		Name = "DronePanel",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -30),
		Size = UDim2.fromOffset(300, 54),
		BackgroundColor3 = PANEL,
		BackgroundTransparency = 0.35,
		Visible = false,
	})
	Instance.new("UICorner", dronePanel).CornerRadius = UDim.new(0, 8)
	label(dronePanel, {
		Name = "Title",
		Position = UDim2.new(0, 12, 0, 4),
		Size = UDim2.new(1, -24, 0, 16),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = 12,
		TextColor3 = ACCENT,
		Text = "FPV ДРОН",
	})
	local battBG = frame(dronePanel, {
		Name = "BattBG",
		Position = UDim2.new(0, 12, 0, 24),
		Size = UDim2.new(1, -24, 0, 8),
		BackgroundColor3 = Color3.fromRGB(50, 50, 48),
	})
	refs.BatteryFill = frame(battBG, { Name = "Fill", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(120, 220, 120) })
	refs.Signal = label(dronePanel, {
		Name = "Signal",
		Position = UDim2.new(0, 12, 0, 36),
		Size = UDim2.new(1, -24, 0, 14),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = 11,
		Text = "СИГНАЛ: ОТЛИЧНЫЙ",
	})
	refs.DronePanel = dronePanel

	-- Помехи видеоканала (мёрзнущий белый шум)
	refs.Interference = frame(gui, {
		Name = "Interference",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(220, 220, 220),
		BackgroundTransparency = 1,
	})

	-- КИЛЛФИД (правый верхний угол)
	local feed = frame(gui, {
		Name = "Killfeed",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 16),
		Size = UDim2.fromOffset(360, 180),
		BackgroundTransparency = 1,
	})
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.VerticalAlignment = Enum.VerticalAlignment.Top
	layout.Padding = UDim.new(0, 2)
	layout.Parent = feed
	refs.Feed = feed

	-- УВЕДОМЛЕНИЯ (центр снизу)
	refs.Notify = label(gui, {
		Name = "Notify",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -140),
		Size = UDim2.fromOffset(420, 24),
		TextSize = 15,
		TextColor3 = ACCENT,
		Text = "",
	})

	-- ПАНЕЛЬ ТЕХНИКИ (левый нижний угол)
	local vehPanel = frame(gui, {
		Name = "VehiclePanel",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 24, 1, -24),
		Size = UDim2.fromOffset(240, 196),
		BackgroundColor3 = PANEL,
		BackgroundTransparency = 0.35,
		Visible = false,
	})
	Instance.new("UICorner", vehPanel).CornerRadius = UDim.new(0, 8)
	refs.VehiclePanel = vehPanel
	refs.VehicleName = label(vehPanel, {
		Name = "VName",
		Position = UDim2.new(0, 12, 0, 6),
		Size = UDim2.new(1, -24, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = 14,
		TextColor3 = ACCENT,
		Text = "",
	})
	refs.VehicleStatus = label(vehPanel, {
		Name = "VStatus",
		Position = UDim2.new(0, 12, 1, -22),
		Size = UDim2.new(1, -24, 0, 16),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = 12,
		TextColor3 = Color3.fromRGB(255, 100, 70),
		Text = "",
	})

	-- строки модулей
	local rows = {
		{ key = "Hull", title = "Корпус" },
		{ key = "TrackL", title = "Гусеница Л" },
		{ key = "TrackR", title = "Гусеница П" },
		{ key = "Engine", title = "Двигатель" },
		{ key = "Turret", title = "Погон башни" },
		{ key = "AmmoRack", title = "Боеукладка" },
	}
	refs.VehicleRows = {}
	for i, row in ipairs(rows) do
		local y = 26 + (i - 1) * 24
		local rl = label(vehPanel, {
			Name = "L" .. row.key,
			Position = UDim2.new(0, 12, 0, y),
			Size = UDim2.fromOffset(86, 16),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextSize = 11,
			Text = row.title,
		})
		local bg = frame(vehPanel, {
			Name = "BG" .. row.key,
			Position = UDim2.new(0, 104, 0, y + 3),
			Size = UDim2.new(1, -116, 0, 10),
			BackgroundColor3 = Color3.fromRGB(50, 50, 48),
		})
		local fillBar = frame(bg, { Name = "Fill", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(120, 220, 120) })
		refs.VehicleRows[row.key] = { Label = rl, BG = bg, Fill = fillBar }
	end

	-- СНАЙПЕРСКИЙ ПРИЦЕЛ (маска-окуляр)
	local scope = frame(gui, {
		Name = "Scope",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = false,
	})
	local lens = frame(scope, {
		Name = "Lens",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(700, 700),
		BackgroundTransparency = 1,
	})
	Instance.new("UICorner", lens).CornerRadius = UDim.new(1, 0)
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Thickness = 2000 -- чёрное кольцо уходит за края экрана
	stroke.Parent = lens
	frame(lens, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = Color3.new(0, 0, 0) })
	frame(lens, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(0, 1, 1, 0), BackgroundColor3 = Color3.new(0, 0, 0) })
	refs.Scope = scope
	refs.ScopeLens = lens

	-- ПОДАВЛЕНИЕ (белая вспышка по краям)
	refs.Suppression = frame(gui, {
		Name = "Suppression",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(200, 210, 220),
		BackgroundTransparency = 1,
	})
end

-- ---------------------------------------------------------------------------
-- Публичное API
-- ---------------------------------------------------------------------------
function HUD.Init()
	build()

	-- прицел перестраивается при смене зазора
	RunService.RenderStepped:Connect(function()
		local gap = refs.CrossGap
		local cross = refs.Cross
		if not cross[1].Parent then
			return
		end
		cross[1].Position = UDim2.new(0.5, 0, 0.5, -(gap + 5))
		cross[2].Position = UDim2.new(0.5, 0, 0.5, gap + 5)
		cross[3].Position = UDim2.new(0.5, -(gap + 5), 0.5, 0)
		cross[4].Position = UDim2.new(0.5, gap + 5, 0.5, 0)
		cross[3].Size = UDim2.fromOffset(10, 2)
		cross[4].Size = UDim2.fromOffset(10, 2)

		-- помехи видеоканала
		local noise = refs.Interference
		if HUD._signalLevel and HUD._signalLevel > 0.7 then
			noise.BackgroundTransparency = 0.86 + math.random() * 0.13
		elseif noise.BackgroundTransparency < 1 then
			noise.BackgroundTransparency = 1
		end

		-- адаптируем окуляр под высоту экрана
		local viewport = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize
		if viewport then
			local d = math.floor(viewport.Y * 0.92)
			if refs.ScopeLens.Size ~= UDim2.fromOffset(d, d) then
				refs.ScopeLens.Size = UDim2.fromOffset(d, d)
			end
		end
	end)
end

function HUD.SetWeapon(name: string)
	refs.WeaponName.Text = name
end

function HUD.SetAmmo(mag: number?, reserve: number?)
	if mag == nil then
		refs.Ammo.Text = ""
	else
		refs.Ammo.Text = tostring(mag) .. " / " .. tostring(reserve or 0)
	end
end

function HUD.SetReloading(active: boolean)
	refs.Reload.Text = active and "ПЕРЕЗАРЯДКА..." or ""
end

function HUD.SetVenting(active: boolean)
	refs.Reload.Text = active and "ПЕРЕГРЕВ СТВОЛА!" or refs.Reload.Text
	if active then
		refs.Reload.Text = "ПЕРЕГРЕВ СТВОЛА!"
	end
end

function HUD.SetHeat(frac: number?, venting: boolean?)
	refs.HeatBG.Visible = frac ~= nil
	if frac then
		refs.HeatFill.Size = UDim2.fromScale(math.clamp(frac, 0, 1), 1)
		refs.HeatFill.BackgroundColor3 = frac > 0.8 and Color3.fromRGB(255, 60, 40) or Color3.fromRGB(255, 120, 50)
	end
end

function HUD.SetCrosshairGap(px: number)
	refs.CrossGap = px
end

function HUD.SetCrosshairVisible(visible: boolean)
	for _, f in ipairs(refs.Cross) do
		f.Visible = visible
	end
end

function HUD.Hitmarker(kind: string)
	local color = WHITE
	if kind == "kill" or kind == "cookoff" then
		color = Color3.fromRGB(255, 70, 50)
	elseif kind == "ricochet" then
		color = Color3.fromRGB(150, 150, 150)
	elseif kind == "vehicle" then
		color = ACCENT
	end
	for _, f in ipairs(refs.Hit) do
		f.BackgroundColor3 = color
		f.Visible = true
		f.Position = UDim2.new(0.5, 0, 0.5, 0)
	end
	task.delay(0.15, function()
		for _, f in ipairs(refs.Hit) do
			f.Visible = false
		end
	end)
end

function HUD.Killfeed(text: string)
	local entry = label(refs.Feed, {
		Size = UDim2.new(1, 0, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextSize = 13,
		Text = text,
	})
	local children = refs.Feed:GetChildren()
	local count = 0
	for _, c in ipairs(children) do
		if c:IsA("TextLabel") then
			count += 1
		end
	end
	if count > 6 then
		for _, c in ipairs(children) do
			if c:IsA("TextLabel") then
				c:Destroy()
				break
			end
		end
	end
	task.delay(6, function()
		if entry.Parent then
			entry:Destroy()
		end
	end)
end

function HUD.Notify(text: string)
	refs.Notify.Text = text
	task.delay(2.5, function()
		if refs.Notify.Text == text then
			refs.Notify.Text = ""
		end
	end)
end

function HUD.SetDroneVisible(visible: boolean)
	refs.DronePanel.Visible = visible
end

function HUD.SetBattery(frac: number)
	refs.BatteryFill.Size = UDim2.fromScale(math.clamp(frac, 0, 1), 1)
	refs.BatteryFill.BackgroundColor3 = frac > 0.3 and Color3.fromRGB(120, 220, 120) or Color3.fromRGB(255, 90, 60)
end

-- level: 0..1 (1 = предел радиуса)
function HUD.SetSignal(level: number)
	HUD._signalLevel = level
	if level > 0.85 then
		refs.Signal.Text = "СИГНАЛ: КРИТИЧЕСКИЙ!"
		refs.Signal.TextColor3 = Color3.fromRGB(255, 70, 50)
	elseif level > 0.7 then
		refs.Signal.Text = "СИГНАЛ: ПОМЕХИ"
		refs.Signal.TextColor3 = Color3.fromRGB(255, 170, 60)
	else
		refs.Signal.Text = "СИГНАЛ: ОТЛИЧНЫЙ"
		refs.Signal.TextColor3 = WHITE
	end
end

local function barColor(frac: number): Color3
	if frac > 0.55 then
		return Color3.fromRGB(120, 220, 120)
	elseif frac > 0.25 then
		return Color3.fromRGB(255, 190, 80)
	end
	return Color3.fromRGB(255, 70, 50)
end

-- snapshot: { Hull, Modules = {...}, Burning, Immobilized, TurretJammed, Name } или nil
function HUD.SetVehicle(snapshot)
	refs.VehiclePanel.Visible = snapshot ~= nil
	if not snapshot then
		return
	end
	refs.VehicleName.Text = snapshot.Name or "Техника"

	for key, row in pairs(refs.VehicleRows) do
		local frac
		if key == "Hull" then
			frac = snapshot.Hull
		else
			frac = snapshot.Modules and snapshot.Modules[key]
		end
		row.Label.Visible = frac ~= nil
		row.BG.Visible = frac ~= nil
		if frac then
			row.Fill.Size = UDim2.fromScale(math.clamp(frac, 0, 1), 1)
			row.Fill.BackgroundColor3 = barColor(frac)
		end
	end

	local status = {}
	if snapshot.Burning then
		table.insert(status, "ПОЖАР ДВИГАТЕЛЯ!")
	end
	if snapshot.Immobilized then
		table.insert(status, "ИММОБИЛИЗОВАН")
	end
	if snapshot.TurretJammed then
		table.insert(status, "БАШНЯ ЗАКЛИНЕНА")
	end
	refs.VehicleStatus.Text = table.concat(status, "  |  ")
end

function HUD.SetScope(visible: boolean)
	refs.Scope.Visible = visible
end

function HUD.SuppressionPulse()
	refs.Suppression.BackgroundTransparency = 0.82
	task.delay(0.12, function()
		refs.Suppression.BackgroundTransparency = 1
	end)
end

return HUD
