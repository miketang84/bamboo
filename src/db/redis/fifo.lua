
-- FIFO, we push element from left, pop from right,
-- new element is at left, old element is at right
-- because redis has no reversely retrieve method on list
module(..., package.seeall)

local List = require 'lglib.list'
local rdlist = require 'bamboo.db.redis.list'
local db = BAMBOO_DB
local snippets = bamboo.dbsnippets.set
local cmsgpack = reuqire 'cmsgpack'

function save (key, tbl, length)
	local length = length or 100
	db:eval(snippets.SNIPPET_fifoSave, 0, key, cmsgpack.pack(tbl), length)

    -- for i,v in ipairs(tbl) do 
    --     push(key,v,length);
    -- end
end

function update (key, tbl, length)
    for i,v in ipairs(tbl) do 
        push(key,v,length);
    end
end

function push (key, val, length)
	local length = length or 100
	db:eval(snippets.SNIPPET_fifoPush, 0, key, val, length)

	-- local len = db:llen(key)
	
	-- if len < length then
	-- 	db:rpush(key, val)
	-- else
	-- 	-- if FIFO is full, push this element from left, pop one old from right
	-- 	db:lpop(key)
	-- 	db:rpush(key, val)
	-- end
		
end

function pop( key )

	return rdlist.pop(key)
end

function remove( key, val )

	return rdlist.remove(key, val)
end

function retrieve( key )

	return rdlist.retrieve(key)
end

function len( key )

	return rdlist.len(key)
end

function del( key )
	
	return rdlist.del(key)
end

function fakedel(key)
	return db:rename(key, 'DELETED:' + key)
end

function has(key, obj)
	return rdlist.has(key, obj)
end

