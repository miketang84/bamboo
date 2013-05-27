--
-- Now this module can be used only in sync mode in persist connction
-- and in async mode in each connection per request
-- later will enhance it.
-- 
module(..., package.seeall)


local mongol = require "mongol"

-- For background tasks
local SUSPENDED_TASKS = {}
local SUSPENDED_SOCKETS = {}

local mongoCoroDispatcher = function (loop, io_watcher, revents)

  -- wait for database return 
  local state = SUSPENDED_TASKS[io_watcher]
  if state then 
    coroutine.resume(state)
    
    if coroutine.status(state) == "dead" then
      SUSPENDED_TASKS[io_watcher] = nil
      SUSPENDED_SOCKETS[io_watcher].sock:close()
      SUSPENDED_SOCKETS[io_watcher] = nil
      io_watcher:stop(loop)
    end
  end
end

-- useage:
-- local mongo = require 'bamboo.db.mongo'
-- local conn = mongo.connect(mongo_config)
-- local db = conn:use('one_db_name')
-- 
function connect(mongo_config)
  local config = mongo_config or { host="127.0.0.1", port=27017 }
  
  local conn 
  -- async mode
  if config.async then
    conn = mongol(config.host, config.port, bamboo.internal.loop, mongoCoroDispatcher)
  else
    -- sync mode
    conn = mongol(config.host, config.port)
  end
  assert(conn, '[Error] connect to mongodb failed.')
  local db = conn:use(config.db)
  
  return db
end

