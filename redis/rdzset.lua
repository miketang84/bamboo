module(..., package.seeall)

-- 本文件只负责对redis的ZSET结构的封装
local db = BAMBOO_DB


function addToZset( key, val )
	local zsetkey = 'ZSET:' + key
	-- 如果没有，就创建一个
	-- 有，就附加在后面
	local score = db:zscore(zsetkey, val)
	-- 如果存在，就不再添加，不然会更新score，会导致排序变化
	if score then return nil end
	-- 获取到当前集合中的元素个数
	local n = db:zcard(zsetkey)
	-- 给新添加的元素的分值为n+1
	db:zadd(zsetkey, n + 1, val)
	
	return db:zscore(zsetkey, val)
end


function retrieveZset( key )
	local zsetkey = 'ZSET:' + key
	-- 获取集合中的所有元素，返回一个list，元素间按score排序
	return db:zrange(zsetkey, 0, -1)
end

function removeFromZset( key, val )
	local zsetkey = 'ZSET:' + key
	
	return db:zrem(zsetkey, val)
end

function lenZset( key )
	local zsetkey = 'ZSET:' + key
	
	return db:zcard(zsetkey)
end

function delZset( key )
	local zsetkey = 'ZSET:' + key
	
	return db:del(zsetkey)
end
