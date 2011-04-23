module(..., package.seeall)

-- 本文件只负责对redis的ZFIFO结构的封装
local db = BAMBOO_DB

-- 如果要保持顺序，可以在外面对score的计算中做到
function pushToZfifo( key, length, score, val )
	local store_key = 'ZFIFO:' + key

	-- 获取到当前集合中的元素个数
	local n = db:zcard(store_key)
	if n < length then
		db:zadd(store_key, score, val)
	else
		db:zremrangebyrank(store_key, 0, 0)
		db:zadd(store_key, score, val)
	end
	
end

function popFromZfifo( key )
	local store_key = 'ZFIFO:' + key
	local n = db:zcard(store_key)
	
	if n >= 1 then
		-- 
		local it = db:zrange(store_key, 0, 0, 'withscores')[1]
		local score = it[2]
		db:zremrangebyrank(store_key, 0, 0)
		return score
	else
		return nil
	end
end

function removeFromZfifo( key, score, val )
	local store_key = 'ZFIFO:' + key
	
	if not isFalse(score) then
		db:zremrangebyscore(store_key, score, score)
	elseif not isFalse(val) then
		db:zrem(store_key, val)
	end
end

function retrieveZfifo( key )
	local store_key = 'ZFIFO:' + key

	-- 返回的是一个二重嵌套table
	-- 第一层的每个元素中，[1]为val, [2]为score
	return db:zrevrange(store_key, 0, -1, 'withscores')
end

function lenZfifo( key )
	local store_key = 'ZFIFO:' + key

	return db:zcard(store_key)
end

function delZfifo( key )
	local store_key = 'ZFIFO:' + key
	
	return db:del(store_key)
end
