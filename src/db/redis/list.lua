-- wapper to redis list structure
-- new is at right, old is at left
module(..., package.seeall)

local db = BAMBOO_DB
local List = require 'lglib.list'
local snippets = bamboo.dbsnippets.key2sha
local cmsgpack = require 'cmsgpack'

--- create a list
--
function save( key, tbl )

	db:evalsha(snippets.SNIPPET_listSave, 0, key, cmsgpack.pack(tbl))

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

function has(key, obj)
	-- -- Need To Optimaze
	-- local len = db:llen(key)
	-- for i = 0, len-1 do
	-- 	local elem = db:lindex(key, i)
	-- 	if obj == elem then
	-- 		return true
	-- 	end
	-- end 

	local r = db:evalsha(snippets.SNIPPET_listHas, 0, key, obj)
	if r then 
		return true
	else
		return false
	end
end

