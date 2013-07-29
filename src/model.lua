module(..., package.seeall)


local tinsert, tremove = table.insert, table.remove
local format = string.format
local socket = require 'socket'

local driver = require 'bamboo.db.drver'
--local mih = require 'bamboo.model-indexhash'
require 'bamboo.queryset'

local db = BAMBOO_DB


local List = require 'lglib.list'
local rdstring = require 'bamboo.db.redis.string'
local rdlist = require 'bamboo.db.redis.list'
local rdset = require 'bamboo.db.redis.set'
local rdzset = require 'bamboo.db.redis.zset'
local rdfifo = require 'bamboo.db.redis.fifo'
local rdzfifo = require 'bamboo.db.redis.zfifo'
local rdhash = require 'bamboo.db.redis.hash'



-----------------------------------------------------------------
local rdactions = {
	['string'] = {},
	['list'] = {},
	['set'] = {},
	['zset'] = {},
	['hash'] = {},
	['MANY'] = {},
	['FIFO'] = {},
	['ZFIFO'] = {},
	['LIST'] = {},
}

rdactions['string'].save = rdstring.save
rdactions['string'].update = rdstring.update
rdactions['string'].retrieve = rdstring.retrieve
rdactions['string'].remove = rdstring.remove
rdactions['string'].add = rdstring.add
rdactions['string'].has = rdstring.has
rdactions['string'].num = rdstring.num

rdactions['list'].save = rdlist.save
rdactions['list'].update = rdlist.update
rdactions['list'].retrieve = rdlist.retrieve
rdactions['list'].remove = rdlist.remove
--rdactions['list'].add = rdlist.add
rdactions['list'].add = rdlist.append
rdactions['list'].has = rdlist.has
--rdactions['list'].num = rdlist.num
rdactions['list'].num = rdlist.len

rdactions['set'].save = rdset.save
rdactions['set'].update = rdset.update
rdactions['set'].retrieve = rdset.retrieve
rdactions['set'].remove = rdset.remove
rdactions['set'].add = rdset.add
rdactions['set'].has = rdset.has
rdactions['set'].num = rdset.num

rdactions['zset'].save = rdzset.save
rdactions['zset'].update = rdzset.update
--rdactions['zset'].retrieve = rdzset.retrieve
rdactions['zset'].retrieve = rdzset.retrieveWithScores
rdactions['zset'].remove = rdzset.remove
rdactions['zset'].add = rdzset.add
rdactions['zset'].has = rdzset.has
rdactions['zset'].num = rdzset.num

rdactions['hash'].save = rdhash.save
rdactions['hash'].update = rdhash.update
rdactions['hash'].retrieve = rdhash.retrieve
rdactions['hash'].remove = rdhash.remove
rdactions['hash'].add = rdhash.add
rdactions['hash'].has = rdhash.has
rdactions['hash'].num = rdhash.num

rdactions['FIFO'].save = rdfifo.save
rdactions['FIFO'].update = rdfifo.update
rdactions['FIFO'].retrieve = rdfifo.retrieve
rdactions['FIFO'].remove = rdfifo.remove
rdactions['FIFO'].add = rdfifo.push
rdactions['FIFO'].has = rdfifo.has
rdactions['FIFO'].num = rdfifo.len

rdactions['ZFIFO'].save = rdzfifo.save
rdactions['ZFIFO'].update = rdzfifo.update
rdactions['ZFIFO'].retrieve = rdzfifo.retrieve
rdactions['ZFIFO'].remove = rdzfifo.remove
rdactions['ZFIFO'].add = rdzfifo.push
rdactions['ZFIFO'].has = rdzfifo.has
rdactions['ZFIFO'].num = rdzfifo.num

rdactions['LIST'] = rdactions['list']
rdactions['MANY'] = rdactions['zset']

local getStoreModule = function (store_type)
	local store_module = rdactions[store_type]
	assert( store_module, "[Error] store type must be one of 'string', 'list', 'set', 'zset' or 'hash'.")
	return store_module
end
bamboo.internal['getStoreModule'] = getStoreModule

------------------------------------------------------------------------------------
local getModelByName  = bamboo.getModelByName
local dcollector= 'DELETED:COLLECTOR'
local rule_manager_prefix = '_RULE_INDEX_MANAGER:'
local rule_query_result_pattern = '_RULE:%s:%s'   -- _RULE:Model:num
local rule_index_query_sortby_divider = ' |^|^| '
local rule_index_divider = ' ^_^ '
local Model

-- switches
-- can be called by instance and class
local isUsingFulltextIndex = function (self)
	local model = self
	if isInstance(self) then model = getModelByName(self:getClassName()) end
	if bamboo.config.fulltext_index_support and rawget(model, '__use_fulltext_index') then
		return true
	else
		return false
	end
end

--
--local isUsingRuleIndex = function ()
--	if bamboo.config.rule_index_support == false then
--		return false
--	end
--	return true
--end
--



-----------------------------------------------------------------
-- misc functions
-----------------------------------------------------------------
local transEdgeFromLuaToRedis = function (start, stop)
	local istart, istop
	
	if start > 0 then
		istart = start - 1
	else
		istart = start
	end
	
	if stop > 0 then
		istop = stop - 1
	else 
		istop = stop
	end
	
	return istart, istop
end


-----------------------------------------------------------------
-- helper functions
-----------------------------------------------------------------

local function getClassName(self)
	return self.__name
end

local function getCounterName(self)
	return format("%s:__counter", self.__name)
end

-- return a string
local function getCounter(self)
    return db:get(getCounterName(self)) or '0'
end;

local function getNameIdPattern(self)
	return format("%s:%s", self.__name, self.id)
end

local function getNameIdPattern2(self, id)
	return format("%s:%s", self.__name, tostring(id))
end

local function getFieldPattern(self, field)
	return format("%s:%s:%s", self.__name, self.id, field)
end

local function getFieldPattern2(self, id, field)
	return format("%s:%s:%s", self.__name, id, field)
end

