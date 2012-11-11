

module(..., package.seeall)

local List = require 'lglib.list'
local rdzset = require 'bamboo.db.redis.zset'
local db = BAMBOO_DB

function save(key,tbl,length)
    for i,v in ipairs(tbl) do
        push(key,v,length)
    end
end

function update(key,tbl,length)
    for i,v in ipairs(tbl) do
        push(key,v,length)
    end
end


function push( key, val, length )

	local n = db:zcard(key)
	if n < length then
		if n == 0 then
			db:zadd(key, 1, val)
		else
			local _, scores = db:zrange(key, -1, -1, 'withscores')
			local lastscore = scores[1]
			db:zadd(key, lastscore + 1, val)
		end
	else
		local _, scores = db:zrange(key, -1, -1, 'withscores')
		local lastscore = scores[1]

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
		local _, scores = db:zrange(key, 0, 0, 'withscores')
		local score = scores[1]
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
	local values, scores = db:zrevrange(key, 0, -1, 'withscores')
	return List(values), List(scores)
end

function num( key )

	return rdzset.num(key)
end

function del( key )

	return rdzset.del(key)
end

function fakedel(key)
	return db:rename(key, 'DELETED:' + key)
end

function has(key, obj)

	return rdzset.have(key, obj)
end
