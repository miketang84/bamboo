module(..., package.seeall)

local db = BAMBOO_DB

local List = require 'lglib.list'
local rdlist = require 'bamboo.redis.list'
local rdset = require 'bamboo.redis.set'
local rdzset = require 'bamboo.redis.zset'
local rdfifo = require 'bamboo.redis.fifo'
local rdzfifo = require 'bamboo.redis.zfifo'

local getModelByName  = bamboo.getModelByName 


-- return the key of some string like 'User:__index'
--
local function getIndexKey(self)
	return self.__name  + ':__index'
end

local function getCounterName(self)
	return self.__name + ':__counter'
end 

-- return the key of some string like 'User'
--
local function getClassName(self)
	if type(self) ~= 'table' then return nil end
	return self.__tag:match('%.(%w+)$')
end

local function getClassIdPattern(self)
	return getClassName(self) + self.id
end

local function getNameIdPattern(self)
	return self.__name + ':' + self.id
end

local function getFieldPattern(self, field)
	return getNameIdPattern(self) + ':' + field
end 

local function getCustomKey(self, key)
	return getClassName(self) + ':custom:' + key
end

-- in model global index cache (backend is zset),
-- check the existance of some member by its id (score)
--
local function checkExistanceById(self, id)
	local index_key = getIndexKey(self)
	local r = db:zrangebyscore(index_key, id, id)
	if #r == 0 then 
		return false, ''
	else
		-- return the first element, for r is a list
		return true, r[1]
	end
end

-- return the model part and the id part
-- if normal case, get the model string and return item directly
-- if UNFIXED case, split the UNFIXED model:id and return  
-- this function doesn't suite ANYSTRING case
local function checkUnfixed(fld, item)
	local foreign = fld.foreign
	local link_model, linked_id
	if foreign == 'UNFIXED' then
		local link_model_str
		link_model_str, linked_id = item:match('^(%w+):(%d+)$')
		assert(link_model_str)
		assert(linked_id)
		link_model = getModelByName(link_model_str)
	else 
		link_model = getModelByName(foreign)
		assert(link_model, ("[Error] The foreign part (%s) of this field is not a valid model."):format(foreign))
		linked_id = item
	end

	return link_model, linked_id
end

------------------------------------------------------------
-- this function can only be called by Model
-- @param model_key:
--
local getFromRedis = function (self, model_key)
	-- here, the data table contain ordinary field, ONE foreign key, but not MANY foreign key 
	local data = db:hgetall(model_key)
	if not isValidInstance(data) then print("[Warning] Can't get object by", model_key); return nil end

	local fields = self.__fields
	for k, fld in pairs(fields) do
		-- ensure the correction of field description table
		checkType(fld, 'table')
		if fld.foreign then
			local st = fld.st
			-- in redis, we don't save MANY foreign key in db, but we want to fill them when
			-- form lua object
			if st == 'MANY' then
				data[k] = 'FOREIGN MANY'
			elseif st == 'FIFO' then
				data[k] = 'FOREIGN FIFO'
			elseif st == 'ZFIFO' then
				data[k] = 'FOREIGN ZFIFO'
			end
		end
	end

	-- generate an object
	-- XXX: maybe can put 'data' as parameter of self()
	local obj = self()
	table.update(obj, data)
	return obj
end 

--------------------------------------------------------------
-- this function can only be called by instance
--
local delFromRedis = function (self)
	local model_key = getNameIdPattern(self)
	local index_key = getIndexKey(self)
	
	local fields = self.__fields
	-- in redis, delete the associated foreign key-value store
	for k, v in pairs(self) do
		local fld = fields[k]
		if fld and fld.foreign then
			local key = model_key + ':' + k
			if fld.st == 'MANY' then
				rdzset.del(key)
			elseif fld.st == 'FIFO' then
				rdfifo.del(key)
			elseif fld.st == 'ZFIFO' then
				rdzfifo.del(key)
			end
		end
	end

	-- delete the key self
	db:del(model_key)
	-- delete the index in the global model index zset
	db:zremrangebyscore(index_key, self.id, self.id)
	-- release the lua object
	self = nil
end

--------------------------------------------------------------------------------
-- The bellow four assertations, they are called only by class, instance or query set
--
_G['I_AM_CLASS'] = function (self)
	local ok = self:isClass() 
	if not ok then
		print(debug.traceback())
		error('[Error] This function is only allowed to be called by class.', 3)
	end
end

_G['I_AM_CLASS_OR_QUERY_SET'] = function (self)
	local ok = self:isClass() or self.__spectype == 'QuerySet'
	if not ok then
		print(debug.traceback())
		error('[Error] This function is only allowed to be called by class or query set.', 3)
	end

end

_G['I_AM_INSTANCE'] = function (self)
	local ok = self:isInstance()
	if not ok then
		print(debug.traceback())
		error('[Error] This function is only allowed to be called by instance.', 3)
	end
