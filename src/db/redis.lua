
local RDS = {}
local redis = require 'bamboo-redis'

function RDS.connect(config_t)
--	local params = {
	local host = config_t.host or '127.0.0.1'
	local port = config_t.port or 6379
--	}
	local which = config_t.which or 0

	local redis_db = redis.connect(host, port)
	if config_t.auth then
		redis_db:auth(config_t.auth)
	end
	redis_db:select(which)

	return redis_db
end

return RDS
