module(..., package.seeall)

local cjson = require 'cjson'
local cmsgpack = require 'cmsgpack'
local socket = require 'socket'

local mih = require 'bamboo.model-indexhash'
require 'bamboo.queryset'

local tinsert, tremove = table.insert, table.remove
local format = string.format

local db = BAMBOO_DB

local rdstring = require 'bamboo.db.redis.string'
local rdlist = require 'bamboo.db.redis.list'
local rdset = require 'bamboo.db.redis.set'
local rdzset = require 'bamboo.db.redis.zset'
local rdfifo = require 'bamboo.db.redis.fifo'
local rdzfifo = require 'bamboo.db.redis.zfifo'
local rdhash = require 'bamboo.db.redis.hash'

require 'bamboo.db.redis.luascript'
local snippets = bamboo.dbsnippets.set

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
bamboo.internals['getStoreModule'] = getStoreModule

------------------------------------------------------------------------------------
local getModelByName  = bamboo.getModelByName
local dcollector= 'DELETED:COLLECTOR'
local rule_manager_prefix = '_RULE_INDEX_MANAGER:'
local rule_query_result_pattern = '_RULE:%s:%s'   -- _RULE:Model:num
local rule_index_query_sortby_divider = ' |^|^| '
local rule_index_divider = ' ^_^ '
local Model

-- -- switches
-- -- can be called by instance and class
-- local isUsingFulltextIndex = function (self)
-- 	local model = self
-- 	if isInstance(self) then model = getModelByName(self:getClassName()) end
-- 	if bamboo.config.fulltext_index_support and rawget(model, '__use_fulltext_index') then
-- 		return true
-- 	else
-- 		return false
-- 	end
-- end

-- local isUsingRuleIndex = function ()
-- 	if bamboo.config.rule_index_support == false then
-- 		return false
-- 	end
-- 	return true
-- end




-----------------------------------------------------------------
-- misc functions
-----------------------------------------------------------------
local ASSERT_PROMPTS = {
	['undefined_field'] = "Field %s wasn't be defined!",
	['not_foreign_field'] = "%s is not a foreign field!",
	['no_store_type'] = "No store type for this foreign field %s.",
	['not_matched_foreign_type'] = "obj %s can not fit this foreign type %s!",
}


local check = function (statement, atfunc, prompt_key, ...)
	local prompt_str = ASSERT_PROMPTS[prompt_key] or prompt_key
	local assert_msg = pcall(string.format, prompt_str, ...) or ''
	assert(statement, string.format('[Error] @%s', atfunc) .. assert_msg)
end


local transEdgeFromLuaToRedis = function (start, stop)
	local start = start or 1
	local stop = stop or -1
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



--- make lua object from redis' raw data table
local makeObject = function (self, data)
	-- if data is invalid, return nil
	-- if not isValidInstance(data) then
	-- 	--print("[Warning] @makeObject - Object is invalid.")
	-- 	-- print(debug.traceback())
	-- 	return nil
	-- end
	-- XXX: keep id as string for convienent, because http and database are all string

	-- data is the form of {key1, val1, key2, val2, key3, val3}
	-- change form
	local hash_data = {}
	for i = 1, #data, 2 do
		hash_data[data[i]] = data[i+1]
	end

	local fields = self.__fields
	for k, fdt in pairs(fields) do

		local value = hash_data[k]
		-- for ONE foreign object
		if fdt.foreign and fdt.foreign ~= 'ANYSTRING' and fdt.st == 'ONE' and type(value) == 'table' then
			local ihdata = {}
			for i = 1, #value, 2 do
				ihdata[value[i]] = value[i+1]
			end
			hash_data[k] = ihdata
		else
			if fdt.type == 'number' then
				hash_data[k] = tonumber(value)
			elseif fdt.type == 'boolean' then
				hash_data[k] = (value == 'true')
			end
		end
	end
-- print('---- in hash_data')
-- ptable(hash_data)
	-- generate an object
	return self(hash_data)
end

local makeObjects = function (self, data_list)
	local objs = QuerySet()
	local nils = {}
	for i, v in ipairs(data_list) do
		if #v == 0 then
			tinsert(nils, i)
		else
			tinsert(objs, makeObject(self, v))
		end
	end

	return objs, nils
end

