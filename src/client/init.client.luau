--!nonstrict
-- ============================================================================
-- Frontline Arena — клиентская точка входа: HUD -> Settings -> FX -> контроллеры.
-- ============================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
player.CameraMode = Enum.CameraMode.LockFirstPerson
player.CameraMinZoomDistance = 0.5
player.CameraMaxZoomDistance = 0.5
UserInputService.MouseIconEnabled = false

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Net.Remotes)

local HUD = require(script.UI.HUD)
local FXController = require(script.Controllers.FXController)
local SettingsController = require(script.Controllers.SettingsController)
local WeaponController = require(script.Controllers.WeaponController)
local DroneController = require(script.Controllers.DroneController)
local VehicleController = require(script.Controllers.VehicleController)

local ctx = {
	Remotes = Remotes,
	HUD = HUD,
	FX = FXController,
	Settings = SettingsController,
}

HUD.Init()
SettingsController.Init(ctx)
FXController.Init(ctx)
WeaponController.Init(ctx)
DroneController.Init(ctx)
VehicleController.Init(ctx)

print("[Frontline] Клиент готов: HUD, настройки, оружие, дрон, техника")
