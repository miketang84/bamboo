-- wapper to redis list structure
-- new is at right, old is at left
module(..., package.seeall)

local db = BAMBOO_DB
local List = require 'lglib.list'

--- create a list
--
function save( key, tbl )
	-- if exist, remove it first
	if db:exists(key) then
		db:del(key)
	end
	
	-- push all elements in tbl to redis list
	for _, v in ipairs(tbl) do
		db:rpush(key, tostring(v))
	end

end

--- update a list
--
function update( key, tbl )

	local list = db:lrange(key, 0, -1)
	
	if #list == 0 then save(key, tbl) end
	
	if #list >= #tbl then
		for i, v in ipairs(tbl) do
			if list[i] ~= v then
				-- update different elements
				db:lset(key, i - 1, tostring(v))
			end
		end
		-- remove rest elements
		local delta = #list - #tbl
		for i = 1, delta do
			db:rpop(key)
		end
	else
		for i, v in ipairs(list) do
			if tbl[i] ~= v then
				db:lset(key, i - 1, tostring(tbl[i]))
			end
		end
		
		-- push more elements
		local delta = #tbl - #list
		for i = 1, delta do
			db:rpush(key, tostring(tbl[#list + i]))
		end
	end
end

function retrieve( key )
	-- if no element exists, return empty list
	return List(db:lrange(key, 0, -1))
end

function append( key, val )
	-- if have no, create one
	-- if have, append to it
	return db:rpush(key, tostring(val))
end

function prepend( key, val )
	return db:lpush(key, tostring(val))
end

function pop( key )
	return db:rpop(key)
end 

function remove( key, val )
	
	return db:lrem(key, 0, val)
end

function removeByIndex( key, index )
	local elem = db:lindex(key, index)
	if elem then
		return db:lrem(key, 0, elem)
	end 

	return nil
end

function len( key )

	return db:llen(key)
end

function del( key )
	
	return db:del(key)
end

function have(key, obj)
	local len = db:llen(key)
	for i = 0, len-1 do
		local elem = db:lindex(i)
		if obj == elem then
			return true
		end
	end 

	return false
end