local delFromRedis = function (self, id)
	local id = id or self.id
	local model_name = self.__name
	local index_key = getIndexKey(self)

	local fields_string = cmsgpack.pack(self.__fields)
	local data_list = db:eval(snippets.SNIPPET_delInstanceAndForeigns, 0, model_name, id, fields_string)

end
bamboo.internals['delFromRedis'] = delFromRedis

local fakeDelFromRedis = function (self, id)
	local id = id or self.id
	local model_name = self.__name
	local index_key = getIndexKey(self)

	local fields_string = cmsgpack.pack(self.__fields)
	local data_list = db:eval(snippets.SNIPPET_fakeDelInstanceAndForeigns, 0, model_name, id, fields_string)

end
bamboo.internals['fakeDelFromRedis'] = fakeDelFromRedis



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
bamboo.internals.checkLogicRelation = checkLogicRelation


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


local collectQueryFunctionUpvalues = function (func)
	local upvalues = {}
	for i=1, math.huge do
		local name, v = debug.getupvalue(func, i)
		if not name then break end
		local ctype = type(v)
		local table_has_metatable = false
		if ctype == 'table' then
			table_has_metatable = getmetatable(v) and true or false
		end
		-- because we could not collect the upvalues whose type is 'table', print warning here
		if type(v) == 'function' or table_has_metatable then
			return false
		end

		if ctype == 'table' then
			upvalues[#upvalues + 1] = { name, cmsgpack.pack(v), type(v) }
		else
			upvalues[#upvalues + 1] = { name, tostring(v), type(v) }
		end
	end

	return true, upvalues
end


local serializeQueryFunction = function (query_args)
	local flag, upvalues = collectQueryFunctionUpvalues(query_args)
	if not flag then return nil end

	-- query_args now is function
	local out = {}
	table.insert(out, 'function')
	table.insert(out, string.dump(query_args))
	for _, pair in ipairs(upvalues) do
		tinsert(out, pair[1])	-- key
		tinsert(out, pair[2])	-- value
		tinsert(out, pair[3])	-- value type
	end

	-- use a delemeter to seperate obviously
	return table.concat(out, ' ^_^ ')
end



----------------------------------------------------------------------
--- save process
-- called by save
-- self is instance
local processBeforeSave = function (self, params)
	local r_params = {}
	local primarykey = self.__primarykey
	local fields = self.__fields

	-- if parameters exist, update it
	if params and type(params) == 'table' then
		for k, v in pairs(params) do
			local fdt = fields[k]
			if k ~= 'id' and fdt and (fdt.foreign == nil or (fdt.foreign and fdt.st == 'ONE')) then
				self[k] = tostring(v)
			end
		end
	end

	assert( primarykey == 'id' or isTrue(self[primarykey]) ,
		format("[Error] instance's primary field %s's value must not be nil. Please check your model definition.", 
			   primarykey))

	-- check required field
	-- TODO: later we should update this to validate most attributes for each field
	for field, fdt in pairs(fields) do
		if fdt.required then
			assert(self[field], 
				   format("[Error] @processBeforeSave - this field '%s' is required but its' value is nil.", field))
		end
	end

	for k, v in pairs(self) do
		-- when save, need to check something
		-- 1. only save fields defined in model defination
		-- 2. don't save the functional member, and _parent
		-- 3. don't save those fields not defined in model defination
		-- 4. don't save those except ONE foreign fields, which are defined in model defination
		if k ~= 'id' and k ~= 'lastmodified_time' then
			local fdt = fields[k]
			-- if v is nil, pairs will not iterate it, key will and should not be 'id'
			if fdt then
				if not fdt['foreign'] or ( fdt['foreign'] and fdt['st'] == 'ONE') then
					-- save
					r_params[k] = tostring(v)
				end
			end
		end
	end

	return r_params
end

------------------------------------------------------------------------
-- Model Definition
-- Model is the basic object of Bamboo Database Abstract Layer
------------------------------------------------------------------------
Model = Object:extend {
	__name = 'Model';
	__fields = {
	    ['id'] = {},
		['created_time'] = { type="number" },
	    ['lastmodified_time'] = { type="number" },

	};
	__primarykey = "id";

	-- make every object creatation from here: 
	-- every object has the 'id', 'created_time' and 'lastmodified_time' fields
	init = function (self, t)
		local t = t or {}
		local fields = self.__fields

		for field, fdt in pairs(fields) do
			-- assign to default value if exsits
			local value = t[field] or fdt.default
			if type(value) == 'function' then
				self[field] = value()
			else
				self[field] = value
			end
		end

		self.id = self.id or t.id
		self.created_time = self.created_time or t.created_time or socket.gettime()
		self.lastmodified_time = self.lastmodified_time or t.lastmodified_time or socket.gettime()

		return self
	end;


	--------------------------------------------------------------------
	-- Class Functions. Called by class object.
	--------------------------------------------------------------------
	
	-- return the location of 'name' in index
	getRankByPrimaryKey = function (self, name)
		I_AM_CLASS(self)

		local index_key = getIndexKey(self)
		-- id is the score of that index value
		local rank = db:zrank(index_key, tostring(name))
		return tonumber(rank) + 1 
	end;

	getIdByPrimaryKey = function (self, name)
		I_AM_CLASS(self)
		local index_key = getIndexKey(self)
		-- id is the score of that index value
		return db:zscore(index_key, tostring(name))
	end;

	getPrimaryKeyById = function (self, id)
		I_AM_CLASS(self)
		if type(tonumber(id)) ~= 'number' then return nil end

		local index_key = getIndexKey(self)
		local r = db:zrangebyscore(index_key, id, id)
		if #r == 0 then return nil end

		-- return the first element, for r is a list
		return r[1]
	end;

	-- return instance object by primary key value
	--
	getByPrimaryKey = function (self, name)
		I_AM_CLASS(self)
		local id = self:getIdByPrimaryKey(name)
		if not id then return nil end

		return self:getById (id)
	end;

	-- return the location of 'name' in index
	getByRank = function (self, rank_index)
		I_AM_CLASS(self)
		
		if rank_index > 0 then 
			rank_index = rank_index - 1
		end
		
		local index_key = getIndexKey(self)
		-- id is the score of that index value
		local _, r = db:zrange(index_key, rank_index, rank_index, 'withscores')
		if #r == 0 then return nil end

		local id = r[1]
		return self:getById(id)
	end;

	getById = function (self, id)
		I_AM_CLASS(self)
		if type(tonumber(id)) ~= 'number' then return nil end

		local data = db:eval(snippets.SNIPPET_getById, 0, self.__name, id)
		return makeObject(self, data)
	end;

	getByIds = function (self, ids)
		I_AM_CLASS(self)
		assert(type(ids) == 'table')

		local data = db:eval(snippets.SNIPPET_getByIds, 0, self.__name, cmsgpack.pack(ids))
		return makeObjects(self, data)
	end;
	
	getByIdWithForeigns = function (self, id, ...)
		I_AM_CLASS(self)
		if type(tonumber(id)) ~= 'number' then return nil end
		local ffields_args = {...}
		local fields = self.__fields
		local ffields = {}
		for _, field in ipairs(ffields_args) do
			ffields[field] = fields[field]
		end

		local data = db:eval(snippets.SNIPPET_getByIdWithForeigns, 0, self.__name, id, cmsgpack.pack(ffields))
		return makeObject(self, data)
	end;

	getByIdsWithForeigns = function (self, ids, ...)
		I_AM_CLASS(self)
		assert(type(ids) == 'table')
		local ffields_args = {...}
		local fields = self.__fields
		local ffields = {}
		for _, field in ipairs(ffields_args) do
			ffields[field] = fields[field]
		end

		local data = db:eval(snippets.SNIPPET_getByIdsWithForeigns, 0, self.__name, cmsgpack.pack(ids), cmsgpack.pack(ffields))
		return makeObjects(self, data)
	end;
	
	-- return a list containing all ids of all instances of this Model
	--
	allIds = function (self, is_rev)
		I_AM_CLASS(self)
		local index_key = getIndexKey(self)
		local _, r
		if is_rev == 'rev' then
			_, r = db:zrevrange(index_key, 0, -1, 'withscores')
		else
			_, r = db:zrange(index_key, 0, -1, 'withscores')
		end
		
		local all_ids = r
		return List(all_ids)
	end;

	
	-- slice the ids list, start from 1, support negative index (-1)
	--
	sliceIds = function (self, start, stop, is_rev)
		I_AM_CLASS(self)
		local index_key = getIndexKey(self)
		local istart, istop = transEdgeFromLuaToRedis(start, stop)
		local _, r = db:zrange(index_key, istart, istop, 'withscores')

		local ids = List(r)
		if is_rev == 'rev' then
			ids = ids:reverse()
		end

		return ids
	end;

	-- return all instance objects belong to this Model
	--
	all = function (self, is_rev)
		I_AM_CLASS(self)
		local is_rev = is_rev or ''

		local data_list = db:eval(snippets.SNIPPET_all, 0, self.__name, is_rev)
		return makeObjects(self, data_list)
	end;

	-- slice instance object list, support negative index (-1)
	--
	slice = function (self, start, stop, is_rev)
		-- !slice method won't be open to query set, because List has slice method too.
		I_AM_CLASS(self)
		local istart, istop = transEdgeFromLuaToRedis(start, stop)
		local is_rev = is_rev or ''

		local data_list = db:eval(snippets.SNIPPET_slice, 0, self.__name, istart, istop, is_rev)
		return makeObjects(self, data_list)
	end;

	-- return the actual number of the instances
	--
	numbers = function (self)
		I_AM_CLASS(self)
		return db:zcard(getIndexKey(self))
	end;

	-- return the first instance found by query set
	--
	get = function (self, query_args, limit_params)
		I_AM_CLASS(self)

		local logic = ''
		local fields_string = cmsgpack.pack(self.__fields)
		-- XXX: here, we only consider table first
		local query_string
		local ctype = type(query_args)
		if ctype == 'string' then
			query_string = query_args
		elseif ctype == 'function' then
			query_string = serializeQueryFunction(query_args)
		elseif ctype == 'table' then
			logic = query_args[1] == 'or' and 'or' or 'and'
			query_string = cmsgpack.pack(query_args)
		else
			error("[Error] no valid query args type @filter 'query_args'.")
		end
		
		local data = db:eval(snippets.SNIPPET_get, 0, self.__name, fields_string, ctype, query_string, logic) 
		
		if data then return makeObject(self, data) end

		return nil
	end;

	--- filter some instances belong to this model
	-- @param query_args: query arguments in a table
	-- @param 
	-- @param 
	-- @param 
	-- @return
	filter = function (self, query_args, limit_params)
		I_AM_CLASS(self)
		assert(type(query_args) == 'table' or type(query_args) == 'function', 
			'[Error] the query_args passed to filter must be table or function.')

		local logic = query_args[1] == 'or' and 'or' or 'and'
		local fields_string = cmsgpack.pack(self.__fields)
		-- XXX: here, we only consider table first
		local query_string
		local ctype = type(query_args)
		if ctype == 'string' then
			query_string = query_args
		elseif ctype == 'function' then
			query_string = serializeQueryFunction(query_args)
		elseif ctype == 'table' then
			query_string = cmsgpack.pack(query_args)
		else
			error("[Error] no valid query args type @filter 'query_args'.")
		end

		local data_list = db:eval(snippets.SNIPPET_filter, 0, self.__name, fields_string, ctype, query_string, logic) 
		
		if data_list then return makeObjects(self, data_list) end

		return QuerySet()

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
				fakeDelFromRedis(self, v)
			end
		else
			fakeDelFromRedis(self, tostring(ids))
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

		local id = self.id or ''
		local r_params = processBeforeSave(self, params)
		r_params.lastmodified_time = socket.gettime()

		local ret_id = db:eval(snippets.SNIPPET_save, 0, self.__name, id, self.__primarykey, cmsgpack.pack(r_params))

		if ret_id then 
			self.lastmodified_time = r_params.lastmodified_time
			if id == '' then self.id = ret_id end
		end
--[[
		-- make fulltext indexes
		if isUsingFulltextIndex(self) then
			bamboo.internals.makeFulltextIndexes(self)
		end
		if isUsingRuleIndex(self) then
			updateIndexByRules(self, 'update')
		end
--]]
		return self, ret_id ~= nil
	end;

	-- partially update function, once one field
	-- can only apply to none foreign field
	update = function (self, field, new_value)
		I_AM_INSTANCE(self)
		assert(type(new_value) == 'string' or type(new_value) == 'number' or type(new_value) == 'nil')
		local fld = self.__fields[field]
		if not fld then print(("[Warning] Field %s doesn't be defined!"):format(field)); return nil end
		assert( not fld.foreign, ("[Error] %s is a foreign field, shouldn't use update function!"):format(field))

		local new_value = new_value or ''
		local lmtime = socket.gettime()
		local ret = db:eval(snippets.SNIPPET_update, 0, self.__name, self.id, self.__primarykey, field, new_value, self.lastmodified_time)

		if ret then
			self.lastmodified_time = lmtime
			self[field] = new_value
		end

		return self

--[[
		-- if fulltext index
		if fld.fulltext_index and isUsingFulltextIndex(self) then
			bamboo.internals.makeFulltextIndexes(self)
		end
		if isUsingRuleIndex(self) then
			updateIndexByRules(self, 'update')
		end
--]]

	end;


	-- delete self instance object
	-- self can be instance or query set
	fakeDel = function (self)
		-- if self is query set
		fakeDelFromRedis(self)

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

--[[
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
--]]
	-----------------------------------------------------------------------------------
	-- Foreign API
	-----------------------------------------------------------------------------------
	---
	-- add a foreign object's id to this foreign field
	-- return self
	addForeign = function (self, field, obj)
		I_AM_INSTANCE(self)
		assert(type(obj) == 'table' or type(obj) == 'string', '[Error] "obj" should be table or string.')

		local fdt = self.__fields[field]
		local store_type = fdt.st
		local foreign_type = fdt.foreign

		check(fdt, 
			  'addForeign', 'undefined_field', field)
		check(foreign_type, 
			  'addForeign', 'not_foreign_field', field)
		check(store_type, 
			  'addForeign', 'no_store_type', field)

		if foreign_type == 'ANYSTRING' then
			assert(type(obj) == 'string', '[Error] "obj" should be string when foreign type is ANYSTRING.')
		else
			assert( foreign_type == 'UNFIXED' or foreign_type == getClassName(obj),
					("[Error] This foreign field '%s' can't accept the instance of model '%s'."):format(
						field, getClassName(obj) or tostring(obj)))
			assert( obj.id,	"[Error] This object doesn't contain id, it's not a valid object!")
		end

		assert(tonumber(getCounter(self)) >= tonumber(self.id), 
			   '[Error] before doing addForeign, you must save this instance.')

		local new_id
		if fdt.foreign == 'ANYSTRING' then
			new_id = obj
		elseif fdt.foreign == 'UNFIXED' then
			new_id = getNameIdPattern(obj)
		else
			new_id = obj.id
		end

		db:eval(snippets.SNIPPET_addForeign, 0, model_name, id, field, new_id, cmsgpack.pack(fdt))

		-- update the lastmodified_time
		self.lastmodified_time = socket.gettime()

--[[
		if isUsingRuleIndex() then
			updateIndexByRules(self, 'update')
		end
--]]
		return self
	end;

	--
	--
	--
	getForeign = function (self, field, start, stop, is_rev, onlyids)
		I_AM_INSTANCE(self)
		local fdt = self.__fields[field]
		local store_type = fdt.st
		local foreign_type = fdt.foreign
		assert(fdt, ("[Error] Field %s doesn't be defined!"):format(field))
		assert(fdt.foreign, ("[Error] This field %s is not a foreign field."):format(field))
		assert(fdt.st, ("[Error] No store type setting for this foreign field %s."):format(field))

		if store_type == 'ONE' then
			if isFalse(self[field]) then return nil end
			if foreign_type == 'ANYSTRING' then return self[field] end
			if foreign_type == 'UNFIXED' then
				local model_name, id = self[field]:match('(%w+):(%d+)')
				local model = getModelByName(model_name)
				return model:getById(id)
			end
			
			-- normal case
			local model = getModelByName(foreign_type)
			return model:getById(self[filed])
			-- 	if not isValidInstance(obj) then
			-- 		print('[Warning] invalid ONE foreign id or object for field: '..field)

			-- 		if bamboo.config.auto_clear_index_when_get_failed then
			-- 			-- clear invalid foreign value
			-- 			db:hdel(model_key, field)
			-- 			self[field] = nil
			-- 		end

			-- 		return nil
			-- 	else
			-- 		return obj
			-- 	end
			-- end
		else
			if isFalse(self[field]) then return QuerySet() end

			local istart, istop = transEdgeFromLuaToRedis(start, stop)
			db:eval(snippets.SNIPPET_getForeign, 0, self.__name, self.id, field, cmsgpack.pack(fdt), istart, istop, is_rev, onlyids)



			-- local key = getFieldPattern(self, field)

			-- local store_module = getStoreModule(fdt.st)
			-- -- scores may be nil
			-- local list, scores = store_module.retrieve(key)

			-- if list:isEmpty() then return QuerySet() end
			-- list = list:slice(start, stop, is_rev)
			-- if list:isEmpty() then return QuerySet() end
			-- if not isFalse(scores) then scores = scores:slice(start, stop, is_rev) end

			-- local objs, nils = retrieveObjectsByForeignType(fdt.foreign, list)
--[[
			if bamboo.config.auto_clear_index_when_get_failed then
				-- clear the invalid foreign item value
				if not isFalse(nils) then
					-- each element in nils is the id pattern string, when clear, remove them directly
					for _, v in ipairs(nils) do
						store_module.remove(key, v)
					end
				end
			end
--]]
			return objs
		end
	end;


	-- delelte a foreign member
	-- obj can be instance object, also can be object's id, also can be anystring.
	removeForeignMember = function (self, field, obj)
		I_AM_INSTANCE(self)

		local fdt = self.__fields[field]
		local store_type = fdt.st
		local foreign_type = fdt.foreign

		check(not isFalse(obj), 
			  'delForeign', "obj %s is invalid!", tostring(obj))
		check(fdt, 
			  'delForeign', 'undefined_field', field)
		check(foreign_type, 
			  'delForeign', 'not_foreign_field', field)
		check(store_type, 
			  'delForeign', 'no_store_type', field)

		--assert( fdt.foreign == 'ANYSTRING' or obj.id, "[Error] This object doesn't contain id, it's not a valid object!")
		check(foreign_type == 'ANYSTRING'
			or foreign_type == 'UNFIXED'
			or (type(obj) == 'table' and foreign_type == getClassName(obj)),
			'delForeign', 'not_matched_foreign_type', field, getClassName(obj) or tostring(obj))

		if isFalse(self[field]) then return nil end

		local new_id
		if isNumOrStr(obj) then
			-- obj is id or anystring
			new_id = tostring(obj)
		else
			if foreign_type == 'UNFIXED' then
				new_id = getNameIdPattern(obj)
			else
				new_id = tostring(obj.id)
			end
		end

		local model_key = getNameIdPattern(self)
		if store_type == 'ONE' then
			-- we must check the equality of self[filed] and new_id before perform delete action
			if self[field] == new_id then
				-- maybe here is rude
				db:hdel(model_key, field)
				self[field] = nil
			end
		else
			local key = getFieldPattern(self, field)
			local store_module = getStoreModule(fdt.st)
			store_module.remove(key, new_id)
		end

		-- if isUsingRuleIndex() then
		-- 	updateIndexByRules(self, 'update')
		-- end

		-- update the lastmodified_time
		local ct = socket.gettime()
		self.lastmodified_time = ct
		db:hset(model_key, 'lastmodified_time', ct)

		return self
	end;

	delForeign = function (self, field)
		I_AM_INSTANCE(self)

		local fdt = self.__fields[field]
		local store_type = fdt.st
		local foreign_type = fdt.foreign
		assert(fdt, ("[Error] Field %s doesn't be defined!"):format(field))
		assert(foreign_type, ("[Error] This field %s is not a foreign field."):format(field))
		assert(store_type, ("[Error] No store type setting for this foreign field %s."):format(field))

		local model_key = getNameIdPattern(self)
		if store_type == 'ONE' then
			db:hdel(model_key, field)
			self[field] = nil
		else
			local key = getFieldPattern(self, field)
			db:del(key)
		end

		-- if isUsingRuleIndex() then
		-- 	updateIndexByRules(self, 'update')
		-- end

		-- update the lastmodified_time
		local ct = socket.gettime()
		self.lastmodified_time = ct
		db:hset(model_key, 'lastmodified_time', ct)

		return self
	end;

	deepDelForeign = function (self, field)
		I_AM_INSTANCE(self)
		local fdt = self.__fields[field]
		local store_type = fdt.st
		local foreign_type = fdt.foreign

		assert(fdt, ("[Error] Field %s doesn't be defined!"):format(field))
		assert(foreign_type, ("[Error] This field %s is not a foreign field."):format(field))
		assert(store_type, ("[Error] No store type setting for this foreign field %s."):format(field))

		-- delete the foreign objects first
		local fobjs = self:getForeign(field)
		if fobjs then fobjs:del() end

		local model_key = getNameIdPattern(self)
		if store_type == 'ONE' then
			db:hdel(model_key, field)
			self[field] = nil
		else
			local key = getFieldPattern(self, field)
			-- delete the foreign key
			db:del(key)
		end

		-- if isUsingRuleIndex() then
		-- 	updateIndexByRules(self, 'update')
		-- end

		-- update the lastmodified_time
		local ct = socket.gettime()
		self.lastmodified_time = ct
		db:hset(model_key, 'lastmodified_time', ct)

		return self
	end;

	-- check whether obj is already in foreign list
	hasForeign = function (self, field, obj)
		I_AM_INSTANCE(self)

		local fdt = self.__fields[field]
		local store_type = fdt.st
		local foreign_type = fdt.foreign

		assert(fdt, format('[Error] undefined field %s', field))
		assert(foreign_type, ("[Error] This field %s is not a foreign field."):format(field))
		assert(store_type, ("[Error] No store type setting for this foreign field %s."):format(field))
		if foreign_type == 'ANYSTRING' then
			assert(type(obj) == 'string', '[Error] "obj" should be string when foreign type is ANYSTRING.')
		else
			assert(foreign_type == 'UNFIXED' or foreign_type == getClassName(obj),
					("[Error] This foreign field '%s' can't accept the instance of model '%s'."):format(
						field, getClassName(obj) or tostring(obj)))
			assert(obj.id,	"[Error] This object doesn't contain id, it's not a valid object!")
		end

		if isFalse(self[field]) then return nil end

		local new_id
		if isNumOrStr(obj) then
			-- obj is id or anystring
			new_id = tostring(obj)
		else
			if foreign_type == 'UNFIXED' then
				new_id = getNameIdPattern(self)
			else
				new_id = tostring(obj.id)
			end
		end

		if store_type == "ONE" then
			return self[field] == new_id
		else
			local key = getFieldPattern(self, field)
			local store_module = getStoreModule(fdt.st)
			return store_module.has(key, new_id)
		end

		return false
	end;

	-- return the number of elements in the foreign list
	-- @param field:  field of that foreign model
	numForeign = function (self, field)
		I_AM_INSTANCE(self)
		local fdt = self.__fields[field]

		assert(fdt, ("[Error] Field %s doesn't be defined!"):format(field))
		assert(fdt.foreign, ("[Error] This field %s is not a foreign field."):format(field))
		assert(fdt.st, ("[Error] No store type set for this foreign field %s."):format(field))

		if fdt.st == 'ONE' then
			if self[field] == '' or self[field] == nil then
				return 0
			else
				return 1
			end
		else
			local key = getFieldPattern(self, field)
			local store_module = getStoreModule(fdt.st)
			return store_module.num(key)
		end
	end;

--[[
	-- rearrange the foreign index by input list
	reorderForeign = function (self, field, inlist)
		I_AM_INSTANCE(self)
		assert(type(field) == 'string' and type(inlist) == 'table', '[Error] @ rearrangeForeign - parameters type error.' )
		local fdt = self.__fields[field]
		assert(fdt, ("[Error] Field %s doesn't be defined!"):format(field))
		assert(fdt.foreign, ("[Error] This field %s is not a foreign field."):format(field))
		assert(fdt.st, ("[Error] No store type setting for this foreign field %s."):format(field))

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
--]]
	-- check this class/object has a foreign key
	-- @param field:  field of that foreign model
	hasForeignKey = function (self, field)
		I_AM_CLASS_OR_INSTANCE(self)

		local fdt = self.__fields[field]
		if fdt and fdt.foreign then return true
		else return false
		end
	end;


	------------------------------------------------------------------------
	-- misc APIs
	------------------------------------------------------------------------
	getClassName = getClassName;

	getFDT = function (self, field)
		I_AM_CLASS_OR_INSTANCE(self)

		return self.__fields[field]
	end;

	-- get the model's instance counter value
	-- this can be call by Class and Instance
	getCounter = getCounter;
}:include('bamboo.mixins.custom'):include('bamboo.mixins.fulltext')


-- keep compatable with old version
Model.__indexfd = Model.__primarykey
Model.__tag = Model.__name
Model.getRankByIndex = Model.getRankByPrimaryKey
Model.getIdByIndex = Model.getIdByPrimaryKey
Model.getIndexById = Model.getPrimaryKeyById
Model.getByIndex = Model.getByPrimaryKey
Model.classname = Model.getClassName
Model.clearForeign = Model.delForeign
Model.deepClearForeign = Model.deepDelForeign


return Model