-- return the key of some string like 'User:__index'
--
local function getIndexKey(self)
	return format("%s:__index", self.__name)
end


--- make a list, 
-- each element is 'Model_name:id'
local function makeModelKeyList(self, ids)
	local key_list = List()
	for _, v in ipairs(ids) do
		key_list:append(getNameIdPattern2(self, v))
	end
	return key_list
end


--- divide the model_name:id to two part
-- item: 		'Model_name:id'
-- link_model: 	model object
-- lined_id:		instance id
local function seperateModelAndId(item)
	local link_model, linked_id
	local link_model_str
	link_model_str, linked_id = item:match('^(%w+):(%d+)$')
	assert(link_model_str)
	assert(linked_id)
	link_model = getModelByName(link_model_str)
	assert(link_model)

	return link_model, linked_id
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

--- make lua object from redis' raw data table
local makeObject = function (self, data)
	-- if data is invalid, return nil
	if not isValidInstance(data) then
		--print("[Warning] @makeObject - Object is invalid.")
		-- print(debug.traceback())
		return nil
	end
	-- XXX: keep id as string for convienent, because http and database are all string

	local fields = self.__fields
	for k, fld in pairs(fields) do
		-- ensure the correction of field description table
		checkType(fld, 'table')
		-- convert the number type field

		if fld.foreign then
			local st = fld.st
			-- in redis, we don't save MANY foreign key in db, but we want to fill them when
			-- form lua object
			if st == 'MANY' then
				data[k] = 'FOREIGN MANY ' .. fld.foreign
			elseif st == 'FIFO' then
				data[k] = 'FOREIGN FIFO ' .. fld.foreign
			elseif st == 'ZFIFO' then
				data[k] = 'FOREIGN ZFIFO ' .. fld.foreign
			elseif st == 'LIST' then
				data[k] = 'FOREIGN LIST ' .. fld.foreign
			end
		else
			if fld.type == 'number' then
				data[k] = tonumber(data[k])
			elseif fld.type == 'boolean' then
				data[k] = data[k] == 'true' and true or false
				end
		end

	end

	-- generate an object
	-- XXX: maybe can put 'data' as parameter of self()
	local obj = self()
	table.update(obj, data)
	return obj

end

-------------------------------------------------------------------------------------
-- Functions work with redis
-------------------------------------------------------------------------------------

------------------------------------------------------------
-- get one object from redis
-- @param self:	Model
-- @param model_key:	'Model_name:id'
--
local getFromRedis = function (self, model_key)
	-- here, the data table contain ordinary field, ONE foreign key, but not MANY foreign key
	-- all fields are strings
	local data = db:hgetall(model_key)
	return makeObject(self, data)
end
bamboo.internal['getFromRedis'] = getFromRedis

------------------------------------------------------------
-- get objects from redis with pipeline
-- @param self:	Model
-- @param ids:	id list
--
local getFromRedisPipeline = function (self, ids)
	local key_list = makeModelKeyList(self, ids)
	-- all fields are strings
	local data_list = db:pipeline(function (p)
		for _, v in ipairs(key_list) do
			p:hgetall(v)
		end
	end)
	local objs = QuerySet()
	local nils = {}
	local obj
	for i, v in ipairs(data_list) do
		obj = makeObject(self, v)
		if obj then tinsert(objs, obj)
		else tinsert(nils, ids[i])
		end
	end

	return objs, nils
end
bamboo.internal['getFromRedisPipeline'] = getFromRedisPipeline


------------------------------------------------------------
-- get objects from redis with pipeline
-- @param pattern_list:	list of 'Model_name:id' string
--
local getFromRedisPipeline2 = function (pattern_list)
	-- 'list' store model and id info
	local model_list = List()
	for _, v in ipairs(pattern_list) do
		local model, id = seperateModelAndId(v)
		model_list:append(model)
	end

	-- all fields are strings
	local data_list = db:pipeline(function (p)
		for _, v in ipairs(pattern_list) do
			p:hgetall(v)
		end
	end)

	local objs = QuerySet()
	local nils = {}
	local obj
	for i, model in ipairs(model_list) do
		obj = makeObject(model, data_list[i])
		if obj then tinsert(objs, obj)
		else tinsert(nils, pattern_list[i])
		end
	end

	return objs, nils
end
bamboo.internal['getFromRedisPipeline2'] = getFromRedisPipeline2


------------------------------------------------------------
-- get partial objects from redis with pipeline
-- @param self:	Model
-- @param ids:	id list
-- @param fields:	field string list
-- @note: 'fields' must not be empty
local getPartialFromRedisPipeline = function (self, ids, fields)
	-- default retrieve 'id'
	tinsert(fields, 'id')
	local key_list = makeModelKeyList(self, ids)

	local data_list = db:pipeline(function (p)
		for _, v in ipairs(key_list) do
			p:hmget(v, unpack(fields))
		end
	end)

	local proto_fields = self.__fields
	-- all fields are strings
	-- every item is data_list now is the values according to 'fields'
	local objs = QuerySet()
	-- here, data_list is fields' order values
	for _, v in ipairs(data_list) do
		local item = {}
		for i, key in ipairs(fields) do
			-- v[i] is the value of ith key
			item[key] = v[i]

			local fdt = proto_fields[key]
			if fdt and fdt.type then
				if fdt.type == 'number' then
					item[key] = tonumber(item[key])
				elseif fdt.type == 'boolean' then
					item[key] = item[key] == 'true' and true or false
				end
			end
		end
		-- only has valid field other than id can be checked as fit object
		if item[fields[1]] ~= nil then
			-- tinsert(objs, makeObject(self, item))
			-- here, we jumped the makeObject step, to promote performance
			tinsert(objs, item)
		end
	end

	return objs
end


