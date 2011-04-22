module(..., package.seeall)

-- 本文件只负责对redis的FIFO结构的封装
local db = BAMBOO_DB


function pushToFifo( key, length, val )
	local store_key = 'FIFO:' + key
	local len = db:llen(store_key)
	
	if len < length then
		db:lpush(store_key, val)
	else
		-- 如果FIFO已经满了，就从右边弹出，左边压入
		db:rpop(store_key)
		db:lpush(store_key, val)
	end
		
end

function popFromFifo( key )
	local store_key = 'FIFO:' + key
	local len = db:llen(store_key)
	
	-- 如果至少有一个元素
	if len >= 1 then
		return db:rpop(store_key)
	else
		return nil
	end
end

function removeFromFifo( key, val )
	local store_key = 'FIFO:' + key
	
	return db:lrem(store_key, 0, val)
end

function retrieveFifo( key )
	local store_key = 'FIFO:' + key

	return db:lrange(store_key, 0, -1)
	
end

function lenFifo( key )
	local store_key = 'FIFO:' + key

	return db:llen(store_key, 0, -1)
end



function delFifo( key )
	local store_key = 'FIFO:' + key
	
	return db:del(store_key)
end
