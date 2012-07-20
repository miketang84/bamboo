



-----------------------------------------------------------------
-- Cache API
--- seven APIs
-- 1. setCache
-- 2. getCache
-- 3. delCache
-- 4. existCache
-- 5. addCacheMember
-- 6. removeCacheMember
-- 7. hasCacheMember
-- 8. numCache
-- 9. lifeCache
-----------------------------------------------------------------
setCache = function (self, key, vals, orders)
I_AM_CLASS(self)
checkType(key, 'string')
local cache_key = getCacheKey(self, key)
local cachetype_key = getCachetypeKey(self, key)

if type(vals) == 'string' or type(vals) == 'number' then
	db:set(cache_key, vals)
else
	-- checkType(vals, 'table')
	local new_vals = {}
	-- if `vals` is a list, insert its element's id into `new_vals`
	-- ignore the uncorrent element
	
	-- elements in `vals` are ordered, but every element itself is not
	-- nessesary containing enough order info.
	-- for number, it contains enough
	-- for others, it doesn't contain enough
	-- so, we use `orders` to specify the order info
	if #vals >= 1 then
		if isValidInstance(vals[1]) then
			-- save instances' id
			for i, v in ipairs(vals) do
				table.insert(new_vals, v.id)
			end
			
			db:set(cachetype_key, 'instance')
		else
			new_vals = vals
			db:set(cachetype_key, 'general')
		end
	end
		
	rdzset.save(cache_key, new_vals, orders)
end

-- set expiration
db:expire(cache_key, bamboo.config.cache_life or bamboo.CACHE_LIFE)
db:expire(cachetype_key, bamboo.config.cache_life or bamboo.CACHE_LIFE)

end;


getCache = function (self, key, start, stop, is_rev)
I_AM_CLASS(self)
checkType(key, 'string')
local cache_key = getCacheKey(self, key)
local cachetype_key = getCachetypeKey(self, key)

local cache_data_type = db:type(cache_key)
local cache_data
if cache_data_type == 'string' then
	cache_data = db:get(cache_key)
	if isFalse(cache_data) then return nil end
elseif cache_data_type == 'zset' then
	cache_data = rdzset.retrieve(cache_key)
	if start or stop then
		cache_data = cache_data:slice(start, stop, is_rev)
	end
	if isFalse(cache_data) then return List() end
end


local cachetype = db:get(cachetype_key)
if cachetype and cachetype == 'instance' then
	-- if cached instance, return instance list
	local cache_objects = getFromRedisPipeline(self, cache_data)
	
	return cache_objects
else
	-- else return element list directly
	return cache_data
end

db:expire(cache_key, bamboo.config.cache_life or bamboo.CACHE_LIFE)
db:expire(cachetype_key, bamboo.config.cache_life or bamboo.CACHE_LIFE)

end;

delCache = function (self, key)
I_AM_CLASS(self)
checkType(key, 'string')
local cache_key = getCacheKey(self, key)
local cachetype_key = getCachetypeKey(self, key)

db:del(cachetype_key)
return db:del(cache_key)	

end;

-- check whether exist cache key
existCache = function (self, key)
I_AM_CLASS(self)
local cache_key = getCacheKey(self, key)

return db:exists(cache_key)
end;

-- 
addCacheMember = function (self, key, val, score)
I_AM_CLASS(self)
checkType(key, 'string')
local cache_key = getCacheKey(self, key)
local cachetype_key = getCachetypeKey(self, key)

local store_type = db:type(cache_key)

if store_type == 'zset' then
	if cachetype_key == 'instance' then
		-- `val` is instance
		checkType(val, 'table')
		if isValidInstance(val) then
			rdzset.add(cache_key, val.id, score)
		end
	else
		-- `val` is string or number
		rdzset.add(cache_key, tostring(val), score)
	end
elseif store_type == 'string' then
	db:set(cache_key, val)
end

db:expire(cache_key, bamboo.config.cache_life or bamboo.CACHE_LIFE)
db:expire(cachetype_key, bamboo.config.cache_life or bamboo.CACHE_LIFE)

end;

removeCacheMember = function (self, key, val)
I_AM_CLASS(self)
checkType(key, 'string')
local cache_key = getCacheKey(self, key)
local cachetype_key = getCachetypeKey(self, key)

local store_type = db:type(cache_key)

if store_type == 'zset' then
	if cachetype_key == 'instance' then
		-- `val` is instance
		checkType(val, 'table')
		if isValidInstance(val) then
			rdzset.remove(cache_key, val.id)
		end
	else
		-- `val` is string or number
		rdzset.remove(cache_key, tostring(val))
	end

