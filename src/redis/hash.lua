module(..., package.seeall)

local db = BAMBOO_DB

--- create a list
--
function save( key, tbl )
	-- if exist, remove it first
	if db:exists(key) then
		db:del(key)
	end
	
	-- push all elements in tbl to redis hash
	for k, v in pairs(tbl) do
		db:hset(key, k, tostring(v))
	end
end

--- update a list
--
function update( key, tbl )
	for k, v in pairs(tbl) do
		db:hset(key, k, tostring(v))
	end
end

function retrieve( key )
	return db:hgetall(key)
end

-- in hash store, passed into add function should be a table
-- such as { good = true }
function add( key, tbl )
	update(key, tbl)
end

-- in hash store, passed into remove function should be a table
-- remove action will check the key and value's equality before real deletion
function remove(key, tbl)
	for k, v in pairs(tbl) do
		if db:hget(key, k) == tostring(v) then
			db:hdel(key, k)
		end
	end
end

function have(key, keytocheck)
	if db:hget(key, keytocheck) then
		return true
	else
		return false
	end
end

