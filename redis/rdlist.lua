module(..., package.seeall)

-- 本文件只负责对redis的list结构的封装
local db = BAMBOO_DB


function saveList( key, tbl )
	local listkey = 'LIST:' + key
	-- 如果存在，先删除前面有的key
	if db:exists(listkey) then
		db:del(listkey)
	end
	
	-- 将table中的所有元素压入redis列表中去
	for _, v in ipairs(tbl) do
		db:rpush(listkey, seri(v))
	end

end

function updateList( key, tbl )
	local listkey = 'LIST:' + key
	-- 先把之前的元素获取出来
	local list = db:lrange(listkey, 0, -1)
	
	if #list == 0 then saveList(key, tbl) end
	
	if #list >= #tbl then
		for i, v in ipairs(tbl) do
			if list[i] ~= v then
				-- 更新不同的元素
				db:lset(listkey, i - 1, seri(v))
			end
		end
		-- 去除多余的元素
		local delta = #list - #tbl
		for i = 1, delta do
			db:rpop(listkey)
		end
	else
		for i, v in ipairs(list) do
			if tbl[i] ~= v then
				-- 更新不同的元素
				db:lset(listkey, i - 1, seri(tbl[i]))
			end
		end
		
		-- 压入多的元素
		local delta = #tbl - #list
		for i = 1, delta do
			db:rpush(listkey, seri(tbl[#list + i]))
		end
	end
end

function appendToList( key, val )
	local listkey = 'LIST:' + key
	-- 如果没有，就创建一个
	-- 有，就附加在后面
	db:rpush(listkey, seri(val))
end

function retrieveList( key )
	local listkey = 'LIST:' + key
	-- 如果没有，就会返回空值
	return db:lrange(listkey, 0, -1)
end

function removeFromList( key, val )
	local listkey = 'LIST:' + key
	
	return db:lrem(listkey, 0, val)
end

function delList( key )
	local listkey = 'LIST:' + key
	
	return db:del(listkey)
end
