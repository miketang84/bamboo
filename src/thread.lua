local llthreads = require "llthreads"

local _M = {}

local new
local _META = {
  __call = function (self, tcode, wait2ret, ...)
    return new(tcode, wait2ret, ...)
  end
}


new = function (tcode, wait2ret, ...)
  -- create child thread.
  local thread = llthreads.new(tcode, ...)
  if wait2ret then
    -- start joinable detached child thread.
    assert(thread:start())
    
    -- we need lua coroutine to swtich to other coroutine when wait child thread
    -- maybe we need modify join method, but it is not an easy thing.
    thread:join()
    
  else 
    -- start non-joinable detached child thread.
    assert(thread:start(true))
  end
end




--[=[
local Thread = require 'bamboo.thread'

local ret1, ret2 = Thread( [[

	.... thread code ....

]], ...

)
]=]