local updateIndexByRules
--------------------------------------------------------------
-- del object and its single relation in redis
-- @param self:	Model
-- @param id:		instance id
--
local delFromRedis = function (self, id)
	assert(self.id or id, '[Error] @delFromRedis - must specify an id of instance.')
	local model_key = id and getNameIdPattern2(self, id) or getNameIdPattern(self)
	local index_key = getIndexKey(self)

	--del hash index
	if bamboo.config.index_hash then
		mih.indexDel(self);
	end

	local fields = self.__fields
	-- in redis, delete the associated foreign key-value store
	for k, v in pairs(self) do
		local fld = fields[k]
		if fld and fld.foreign then
			local key = model_key + ':' + k
			db:del(key)
		end
	end

	-- delete the key self
	db:del(model_key)
	-- delete the index in the global model index zset
	db:zremrangebyscore(index_key, self.id or id, self.id or id)

	-- clear fulltext index, only when it is instance
	if isUsingFulltextIndex(self) and self.id then
		bamboo.internal.clearFtIndexesOnDeletion(self)
	end
--	if isUsingRuleIndex(self) and self.id then
--		updateIndexByRules(self, 'del')
--	end

	-- release the lua object
	self = nil
end
bamboo.internal['delFromRedis'] = delFromRedis

--------------------------------------------------------------
-- Fake Deletion
--
local fakedelFromRedis = function (self, id)
	assert(self.id or id, '[Error] @fakedelFromRedis - must specify an id of instance.')
	local model_key = id and getNameIdPattern2(self, id) or getNameIdPattern(self)
	local index_key = getIndexKey(self)

	--del hash index
	if bamboo.config.index_hash then
		mih.indexDel(self);
	end

	local fields = self.__fields
	-- in redis, delete the associated foreign key-value store
	for k, v in pairs(self) do
		local fld = fields[k]
		if fld and fld.foreign then
			local key = model_key + ':' + k
			if db:exists(key) then
				db:rename(key, 'DELETED:' + key)
			end
		end
	end

	-- rename the key self
	db:rename(model_key, 'DELETED:' + model_key)
	-- delete the index in the global model index zset
	-- when deleted, the instance's index cache was cleaned.
	db:zremrangebyscore(index_key, self.id or id, self.id or id)
	-- add to deleted collector
	rdzset.add(dcollector, model_key)

	-- clear fulltext index
	if isUsingFulltextIndex(self) and self.id then
		bamboo.internal.clearFtIndexesOnDeletion(self)
	end
--	if isUsingRuleIndex(self) and self.id then
--		updateIndexByRules(self, 'del')
--	end

	-- release the lua object
	self = nil
end
bamboo.internal['fakedelFromRedis'] = fakedelFromRedis


--------------------------------------------------------------
-- Restore Fake Deletion
-- called by Model: self, not instance
local restoreFakeDeletedInstance = function (self, id)
	checkType(tonumber(id),  'number')
	local model_key = getNameIdPattern2(self, id)
	local index_key = getIndexKey(self)

	local instance = getFromRedis(self, 'DELETED:' + model_key)
	if not instance then return nil end
	-- rename the key self
	db:rename('DELETED:' + model_key, model_key)
	local fields = self.__fields
	-- in redis, restore the associated foreign key-value
	for k, v in pairs(instance) do
		local fld = fields[k]
		if fld and fld.foreign then
			local key = model_key + ':' + k
			if db:exists('DELETED:' + key) then
				db:rename('DELETED:' + key, key)
			end
		end
	end

	-- when restore, the instance's index cache was restored.
	db:zadd(index_key, instance.id, instance.id)
	-- remove from deleted collector
	db:zrem(dcollector, model_key)

    if bamboo.config.index_hash then
        mih.index(instance,true);--create hash index
    end

	return instance
end



local retrieveObjectsByForeignType = function (foreign, list)
	if foreign == 'ANYSTRING' then
		-- return string list directly
		return QuerySet(list)
	elseif foreign == 'UNFIXED' then
		return getFromRedisPipeline2(list)
	else
		-- foreign field stores "id, id, id" list
		local model = getModelByName(foreign)
		return getFromRedisPipeline(model, list)
	end

end


local checkLogicRelation = function (obj, query_args, logic_choice, model)
	-- NOTE: query_args can't contain [1]
	-- here, obj may be object or string
	-- when obj is string, query_args must be function;
	-- when query_args is table, obj must be table, and must be real object.
	local flag = logic_choice
	if type(query_args) == 'table' then
		local fields = model and model.__fields or obj.__fields
		for k, v in pairs(query_args) do
			-- to redundant query condition, once meet, jump immediately
			if not fields[k] then flag=false; break end

			if type(v) == 'function' then
				flag = v(obj[k])
			else
				flag = (obj[k] == v)
			end
			---------------------------------------------------------------
			-- logic_choice,       flag,      action,          append?
			---------------------------------------------------------------
			-- true (and)          true       next field       --
			-- true (and)          false      break            no
			-- false (or)          true       break            yes
			-- false (or)          false      next field       --
			---------------------------------------------------------------
			if logic_choice ~= flag then break end
		end
	else
		-- call this query args function
		flag = query_args(obj)
	end

	return flag
end
bamboo.internal.checkLogicRelation = checkLogicRelation


function luasplit(str, pat)
   local t = {}
   local fpat = "(.-)" .. pat
   local last_end = 1
   local s, e, cap = str:find(fpat, 1)
   while s do
      if s ~= 1 or cap ~= "" then
      		table.insert(t,cap)
      end
      last_end = e+1
      s, e, cap = str:find(fpat, last_end)
   end
   if last_end <= #str then
      cap = str:sub(last_end)
      table.insert(t, cap)
   end
   return t
end


