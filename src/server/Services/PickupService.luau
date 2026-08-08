--!nonstrict
-- ============================================================================
-- PickupService — контейнеры снабжения на карте.
-- ПКМ и СВ-98 лежат ТОЛЬКО здесь; также мины/C4/боеприпасы.
-- После взятия контейнер пустеет и через 45-90 сек наполняется снова —
-- лут на арене бесконечный.
-- ============================================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local HitboxTags = require(Shared.Combat.HitboxTags)
local CollectionService = game:GetService("CollectionService")

local PickupService = {}

local ctx
local rng = Random.new()

-- Что лежит в контейнерах (цикл по точкам спавна)
local CONTENT_CYCLE = { "LMG", "SniperRifle", "MinePack", "C4Pack", "Ammo" }
local CONTENT_LABEL = {
	LMG = "ПКМ",
	SniperRifle = "СВ-98",
	MinePack = "Мины ПТ",
	C4Pack = "Заряд C4",
	Ammo = "Боеприпасы",
}
local CONTENT_COLOR = {
	LMG = Color3.fromRGB(255, 140, 40),
	SniperRifle = Color3.fromRGB(60, 200, 255),
	MinePack = Color3.fromRGB(255, 70, 60),
	C4Pack = Color3.fromRGB(255, 220, 60),
	Ammo = Color3.fromRGB(90, 220, 90),
}

local function giveContent(player: Player, content: string)
	if content == "LMG" or content == "SniperRifle" then
		ctx.Weapons.GiveWeapon(player, content)
	elseif content == "MinePack" then
		ctx.Explosives.AddCharges(player, "Mine", 2)
	elseif content == "C4Pack" then
		ctx.Explosives.AddCharges(player, "C4", 1)
	elseif content == "Ammo" then
		ctx.Weapons.RefillReserve(player)
	end
end

local function buildContainer(cframe: CFrame, content: string, parent: Instance)
	local model = Instance.new("Model")
	model.Name = "SupplyContainer"

	local root = Instance.new("Part")
	root.Name = "Case"
	root.Size = Vector3.new(3.2, 2.2, 3.2)
	root.CFrame = cframe + Vector3.new(0, 1.1, 0)
	root.Color = Color3.fromRGB(74, 80, 60)
	root.Material = Enum.Material.Metal
	root.Anchored = true
	root.Parent = model

	local stripe = Instance.new("Part")
	stripe.Name = "Stripe"
	stripe.Size = Vector3.new(3.3, 0.45, 3.3)
	stripe.CFrame = root.CFrame + Vector3.new(0, 0.55, 0)
	stripe.Color = CONTENT_COLOR[content]
	stripe.Material = Enum.Material.Neon
	stripe.Anchored = true
	stripe.CanCollide = false
	stripe.Parent = model

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = stripe
	weld.Part1 = root
	weld.Parent = stripe

	model.PrimaryPart = root
	model.Parent = parent
	CollectionService:AddTag(root, HitboxTags.SupplyContainer)
	return model, root, stripe
end

function PickupService.Init(deps, containerSpawns)
	ctx = deps

	local folder = Instance.new("Folder")
	folder.Name = "SupplyContainers"
	folder.Parent = workspace

	for i, cframe in ipairs(containerSpawns) do
		local content = CONTENT_CYCLE[(i - 1) % #CONTENT_CYCLE + 1]
		local model, root, stripe = buildContainer(cframe, content, folder)

		local available = true
		local prompt = Instance.new("ProximityPrompt")
		prompt.ObjectText = "Контейнер снабжения"
		prompt.ActionText = "Взять: " .. CONTENT_LABEL[content]
		prompt.HoldDuration = 0.5
		prompt.MaxActivationDistance = 9
		prompt.RequiresLineOfSight = false
		prompt.Parent = root

		prompt.Triggered:Connect(function(player)
			if not available then
				return
			end
			available = false
			prompt.Enabled = false
			stripe.Transparency = 0.75

			giveContent(player, content)

			-- бесконечный респавн содержимого
			task.delay(rng:NextNumber(GameConfig.PickupRespawnMin, GameConfig.PickupRespawnMax), function()
				if model.Parent then
					available = true
					prompt.Enabled = true
					stripe.Transparency = 0
				end
			end)
		end)
	end
end

return PickupService
