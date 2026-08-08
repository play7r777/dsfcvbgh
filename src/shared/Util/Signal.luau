--!nonstrict
-- Лёгкая реализация Signal (RBXScriptSignal-подобная), без внешних зависимостей.

local Connection = {}
Connection.__index = Connection

function Connection:Disconnect()
	if self._signal then
		self._signal:_remove(self)
		self._signal = nil
	end
	self.Connected = false
end

local Signal = {}
Signal.__index = Signal

function Signal.new()
	return setmetatable({ _handlers = {}, _next = 1 }, Signal)
end

function Signal:Connect(fn)
	assert(type(fn) == "function", "Signal:Connect ожидает функцию")
	local id = self._next
	self._next += 1
	local conn = setmetatable({ _signal = self, _id = id, Connected = true }, Connection)
	self._handlers[id] = fn
	return conn
end

function Signal:_remove(conn)
	self._handlers[conn._id] = nil
end

function Signal:Fire(...)
	if next(self._handlers) == nil then
		return
	end
	local snapshot = table.clone(self._handlers)
	for _, fn in pairs(snapshot) do
		task.spawn(fn, ...)
	end
end

function Signal:Wait()
	local co = coroutine.running()
	local conn
	conn = self:Connect(function(...)
		conn:Disconnect()
		task.spawn(co, ...)
	end)
	return coroutine.yield()
end

function Signal:Destroy()
	table.clear(self._handlers)
end

return Signal
