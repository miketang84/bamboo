module(..., package.seeall)


local db = BAMBOO_DB

-- @param tbl:  a member list
function save(key, val)
	db:set(key, val)
end

update = save
add = save

function retrieve(key)
	return db:get(key)
end

function remove(key, val)
	return db:set(key, '')
end

function num( key )
	return 1
end

function del( key )
	return db:del(key)
end

function has(key, obj)
	return db:get(key) == obj
end