----------------------------------------------------------------------
--- save process
-- called by save
-- self is instance
local processBeforeSave = function (self, params)
	local primarykey = self.__primarykey
	local fields = self.__fields
	local store_kv = {}
	--- save an hash object
	-- 'id' are essential in an object instance
	tinsert(store_kv, 'id')
	tinsert(store_kv, self.id)

	-- if parameters exist, update it
	if params and type(params) == 'table' then
		for k, v in pairs(params) do
			if k ~= 'id' and fields[k] then
				self[k] = tostring(v)
			end
		end
	end

	assert(not isFalse(self[primarykey]) ,
		format("[Error] instance's index field %s's value must not be nil. Please check your model defination.", primarykey))

	-- check required field
	-- TODO: later we should update this to validate most attributes for each field
	for field, fdt in pairs(fields) do
		if fdt.required then
			assert(self[field], format("[Error] @processBeforeSave - this field '%s' is required but its' value is nil.", field))
		end
	end

	for k, v in pairs(self) do
		-- when save, need to check something
		-- 1. only save fields defined in model defination
		-- 2. don't save the functional member, and _parent
		-- 3. don't save those fields not defined in model defination
		-- 4. don't save those except ONE foreign fields, which are defined in model defination
		local fdt = fields[k]
		-- if v is nil, pairs will not iterate it, key will and should not be 'id'
		if fdt then
			if not fdt['foreign'] or ( fdt['foreign'] and fdt['st'] == 'ONE') then
				-- save
				tinsert(store_kv, k)
				tinsert(store_kv, tostring(v))
			end
		end
	end

	return self, store_kv
end

