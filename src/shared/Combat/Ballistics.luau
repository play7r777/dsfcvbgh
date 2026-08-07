--!nonstrict
-- ============================================================================
-- Ballistics — компактный снарядный кастер по схеме FastCast.
--
-- Один и тот же модуль работает на клиенте (визуальный трассер) и на сервере
-- (авторитетная симуляция попаданий). Снаряд интегрируется по кадрам:
--   v' = v + g*dt ;  p' = p + v*dt + 0.5*g*dt^2
-- и на каждом шаге делает Raycast вдоль сегмента — пули падают с гравитацией,
-- снайперские выстрелы имеют реальное время пролёта.
--
-- Использование:
--   local cast = Ballistics.Fire({
--       Origin = ..., Direction = unitVector, Speed = 760,
--       Gravity = Vector3.new(0, -workspace.Gravity, 0),
--       MaxDistance = 900, RaycastParams = params,
--   })
--   cast.OnStep:Connect(function(lastPos, pos, vel, dt) ... end)
--   cast.OnHit:Connect(function(result, velocity) ... end)
--   cast.OnTerminating:Connect(function() ... end)
-- ============================================================================

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Signal = require(script.Parent.Parent.Util.Signal)

local Ballistics = {}

local Cast = {}
Cast.__index = Cast

function Ballistics.Fire(config)
	assert(config.Origin, "[Ballistics] Нужен Origin")
	assert(config.Direction, "[Ballistics] Нужен Direction")
	assert(config.Speed and config.Speed > 0, "[Ballistics] Нужен Speed > 0")

	local self = setmetatable({}, Cast)
	self.Position = config.Origin
	self.Velocity = config.Direction.Unit * config.Speed
	self.Gravity = config.Gravity or Vector3.new(0, -Workspace.Gravity, 0)
	self.MaxDistance = config.MaxDistance or 1000
	self.RaycastParams = config.RaycastParams
	self.StateInfo = config.StateInfo -- произвольные данные владельца (userId и т.п.)

	self.OnHit = Signal.new() -- (RaycastResult, velocity)
	self.OnStep = Signal.new() -- (lastPosition, position, velocity, dt)
	self.OnTerminating = Signal.new() -- ()

	self._distance = 0
	self._elapsed = 0
	self._maxTime = (self.MaxDistance / config.Speed) * 3 + 4
	self._terminated = false

	self._conn = RunService.Heartbeat:Connect(function(dt)
		self:_step(dt)
	end)

	return self
end

function Cast:_step(dt: number)
	if self._terminated then
		return
	end
	self._elapsed += dt

	local g = self.Gravity
	local displacement = self.Velocity * dt + 0.5 * g * dt * dt
	local newVelocity = self.Velocity + g * dt
	local origin = self.Position

	local result = Workspace:Raycast(origin, displacement, self.RaycastParams)
	if result then
		self.Position = result.Position
		self.Velocity = newVelocity
		self.OnHit:Fire(result, newVelocity)
		self:Terminate()
		return
	end

	self.Position = origin + displacement
	self.Velocity = newVelocity
	self._distance += displacement.Magnitude
	self.OnStep:Fire(origin, self.Position, newVelocity, dt)

	if
		self._distance >= self.MaxDistance
		or self._elapsed >= self._maxTime
		or self.Position.Y < Workspace.FallenPartsDestroyHeight + 50
	then
		self:Terminate()
	end
end

function Cast:Terminate()
	if self._terminated then
		return
	end
	self._terminated = true
	if self._conn then
		self._conn:Disconnect()
		self._conn = nil
	end
	self.OnTerminating:Fire()
end

-- Аналитическая точка траектории (для клиентских эффектов и прицелов)
function Ballistics.PointAtTime(origin: Vector3, velocity: Vector3, gravity: Vector3, t: number): Vector3
	return origin + velocity * t + 0.5 * gravity * t * t
end

return Ballistics
