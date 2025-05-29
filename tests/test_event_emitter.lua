local eq = MiniTest.expect.equality

local T = MiniTest.new_set()

T['EventEmitter'] = MiniTest.new_set()

T['EventEmitter']['should notify a single subscriber'] = function()
  local EventEmitter = require('ai.utils.event_emitter')
  local emitter = EventEmitter.new()
  local received = nil
  emitter:subscribe(function(event)
    received = event
  end, 'test')
  emitter:notify('hello')
  eq(received, 'hello')
end

T['EventEmitter']['should notify multiple subscribers'] = function()
  local EventEmitter = require('ai.utils.event_emitter')
  local emitter = EventEmitter.new()
  local received1, received2 = nil, nil
  emitter:subscribe(function(event)
    received1 = event
  end, 'a')
  emitter:subscribe(function(event)
    received2 = event
  end, 'b')
  emitter:notify({ foo = 'bar' })
  eq(received1, { foo = 'bar' })
  eq(received2, { foo = 'bar' })
end

T['EventEmitter']['should not notify unsubscribed subscribers'] = function()
  local EventEmitter = require('ai.utils.event_emitter')
  local emitter = EventEmitter.new()
  local called = false
  emitter:subscribe(function()
    called = true
  end, 'x')
  emitter:unsubscribe('x')
  emitter:notify('event')
  eq(called, false)
end

T['EventEmitter']['should overwrite subscriber with same id'] = function()
  local EventEmitter = require('ai.utils.event_emitter')
  local emitter = EventEmitter.new()
  local value = 0
  emitter:subscribe(function()
    value = 1
  end, 'dup')
  emitter:subscribe(function()
    value = 2
  end, 'dup')
  emitter:notify('event')
  eq(value, 2)
end

T['EventEmitter']['should handle no subscribers gracefully'] = function()
  local EventEmitter = require('ai.utils.event_emitter')
  local emitter = EventEmitter.new()
  -- Should not error
  emitter:notify('anything')
  eq(true, true)
end

T['EventEmitter']['should support numeric ids'] = function()
  local EventEmitter = require('ai.utils.event_emitter')
  local emitter = EventEmitter.new()
  local got = nil
  emitter:subscribe(function(event)
    got = event
  end, 123)
  emitter:notify('num')
  eq(got, 'num')
end

T['EventEmitter']['should allow unsubscribing one of multiple subscribers'] = function()
  local EventEmitter = require('ai.utils.event_emitter')
  local emitter = EventEmitter.new()
  local got_a, got_b = false, false
  emitter:subscribe(function()
    got_a = true
  end, 'a')
  emitter:subscribe(function()
    got_b = true
  end, 'b')
  emitter:unsubscribe('a')
  emitter:notify('event')
  eq(got_a, false)
  eq(got_b, true)
end

T['EventEmitter']['should emit last event to new subscriber if emit_initially is true'] = function()
  local EventEmitter = require('ai.utils.event_emitter')
  local emitter = EventEmitter.new({ emit_initially = true })
  local received = nil
  emitter:notify('initial')
  emitter:subscribe(function(event)
    received = event
  end, 'late')
  eq(received, 'initial')
end

T['EventEmitter']['should allow subscribing without id and still receive events'] = function()
  local EventEmitter = require('ai.utils.event_emitter')
  local emitter = EventEmitter.new()
  local received = nil
  emitter:subscribe(function(event)
    received = event
  end)
  emitter:notify('anon')
  eq(received, 'anon')
end

T['EventEmitter']['should allow multiple anonymous subscribers'] = function()
  local EventEmitter = require('ai.utils.event_emitter')
  local emitter = EventEmitter.new()
  local got1, got2 = false, false
  emitter:subscribe(function()
    got1 = true
  end)
  emitter:subscribe(function()
    got2 = true
  end)
  emitter:notify('event')
  eq(got1, true)
  eq(got2, true)
end

return T
