--!nonstrict
-- ============================================================================
-- Frontline Arena — точка входа сервера.
-- Порядок: Remotes -> карта -> сервисы (с ручным DI через ctx) -> техника.
-- ============================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Remotes = require(Shared.Net.Remotes)

Players.RespawnTime = GameConfig.RespawnTime

-- 1. Сеть
Remotes.Ensure()

-- 2. Карта (окопы, руины, площадки, точки контейнеров)
local MapBuilder = require(script.Map.MapBuilder)
local mapData = MapBuilder.Build()

-- 3. Сервисы (порядок важен: зависимости инициализируются раньше потребителей)
local DamageService = require(script.Services.DamageService)
local ArmorService = require(script.Vehicles.ArmorService)
local ExplosivesService = require(script.Services.ExplosivesService)
local WeaponService = require(script.Services.WeaponService)
local DroneService = require(script.Services.DroneService)
local LoadoutService = require(script.Services.LoadoutService)
local PickupService = require(script.Services.PickupService)
local SettingsService = require(script.Services.SettingsService)
local WeaponVisualService = require(script.Services.WeaponVisualService)
local VehicleControl = require(script.Vehicles.VehicleControl)
local VehicleSpawner = require(script.Vehicles.VehicleSpawner)

local ctx = {
	Remotes = Remotes,
	Damage = DamageService,
	Armor = ArmorService,
	Explosives = ExplosivesService,
	Weapons = WeaponService,
	Drone = DroneService,
	Loadout = LoadoutService,
	Pickups = PickupService,
	Settings = SettingsService,
	WeaponVisual = WeaponVisualService,
	VehicleControl = VehicleControl,
	Spawner = VehicleSpawner,
}

DamageService.Init(ctx)
ArmorService.Init(ctx)
ExplosivesService.Init(ctx)
WeaponService.Init(ctx)
DroneService.Init(ctx)
VehicleControl.Init(ctx)
SettingsService.Init(ctx)
WeaponVisualService.Init(ctx)
LoadoutService.Init(ctx)
PickupService.Init(ctx, mapData.ContainerSpawns)
VehicleSpawner.Init(ctx, mapData)

print("[Frontline] Сервер готов: карта x4, оружие, техника, контейнеры, дроны, настройки — ONLINE")
