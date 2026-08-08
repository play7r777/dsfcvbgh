--!nonstrict
-- ============================================================================
-- DamageService — единая точка нанесения урона персонажам.
-- Здесь же: спавн-протекция, атрибуция убийств, киллфид, leaderstats.
-- ============================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)

local DamageService = {}

local ctx

-- ---------------------------------------------------------------------------
-- Спавн-протекция
-- ---------------------------------------------------------------------------
local function protectCharacter(character: Model)
	local untilTime = workspace:GetServerTimeNow() + GameConfig.SpawnProtection
	character:SetAttribute("SpawnProtectedUntil", untilTime)

	local ff = Instance.new("ForceField")
	ff.Visible = true
	ff.Parent = character
	task.delay(GameConfig.SpawnProtection, function()
		if ff and ff.Parent then
			ff:Destroy()
		end
	end)
end

local function isProtected(character: Model): boolean
	local untilTime = character:GetAttribute("SpawnProtectedUntil")
	return type(untilTime) == "number" and workspace:GetServerTimeNow() < untilTime
end

-- ---------------------------------------------------------------------------
-- Киллфид и статистика
-- ---------------------------------------------------------------------------
local function onHumanoidDied(humanoid: Humanoid)
	local character = humanoid.Parent
	local victim = character and Players:GetPlayerFromCharacter(character)

	local attackerName = humanoid:GetAttribute("LastAttackerName")
	local weaponId = humanoid:GetAttribute("LastWeaponId") or "unknown"
	local at = humanoid:GetAttribute("LastAttackerAt") or 0

	-- атрибуция протухает через 10 секунд
	if attackerName and workspace:GetServerTimeNow() - at > 10 then
		attackerName = nil
	end

	if victim then
		local stats = victim:FindFirstChild("leaderstats")
		if stats and stats:FindFirstChild("Deaths") then
			stats.Deaths.Value += 1
		end
		local attacker = attackerName and Players:FindFirstChild(attackerName)
		if attacker and attacker ~= victim then
			local aStats = attacker:FindFirstChild("leaderstats")
			if aStats and aStats:FindFirstChild("Kills") then
				aStats.Kills.Value += 1
			end
		end
		ctx.Remotes.Get("Killfeed"):FireAllClients(attackerName, victim.Name, weaponId)
		if attacker and attacker ~= victim then
			ctx.Remotes.Get("FX_Hitmarker"):FireClient(attacker, "kill")
		end
	end
end

-- ---------------------------------------------------------------------------
-- Публичное API
-- ---------------------------------------------------------------------------

-- Основной вызов. meta: { WeaponId = string? }
function DamageService.Damage(attacker: Player?, humanoid: Humanoid, amount: number, meta)
	if not humanoid or humanoid.Health <= 0 or amount <= 0 then
		return 0
	end
	local character = humanoid.Parent
	if not character then
		return 0
	end
	if isProtected(character) then
		if attacker then
			ctx.Remotes.Get("FX_Hitmarker"):FireClient(attacker, "protected")
		end
		return 0
	end

	if attacker then
		humanoid:SetAttribute("LastAttackerName", attacker.Name)
		humanoid:SetAttribute("LastWeaponId", (meta and meta.WeaponId) or "unknown")
		humanoid:SetAttribute("LastAttackerAt", workspace:GetServerTimeNow())
	end

	humanoid:TakeDamage(amount)

	if attacker then
		ctx.Remotes.Get("FX_Hitmarker"):FireClient(attacker, "hit")
	end
	return amount
end

-- Мгновенное уничтожение (экипаж взорвавшейся техники и т.п.)
function DamageService.ForceKill(humanoid: Humanoid, attacker: Player?, weaponId: string?)
	if not humanoid or humanoid.Health <= 0 then
		return
	end
	if attacker then
		humanoid:SetAttribute("LastAttackerName", attacker.Name)
		humanoid:SetAttribute("LastWeaponId", weaponId or "unknown")
		humanoid:SetAttribute("LastAttackerAt", workspace:GetServerTimeNow())
	end
	humanoid.Health = 0
end

-- ---------------------------------------------------------------------------
function DamageService.Init(deps)
	ctx = deps

	local function onPlayer(player: Player)
		local stats = Instance.new("Folder")
		stats.Name = "leaderstats"
		local kills = Instance.new("IntValue")
		kills.Name = "Kills"
		kills.Parent = stats
		local deaths = Instance.new("IntValue")
		deaths.Name = "Deaths"
		deaths.Parent = stats
		stats.Parent = player

		player.CharacterAdded:Connect(function(character)
			protectCharacter(character)
			local humanoid = character:WaitForChild("Humanoid", 10)
			if humanoid then
				humanoid.Died:Connect(function()
					onHumanoidDied(humanoid)
				end)
			end
		end)
	end

	Players.PlayerAdded:Connect(onPlayer)
	for _, player in ipairs(Players:GetPlayers()) do
		onPlayer(player)
	end
end

return DamageService
