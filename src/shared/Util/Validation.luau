--!nonstrict
-- Validation — серверные проверки входных данных от клиентов.
-- Никогда не доверяем payload'у RemoteEvent'а.

local Validation = {}

function Validation.IsFiniteNumber(n): boolean
	return type(n) == "number" and n == n and math.abs(n) ~= math.huge
end

function Validation.IsFiniteVector(v): boolean
	return typeof(v) == "Vector3"
		and Validation.IsFiniteNumber(v.X)
		and Validation.IsFiniteNumber(v.Y)
		and Validation.IsFiniteNumber(v.Z)
end

function Validation.IsUnitVector(v, tolerance: number?): boolean
	if not Validation.IsFiniteVector(v) then
		return false
	end
	local tol = tolerance or 0.06
	return math.abs(v.Magnitude - 1) <= tol
end

-- Токен-бакет: ограничение частоты событий на ключ (обычно Player).
-- Возвращает функцию allow(key) -> boolean
function Validation.NewFloodCheck(maxPerSecond: number, burst: number?)
	local capacity = burst or maxPerSecond * 2
	local buckets = {}
	return function(key): boolean
		local now = os.clock()
		local b = buckets[key]
		if not b then
			b = { tokens = capacity - 1, at = now }
			buckets[key] = b
			return true
		end
		local refill = (now - b.at) * maxPerSecond
		b.at = now
		b.tokens = math.min(capacity, b.tokens + refill)
		if b.tokens < 1 then
			return false
		end
		b.tokens -= 1
		return true
	end
end

-- Живой персонаж игрока: character, humanoid, rootPart или nil
function Validation.AliveCharacter(player: Player)
	local char = player.Character
	if not char then
		return nil
	end
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end
	return char, humanoid, char:FindFirstChild("HumanoidRootPart")
end

return Validation
