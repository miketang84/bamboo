local List = require 'lglib.list'

module(..., package.seeall)


local db = BAMBOO_DB

function save(key, tbl, scores)
	db:del(key)
	if not scores then
		local n = 0
		for _, v in ipairs(tbl) do
			db:zadd(key, n + 1, tostring(v))
			n = n + 1
		end
	else
		checkType(scores, 'table')
		assert(#tbl == #scores, '[Error] the lengths of val and scores are not equal.')

		for i, v in ipairs(tbl) do
			local score = scores[i]
			assert(type(tonumber(score)) == 'number', '[Error] Some score in score list is not number.')
			db:zadd(key, score, tostring(v))
		end
	end
end

function update(key, tbl)
	local n = db:zcard(key)

	for _, v in ipairs(tbl) do
		db:zadd(key, n + 1, tostring(v))
		n = n + 1
	end
end



function add( key, val, score )
--	local oscore = db:zscore(key, val)
	-- is exist, do nothing, else redis will update the score of val
--	if oscore then return nil end
	if not score then
		-- get the current element in zset
		local n = db:zcard(key)
		if n == 0 then
			db:zadd(key, 1, val)
		else
			local _, scores = db:zrange(key, -1, -1, 'withscores')
			lastscore = scores[1]
            -- give the new added element score n+1
			db:zadd(key, lastscore + 1, val)
		end
	else
		-- checkType(score, 'number')
		db:zadd(key, score, val)
	end

	-- return the score
	return db:zscore(key, val)
end


function retrieveNormally( key, start, stop, is_rev )
	-- only have members, no scores
--	return List(db:zrange(key, 0, -1))

	local value_list = db:zrange(key, start, stop)
	if is_rev == 'rev' then
		return List(value_list):reverse()
	else
		return List(value_list)
	end
end

-- function retrieveReversely( key )
-- 	return List(db:zrevrange(key, 0, -1))
-- end

function retrieveWithScores( key, start, stop, is_rev )
	-- -- [1] is member, [2] is score
	-- local value_list, score_list = db:zrange(key, 0, -1, 'withscores')
	-- return List(value_list), List(score_list)

	local value_list, score_list = db:zrange(key, start, stop, 'withscores')
	if is_rev == 'rev' then
		return List(value_list):reverse(), List(score_list):reverse()
	else
		return List(value_list), List(score_list)
	end

end

-- function retrieveReverselyWithScores( key )
-- 	-- [1] is member, [2] is score
-- 	local value_list, score_list = db:zrevrange(key, 0, -1, 'withscores')

-- 	return List(value_list), List(score_list)
-- end

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

function fakedel(key)
	return db:rename(key, 'DELETED:' + key)
end

function has(key, obj)

	local score = db:zscore(key, tostring(obj))

	return (score ~= nil)
end

