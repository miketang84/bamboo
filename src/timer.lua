--
-- define setTimeout and setInterval functions like javascript
-- 
local _G = _G
local ev = require'ev'
local loop = bamboo.internal.loop

local _M = {}


local function timer_cb()
	zpub:send(tostring(msg_id))
  msg_id = msg_id + 1
end



_G.setTimeout = function (func, seconds) 
  assert(type(func)=='function', '#1 of setTimeout must be function.')
  local timer = ev.Timer.new(func, seconds)
  timer:start(loop)
end


_G.setInterval = function (func, seconds) 
  assert(type(func)=='function', '#1 of setInterval must be function.')
  local timer = ev.Timer.new(func, seconds, seconds)
  timer:start(loop)
end

return _M