end

_G['I_AM_INSTANCE_OR_QUERY_SET'] = function (self)
	local ok = self:isInstance() or self.__spectype == 'QuerySet'
	if not ok then
		print(debug.traceback())
		error('[Error] This function is only allowed to be called by instance or query set.', 3)
	end
end

-------------------------------------------
-- judge if it is a class
--
_G['isClass'] = function (t)
	if t.isClass then
		if type(t.isClass) == 'function' then
			return t:isClass()
		else
			return false
		end
	else 
		return false
	end
end

-------------------------------------------
-- judge if it is an instance
-- 
_G['isInstance'] = function (t)
	if t.isInstance then 
		if type(t.isInstance) == 'function' then
			return t:isInstance()
		else
			return false
		end
	else 
		return false
	end
end

---------------------------------------------------------------
-- judge if it is an empty object.
-- the empty rules are defined by ourselves, see follows.
-- 
_G['isValidInstance'] = function (obj)
	if isFalse(obj) then return false end
	checkType(obj, 'table')
	
	for k, v in pairs(obj) do
		if type(k) == 'string' then
			if k ~= 'id' then
				return true
			end
		end
	end
	
	return false
end;

------------------------------------------------------------------------
-- Query Function Set
-- for convienent, import them into _G directly
------------------------------------------------------------------------

_G['eq'] = function ( cmp_obj )
	return function (v)
		if v == cmp_obj then
			return true
		else
			return false
		end
	end
end

_G['uneq'] = function ( cmp_obj )
	return function (v)
		if v ~= cmp_obj then
			return true
		else
			return false
		end
	end
end

_G['lt'] = function (limitation)
	return function (v)
		if tonumber(v) < limitation then
			return true
		else
			return false
		end
	end
end

_G['gt'] = function (limitation)
	return function (v)
		if tonumber(v) > limitation then
			return true
		else
			return false
		end
	end
end


_G['le'] = function (limitation)
	return function (v)
		if tonumber(v) <= limitation then
			return true
		else
			return false
		end
	end
end

_G['ge'] = function (limitation)
	return function (v)
		if tonumber(v) >= limitation then
			return true
		else
			return false
		end
	end
end

_G['bt'] = function (small, big)
	return function (v)
		if tonumber(v) > small and v < big then
			return true
		else
			return false
		end
	end
end

_G['be'] = function (small, big)
	return function (v)
		if tonumber(v) >= small and v <= big then
			return true
		else
			return false
		end
	end
end

_G['outside'] = function (small, big)
	return function (v)
		local v = tonumber(v)
		
		if v < small and v > big then
			return true
		else
			return false
		end
	end
end

_G['contains'] = function (substr)
	return function (v)
		v = tostring(v)
		if v:contains(substr) then 
			return true
		else
			return false
		end
	end
end

_G['startsWith'] = function (substr)
	return function (v)
		v = tostring(v)
		if v:startsWith(substr) then 
			return true
		else
			return false
		end
	end
end

_G['endsWith'] = function (substr)
	return function (v)
		v = tostring(v)
		if v:endsWith(substr) then 
			return true
		else
			return false
		end
	end
end

_G['inset'] = function (...)
	local args = {...}
	return function (v)
		v = tostring(v)
		for _, val in ipairs(args) do
			-- once meet one, ok
			if tostring(val) == v then
				return true
			end
		end
		
		return false
	end

end

_G['uninset'] = function (...)
	local args = {...}
	return function (v)
		v = tostring(v)
		for _, val in ipairs(args) do
			-- once meet one, false
			if tostring(val) == v then
				return false
			end
		end
		
		return true
	end

end



------------------------------------------------------------------------
-- 
------------------------------------------------------------------------
local Model 

local function makeQuerySet(list)
	local list = list or List()
	-- create a query set	
	local query_set = setProto(list, Model)
	-- add it to fit the check of isClass function
	query_set.__spectype = 'QuerySet'
	
	return query_set
end

------------------------------------------------------------------------
-- Model Define
-- Model is the basic object of Bamboo Database Abstract Layer
------------------------------------------------------------------------


