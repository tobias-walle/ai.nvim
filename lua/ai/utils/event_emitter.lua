---@class ai.EventEmitter.Options
---@field emit_initially? boolean Emit last emitted event on subscription if it exists

---@class ai.EventEmitter<T>
---@field _subscribers table<string|number, fun(event: any)>
---@field _last_event any
---@field _emit_initially boolean
local EventEmitter = {}
EventEmitter.__index = EventEmitter

---Create a new EventEmitter instance.
---@generic T
---@param opts? ai.EventEmitter.Options
---@return ai.EventEmitter<T>
function EventEmitter.new(opts)
  opts = opts or {}
  local self = setmetatable({}, EventEmitter)
  self._subscribers = {}
  self._last_event = nil
  self._emit_initially = opts.emit_initially or false
  return self
end

---Subscribe to events.
---@generic T
---@param callback fun(event: T)
---@param id? string|number Unique identifier for the subscriber.
function EventEmitter:subscribe(callback, id)
  id = id or tostring(callback)
  self._subscribers[id] = callback
  if self._emit_initially and self._last_event ~= nil then
    callback(self._last_event)
  end
end

---Notify all subscribers about an event.
---@generic T
---@param event T
function EventEmitter:notify(event)
  self._last_event = event
  for _, callback in pairs(self._subscribers) do
    callback(event)
  end
end

---Unsubscribe from events.
---@param id string|number
function EventEmitter:unsubscribe(id)
  self._subscribers[id] = nil
end

return EventEmitter