elseif store_type == 'string' then
	db:set(cache_key, '')
end

db:expire(cache_key, bamboo.config.cache_life or bamboo.CACHE_LIFE)
db:expire(cachetype_key, bamboo.config.cache_life or bamboo.CACHE_LIFE)

end;

hasCacheMember = function (self, key, mem)
I_AM_CLASS(self)
checkType(key, 'string')
local cache_key = getCacheKey(self, key)
local cachetype_key = getCachetypeKey(self, key)

local store_type = db:type(cache_key)

if store_type == 'zset' then
	if cachetype_key == 'instance' then
		-- `val` is instance
		checkType(mem, 'table')
		if isValidInstance(val) then
			return rdzset.has(cache_key, val.id)
		end
	else
		-- `val` is string or number
		return rdzset.has(cache_key, tostring(mem))
	end

elseif store_type == 'string' then
	return db:get(cache_key) == mem
end

db:expire(cache_key, bamboo.config.cache_life or bamboo.CACHE_LIFE)
db:expire(cachetype_key, bamboo.config.cache_life or bamboo.CACHE_LIFE)
end;

numCache = function (self, key)
I_AM_CLASS(self)

local cache_key = getCacheKey(self, key)
local cachetype_key = getCachetypeKey(self, key)

db:expire(cache_key, bamboo.config.cache_life or bamboo.CACHE_LIFE)
db:expire(cachetype_key, bamboo.config.cache_life or bamboo.CACHE_LIFE)

local store_type = db:type(cache_key)
if store_type == 'zset' then
	return rdzset.num(cache_key)
elseif store_type == 'string' then
	return 1
end
end;

lifeCache = function (self, key)
I_AM_CLASS(self)
checkType(key, 'string')
local cache_key = getCacheKey(self, key)

return db:ttl(cache_key)
end;


addToCacheAndSortBy = function (self, cache_key, field, sort_func)
	I_AM_INSTANCE(self)
	checkType(cache_key, field, 'string', 'string')
	
	--DEBUG(cache_key)
	--DEBUG('entering addToCacheAndSortBy')
	local cache_saved_key = getCacheKey(self, cache_key)
	if not db:exists(cache_saved_key) then 
		print('[WARNING] The cache is missing or expired.')
		return nil
	end
	
	local cached_ids = db:zrange(cache_saved_key, 0, -1)
	local head = db:hget(getNameIdPattern2(self, cached_ids[1]), field)
	local tail = db:hget(getNameIdPattern2(self, cached_ids[#cached_ids]), field)
	assert(head and tail, "[Error] @addToCacheAndSortBy. the object referring to head or tail of cache list may be deleted, please check.")
	--DEBUG(head, tail)
	local order_type = 'asc'
	local field_value, stop_id
	local insert_position = 0
	
	if head > tail then order_type = 'desc' end
	-- should always keep `a` and `b` have the same type
	local sort_func = sort_func or function (a, b)
		if order_type == 'asc' then
			return a > b
		elseif order_type == 'desc' then
			return a < b
		end
	end
	
	--DEBUG(order_type)
	-- find the inserting position
	-- FIXME: use 2-part searching method is better
	for i, id in ipairs(cached_ids) do
		field_value = db:hget(getNameIdPattern2(self, id), field)
		if sort_func(field_value, self[field]) then
			stop_id = db:hget(getNameIdPattern2(self, id), 'id')
			insert_position = i
			break
		end
	end
	--DEBUG(insert_position)

	local new_score
	if insert_position == 0 then 
		-- means till the end, all element is smaller than self.field
		-- insert_position = #cached_ids
		-- the last element's score + 1
		local end_score = db:zrange(cache_saved_key, -1, -1, 'withscores')[1][2]
		new_score = end_score + 1
	
	elseif insert_position == 1 then
		-- get the half of the first element
		local stop_score = db:zscore(cache_saved_key, stop_id)
		new_score = tonumber(stop_score) / 2
	elseif insert_position > 1 then
		-- get the middle value of the left and right neighbours
		local stop_score = db:zscore(cache_saved_key, stop_id)
		local stopprev_rank = db:zrank(cache_saved_key, stop_id) - 1
		local stopprev_score = db:zrange(cache_saved_key, stopprev_rank, stopprev_rank, 'withscores')[1][2]
		new_score = tonumber(stop_score + stopprev_score) / 2
	
	end
	
	--DEBUG(new_score)
	-- add new element to cache
	db:zadd(cache_saved_key, new_score, self.id)
		
	
	return self
end;
