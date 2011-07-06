local List = require 'lglib.list'

module(..., package.seeall)


local db = BAMBOO_DB

function saveSet(key, val_table)


end

function updateSet(key, val_table)


end



function addToSet( key, val )
	local zsetkey = 'SET:' + key
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


function retrieveSet( key )
	local zsetkey = 'SET:' + key
	-- 获取集合中的所有元素，返回一个list，元素间按score排序
	return List(db:zrange(zsetkey, 0, -1))
end

function removeFromSet( key, val )
	local zsetkey = 'SET:' + key
	
	return db:zrem(zsetkey, val)
end

function lenSet( key )
	local zsetkey = 'SET:' + key
	
	return db:zcard(zsetkey)
end

function delSet( key )
	local zsetkey = 'SET:' + key
	
	return db:del(zsetkey)
end

function inSet(key, obj)
	local zsetkey = 'SET:' + key

	local score = db:zscore(zsetkey, tostring(obj))

	return (score ~= nil) 
end

