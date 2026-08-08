--!nonstrict
-- ============================================================================
-- VehicleSpawner — точки спавна техники по карте.
-- Танки и мотоциклы НЕ выдаются при спавне игрока — их нужно найти на карте.
-- Уничтоженная техника возрождается через время (бесконечный цикл арены).
-- ============================================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local VehicleFactory = require(script.Parent.VehicleFactory)

local VehicleSpawner = {}

local ctx
local pads = {} -- { { Kind, CFrame, State } }

local function spawnOnPad(pad)
	local data
	if pad.Kind == "Tank" then
		data = VehicleFactory.BuildTank(pad.CFrame)
	else
		data = VehicleFactory.BuildBike(pad.CFrame)
	end
	data.Model.Parent = pad.Folder
	local state = ctx.Armor.RegisterVehicle(data)
	state.Pad = pad
	pad.State = state
end

function VehicleSpawner.OnVehicleDestroyed(state)
	local pad = state.Pad
	if not pad then
		return
	end
	pad.State = nil

	local delayTime = pad.Kind == "Tank" and GameConfig.TankRespawn or GameConfig.BikeRespawn
	task.delay(delayTime, function()
		if not pad.State then
			spawnOnPad(pad)
		end
	end)
end

function VehicleSpawner.Init(deps, mapData)
	ctx = deps

	local folder = Instance.new("Folder")
	folder.Name = "Vehicles"
	folder.Parent = workspace

	for _, cf in ipairs(mapData.TankPads) do
		table.insert(pads, { Kind = "Tank", CFrame = cf, State = nil, Folder = folder })
	end
	for _, cf in ipairs(mapData.BikePads) do
		table.insert(pads, { Kind = "Bike", CFrame = cf, State = nil, Folder = folder })
	end

	-- стартовый спавн с небольшой рассадкой по времени
	for i, pad in ipairs(pads) do
		task.delay(0.3 * i, function()
			spawnOnPad(pad)
		end)
	end
end

return VehicleSpawner
