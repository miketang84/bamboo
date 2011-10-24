local List = require 'lglib.list'

module(..., package.seeall)


local db = BAMBOO_DB

function save(key, tbl)
	db:del(key)
	local n = 0
	for _, v in ipairs(tbl) do
		db:zadd(key, n + 1, tostring(v))
		n = n + 1
	end 
end

function update(key, tbl)
	local n = db:zcard(key)
	
	for _, v in ipairs(tbl) do
		db:zadd(key, n + 1, tostring(v))
		n = n + 1
	end 
end



function add( key, val )
	local score = db:zscore(key, val)
	-- is exist, do nothing, else redis will update the score of val
	if score then return nil end
	
	-- get the current element in zset
	local n = db:zcard(key)
	if n == 0 then
		db:zadd(key, 1, val)
	else
		local lastscore = db:zrange(key, -1, -1, 'withscores')[1][2]
		-- give the new added element score n+1
		db:zadd(key, lastscore + 1, val)
	end	

	-- return the score 
	return db:zscore(key, val)
end


function retrieve( key )

	-- only have members, no scores
	return List(db:zrange(key, 0, -1))
end

function retrieveReversely( key )
	return List(db:zrevrange(key, 0, -1))
end 

function retrieveWithScores( key )
	-- [1] is member, [2] is score
	return List(db:zrange(key, 0, -1, 'withscores'))
end

function retrieveReverselyWithScores( key )
	-- [1] is member, [2] is score
	return List(db:zrevrange(key, 0, -1, 'withscores'))
end

function remove( key, val )
	return db:zrem(key, val)
end

function removeByScore(key, score)
	return db:zremrangebyscore(key, score, score)
end

function num( key )
	
	return db:zcard(key)
end

function del( key )
	
	return db:del(key)
end

function have(key, obj)

	local score = db:zscore(key, tostring(obj))

	return (score ~= nil) 
end

