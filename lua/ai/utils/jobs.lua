local M = {}

---@class Job -- A asynchronous job
---@field stop fun(): nil -- Kill the running job
local Job = {}
Job.__index = {}
M.Job = Job

---@param opts Job
---@return Job
function Job:new(opts)
  return setmetatable(opts, self)
end

return M
