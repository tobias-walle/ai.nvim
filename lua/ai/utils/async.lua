local co = coroutine

--- Just mark a type as async. Due to limitations to the lua language server this is not fully typesafe.
--- @alias Async<T> T

--- Executes a function within a coroutine and handles its completion.
--- @generic T
--- @param func fun(): T|nil The function to execute within the coroutine.
--- @param callback fun(result: T) The callback function to call upon completion.
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

--- Wraps a function to create a defer factory.
--- @generic T
--- @param func fun(...):T The function to wrap.
--- @return fun(...):fun(step?: fun(result:T)) -- A defer factory.
local wrap_any = function(func)
  assert(type(func) == 'function', 'type error :: expected func')
  local factory = function(...)
    local params = { ... }
    local defer = function(step)
      table.insert(params, step)
      return func(unpack(params))
    end
    return defer
  end
  return factory
end

--- @generic T
--- @param func fun(callback: fun(result: T))
--- @return fun(): Async<T>
local wrap_0 = function(func)
  return wrap_any(func)
end

--- @generic T, A
--- @param func fun(a: A, callback: fun(result: T))
--- @return fun(a: A): Async<T>
local wrap_1 = function(func)
  return wrap_any(func)
end

--- @generic T, A, B
--- @param func fun(a: A, b: B, callback: fun(result: T))
--- @return fun(a: A, b: B): Async<T>
local wrap_2 = function(func)
  return wrap_any(func)
end

--- @generic T, A, B, C
--- @param func fun(a: A, b: B, c: C, callback: fun(result: T))
--- @return fun(a: A, b: B, c: C): Async<T>
local wrap_3 = function(func)
  return wrap_any(func)
end

--- @generic T, A, B, C, D
--- @param func fun(a: A, b: B, c: C, d: D, callback: fun(result: T))
--- @return fun(a: A, b: B, c: C, d: D): Async<T>
local wrap_4 = function(func)
  return wrap_any(func)
end

--- @generic T, A, B, C, D, E
--- @param func fun(a: A, b: B, c: C, d: D, e: E, callback: fun(result: T))
--- @return fun(a: A, b: B, c: C, d: D, e: E): Async<T>
local wrap_5 = function(func)
  return wrap_any(func)
end

--- Joins multiple async values into a single one.
--- @generic T
--- @param async_values Async<T>[]
--- @return Async<T[]>
local join = function(async_values)
  local len = #async_values
  local done = 0
  local acc = {}

  --- @type any
  local defer = function(step)
    if len == 0 then
      return step()
    end
    for i, tk in ipairs(async_values) do
      assert(type(tk) == 'function', 'defer must be function')
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
  return defer
end

--- Suspends the execution of the current coroutine, yielding control to the provided function.
--- @generic T
--- @param async_value Async<T>
--- @return T
local await = function(async_value)
  assert(type(async_value) == 'function', 'type error :: expected func')
  return co.yield(async_value)
end

--- Suspends the execution of the current coroutine, yielding control to the provided array of functions.
--- @generic T
--- @param async_values Async<T>[] The array of functions to defer.
--- @return T[] The result of the deferred functions.
local await_all = function(async_values)
  assert(type(async_values) == 'table', 'type error :: expected table')
  return co.yield(join(async_values))
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
