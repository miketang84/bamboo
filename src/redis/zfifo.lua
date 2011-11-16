

module(..., package.seeall)

local List = require 'lglib.list'
local rdzset = require 'bamboo.redis.zset'
local db = BAMBOO_DB

function save()
end

function update()
end


function push( key, length, val )

	local n = db:zcard(key)
	if n < length then
		if n == 0 then
			db:zadd(key, 1, val)
		else
			local lastscore = db:zrange(key, -1, -1, 'withscores')[1][2]
			db:zadd(key, lastscore + 1, val)
		end 
	else
		-- get the last element ([1]) 's score ([2]) 
		local lastscore = db:zrange(key, -1, -1, 'withscores')[1][2]

		-- remove the oldest one
		db:zremrangebyrank(key, 0, 0)
		-- add the new one
		db:zadd(key, lastscore + 1, val)
	end
	
end

function pop( key )
	local n = db:zcard(key)
	
	if n >= 1 then
		-- 
		local it = db:zrange(key, 0, 0, 'withscores')[1]
		local score = it[2]
		db:zremrangebyrank(key, 0, 0)
		return score
	else
		return nil
	end
end

function remove( key, val )
	return rdzset.remove(key, val)
end

function removeByScore(key, score)
	return rdzset.removeByScore(key, score)
end


function retrieve( key )
	-- reverse get

	return List(db:zrevrange(key, 0, -1))
end

function retrieveWithScores(key)
	-- every element, [1] is val, [2] is score
	return List(db:zrevrange(key, 0, -1, 'withscores'))
end 

function num( key )

	return rdzset.num(key)
end

function del( key )
	
	return rdzset.del(key)
end

function has(key, obj)

	return rdzset.have(key, obj) 
end
