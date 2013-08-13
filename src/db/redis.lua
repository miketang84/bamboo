
local RDS = {}
local redis = require 'bamboo-redis'

function RDS.connect(config_t)
--	local params = {
	local host = config_t.host or '127.0.0.1'
	local port = config_t.port or 6379
--	}
	local db = config_t.db or 0

	local redis_db = redis.connect(host, port)
	if config_t.auth then
		redis_db:auth(config_t.auth)
	end
	redis_db:select(db)

	return redis_db
end

function RDS.connectAll (config)
  -- connect redis, basic db
  config = config or {master={host="127.0.0.1", port=6379}, slaves={}}

  local DB_HOST = config.master.host
  local DB_PORT = config.master.port
  local WHICH_DB = config.master.db or 0
  local AUTH = config.AUTH or config.master.auth

  -- create a redis connection in this process
  -- we will create one redis connection for every process
  local master = RDS.connect { 
    host=DB_HOST, 
    port=DB_PORT, 
    db = WHICH_DB, 
    auth = AUTH}
  assert(master, '[Error] Redis master database connect failed.')
  -- try to connect slaves
  master._slaves = {}
  for i, slave in ipairs(config.slaves or {}) do
    local sdb = RDS.connect {
            host=slave.host, 
            port=slave.port, 
            db = slave.db, 
            auth = slave.auth}
    if sdb then
      table.insert(master._slaves, sdb)
    end
  end
  
  -- keep compatible with old version
  -- _G['BAMBOO_DB'] = master
  return master
end

return RDS