Model = Object:extend {
	__tag = 'Bamboo.Model';
	-- ATTEN: __name's value is not neccesary be equal strictly to the last word of __tag
	__name = 'Model';
	__desc = 'Model is the base of all models.';
	__fields = {};
	__indexfd = "";

	-- make every object creatation from here: every object has the 'id' and 'name' fields
	init = function (self)
		-- get the latest instance counter
		self.id = self:getCounter() + 1

		return self 
	end;
    

	--------------------------------------------------------------------
	-- Class Functions. Called by class object.
	--------------------------------------------------------------------

	-- return id queried by index
	--
    getIdByIndex = function (self, name)
		I_AM_CLASS(self)
		checkType(name, 'string')
		
		local index_key = getIndexKey(self)
		-- id is the score of that index value
		local idstr = db:zscore(index_key, name)
		return tonumber(idstr)
    end;
    
    -- return name query by id
	-- 
    getIndexById = function (self, id)
		I_AM_CLASS(self)
		checkType(tonumber(id), 'number')
		
		local flag, name = checkExistanceById(self, id)
		if isFalse(flag) or isFalse(name) then return nil end

		return name
    end;

    -- return instance object by id
	--
	getById = function (self, id)
		I_AM_CLASS(self)
		checkType(tonumber(id), 'number')
		
		-- check the existance in the index cache
		if not checkExistanceById(self, id) then return nil end
		-- and then check the existance in the key set
		local key = self.__name + ':' + id
		if not db:exists(key) then return nil end

		return getFromRedis(self, key)
	end;
	
	-- return instance object by name
	--
	getByIndex = function (self, name)
		I_AM_CLASS(self)
		local id = self:getIdByIndex(name)
		if not id then return nil end

		return self:getById (id)
	end;
	
	-- return a list containing all ids of all instances belong to this Model
	--
	allIds = function (self, is_rev)
		I_AM_CLASS(self)
		local index_key = getIndexKey(self)
		local all_ids 
		if is_rev == 'rev' then
			all_ids = db:zrevrange(index_key, 0, -1, 'withscores')
		else
			all_ids = db:zrange(index_key, 0, -1, 'withscores')
		end
		local ids = List()
		for _, v in ipairs(all_ids) do
			-- v[1] is the 'index value', v[2] is the 'id'
			ids:append(v[2])
		end
		
		return ids
	end;
	
	-- slice the ids list, start from 1, support negative index (-1)
	-- 
	sliceIds = function (self, start, stop, is_rev)
		I_AM_CLASS(self)
		checkType(start, stop, 'number', 'number')
		local index_key = getIndexKey(self)
		if start > 0 then start = start - 1 end
		if stop > 0 then stop = stop - 1 end
		local all_ids
		if is_rev == 'rev' then
			all_ids = db:zrevrange(index_key, start, stop, 'withscores')
		else
			all_ids = db:zrange(index_key, start, stop, 'withscores')
		end
		local ids = List()
		for _, v in ipairs(all_ids) do
			-- v[1] is the 'index value', v[2] is the 'id'
			ids:append(v[2])
		end
		
		return ids
	end;	
	
	-- return all instance objects belong to this Model
	-- 
	all = function (self, is_rev)
		I_AM_CLASS(self)
		local all_instaces = makeQuerySet()
		
		local index_key = getIndexKey(self)
		local all_ids = self:allIds(is_rev)
		local getById = self.getById 
		
		local obj, data
		for _, id in ipairs(all_ids) do
			local obj = getById(self, id)
			if isValidInstance(obj) then
				all_instaces:append(obj)
			end
		end
		return all_instaces
	end;

	-- slice instance object list, support negative index (-1)
	-- 
	slice = function (self, start, stop, is_rev)
		I_AM_CLASS(self)
		local ids = self:sliceIds(start, stop, is_rev)
		local objs = makeQuerySet()
		local getById = self.getById 

		for _, id in ipairs(ids) do
			local obj = getById(self, id)
			if isValidInstance(obj) then
				objs:append(obj)
			end
		end
		
		return objs
	end;
	
	-- this is a magic function
	-- return all the keys belong to this Model (or this model's parent model)
	-- all elements in returning list are string
	--
	allKeys = function (self)
		I_AM_CLASS(self)
		return db:keys(self.__name + ':*')
	end;
	
	-- return the actual number of the instances
	--
	numbers = function (self)
		I_AM_CLASS(self)
		return db:zcard(getIndexKey(self))
	end;
	
	-- return the first instance found by query set
	--
	get = function (self, query_args, is_rev)
		I_AM_CLASS(self)
		local id = query_args.id
		
		-- if there is 'id' field in query set, use id as the main query key
		-- because id is stored as part of the key, so need to treat it separately 
		if id then
			-- remove the id field, for later we will use query_args to continue query
			query_args['id'] = nil

			-- retrieve this instance by id
			local obj = self:getById( id )
			if not isValidInstance(obj) then return nil end
			
			local fields = obj.__fields
			for k, v in pairs(query_args) do
				-- if no description table associated to k, return nil directly
				if not fields[k] then return nil end
				-- if v is the query function
				if type(v) == 'function' then
					-- the parameter passed to query function, is always the value of the object's k field
					local flag = v(obj[k])
					-- if not in limited condition
					if not flag then return nil end
				else
					-- if v is normal value
					if obj[k] ~= v then return nil end
				end
			end

			-- if process walk here, means having found an instance object
			return obj
		
		else
			-- if there is no id in query parameters
			local all_ids = self:allIds(is_rev)
			local getById = self.getById 
			for _, kk in ipairs(all_ids) do
				-- get an object by key 'kk'
				local obj = getById(self, kk)
				assert(isValidInstance(obj), "[Error] object must not be empty.")
				local flag = true
				local fields = obj.__fields
				for k, v in pairs(query_args) do
					if not fields[k] then flag=false; break end
					
					if type(v) == 'function' then
						flag = v(obj[k])
						if not flag then break end
					else
						if obj[k] ~= v then flag=false; break end
					end
				end
				if flag then
					return obj
				end
			end
		end
		
		return nil		
	end;

	--- fitler some instances belong to this model
	-- @param query_args: query arguments in a table
	-- @param is_rev: 'rev' or other value, means start to search from begining or from end
	-- @param starti: specify which index to start search
	-- @param length: specify how many elements to find
	-- @param dir: specify the direction of the search action, 1 means positive, -1 means negative
	-- @return: an object list (query set)
	--          the end position last search
	-- @note: this function can be called by class object and query set
	filter = function (self, query_args, is_rev, starti, length, dir)
		I_AM_CLASS_OR_QUERY_SET(self)
		
		local is_query_set = false
		if isList(self) then is_query_set = true end
		
		-- normalize the direction value
		local dir = dir or 1
		assert( dir == 1 or dir == -1, '[Error] dir must be 1 or -1.')
		
		if query_args and query_args['id'] then
			-- remove 'id' query argument
			print("[Warning] Filter doesn't support search by id.")
			query_args['id'] = nil 
			
		end
		
		-- if query table is empty, return all instances
		if isFalse(query_args) then return self:all() end

		-- normalize the 'and' and 'or' logic
		local logic = 'and'
		if query_args[1] then
			if query_args[1] == 'or' then
				logic = 'or'
			end
			query_args[1] = nil
		end
		
		-- create a query set
		local query_set = setProto(List(), Model)
		-- add it to fit the check of isClass function
		query_set.__spectype = 'QuerySet'
		
			
		local all_ids
		if is_query_set then
			-- if self is query set, we think of all_ids as object list, rather than id string list
			all_ids = self
		else
			-- all_ids is id string list
			all_ids = self:allIds(is_rev)
		end
		
		if starti then
			checkType(starti, 'number')
			assert( starti >= 1, '[Error] starti must be greater than 1.')
			
			if dir == 1 then
				-- get the part of starti to end of the list
				all_ids = all_ids:slice(starti, -1)
			else
				all_ids = all_ids:slice(1, starti)
			end
		end
		-- nothing in id list, return empty table
		if #all_ids == 0 then return List() end
		
		-- 's': start
		-- 'e': end
		-- 'dir': direction
		local s, e
		local exiti = 0
		local getById = self.getById 
		if dir > 0 then
			s = 1
			e = #all_ids
			dir = 1
		else
			s = #all_ids
			e = 1
			dir = -1
		end
			
		for i = s, e, dir do
			local flag = true	
			local obj
			if is_query_set then
				obj = all_ids[i]
			else
				local kk = all_ids[i]
				obj = getById (self, kk)
			end
			assert(isValidInstance(obj), "[Error] object must not be empty.")
			local fields = obj.__fields
			assert(not isFalse(fields), "[Error] object's description table must not be blank.")
			
			for k, v in pairs(query_args) do
				-- to redundant query condition, once meet, jump immediately
				if not fields[k] then flag=false; break end

				if type(v) == 'function' then
					flag = v(obj[k])
					if logic == 'and' then
						if not flag then break end
					else
						if flag then break end
					end
	
				else
					if logic == 'and' then
						if obj[k] ~= v then flag=false; break end
					else
						if obj[k] == v then flag=true; break end
					end
				end
			end
			-- if walk to this line, means find one 
			if flag then
				query_set:append(obj)
				if length then 
					checkType(length, 'number')
					if length > 0 and #query_set >= length then
						-- if find enough
						exiti = i
						break
					end
				end
			end
		end
			
		-- calculate the search end position when return 
		local endpoint
		if starti then
			if exiti > 0 then
				endpoint = (dir == 1) and starti + exiti - 1 or exiti
			else
				endpoint = (dir == 1) and starti + #all_ids - 1 or 1
			end
		else
			endpoint = #all_ids
		end
		
		-- when length search is negative, need to reverse once 
		if dir == -1 then
			query_set:reverse()
		end
		
		return query_set, endpoint
		
	end;
    
	-- CAREFUL! 
	clearAll = function (self)
		I_AM_CLASS(self)
		local all_objs = self:all()
		for i, v in ipairs(all_objs) do
			v:del()
		end
		db:set(getCounterName(self), 0)
		
		return self
	end;
	
	-------------------------------------------------------------------
	-- CUSTOM API
	--- seven APIs
	-- 1. setCustom
	-- 2. getCustom
	-- 3. delCustom
	-- 4. updateCustom
	-- 5. addCustomMember
	-- 6. removeCustomMember
	-- 7. numCustom
	--
	--- four store type
	-- 1. string
	-- 2. list
	-- 3. set
	-- 4. zset
	-------------------------------------------------------------------
	
	-- store customize key-value pair to db
	-- now: it support string, list and so on
	setCustom = function (self, key, val, st)
		I_AM_CLASS(self)
		checkType(key, 'string')
		local custom_key = getCustomKey(self, key)

		if not st or st == 'string' then
			assert( type(val) == 'string' or type(val) == 'number',
					"[Error] In the string mode of setCustom, val should be string or number.")
			db:set(custom_key, val)
		else
			checkType(val, 'table')
			if st == 'list' then
				rdlist.save(val)
			elseif st == 'set' then
				rdset.save(val)
			elseif st == 'zset' then
				rdzset.save(val)
			else
				error("[Error] st must be one of 'string', 'list', 'set' or 'zset'")
			end
		end
	end;

	-- 
	getCustom = function (self, key)
		I_AM_CLASS(self)
		checkType(key, 'string')
		local custom_key = getCustomKey(self, key)
		if not db:exists(custom_key) then
			print(("[Warning] Key %s doesn't exist!"):format(custom_key))
			return nil
		end

		-- get the store type in redis
		local store_type = db:type(custom_key)
		if store_type == 'string' then
			return db:get(custom_key), store_type
		elseif store_type == 'list' then
			return rdlist.retrieve(custom_key), store_type
		elseif store_type == 'set' then
			return rdset.retrieve(custom_key), store_type
		elseif store_type == 'zset' then
			return rdzset.retrieve(custom_key), store_type
		end

		return nil
	end;

	delCustom = function (self, key)
		I_AM_CLASS(self)
		checkType(key, 'string')
		local custom_key = getCustomKey(self, key)

		return db:del(custom_key)		
	end;

	updateCustom = function (self, key, val)
		I_AM_CLASS(self)
		checkType(key, 'string')
		local custom_key = getCustomKey(self, key)

		local store_type = db:type(custom_key)
		if store_type == 'string' then
			db:set(custom_key, tostring(val))
		else
			checkType(val, 'table')
			if store_type == 'list' then
				rdlist.update(custom_key, val)
			elseif store_type == 'set' then
				rdset.update(custom_key, val)
			elseif store_type == 'zset' then
				rdzset.update(custom_key, val)
			end
		end
				 
	end;

	removeCustomMember = function (self, key, val)
		I_AM_CLASS(self)
		checkType(key, 'string')
		local custom_key = getCustomKey(self, key)

		local store_type = db:type(custom_key)
		if store_type == 'string' then
			db:set(custom_key, '')
		elseif store_type == 'list' then
			rdlist.remove(key, val)
		elseif store_type == 'set' then
			rdset.remove(key, val)
		elseif store_type == 'zset' then
			rdzset.remove(key, val)
		end 
		
	end;
	
	addCustomMember = function (self, key, val)
		I_AM_CLASS(self)
		checkType(key, 'string')
		local custom_key = getCustomKey(self, key)

		local store_type = db:type(custom_key)
		if store_type == 'string' then
			db:set(custom_key, val)
		elseif store_type == 'list' then
			rdlist.append(key, val)
		elseif store_type == 'set' then
			rdset.add(key, val)
		elseif store_type == 'zset' then
			rdzset.add(key, val)
		end
		
	end;

	numCustom = function (self, key)
		I_AM_CLASS(self)
		checkType(key, 'string')
		local custom_key = getCustomKey(self, key)

		local store_type = db:type(custom_key)
		if store_type == 'string' then
			return 1
		elseif store_type == 'list' then
			return rdlist.len(key)
		elseif store_type == 'set' then
			return rdset.num(key)
		elseif store_type == 'zset' then
			return rdzset.num(key)
		end
	end;
	-----------------------------------------------------------------

	-----------------------------------------------------------------
	-- validate form parameters by model defination
	-- usually, params = Form:parse(req)
	-- 
	validate = function (self, params)
		I_AM_CLASS(self)
		checkType(params, 'table')
		local fields = self.__fields
		for k, v in pairs(fields) do
			local t = params[k]
			-- rule 1: if this field have attribute required=true
			if v.required then
				-- when be required, if miss, or blank 
				if not t or #t == 0 then return false, ('Required parameter "%s" is missing.'):format(k) end
			end
			-- if exists in params
			if t and t ~= '' then
				-- rule 2: if this field has min, max attributes, means type is limited number
				if v.min then
					local num = tonumber(t)
					if not num or num < tonumber(v.min) then
						return false, ('Parameter "%s" should be equal or larger than %s.'):format(k, v.min) 
					end
				end
				if v.max then
					local num = tonumber(t)
					if not num or num > tonumber(v.max) then
						return false, ('Parameter "%s" should be equal or smaller than %s.'):format(k, v.max) 
					end
				end
				-- rule 3: if this field has min_length, max_length，means type is limited string
				if v.min_length then
					if #t < v.min_length then
						return false, ('Parameter "%s" should be equal or larger than %s.'):format(k, v.min_length) 
					end
				end
				if v.max_length then
					if #t > v.max_length then
						return false, ('Parameter "%s" should be equal or smaller than %s.'):format(k, v.max_length) 
					end
				end
				-- rule 4: if this field has pattern，means type is a set of string, fit your regular expression
				if v.pattern then
					local ret = t:match(v.pattern)
					if not ret or #t ~= #ret then
						return false, ('Parameter "%s" should be suited to the internal pattern.'):format(k) 
					end
				end
			end
		end
		
		return true
	end;
	
	
	
    --------------------------------------------------------------------
	-- Instance Functions
	--------------------------------------------------------------------
    -- save instace's normal field
    save = function (self)
		I_AM_INSTANCE(self)
        assert(self.id, "[Error] The main key 'id' field doesn't exist!")
        local indexfd = self.__indexfd
        assert(type(indexfd) == 'string' or type(indexfd) == 'nil', "[Error] the __indexfd should be string.")
        local model_key = getNameIdPattern(self)
		local is_existed = db:exists(model_key)

		local index_key = getIndexKey(self)
		if not is_existed then
			-- increse counter 
			db:incr(getCounterName(self))
		else
			-- if exist, update the index cache
			-- delete the old one
			db:zremrangebyscore(index_key, self.id, self.id)
		end
		-- score is the instance's id, member is the instance's index value
		if isFalse(indexfd) or isFalse(self[indexfd]) then
			db:zadd(index_key, self.id, self.id)
		else
			local score = db:zscore(index_key, self[indexfd])
			-- is exist, return directely, else redis will update the score of val
			if score then 
				print("[Warning] save duplicate to an unique limited field, aborted!")
				return nil 
			end
			db:zadd(index_key, self.id, self[indexfd])				
		end

		
		--- save an hash object
		-- 'id' are essential in an object instance
		db:hset(model_key, 'id', self.id)

		for k, v in pairs(self) do
			-- when save, need to check something
			-- 1. only save fields defined in model defination
			-- 2. don't save the functional member, and _parent
			-- 3. don't save those fields not defined in model defination
			-- 4. don't save those except ONE foreign fields, which are defined in model defination
			local field = self.__fields[k]
			-- if v is nil, pairs will not iterate it
			if field then
				if not field['foreign'] or ( field['foreign'] and field['st'] == 'ONE') then
					-- save
					db:hset(model_key, k, tostring(v))
				end
			end
		end
		
		return self
    end;
    
    -- partially update function, once one field
	-- can only apply to none foreign field
    update = function (self, field, new_value)
		I_AM_INSTANCE(self)
		checkType(field, new_value, 'string', 'string')
		local fld = self.__fields[field]
		assert(fld, ("[Error] Field %s doesn't be defined!"):format(field))
		assert( not fld.foreign, ("[Error] %s is a foreign field, shouldn't use update function!"):format(field))
		local model_key = getNameIdPattern(self)
		assert(db:exists(model_key), ("[Error] Key %s does't exist! Can't apply update."):format(model_key))
		-- apply
		db:hset(model_key, field, new_value)
		
		return self
    end;
    
    -- get the model's instance counter value
	-- this can be call by Class and Instance
    getCounter = function (self)
		-- 
		return tonumber(db:get(getCounterName(self)) or 0)
    end;
    
    -- delete self instance object
    -- self can be instance or query set
    del = function (self)
		I_AM_INSTANCE_OR_QUERY_SET(self)
		-- if self is query set
		if self.__spectype == 'QuerySet' then
			for _, v in ipairs(self) do
				delFromRedis(v)
				v = nil
			end
		else
			delFromRedis(self)
		end
		
		self = nil
    end;

	-----------------------------------------------------------------------------------
	-- Foreign API
	-----------------------------------------------------------------------------------
	---
	-- add a foreign object's id to this foreign field
	-- return self
	addForeign = function (self, field, obj)
		I_AM_INSTANCE(self)
		checkType(field, 'string')
		assert(type(obj) == 'table' or type(obj) == 'string', '[Error] "obj" should be table or string.')
		if type(obj) == 'table' then checkType(tonumber(obj.id), 'number') end
		
		local fld = self.__fields[field]
		assert(fld, ("[Error] Field %s doesn't be defined!"):format(field))
		assert( fld.foreign, ("[Error] This field %s is not a foreign field."):format(field))
		assert( fld.st, ("[Error] No store type setting for this foreign field %s."):format(field))
		assert( fld.foreign == 'ANYSTRING' or obj.id, 
			"[Error] This object doesn't contain id, it's not a valid object!")
		assert( fld.foreign == 'ANYSTRING' or fld.foreign == 'UNFIXED' or fld.foreign == getClassName(obj), 
			("[Error] This foreign field '%s' can't accept the instance of model '%s'."):format(
			field, getClassName(obj) or tostring(obj)))
		
		local new_id
		if fld.foreign == 'ANYSTRING' then
			checkType(obj, 'string')
			new_id = obj
		elseif fld.foreign == 'UNFIXED' then
			new_id = getNameIdPattern(obj)
		else
			new_id = obj.id
		end
		
		
		if fld.st == 'ONE' then
			local model_key = getNameIdPattern(self)
			-- record in db
			db:hset(model_key, field, new_id)
			-- ONE foreign value can be get by 'get' series functions
			self[field] = new_id

		elseif fld.st == 'MANY' then

			local key = getFieldPattern(self, field)
			-- update the new value to db, so later we don't need to do save
			rdzset.add(key, new_id)

		elseif fld.st == 'FIFO' then
			local length = fld.fifolen or 100
			assert(length and type(length) == 'number' and length > 0 and length <= 10000, 
				"[Error] In Fifo foreign, the 'fifolen' must be number greater than 0!")
			local key = getFieldPattern(self, field)
			rdfifo.push(key, length, new_id)

		elseif fld.st == 'ZFIFO' then
			local length = fld.fifolen or 100
			assert(length and type(length) == 'number' and length > 0 and length <= 10000, 
				"[Error] In Zfifo foreign, the 'fifolen' must be number greater than 0!")
			local key = getFieldPattern(self, field)
			-- in zset, the newest member have the higher score
			-- but use getForeign, we retrieve them from high to low, so newest is at left of result
			rdzfifo.push(key, length, new_id)
		end
		
		return self
	end;
	
	-- 
	-- 
	-- 
	getForeign = function (self, field, start, stop, is_rev)
		I_AM_INSTANCE(self)
		checkType(field, 'string')
		local fld = self.__fields[field]
		assert(fld, ("[Error] Field %s doesn't be defined!"):format(field))
		assert(fld.foreign, ("[Error] This field %s is not a foreign field."):format(field))
		assert( fld.st, ("[Error] No store type setting for this foreign field %s."):format(field))
				
		if fld.st == 'ONE' then
			if isFalse(self[field]) then return nil end

			local model_key = getNameIdPattern(self)
			if fld.foreign == 'ANYSTRING' then
				-- return string directly
				return self[field]
			else
				-- the true foreign case
				local link_model, linked_id = checkUnfixed(fld, self[field])

				local obj = link_model:getById (linked_id)
				if not isValidInstance(obj) then
					-- if get not, remove the empty foreign key
					db:hset(model_key, field, '')
					self[field] = ''
					return nil
				else
					return obj
				end
			end
		elseif fld.st == 'MANY' then
			if isFalse(self[field]) then return List() end
			
			local key = getFieldPattern(self, field)
			local list = rdzset.retrieve(key)
			if isEmpty(list) then return List() end
			
			list = list:slice(start, stop, is_rev)
			if isEmpty(list) then return List() end
			
			if fld.foreign == 'ANYSTRING' then
				-- return string list directly
				return list
			else
				local obj_list = List()
				for _, v in ipairs(list) do
					local link_model, linked_id = checkUnfixed(fld, v)

					local obj = link_model:getById(linked_id)
					
					if not isValidInstance(obj) then
						-- if find no, remove this empty foreign key, by member
						rdzset.remove(key, v)
					else
						obj_list:append(obj)
					end
				end
				
				return obj_list
			end
			
		elseif fld.st == 'FIFO' then
			if isFalse(self[field]) then return List() end
		
			local key = getFieldPattern(self, field)
			local list = rdfifo.retrieve(key)
			
			list = list:slice(start, stop, is_rev)
			if isFalse(list) then return List() end
	
			if fld.foreign == 'ANYSTRING' then
				-- 
				return list
			else
				local obj_list = List()
				for _, v in ipairs(list) do
					local link_model, linked_id = checkUnfixed(fld, v)

					local obj = link_model:getById(linked_id)
					-- 
					if not isValidInstance(obj) then
						-- if find no, remove this empty foreign
						rdfifo.remove(key, v)
					else
						obj_list:append(obj)
					end
				end
				
				return obj_list
			end
			
		elseif fld.st == 'ZFIFO' then
			if isFalse(self[field]) then return List() end
		
			local key = getFieldPattern(self, field)
			-- due to FIFO, the new id is at left, old id is at right
			-- 
			local list = rdzfifo.retrieve(key)
			
			list = list:slice(start, stop, is_rev)
			if isFalse(list) then return List() end
	
			if fld.foreign == 'ANYSTRING' then
				--
				return list
			else
				local obj_list = List()
				
				for _, v in ipairs(list) do
					local link_model, linked_id = checkUnfixed(fld, v)

					local obj = link_model:getById(linked_id)
					-- 
					if not isValidInstance(obj) then
						rdzfifo.remove(key, v)
					else
						obj_list:append(obj)
					end
				end
				
				return obj_list
			end
		end

	end;    
	
	delForeign = function (self, field, obj)
		I_AM_INSTANCE(self)
		checkType(field, 'string')
		local fld = self.__fields[field]
		assert(fld, ("[Error] Field %s doesn't be defined!"):format(field))
		assert( fld.foreign, ("[Error] This field %s is not a foreign field."):format(field))
		assert( fld.st, ("[Error] No store type setting for this foreign field %s."):format(field))
		assert( fld.foreign == 'ANYSTRING' or obj.id, "[Error] This object doesn't contain id, it's not a valid object!")
		assert( fld.foreign == 'ANYSTRING' or fld.foreign == 'UNFIXED' or fld.foreign == getClassName(obj), ("[Error] This foreign field '%s' can't accept the instance of model '%s'."):format(field, getClassName(obj) or tostring(obj)))

		-- if self[field] is nil, it must be wrong somewhere
		if isFalse(self[field]) then return nil end
		
		local new_id
		if fld.foreign == 'ANYSTRING' then
			checkType(obj, 'string')
			new_id = obj
		else
			checkType(obj, 'table')
			if fld.foreign == 'UNFIXED' then
				new_id = getNameIdPattern(obj)
			else 
				new_id = tostring(obj.id)
			end
		end
		
		
		if fld.st == 'ONE' then
			-- we must check the equality of self[filed] and new_id before perform delete action
			local key = getNameIdPattern(self)
			if self[field] == new_id then
				db:hset(key, field, '')
				self[field] = ''
			end
			
		else
			local key = getFieldPattern(self, field)
			if fld.st == 'MANY' then
				rdzset.remove(key, new_id)
				
			elseif fld.st == 'FIFO' then
				rdfifo.remove(key, new_id)
				
			elseif fld.st == 'ZFIFO' then
				-- here, new_id is the score of that element ready to be deleted
				-- XXX: new_id is score or member?
				rdzfifo.remove(key, new_id)
			end
		end
	
		return self
	end;

	-- check whether some obj is already in foreign list
	-- instance:inForeign('some_field', obj)
	haveForeign = function (self, field, obj)
		I_AM_INSTANCE(self)
		checkType(field, 'string')
		local fld = self.__fields[field]
		assert(fld, ("[Error] Field %s doesn't be defined!"):format(field))
		assert(fld.foreign, ("[Error] This field %s is not a foreign field."):format(field))
		assert( fld.st, ("[Error] No store type setting for this foreign field %s."):format(field))
		assert(fld.foreign == 'ANYSTRING' or obj.id, "[Error] This object doesn't contain id, it's not a valid object!")
		assert(fld.foreign == 'ANYSTRING' or fld.foreign == 'UNFIXED' or fld.foreign == getClassName(obj),
			   ("[Error] The foreign model (%s) of this field %s doesn't equal the object's model %s."):format(fld.foreign, field, link_model))
		if isFalse(self[field]) then return nil end

		local new_id
		if fld.foreign == 'ANYSTRING' then
			checkType(obj, 'string')
			new_id = obj
		else
			checkType(obj, 'table')
			if fld.foreign == 'UNFIXED' then
				new_id = getClassIdPattern(self)
			else
				new_id = tostring(obj.id)
			end
		end

		local model_key = getFieldPattern(self, field)
		if fld.st == "ONE" then
			return self[field] == new_id
		elseif fld.st == 'MANY' then
			return rdzset.have(model_key, new_id)

		elseif fld.st == 'FIFO' then
			return rdfifo.have(model_key, new_id)

		elseif fld.st == 'ZFIFO' then
			return rdzfifo.have(model_key, new_id)
		end 
	
	end;

	-- return the number of elements in the foreign list
	-- @param field:  field of that foreign model
	numForeign = function (self, field)
		I_AM_INSTANCE(self)
		checkType(field, 'string')
		local fld = self.__fields[field]
		assert(fld, ("[Error] Field %s doesn't be defined!"):format(field))
		assert( fld.foreign, ("[Error] This field %s is not a foreign field."):format(field))
		assert( fld.st, ("[Error] No store type setting for this foreign field %s."):format(field))
		-- if foreign field link is now null
		if isFalse(self[field]) then return 0 end
		
		if fld.st == 'ONE' then
			-- the ONE foreign field has only 1 element
			return 1
		else
			local key = getFieldPattern(self, field)

			if fld.st == 'MANY' then
				return rdzset.num(key)

			elseif fld.st == 'FIFO' then
				return rdfifo.len(key)

			elseif fld.st == 'ZFIFO' then
				return rdzfifo.num(key)

			end
		end
	end;

	--- return the class name of an instance
	classname = function (self)
		-- I_AM_INSTANCE(self)
		
		return getClassName(self)
	end;

	--- return the field description table
	-- if have, return table
	-- if no, return nil
	fieldInfo = function (self, field)
		checkType(field, 'string')
		
		return self.__fields[field]
	end;
	
}



return Model
