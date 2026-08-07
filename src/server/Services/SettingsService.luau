--!nonstrict
-- ============================================================================
-- SettingsService — сохранение клиентских настроек в DataStore.
-- Всё в pcall: если DataStore недоступен (Studio без API), настройки просто
-- живут одну сессию — игра не ломается.
-- ============================================================================

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SettingsService = {}

local ctx
local store = nil
local pendingSave = {} -- [Player] = table
local lastSaveAt = {} -- [Player] = os.clock()

local ALLOWED = {
	CrosshairGap = "number",
	CrosshairDynamic = "boolean",
	CrosshairColor = "string",
	AimFOV = "number",
}

local function sanitize(input): { [string]: any }
	local out = {}
	if type(input) ~= "table" then
		return out
	end
	for key, kind in pairs(ALLOWED) do
		local v = input[key]
		if typeof(v) == kind then
			out[key] = v
		end
	end
	if out.CrosshairGap then
		out.CrosshairGap = math.clamp(out.CrosshairGap, 0, 24)
	end
	if out.AimFOV then
		out.AimFOV = math.clamp(out.AimFOV, 45, 80)
	end
	if out.CrosshairColor and out.CrosshairColor ~= "White" and out.CrosshairColor ~= "Green" and out.CrosshairColor ~= "Yellow" and out.CrosshairColor ~= "Red" then
		out.CrosshairColor = "White"
	end
	return out
end

local function savePlayer(player: Player)
	if not store then
		return
	end
	local data = pendingSave[player]
	if not data then
		return
	end
	pendingSave[player] = nil
	lastSaveAt[player] = os.clock()
	pcall(function()
		store:SetAsync("u_" .. player.UserId, data)
	end)
end

function SettingsService.Init(deps)
	ctx = deps

	pcall(function()
		store = DataStoreService:GetDataStore("FrontlineSettingsV1")
	end)

	ctx.Remotes.Get("Settings_Request").OnServerEvent:Connect(function(player)
		local loaded = nil
		if store then
			pcall(function()
				loaded = store:GetAsync("u_" .. player.UserId)
			end)
		end
		ctx.Remotes.Get("Settings_Load"):FireClient(player, loaded or {})
	end)

	ctx.Remotes.Get("Settings_Save").OnServerEvent:Connect(function(player, tbl)
		pendingSave[player] = sanitize(tbl)
		-- троттлинг SetAsync: не чаще раза в 6 секунд на игрока
		if os.clock() - (lastSaveAt[player] or 0) >= 6 then
			savePlayer(player)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		savePlayer(player)
		lastSaveAt[player] = nil
	end)
end

return SettingsService
