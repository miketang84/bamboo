module('bamboo.redis', package.seeall)

require 'redis'

function connect(config_t)
	local params = {
		host = config_t.host or '127.0.0.1',
		port = config_t.port or 6379,
	}
	local which = config_t.which or 0

	local redis_db = Redis.connect(params)
	redis_db:select(which)

	return redis_db
end


