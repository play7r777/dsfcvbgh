--!nonstrict
-- ============================================================================
-- LoadoutService — стартовый набор пехоты при каждом спавне.
-- С собой: автомат, пистолет, C4 + детонатор, ПТ-мины, планшет FPV.
-- ПКМ и СВ-98 выдаёт PickupService из контейнеров.
--
-- При экипировке инструмента WeaponVisualService крепит модель в правую руку.
-- ============================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local WeaponConfig = require(Shared.Config.WeaponConfig)

local LoadoutService = {}

local ctx

-- Отображаемые имена нестрелковых инструментов
local UTILITY_NAMES = {
	C4Charge = "C4 (липучка)",
	Detonator = "Детонатор",
	Landmine = "Мина ПТ",
	DroneTablet = "Планшет FPV",
}

-- Создать инструмент и связать его с серверным трекингом экипировки.
-- Публично: PickupService выдаёт ПКМ/СВД через WeaponService.GiveWeapon.
function LoadoutService.MakeTool(player: Player, weaponId: string): Tool
	local cfg = WeaponConfig.Get(weaponId)

	local tool = Instance.new("Tool")
	tool.Name = weaponId
	tool.RequiresHandle = false
	tool.CanBeDropped = false
	tool:SetAttribute("WeaponId", weaponId)
	tool.ToolTip = (cfg and cfg.DisplayName) or UTILITY_NAMES[weaponId] or weaponId

	tool.Equipped:Connect(function()
		ctx.Weapons.OnToolEquipped(player, weaponId)
		if ctx.WeaponVisual then
			ctx.WeaponVisual.Attach(player, weaponId)
		end
	end)
	tool.Unequipped:Connect(function()
		ctx.Weapons.OnToolUnequipped(player, weaponId)
		if ctx.WeaponVisual then
			ctx.WeaponVisual.Detach(player, weaponId)
		end
	end)

	tool.Parent = player.Backpack
	return tool
end

local function onCharacterAdded(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid then
		return
	end
	humanoid.WalkSpeed = GameConfig.WalkSpeed
	humanoid.JumpPower = 50

	-- сброс и выдача снаряжения
	ctx.Weapons.ResetLoadout(player)
	ctx.Explosives.ResetCharges(player)

	for _, id in ipairs(GameConfig.Loadout) do
		LoadoutService.MakeTool(player, id)
	end
end

function LoadoutService.Init(deps)
	ctx = deps

	local function onPlayer(player: Player)
		player.CharacterAdded:Connect(function(character)
			onCharacterAdded(player, character)
		end)
		if player.Character then
			onCharacterAdded(player, player.Character)
		end
	end

	Players.PlayerAdded:Connect(onPlayer)
	for _, player in ipairs(Players:GetPlayers()) do
		onPlayer(player)
	end
end

return LoadoutService
