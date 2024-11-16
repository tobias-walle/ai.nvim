local co = coroutine

--- Executes a function within a coroutine and handles its completion.
--- @generic T
--- @param func fun():T The function to execute within the coroutine.
--- @param callback fun(result:T) The callback function to call upon completion.
local pong = function(func, callback)
  assert(type(func) == 'function', 'type error :: expected func')
  local thread = co.create(func)
  local step = nil
  step = function(...)
    local pack = { co.resume(thread, ...) }
    local status = pack[1]
    local ret = pack[2]
    assert(status, ret)
    if co.status(thread) == 'dead' then
      if callback then
        (function(_, ...)
          callback(...)
        end)(table.unpack(pack))
      end
    else
      assert(
        type(ret) == 'function',
        'type error :: expected func - coroutine yielded some value'
      )
      ret(step)
    end
  end
  step()
end

--- Wraps a function to create a thunk factory.
--- @generic T
--- @param func fun(...):T The function to wrap.
--- @return fun(...):fun(step?: fun(result:T)) -- A thunk factory.
local wrap_any = function(func)
  assert(type(func) == 'function', 'type error :: expected func')
  local factory = function(...)
    local params = { ... }
    local thunk = function(step)
      table.insert(params, step)
      return func(unpack(params))
    end
    return thunk
  end
  return factory
end

--- @generic T
--- @param func fun( callback: fun(result: T)):unknown
--- @return fun(): fun(step?: fun(result:T))
local wrap_0 = function(func)
  return wrap_any(func)
end

--- @generic T, A
--- @param func fun(a: A, callback: fun(result: T)):unknown
--- @return fun(a: A): fun(step?: fun(result:T))
local wrap_1 = function(func)
  return wrap_any(func)
end

--- @generic T, A, B
--- @param func fun(a: A, b: B, callback: fun(result: T)):unknown
--- @return fun(a: A, b: B):fun(step?: fun(result:T))
local wrap_2 = function(func)
  return wrap_any(func)
end

--- @generic T, A, B, C
--- @param func fun(a: A, b: B, c: C, callback: fun(result: T)):unknown
--- @return fun(a: A, b: B, c: C):fun(step?: fun(result:T))
local wrap_3 = function(func)
  return wrap_any(func)
end

--- @generic T, A, B, C, D
--- @param func fun(a: A, b: B, c: C, d: D, callback: fun(result: T)):unknown
--- @return fun(a: A, b: B, c: C, d: D):fun(step?: fun(result:T))
local wrap_4 = function(func)
  return wrap_any(func)
end

--- @generic T, A, B, C, D, E
--- @param func fun(a: A, b: B, c: C, d: D, e: E, callback: fun(result: T)):unknown
--- @return fun(a: A, b: B, c: C, d: D, e: E):fun(step?: fun(result:T))
local wrap_5 = function(func)
  return wrap_any(func)
end

--- Joins multiple thunks into a single thunk.
--- @generic T
--- @param thunks fun(step:fun(result:T))[] The array of thunks to join.
--- @return fun(step:fun(results:T[])) A single thunk that represents the joined thunks.
local join = function(thunks)
  local len = #thunks
  local done = 0
  local acc = {}

  local thunk = function(step)
    if len == 0 then
      return step()
    end
    for i, tk in ipairs(thunks) do
      assert(type(tk) == 'function', 'thunk must be function')
      local callback = function(...)
        acc[i] = { ... }
        done = done + 1
        if done == len then
          step(acc)
        end
      end
      tk(callback)
    end
  end
  return thunk
end

--- Suspends the execution of the current coroutine, yielding control to the provided function.
--- @generic T
--- @param defer fun(step?: fun(result: T))
--- @return T The result of the deferred function.
local await = function(defer)
  assert(type(defer) == 'function', 'type error :: expected func')
  return co.yield(defer)
end

--- Suspends the execution of the current coroutine, yielding control to the provided array of functions.
--- @generic T
--- @param defer (fun():T)[] The array of functions to defer.
--- @return T[] The result of the deferred functions.
local await_all = function(defer)
  assert(type(defer) == 'table', 'type error :: expected table')
  return co.yield(join(defer))
end

local async = wrap_1(pong)

return {
  async = async,
  await = await,
  await_all = await_all,
  wrap_0 = wrap_0,
  wrap_1 = wrap_1,
  wrap_2 = wrap_2,
  wrap_3 = wrap_3,
  wrap_4 = wrap_4,
  wrap_5 = wrap_5,
}
