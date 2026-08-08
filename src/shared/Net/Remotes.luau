--!nonstrict
-- ============================================================================
-- Remotes — единый реестр RemoteEvent'ов игры.
-- Сервер вызывает Remotes.Ensure() при старте, клиент — Remotes.Get(name).
-- ============================================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local REMOTE_NAMES = {
	-- Оружие
	"Weapon_Fire", -- c->s: weaponId, origin, aimDir, seed, timestamp, scoped
	"Weapon_Reload", -- c->s: weaponId
	"Weapon_Sync", -- s->c: таблица состояния боеприпасов/перегрева
	-- Визуал
	"FX_Shot", -- s->c (всем, кроме стрелка): userId, weaponId, origin, finalDir
	"FX_Hitmarker", -- s->c (атакующему): kind
	-- Взрывчатка
	"C4_Place", -- c->s: hitPart, hitCFrame
	"C4_Detonate", -- c->s
	"Mine_Place", -- c->s: position
	-- Дрон
	"Drone_Request", -- c->s
	"Drone_Input", -- c->s: yaw, pitch, axes Vector3
	"Drone_Exit", -- c->s
	"Drone_State", -- s->c: { Active, Battery, Position, Reason }
	-- Техника
	"Turret_Aim", -- c->s: lookDir
	"Tank_Fire", -- c->s
	"Vehicle_Event", -- s->c: ("State", id, snapshot) | ("Destroyed", id, attackerName, label)
	-- Прочее
	"Killfeed", -- s->c: attackerName?, victimLabel, weaponId
	-- Настройки клиента
	"Settings_Request", -- c->s
	"Settings_Load", -- s->c: table
	"Settings_Save", -- c->s: table
}

local Remotes = {}
local folder: Folder? = nil

-- Сервер: создать папку и все RemoteEvent'ы (идемпотентно).
function Remotes.Ensure()
	local existing = ReplicatedStorage:FindFirstChild("Remotes")
	if existing then
		folder = existing
		return folder
	end
	local f = Instance.new("Folder")
	f.Name = "Remotes"
	for _, name in ipairs(REMOTE_NAMES) do
		local ev = Instance.new("RemoteEvent")
		ev.Name = name
		ev.Parent = f
	end
	f.Parent = ReplicatedStorage
	folder = f
	return f
end

-- Клиент/сервер: получить RemoteEvent по имени (ожидает появления).
function Remotes.Get(name: string): RemoteEvent
	if not folder then
		folder = ReplicatedStorage:WaitForChild("Remotes", 10)
	end
	assert(folder, "[Remotes] Папка Remotes не создана сервером")
	local ev = folder:WaitForChild(name, 10)
	assert(ev, ("[Remotes] RemoteEvent %q не найден"):format(name))
	return ev :: RemoteEvent
end

return Remotes
