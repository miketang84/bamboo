local List = require 'lglib.list'

module(..., package.seeall)


local db = BAMBOO_DB
local snippets = bamboo.dbsnippets.set
local cmsgpack = require 'cmsgpack'

-- @param tbl:  a member list
function save(key, tbl)
	db:eval(snippets.SNIPPET_setSave, 0, key, cmsgpack.pack(tbl))

	-- for _, v in ipairs(tbl) do
	-- 	db:sadd(key, tostring(v))
	-- end
end

function update(key, tbl)
	save(key, tbl)
end


function add( key, val )

	return db:sadd(key, val)
end


function retrieve( key )

	return List(db:smembers(key))
end

function remove( key, val )
	
	return db:srem(key, val)
end

function num( key )
	
	return db:scard(key)
end

function del( key )
	
	return db:del(key)
end

function has(key, obj)

	return db:sismember(key, tostring(obj))
end