------------------------------------------------------------------------
-- Model Definition
-- Model is the basic object of Bamboo Database Abstract Layer
------------------------------------------------------------------------
Model = Object:extend {
	__name = 'Model';
	__fields = {
	    -- here, we don't put 'id' as a field
	    ['created_time'] = { type="number" },
	    ['lastmodified_time'] = { type="number" },

	};
--	__primarykey = "id";

	-- make every object creatation from here: 
	-- every object has the 'id', 'created_time' and 'lastmodified_time' fields
	init = function (self, t)
		local t = t or {}
		local fields = self.__fields

		for field, fdt in pairs(fields) do
			-- assign to default value if exsits
			local tmp = t[field] or fdt.default
			if type(tmp) == 'function' then
				self[field] = tmp()
			else
				self[field] = tmp
			end
		end

		self.created_time = socket.gettime()
		self.lastmodified_time = self.created_time

		return self
	end;


	--------------------------------------------------------------------
	-- Class Functions. Called by class object.
	--------------------------------------------------------------------
	
--	-- return the location of 'name' in index
--	getRankByPrimaryKey = function (self, name)
--		I_AM_CLASS(self)
--
--		local index_key = getIndexKey(self)
--		-- id is the score of that index value
--		local rank = db:zrank(index_key, tostring(name))
--		return tonumber(rank) + 1 
--	end;
--
--	getIdByPrimaryKey = function (self, name)
--		I_AM_CLASS(self)
--		local index_key = getIndexKey(self)
--		-- id is the score of that index value
--		return db:zscore(index_key, tostring(name))
--	end;
--
--	getPrimaryKeyById = function (self, id)
--		I_AM_CLASS(self)
--		if type(tonumber(id)) ~= 'number' then return nil end
--
--		local flag, name = checkExistanceById(self, id)
--		if isFalse(flag) or isFalse(name) then return nil end
--
--		return name
--	end;
--
--	-- return instance object by primary key value
--	--
--	getByPrimaryKey = function (self, name)
--		I_AM_CLASS(self)
--		local id = self:getIdByPrimaryKey(name)
--		if not id then return nil end
--
--		return self:getById (id)
--	end;
--
--	-- return the location of 'name' in index
--	getByRank = function (self, rank_index)
--		I_AM_CLASS(self)
--		
--		if rank_index > 0 then 
--			rank_index = rank_index - 1
--		end
--		
--		local index_key = getIndexKey(self)
--		-- id is the score of that index value
--		local _, ids = db:zrange(index_key, rank_index, rank_index, 'withscores')
--		return self:getById(ids[1])
--	end;

	getById = function (self, id)
		I_AM_CLASS(self)
		if type(tonumber(id)) ~= 'number' then return nil end

		-- check the existance in the index cache
		-- if not checkExistanceById(self, id) then return nil end
		-- and then check the existance in the key set
		local key = getNameIdPattern2(self, id)
		if not db:exists(key) then return nil end
		return getFromRedis(self, key)
	end;

	getByIds = function (self, ids)
		I_AM_CLASS(self)
		assert(type(ids) == 'table')

		return getFromRedisPipeline(self, ids)
	end;

	
	-- return a list containing all ids of all instances of this Model
	--
	allIds = function (self, is_rev)
		I_AM_CLASS(self)
		local index_key = getIndexKey(self)
		local all_ids
		if is_rev == 'rev' then
			_, all_ids = db:zrevrange(index_key, 0, -1, 'withscores')
		else
			_, all_ids = db:zrange(index_key, 0, -1, 'withscores')
		end

		return List(all_ids)
	end;

	
	-- slice the ids list, start from 1, support negative index (-1)
	--
	sliceIds = function (self, start, stop, is_rev)
		I_AM_CLASS(self)
		checkType(start, stop, 'number', 'number')
		local index_key = getIndexKey(self)
		local istart, istop = transEdgeFromLuaToRedis(start, stop)
		local ids
		_, ids = db:zrange(index_key, istart, istop, 'withscores')
		if is_rev == 'rev' then
			return List(ids):reverse()
		else
			return List(ids)
		end

	end;

	-- return all instance objects belong to this Model
	--
	all = function (self, is_rev)
		I_AM_CLASS(self)
		local all_ids = self:allIds(is_rev)
		return getFromRedisPipeline(self, all_ids)
	end;

	-- slice instance object list, support negative index (-1)
	--
	slice = function (self, start, stop, is_rev)
		-- !slice method won't be open to query set, because List has slice method too.
		I_AM_CLASS(self)
		local ids = self:sliceIds(start, stop, is_rev)
		return getFromRedisPipeline(self, ids)
	end;

	-- return the actual number of the instances
	--
	numbers = function (self)
		I_AM_CLASS(self)
		return db:zcard(getIndexKey(self))
	end;

	-- return the first instance found by query set
	--
	get = function (self, query_args, find_rev)
		I_AM_CLASS(self)
		
		local PART_LEN = 100
		local total = self:numbers()
		local nparts = math.floor((total+PART_LEN-1)/PART_LEN)
		local logic = type(query_args) == 'table' and query_args[1] == 'or' and 'or' or 'and'
		local flag

		local walkcheck = function (ids)
			local objs = getFromRedisPipeline(self, ids)
			for _, obj in ipairs(objs) do
				-- logic check
				flag = checkLogicRelation(obj, query_args, logic == 'and', self)
				if flag then return obj end
			end
			
			return nil
		end
			
		
		if find_rev == 'rev' then
			for i=nparts, 1, -1 do
				local ids = self:sliceIds(PART_LEN*(i-1)+1, PART_LEN*i, 'rev')
				local obj = walkcheck(ids)
				if obj then return obj end
			end
		
		else
			for i=1, nparts do
				local ids = self:sliceIds(PART_LEN*(i-1)+1, PART_LEN*i)
				local obj = walkcheck(ids)
				if obj then return obj end
			end
			
		end
	
		return nil
	end;

	--- fitler some instances belong to this model
	-- @param query_args: query arguments in a table
	-- @param 
	-- @param 
	-- @param 
	-- @return
  

  
	filter = function (self, query_args, start, stop, is_rev)
		I_AM_CLASS(self)
		assert(type(query_args) == 'table' or type(query_args) == 'function', 
			'[Error] the query_args passed to filter must be table or function.')
        
		if start then assert(type(start) == 'number', '[Error] @filter - start must be number.') end
		if stop then assert(type(stop) == 'number', '[Error] @filter - stop must be number.') end
		if is_rev then assert(type(is_rev) == 'string', '[Error] @filter - is_rev must be string.') end

		local is_args_table = (type(query_args) == 'table')
		local logic = 'and'

		------------------------------------------------------------------------------
		-- start do real filter
		local all_ids = {}
		local query_set = QuerySet()

		if is_args_table then
			assert( not query_args['id'], 
				"[Error] get and filter don't support search by id, please use getById.")

			-- if query table is empty, treate it as all action, or slice action
			if isFalse(query_args) then
				-- need to participate sort, if has
				if no_sort_rule then
					return self:slice(start, stop, is_rev), self:numbers()
				else
					query_set = self:all()
				end
			end
			
			if query_args[1] then
				-- normalize the 'and' and 'or' logic
				assert(query_args[1] == 'or' or query_args[1] == 'and',
					"[Error] The logic should be 'and' or 'or', rather than: " .. tostring(query_args[1]))
				if query_args[1] == 'or' then
					logic = 'or'
				end
				query_args[1] = nil
			end
		end

		local logic_choice = (logic == 'and')
--		local partially_got = false
		local fields = self.__fields
		
		-- walkcheck can process full object and partial object
		local walkcheck = function (objs, model)
			for i, obj in ipairs(objs) do
				-- check the object's legalery, only act on valid object
				local flag = checkLogicRelation(obj, query_args, logic_choice, model)

				-- if walk to this line, means find one
				if flag then
					tinsert(query_set, obj)
				end
			end
		end

    all_ids = self:allIds()

    local objs, nils = getFromRedisPipeline(self, all_ids)
    walkcheck(objs, self)

--				if bamboo.config.auto_clear_index_when_get_failed then
--					-- clear model main index
--					if not isFalse(nils) then
--						local index_key = getIndexKey(self)
--						-- each element in nils is the id pattern string, when clear, remove them directly
--						for _, v in ipairs(nils) do
--							db:zremrangebyscore(index_key, v, v)
--						end
--					end
--				end

		------------------------------------------------------------------------------
		-- do later process
		local total_length = #query_set
		-- here, _t_query_set is the all instance fit to query_args now
		local _t_query_set = query_set

		-- slice
		if start or stop then
			-- now id_list is a list containing all id of instances fit to this query_args rule, so need to slice
			query_set = _t_query_set:slice(start, stop, is_rev)
		end

		-- return results
		return query_set
	end;


    	-- deprecated
	-- count the number of instance fit to some rule
	count = function (self, query_args)
		I_AM_CLASS(self)
		local _, length = self:filter(query_args)
		return length
	end;


	
	
	-- delete self instance object
	-- self can be instance or query set
	delById = function (self, ids)
		I_AM_CLASS(self)
		if bamboo.config.use_fake_deletion == true then
			return self:fakeDelById(ids)
		else
			return self:trueDelById(ids)
		end
	end;

	fakeDelById = function (self, ids)
		local idtype = type(ids)
		if idtype == 'table' then
			for _, v in ipairs(ids) do
				v = tostring(v)
				fakedelFromRedis(self, v)
			end
		else
			fakedelFromRedis(self, tostring(ids))
		end
	end;

	trueDelById = function (self, ids)
		local idtype = type(ids)
		if idtype == 'table' then
			for _, v in ipairs(ids) do
				v = tostring(v)
				delFromRedis(self, v)
			end
		else
			delFromRedis(self, tostring(ids))
		end
	end;

	-----------------------------------------------------------------
	-- validate form parameters by model defination
	-- usually, params = Form:parse(req)
	-- TODO: should perfect 
	validate = function (self, params)
		I_AM_CLASS(self)
		checkType(params, 'table')
		local fields = self.__fields
		local err_msgs = {}
		local is_valid = true
		for k, v in pairs(fields) do
			local ret, err_msg = v:validate(params[k], k)
			if not ret then
				is_valid = false
				for _, msg in ipairs(err_msg) do
					table.insert(err_msgs, msg)
				end
			end
		end
		return is_valid, err_msgs
	end;



	--------------------------------------------------------------------
	-- Instance Functions
	--------------------------------------------------------------------
	-- save instance's normal field
	-- before save, the instance has no id
	save = function (self, params)
		I_AM_INSTANCE(self)

		local new_case = true
		-- here, we separate the new create case and update case
		-- if backwards to Model, the __primarykey is 'id'
		local primarykey = self.__primarykey
		assert(type(primarykey) == 'string', "[Error] the __primarykey should be string.")

		-- if self has id attribute, it is an instance saved before. use id to separate two cases
		if self.id then new_case = false end

		-- update the lastmodified_time
		self.lastmodified_time = socket.gettime()

		local index_key = getIndexKey(self)
		local replies
		if new_case then
			local countername = getCounterName(self)
			local options = { watch = {countername, index_key}, cas = true, retry = 2 }
			replies = db:transaction(function(db)
				-- increase the instance counter
				db:incr(countername)
				self.id = db:get(countername)
				local model_key = getNameIdPattern(self)
				local self, store_kv = processBeforeSave(self, params)
				-- assert(not db:zscore(index_key, self[primarykey]), "[Error] save duplicate to an unique limited field, aborted!")
				if db:zscore(index_key, self[primarykey]) then print(format("[Warning] save duplicate to an unique limited field: %s.", primarykey)); return nil end

				db:zadd(index_key, self.id, self[primarykey])
				-- update object hash store key
				db:hmset(model_key, unpack(store_kv))

				if bamboo.config.index_hash then
					mih.index(self,true);--create hash index
				end
			end, options)
		else
			-- update case
			assert(tonumber(getCounter(self)) >= tonumber(self.id), '[Error] @save - invalid id.')
			-- in processBeforeSave, there is no redis action
			local self, store_kv = processBeforeSave(self, params)
			local model_key = getNameIdPattern(self)

			local options = { watch = {index_key}, cas = true, retry = 2 }
			replies = db:transaction(function(db)
				if bamboo.config.index_hash then
					mih.index(self,false);--update hash index
				end

				local score = db:zscore(index_key, self[primarykey])
				-- assert(score == self.id or score == nil, "[Error] save duplicate to an unique limited field, aborted!")
				-- score is number, self.id is string
				if not (tostring(score) == self.id or score == nil) then print(format("[Warning] save duplicate to an unique limited field: %s.", primarykey)); return nil  end

				-- if modified primarykey, score will be nil, remove the old id-primarykey pair, for later new save primarykey
				if not score then
					db:zremrangebyscore(index_key, self.id, self.id)
				end
				-- update __index score and member
				db:zadd(index_key, self.id, self[primarykey])
				-- update object hash store key
				db:hmset(model_key, unpack(store_kv))
			end, options)
		end

		-- make fulltext indexes
		if isUsingFulltextIndex(self) then
			bamboo.internal.makeFulltextIndexes(self)
		end
--		if isUsingRuleIndex(self) then
--			updateIndexByRules(self, 'update')
--		end

		return self
	end;

	-- partially update function, once one field
	-- can only apply to none foreign field
	update = function (self, field, new_value)
		I_AM_INSTANCE(self)
		checkType(field, 'string')
		assert(type(new_value) == 'string' or type(new_value) == 'number' or type(new_value) == 'nil')
		local fld = self.__fields[field]
		if not fld then print(("[Warning] Field %s doesn't be defined!"):format(field)); return nil end
		assert( not fld.foreign, ("[Error] %s is a foreign field, shouldn't use update function!"):format(field))
		local model_key = getNameIdPattern(self)
		assert(db:exists(model_key), ("[Error] Key %s does't exist! Can't apply update."):format(model_key))

		local primarykey = self.__primarykey

		-- if field is indexed, need to update the __index too
		if field == primarykey then
			assert(new_value ~= nil, "[Error] Can not delete primarykey field");
			local index_key = getIndexKey(self)
			db:zremrangebyscore(index_key, self.id, self.id)
		   	db:zadd(index_key, self.id, new_value)
		end

		-- update the lua object
		self[field] = new_value
		--hash index
		if bamboo.config.index_hash then
			mih.index(self,false,field);
		end

		--update object in database
		if new_value == nil then
			-- could not delete index field
			if field ~= primarykey then
				db:hdel(model_key, field)
			end
		else
			-- apply to db
			-- if field is indexed, need to update the __index too
			if field == primarykey then
				local index_key = getIndexKey(self)
				db:zremrangebyscore(index_key, self.id, self.id)
				db:zadd(index_key, self.id, new_value)
			end

			db:hset(model_key, field, new_value)
		end
		-- update the lastmodified_time
		self.lastmodified_time = socket.gettime()
		db:hset(model_key, 'lastmodified_time', self.lastmodified_time)

		-- apply to lua object
		self[field] = new_value

		-- if fulltext index
		if fld.fulltext_index and isUsingFulltextIndex(self) then
			bamboo.internal.makeFulltextIndexes(self)
		end
--		if isUsingRuleIndex(self) then
--			updateIndexByRules(self, 'update')
--		end


		return self
	end;


	-- delete self instance object
	-- self can be instance or query set
	fakeDel = function (self)
		-- if self is query set
		fakedelFromRedis(self)

		self = nil
	end;

	-- delete self instance object
	-- self can be instance or query set
	trueDel = function (self)
		delFromRedis(self)

		self = nil
	end;


	-- delete self instance object
	-- self can be instance or query set
	del = function (self)
		I_AM_INSTANCE(self)
		if bamboo.config.use_fake_deletion == true then
			return self:fakeDel()
		else
			return self:trueDel()
		end
	end;

	-- use style: Model_name:restoreDeleted(id)
	restoreDeleted = function (self, id)
		I_AM_CLASS(self)
		return restoreFakeDeletedInstance(self, id)
	end;

	-- clear all deleted instance and its foreign relations
	sweepDeleted = function (self)
		local deleted_keys = db:keys('DELETED:*')
		for _, v in ipairs(deleted_keys) do
			-- containing hash structure and foreign zset structure
			db:del(v)
		end
		db:del(dcollector)
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
		assert(tonumber(getCounter(self)) >= tonumber(self.id), '[Error] before doing addForeign, you must save this instance.')
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

		local model_key = getNameIdPattern(self)
		if fld.st == 'ONE' then
			-- record in db
			db:hset(model_key, field, new_id)
			-- ONE foreign value can be get by 'get' series functions
			self[field] = new_id

		else
			local key = getFieldPattern(self, field)
			local store_module = getStoreModule(fld.st)
			store_module.add(key, new_id, fld.fifolen or socket.gettime())
			-- in zset, the newest member has the higher score
			-- but use getForeign, we retrieve them from high to low, so newest is at left of result
		end

--		if isUsingRuleIndex() then
--			updateIndexByRules(self, 'update')
--		end

		-- update the lastmodified_time
		self.lastmodified_time = socket.gettime()
		db:hset(model_key, 'lastmodified_time', self.lastmodified_time)
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
		assert(fld.st, ("[Error] No store type setting for this foreign field %s."):format(field))

		if fld.st == 'ONE' then
			if isFalse(self[field]) then return nil end

			local model_key = getNameIdPattern(self)
			if fld.foreign == 'ANYSTRING' then
				-- return string directly
				return self[field]
			else
				local link_model, linked_id
				if fld.foreign == 'UNFIXED' then
					link_model, linked_id = seperateModelAndId(self[field])
				else
					-- normal case
					link_model = getModelByName(fld.foreign)
					linked_id = self[field]
				end

				local obj = link_model:getById (linked_id)
				if not isValidInstance(obj) then
					print('[Warning] invalid ONE foreign id or object for field: '..field)

					if bamboo.config.auto_clear_index_when_get_failed then
						-- clear invalid foreign value
						db:hdel(model_key, field)
						self[field] = nil
					end

					return nil
				else
					return obj
				end
			end
		else
			if isFalse(self[field]) then return QuerySet() end

			local key = getFieldPattern(self, field)

			local store_module = getStoreModule(fld.st)
			-- scores may be nil
			local list, scores = store_module.retrieve(key)

			if list:isEmpty() then return QuerySet() end
			list = list:slice(start, stop, is_rev)
			if list:isEmpty() then return QuerySet() end
			if not isFalse(scores) then scores = scores:slice(start, stop, is_rev) end

			local objs, nils = retrieveObjectsByForeignType(fld.foreign, list)

			if bamboo.config.auto_clear_index_when_get_failed then
				-- clear the invalid foreign item value
				if not isFalse(nils) then
					-- each element in nils is the id pattern string, when clear, remove them directly
					for _, v in ipairs(nils) do
						store_module.remove(key, v)
					end
				end
			end

			return objs, scores
		end
	end;

	getForeignIds = function (self, field, start, stop, is_rev)
		I_AM_INSTANCE(self)
		checkType(field, 'string')
		local fld = self.__fields[field]
		assert(fld, ("[Error] Field %s doesn't be defined!"):format(field))
		assert(fld.foreign, ("[Error] This field %s is not a foreign field."):format(field))
		assert(fld.st, ("[Error] No store type setting for this foreign field %s."):format(field))

		if fld.st == 'ONE' then
			if isFalse(self[field]) then return nil end

			return self[field]

		else
			if isFalse(self[field]) then return List() end
			local key = getFieldPattern(self, field)
			local store_module = getStoreModule(fld.st)
			local list, scores = store_module.retrieve(key)
			if list:isEmpty() then return List() end
			list = list:slice(start, stop, is_rev)
			if list:isEmpty() then return List() end
			if not isFalse(scores) then scores = scores:slice(start, stop, is_rev) end

			return list, scores
		end

	end;

	-- rearrange the foreign index by input list
	rearrangeForeignMembers = function (self, field, inlist)
		I_AM_INSTANCE(self)
		assert(type(field) == 'string' and type(inlist) == 'table', '[Error] @ rearrangeForeign - parameters type error.' )
		local fld = self.__fields[field]
		assert(fld, ("[Error] Field %s doesn't be defined!"):format(field))
		assert(fld.foreign, ("[Error] This field %s is not a foreign field."):format(field))
		assert(fld.st, ("[Error] No store type setting for this foreign field %s."):format(field))

		local new_orders = {}
		local orig_orders = self:getForeignIds(field)
		local orig_len = #orig_orders
		local rorig_orders = {}
		-- make reverse hash for all ids
		for i, v in ipairs(orig_orders) do
			rorig_orders[tostring(v)] = i
		end
		-- retrieve valid elements in inlist
		for i, elem in ipairs(inlist) do
			local pos = rorig_orders[elem]  -- orig_orders:find(tostring(elem))
			if pos then
				tinsert(new_orders, elem)
				-- remove the original element
				orig_orders[pos] = nil
			end
		end
		-- append the rest elements in foreign to the end of new_orders
		for i = 1, orig_len do
			if orig_orders[i] ~= nil then
				tinsert(new_orders, v)
			end
		end

		local key = getFieldPattern(self, field)
		-- override the original foreign zset value
		rdzset.save(key, new_orders)

		return self
	end;

	-- delelte a foreign member
	-- obj can be instance object, also can be object's id, also can be anystring.
	removeForeignMember = function (self, field, obj)
		I_AM_INSTANCE(self)
		checkType(field, 'string')
		local fld = self.__fields[field]
		assert(not isFalse(obj), "[Error] @delForeign. param obj must not be nil.")
		assert(fld, ("[Error] Field %s doesn't be defined!"):format(field))
		assert(fld.foreign, ("[Error] This field %s is not a foreign field."):format(field))
		assert(fld.st, ("[Error] No store type setting for this foreign field %s."):format(field))
		--assert( fld.foreign == 'ANYSTRING' or obj.id, "[Error] This object doesn't contain id, it's not a valid object!")
		assert(fld.foreign == 'ANYSTRING'
			or fld.foreign == 'UNFIXED'
			or (type(obj) == 'table' and fld.foreign == getClassName(obj)),
			("[Error] This foreign field '%s' can't accept the instance of model '%s'."):format(field, getClassName(obj) or tostring(obj)))

		-- if self[field] is nil, it must be wrong somewhere
		if isFalse(self[field]) then return nil end

		local new_id
		if isNumOrStr(obj) then
			-- obj is id or anystring
			new_id = tostring(obj)
		else
			checkType(obj, 'table')
			if fld.foreign == 'UNFIXED' then
				new_id = getNameIdPattern(obj)
			else
				new_id = tostring(obj.id)
			end
		end

		local model_key = getNameIdPattern(self)
		if fld.st == 'ONE' then
			-- we must check the equality of self[filed] and new_id before perform delete action
			if self[field] == new_id then
				-- maybe here is rude
				db:hdel(model_key, field)
				self[field] = nil
			end
		else
			local key = getFieldPattern(self, field)
			local store_module = getStoreModule(fld.st)
			store_module.remove(key, new_id)
		end

--		if isUsingRuleIndex() then
--			updateIndexByRules(self, 'update')
--		end

		-- update the lastmodified_time
		self.lastmodified_time = socket.gettime()
		db:hset(model_key, 'lastmodified_time', self.lastmodified_time)
		return self
	end;

	delForeign = function (self, field)
		I_AM_INSTANCE(self)
		checkType(field, 'string')
		local fld = self.__fields[field]
		assert(fld, ("[Error] Field %s doesn't be defined!"):format(field))
		assert(fld.foreign, ("[Error] This field %s is not a foreign field."):format(field))
		assert(fld.st, ("[Error] No store type setting for this foreign field %s."):format(field))


		local model_key = getNameIdPattern(self)
		if fld.st == 'ONE' then
			-- maybe here is rude
			db:hdel(model_key, field)
			self[field] = nil
		else
			local key = getFieldPattern(self, field)
			-- delete the foreign key
			db:del(key)
		end

--		if isUsingRuleIndex() then
--			updateIndexByRules(self, 'update')
--		end

		-- update the lastmodified_time
		self.lastmodified_time = socket.gettime()
		db:hset(model_key, 'lastmodified_time', self.lastmodified_time)
		return self
	end;

	deepDelForeign = function (self, field)
		I_AM_INSTANCE(self)
		checkType(field, 'string')
		local fld = self.__fields[field]
		assert(fld, ("[Error] Field %s doesn't be defined!"):format(field))
		assert(fld.foreign, ("[Error] This field %s is not a foreign field."):format(field))
		assert(fld.st, ("[Error] No store type setting for this foreign field %s."):format(field))

		-- delete the foreign objects first
		local fobjs = self:getForeign(field)
		if fobjs then fobjs:del() end

		local model_key = getNameIdPattern(self)
		if fld.st == 'ONE' then
			-- maybe here is rude
			db:hdel(model_key, field)
			self[field] = nil
		else
			local key = getFieldPattern(self, field)
			-- delete the foreign key
			db:del(key)
		end

--		if isUsingRuleIndex() then
--			updateIndexByRules(self, 'update')
--		end

		-- update the lastmodified_time
		self.lastmodified_time = socket.gettime()
		db:hset(model_key, 'lastmodified_time', self.lastmodified_time)
		return self
	end;

	-- check whether some obj is already in foreign list
	-- instance:inForeign('some_field', obj)
	hasForeignMember = function (self, field, obj)
		I_AM_INSTANCE(self)
		checkType(field, 'string')
		local fld = self.__fields[field]
		assert(fld, ("[Error] Field %s doesn't be defined!"):format(field))
		assert(fld.foreign, ("[Error] This field %s is not a foreign field."):format(field))
		assert( fld.st, ("[Error] No store type setting for this foreign field %s."):format(field))
		assert(fld.foreign == 'ANYSTRING' or obj.id, "[Error] This object doesn't contain id, it's not a valid object!")
		assert(fld.foreign == 'ANYSTRING' or fld.foreign == 'UNFIXED' or fld.foreign == getClassName(obj),
			   ("[Error] The foreign model (%s) of this field %s doesn't equal the object's model %s."):format(fld.foreign, field, getClassName(obj) or ''))
		if isFalse(self[field]) then return nil end

		local new_id
		if isNumOrStr(obj) then
			-- obj is id or anystring
			new_id = tostring(obj)
		else
			checkType(obj, 'table')
			if fld.foreign == 'UNFIXED' then
				new_id = getNameIdPattern(self)
			else
				new_id = tostring(obj.id)
			end
		end

		if fld.st == "ONE" then
			return self[field] == new_id
		else
			local key = getFieldPattern(self, field)
			local store_module = getStoreModule(fld.st)
			return store_module.has(key, new_id)
		end

		return false
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
			local store_module = getStoreModule(fld.st)
			return store_module.num(key)
		end
	end;

	-- check this class/object has a foreign key
	-- @param field:  field of that foreign model
	hasForeignKey = function (self, field)
		I_AM_CLASS_OR_INSTANCE(self)
		checkType(field, 'string')
		local fld = self.__fields[field]
		if fld and fld.foreign then return true
		else return false
		end
	end;

	------------------------------------------------------------------------
	-- misc APIs
	------------------------------------------------------------------------

	
	getClassName = getClassName;


	getFDT = function (self, field)
		I_AM_CLASS_OR_INSTANCE(self)
		checkType(field, 'string')

		return self.__fields[field]

	end;

	-- get the model's instance counter value
	-- this can be call by Class and Instance
	getCounter = getCounter;
}:include('bamboo.mixins.custom'):include('bamboo.mixins.fulltext')


-- keep compatable with old version
--Model.__indexfd = Model.__primarykey
Model.__tag = Model.__name
--Model.getRankByIndex = Model.getRankByPrimaryKey
--Model.getIdByIndex = Model.getIdByPrimaryKey
--Model.getIndexById = Model.getPrimaryKeyById
--Model.getByIndex = Model.getByPrimaryKey
Model.classname = Model.getClassName


Model.clearForeign = Model.delForeign
Model.deepClearForeign = Model.deepDelForeign
Model.hasForeign = Model.hasForeignMember
Model.rearrangeForeign = Model.rearrangeForeignMembers



return Model

