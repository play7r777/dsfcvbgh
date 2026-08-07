--!nonstrict
-- ============================================================================
-- Frontline Arena — клиентская точка входа: HUD -> FX -> контроллеры.
-- ============================================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Net.Remotes)

local HUD = require(script.UI.HUD)
local FXController = require(script.Controllers.FXController)
local WeaponController = require(script.Controllers.WeaponController)
local DroneController = require(script.Controllers.DroneController)
local VehicleController = require(script.Controllers.VehicleController)

local ctx = {
	Remotes = Remotes,
	HUD = HUD,
	FX = FXController,
}

HUD.Init()
FXController.Init(ctx)
WeaponController.Init(ctx)
DroneController.Init(ctx)
VehicleController.Init(ctx)

print("[Frontline] Клиент готов: HUD, оружие, дрон, техника")
