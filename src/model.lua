module(..., package.seeall)

local mih = require 'bamboo.model-indexhash'
require 'bamboo.queryset'

local tinsert, tremove = table.insert, table.remove
local format = string.format

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

local isUsingRuleIndex = function ()
	if bamboo.config.rule_index_support == false then
		return false
	end
	return true
end




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
	if isUsingRuleIndex(self) and self.id then
		updateIndexByRules(self, 'del')
	end

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
	if isUsingRuleIndex(self) and self.id then
		updateIndexByRules(self, 'del')
	end

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

---------------------------------------------------------------------------------
-- RULE INDEX CODE
---------------------------------------------------------------------------------
local specifiedRulePrefix = function ()
	return rule_manager_prefix, rule_query_result_pattern
end

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


local upvalue_collector = {}

local collectRuleFunctionUpvalues = function (query_args)
	local upvalues = upvalue_collector
	for i=1, math.huge do
		local name, v = debug.getupvalue(query_args, i)
		if not name then break end
		local ctype = type(v)
		local table_has_metatable = false
		if ctype == 'table' then
			table_has_metatable = getmetatable(v) and true or false
		end
		-- because we could not collect the upvalues whose type is 'table', print warning here
		if type(v) == 'function' or table_has_metatable then
			print"[Warning] @collectRuleFunctionUpvalues of filter - bamboo has no ability to collect the function upvalue whose type is 'function' or 'table' with metatable."
			return false
		end

		if ctype == 'table' then
			upvalues[#upvalues + 1] = { name, serialize(v), type(v) }
		else
			upvalues[#upvalues + 1] = { name, tostring(v), type(v) }
		end
	end

	return true, upvalues
end


local compressQueryArgs = function (query_args)
	local out = {}
	local qtype = type(query_args)
	if qtype == 'table' then
		if table.isEmpty(query_args) then return '' end

		if query_args[1] == 'or' then tinsert(out, 'or')
		else tinsert(out, 'and')
		end
		query_args[1] = nil
		tinsert(out, '|')

		local queryfs = {}
		for kf in pairs(query_args) do
			tinsert(queryfs, kf)
		end
		table.sort(queryfs)

		for _, k in ipairs(queryfs) do
			v = query_args[k]
			tinsert(out, k)
			if type(v) ~= 'function' then
				tinsert(out, tostring(v))
				tinsert(out, type(v))
			else
				local _, func_name, cmp_obj = v(uglystr)
				local queryt_iden
				local _args = {}
				if type(cmp_obj) == 'table' then
					for _, v in ipairs(cmp_obj) do
						tinsert(_args, tostring(v), type(v))
					end
					queryt_iden = {func_name, unpack(_args)}
				else
					queryt_iden = {func_name, tostring(cmp_obj), type(cmp_obj)}
				end
				-- XXX: here, queryt_iden[2] may be nil, this will not be stored now
              for _, item in ipairs(queryt_iden) do
					tinsert(out, item)
				end
			end
			tinsert(out, '|')
		end

		-- restore the first element, avoiding side effect
		query_args[1] = out[1]

	elseif qtype == 'function' then
		tinsert(out, 'function')
		tinsert(out, '|')
		tinsert(out, string.dump(query_args))
		tinsert(out, '|')
		for _, pair in ipairs(upvalue_collector) do
			tinsert(out, pair[1])	-- key
			tinsert(out, pair[2])	-- value
			tinsert(out, pair[3])	-- value type
		end

		-- clear the upvalue_collector
		upvalue_collector = {}
	end

	-- use a delemeter to seperate obviously
	return table.concat(out, rule_index_divider)
end

local extractQueryArgs = function (qstr)
	local query_args

	--DEBUG(string.len(qstr))
	if qstr:startsWith('function') then
		local startpoint = qstr:find('|') or 1
		local endpoint = qstr:rfind('|') or -1
		fpart = qstr:sub(startpoint + 6, endpoint - 6) -- :trim()
		apart = qstr:sub(endpoint + 6, -1) -- :trim()
		-- now fpart is the function binary string
		query_args = loadstring(fpart)
		-- now query_args is query function
		if not isFalse(apart) then
			-- item 1 is key, item 2 is value, item 3 is value type, item 4 is key ....
			local flat_upvalues = apart:split(rule_index_divider)
			for i=1, #flat_upvalues / 3 do
				local vtype = flat_upvalues[3*i]
				local key = flat_upvalues[3*i - 2]
				local value = flat_upvalues[3*i - 1]
				if vtype == 'table' then
					value = deserialize(value)
				elseif vtype == 'number' then
					value = tonumber(value)
				elseif vtype == 'boolean' then
					value = loadstring('return ' .. value)()
				elseif vtype == 'nil' then
					value = nil
				end
				-- set upvalues
				debug.setupvalue(query_args, i, value)
			end
		end
	else

		local endpoint = -1
		qstr = qstr:sub(1, endpoint - 1)
		local _qqstr = qstr:split('|')
		local logic = _qqstr[1]:sub(1, -6)
		query_args = {logic}
		for i=2, #_qqstr do
			local str = _qqstr[i]
			local kt = str:splittrim(rule_index_divider):slice(2, -2)
			-- kt[1] is 'key', [2] is 'closure', [3] .. are closure's parameters
			local key = kt[1]
			local closure = kt[2]
			if #kt > 3 then
				-- here, all args are string type
				local flat_args = {}
				for j=3, #kt do
					tinsert(flat_args, kt[j])
				end
				local _args = {}
				for i=1, #flat_args, 2 do
					local ctype = flat_args[i+1]
					if ctype == 'number' then
						tinsert(_args, tonumber(flat_args[i]))
					elseif ctype == 'boolean' then
						tinsert(_args, flat_args[i] == 'true')
					elseif ctype == 'nil' then
						-- XXX: won't workable
						tinsert(_args, nil)
						
					end

				end
				-- compute closure now
				query_args[key] = _G[closure]( #_args > 0 and unpack(_args) or nil)
			else
					local ctype = kt[3]
					local val = closure
					if ctype == 'number' then
						val = tonumber(val)
					elseif ctype == 'boolean' then
						val = val == 'true'
					end
				
				-- no args, means this 'closure' is a string, here, we only store string type?
				query_args[key] = val
			end
		end
	end

	return query_args
end

-- query_str_iden is at least ''
local compressSortByArgs = function (sortby_args)
	local strs = {}
	for i = 1, #sortby_args do
       		local v = sortby_args[i]
		local ctype = type(v)
		if ctype == 'string' then
            		tinsert(strs, v)
        	-- may don't appear
        	elseif ctype == 'nil' then
            		tinsert(strs, 'nil')
        	elseif ctype == 'function' then
			tinsert(strs, string.dump(v))
		end
	end

	return table.concat(strs, rule_index_divider)
end

local compressTwoPartArgs = function (query_str_iden, sortby_str_iden)
	return query_str_iden .. rule_index_query_sortby_divider .. sortby_str_iden	
end


local extractSortByArgs = function (sortby_str_iden)
	assert(sortby_str_iden ~= '', "[Error] @extractSortByArgs - sortby_str_iden should not be emply!")
	local sortby_args = luasplit(sortby_str_iden, rule_index_divider)
	--local sortby_args = sortby_str_iden:split(rule_index_divider)
	-- [1] is string or function, [2] is nil or string, 
	local first_arg = sortby_args[1]
	local first_arg_compile = loadstring(first_arg)
	if type(first_arg_compile) == 'function' then
		return first_arg_compile
	elseif not first_arg_compile then
		-- if type(first_arg_compile) ~= 'function', first_arg_compile is a nil
		if #first_arg > 0 then
			local key = first_arg
			local dir = (sortby_args[2] == 'desc' and 'desc' or 'asc')
			return function (a, b)
				local af = a[key]
				local bf = b[key]
				if af and bf then
					if dir == 'asc' then
						return af < bf
					elseif dir == 'desc' then
						return af > bf
					end
				else
					return nil
				end
			end
		end
	else
		return nil
	end
end

local function divideQueryPartAndSortbyPart (combine_str_iden)
	local query_str_iden, sortby_str_iden
	local divider_start, divider_stop = combine_str_iden:find(rule_index_query_sortby_divider)
	if divider_start then
		query_str_iden = combine_str_iden:sub(1, divider_start - 1)
		sortby_str_iden = combine_str_iden:sub(divider_stop + 1, -1)
	else
		query_str_iden = combine_str_iden
		sortby_str_iden = nil
	end
	
	return query_str_iden, sortby_str_iden	
end

local canInstanceFitQueryRule = function (self, qstr)
	local query_args = extractQueryArgs(qstr)
	--DEBUG(query_args)
	local logic_choice = true
	if type(query_args) == 'table' then logic_choice = (query_args[1] == 'and'); query_args[1]=nil end
	return checkLogicRelation(self, query_args, logic_choice)
end

local canInstanceFitQueryRuleAndFindProperPosition = function (self, combine_str_iden)
	local p = 0
--[[	local divider_start, divider_stop = combine_str_iden:find(rule_index_query_sortby_divider)
	if divider_start then
		query_str_iden = combine_str_iden:sub(1, divider_start - 1)
		sortby_str_iden = combine_str_iden:sub(divider_stop + 1, -1)
	else
		query_str_iden = combine_str_iden
		sortby_str_iden = nil
	end
--]]

	local query_str_iden, sortby_str_iden = divideQueryPartAndSortbyPart(combine_str_iden)
	local flag = true

	if query_str_iden ~= '' then
		flag = canInstanceFitQueryRule (self, query_str_iden)
		-- if no sortby part, return directly
		if isFalse(sortby_str_iden) then
			return flag, self.id, -1
		end
	end

	local id_list = {}
	if flag then
		local manager_key = rule_manager_prefix .. self.__name
		local score = db:zscore(manager_key, combine_str_iden)
		local item_key = rule_query_result_pattern:format(self.__name, math.floor(score))
		id_list = db:lrange(item_key, 0, -1)
		local length = #id_list
		local model = self:getClass()
		local func = extractSortByArgs(sortby_str_iden)

		local l, r = 1, #id_list
		local left_obj
		local right_obj
		local bflag, left_flag, right_flag, pflag

		left_obj = model:getById(id_list[l])
		right_obj = model:getById(id_list[r])
		if left_obj == nil or right_obj == nil then
			return nil, id_list[#id_list], #id_list
		end
		bflag = func(left_obj, right_obj)

		p = l
		while (r ~= l) do

			left_flag = func(left_obj, self)
			right_flag = func(self, right_obj)
			if bflag == left_flag and bflag == right_flag then
			-- between
				p = math.floor((l + r)/2)
			elseif bflag == left_flag then
			-- and unequal to right_flag
			-- on the right hand
				p = r
				break
			elseif bflag == right_flag then
			-- and unequal to left_flag
			-- on the left hand
				p = l - 1
				break
			end

			local mobj = model:getById(id_list[p])
			if mobj == nil then
				return nil, id_list[#id_list], #id_list
			end

			pflag = func(mobj, self)
			if pflag == bflag then
				l = p + 1
			else
				r = p - 1
			end

			left_obj = model:getById(id_list[l])
			right_obj = model:getById(id_list[r])
			if left_obj == nil or right_obj == nil then
				return nil, id_list[#id_list], #id_list
			end
		end
	end

	return flag, id_list[p], p
end

-------------------------------------------------------------------------
--  
--
local updateInstanceToIndexOnRule = function (self, qstr)
	local rule_manager_prefix, rule_result_pattern = specifiedRulePrefix()

	local manager_key = rule_manager_prefix .. self.__name
	local score = db:zscore(manager_key, qstr)
	local item_key = rule_result_pattern:format(self.__name, score)

	local flag, cmpid, p = canInstanceFitQueryRuleAndFindProperPosition(self, qstr)
	local success
	local options = { watch = item_key, retry = 2 }
	db:transaction(function(db)
		if flag then
			-- consider the left end case
			if cmpid == nil and p < 1 then
				db:lrem(item_key, 1, self.id)
				db:lpush(item_key, self.id)
			else			
				if cmpid ~= self.id then
					-- delete old self first, insert self to proper position
					db:lrem(item_key, 1, self.id)
					success = db:linsert(item_key, 'AFTER', cmpid, self.id)
				else
					-- cmpid == self.id, means use query rule only, keep the old position
					success = db:linsert(item_key, 'AFTER', cmpid, self.id)
					db:lrem(item_key, 1, self.id)
				end

				db:multi()
				-- no this id in index before
				if success == -1 then
					db:rpush(item_key, self.id)
				end
				db:exec()
			end
--[[		else
			if db:exists(item_key) then
				-- delete the old one id
				db:lrem(item_key, 1, self.id)
			end
--]]
		end

		-- db:expire(item_key, bamboo.config.rule_expiration or bamboo.RULE_LIFE)
	end, options)
	return self
end

local delInstanceToIndexOnRule = function (self, qstr)
	local rule_manager_prefix, rule_result_pattern = specifiedRulePrefix()

	local manager_key = rule_manager_prefix .. self.__name
	local score = db:zscore(manager_key, qstr)
	local item_key = rule_result_pattern:format(self.__name, score)

	local options = { watch = item_key, retry = 2 }
	db:transaction(function(db)
		if db:exists(item_key) then
			db:lrem(item_key, 0, self.id)
		end
		-- db:expire(item_key, bamboo.config.rule_expiration or bamboo.RULE_LIFE)
	end, options)

	return self
end

local INDEX_ACTIONS = {
	['update'] = updateInstanceToIndexOnRule,
	['del'] = delInstanceToIndexOnRule
}

updateIndexByRules = function (self, action)
	local rule_manager_prefix, rule_result_pattern = specifiedRulePrefix()

	local manager_key = rule_manager_prefix .. self.__name
	local qstr_list = db:zrange(manager_key, 0, -1)
	local action_func = INDEX_ACTIONS[action]
	for _, qstr in ipairs(qstr_list) do
		action_func(self, qstr)
	end
end

-- can be reentry
local addIndexToManager = function (self, str_iden, obj_list)
	local rule_manager_prefix, rule_result_pattern = specifiedRulePrefix()
	local manager_key = rule_manager_prefix .. self.__name
	-- add to index manager
	local score = db:zscore(manager_key, str_iden)
	-- if score then return end
	local new_score
	if not score then
		-- when it is a new rule
		new_score = db:zcard(manager_key) + 1
		db:zadd(manager_key, new_score, str_iden)
	else
		-- when rule result is expired, re enter this function
		new_score = score
	end
	if #obj_list == 0 then return end

	local item_key = rule_result_pattern:format(self.__name, new_score)
	local options = { watch = item_key, retry = 2 }
	db:transaction(function(db)
		if not db:exists(item_key) then
			-- generate the index item, use list
			db:rpush(item_key, unpack(obj_list))
		end
		-- set expiration to each index item
		-- db:expire(item_key, bamboo.config.rule_expiration or bamboo.RULE_LIFE)
	end, options)
end

local getIndexFromManager = function (self, str_iden, getnum)
	local rule_manager_prefix, rule_result_pattern = specifiedRulePrefix()

	local manager_key = rule_manager_prefix .. self.__name
	-- get this rule's score
	local score = db:zscore(manager_key, str_iden)
	-- if has no score, means it is not rule indexed,
	-- return nil directly
	if not score then
		return nil
	end

	local item_key = rule_result_pattern:format(self.__name, score)
	if not db:exists(item_key) then
		return List()
	end

	-- update expiration
	-- db:expire(item_key, bamboo.config.rule_expiration or bamboo.RULE_LIFE)
	-- rule result is not empty, and not expired, retrieve them
	if getnum then
		-- return the number of this list
		return db:llen(item_key)
	else
		-- return a list
		return List(db:lrange(item_key, 0, -1))
	end
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
	__primarykey = "id";

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

		local flag, name = checkExistanceById(self, id)
		if isFalse(flag) or isFalse(name) then return nil end

		return name
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
		local _, ids = db:zrange(index_key, rank_index, rank_index, 'withscores')
		return self:getById(ids[1])
	end;

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
	filter = function (self, query_args, ...)
		I_AM_CLASS_OR_QUERY_SET(self)
		assert(type(query_args) == 'table' or type(query_args) == 'function', 
			'[Error] the query_args passed to filter must be table or function.')
		local no_sort_rule = true
		-- regular the args
		local sort_field, sort_dir, sort_func, start, stop, is_rev, no_cache
		local first_arg = select(1, ...)
		if type(first_arg) == 'function' then
			sort_func = first_arg
			start = select(2, ...)
			stop = select(3, ...)
			is_rev = select(4, ...)
			no_cache = select(5, ...)
			no_sort_rule = false
		elseif type(first_arg) == 'string' then
			sort_field = first_arg
			sort_dir = select(2, ...)
			start = select(3, ...)
			stop = select(4, ...)
			is_rev = select(5, ...)
			no_cache = select(6, ...)
			no_sort_rule = false
		elseif type(first_arg) == 'number' then
			start = first_arg
			stop = select(2, ...)
			is_rev = select(3, ...)
			no_cache = select(4, ...)
			no_sort_rule = true
		end
        
		if start then assert(type(start) == 'number', '[Error] @filter - start must be number.') end
		if stop then assert(type(stop) == 'number', '[Error] @filter - stop must be number.') end
		if is_rev then assert(type(is_rev) == 'string', '[Error] @filter - is_rev must be string.') end

		local is_args_table = (type(query_args) == 'table')
		local logic = 'and'

		------------------------------------------------------------------------------
		-- do rule index lookup
		local query_str_iden, is_capable_press_rule = '', true
		local do_rule_index_cache = isUsingRuleIndex() and (no_cache ~= 'nocache')
		if do_rule_index_cache then
			if type(query_args) == 'function' then
				is_capable_press_rule = collectRuleFunctionUpvalues(query_args)
			end

			if is_capable_press_rule then
				-- make query identification string
				query_str_iden = compressQueryArgs(query_args)
				if not no_sort_rule then
					local sortby_str_iden = compressSortByArgs({sort_field or sort_func, sort_dir})
					query_str_iden = compressTwoPartArgs(query_str_iden, sortby_str_iden)
				end
				if #query_str_iden > 0 then
					-- check index
					-- XXX: Only support class now, don't support query set, maybe query set doesn't need this feature
					local id_list = getIndexFromManager(self, query_str_iden)
					if type(id_list) == 'table' then
						if #id_list == 0 then
							return QuerySet(), 0
						else
							if start or stop then
								-- now id_list is a list containing all id of instances fit to this query_args rule, so need to slice
								id_list = id_list:slice(start, stop, is_rev)
							end

							-- if have this list, return objects directly
							if #id_list > 0 then
								return getFromRedisPipeline(self, id_list), #id_list
							end
						end
					end
				end
				-- else go ahead
			end
		end

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
		local partially_got = false
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

		local hash_index_query_args = {};
		local hash_index_flag = false;
		local raw_filter_flag = false;

		if type(query_args) == 'function' then
			hash_index_flag = false;
			raw_filter_flag = true;
		elseif bamboo.config.index_hash then
			for field, value in pairs(query_args) do
				-- very odd, flags are assinged many times
				if fields[field].hash_index then
					hash_index_query_args[field] = value;
					query_args[field] = nil;
					hash_index_flag = true;
				else
					raw_filter_flag = true;
				end
			end
                end


		if hash_index_flag then
			all_ids = mih.filter(self,hash_index_query_args,logic);
		else
    			all_ids = self:allIds()
		end

		-- if not nessesary to use raw filter, retrieve objects immediately
		if not raw_filter_flag then
			query_set = getFromRedisPipeline(self, all_ids)
		else
			if #query_set == 0 then
				local qfs = {}
				if is_args_table then
					for k, _ in pairs(query_args) do
						tinsert(qfs, k)
					end
					table.sort(qfs)
				end

				local objs, nils
				if #qfs == 0 then
					-- collect nothing, use 'hgetall' to retrieve, partially_got is false
					-- when query_args is function, do this
					objs, nils = getFromRedisPipeline(self, all_ids)
				else
					-- use hmget to retrieve, now the objs are partial objects
					-- qfs here must have key-value pair
					-- here, objs are not real objects, only ordinary table
					objs = getPartialFromRedisPipeline(self, all_ids, qfs)
					partially_got = true
				end
				walkcheck(objs, self)

				if bamboo.config.auto_clear_index_when_get_failed then
					-- clear model main index
					if not isFalse(nils) then
						local index_key = getIndexKey(self)
						-- each element in nils is the id pattern string, when clear, remove them directly
						for _, v in ipairs(nils) do
							db:zremrangebyscore(index_key, v, v)
						end
					end
				end
			end
		end

		------------------------------------------------------------------------------
		-- do later process
		local total_length = #query_set
		-- here, _t_query_set is the all instance fit to query_args now
		local _t_query_set = query_set
		-- check if it is empty
		if #query_set == 0 and do_rule_index_cache and is_capable_press_rule and #query_str_iden > 0 then
			addIndexToManager(self, query_str_iden, {})
			return QuerySet(), 0
		end
		-- do sort
		if not no_sort_rule then
			query_set = query_set:sortBy(sort_field or sort_func, sort_dir)
			_t_query_set = query_set
		end
		-- slice
		if start or stop then
			-- now id_list is a list containing all id of instances fit to this query_args rule, so need to slice
			query_set = _t_query_set:slice(start, stop, is_rev)
		end

		-- add to index, here, we index all instances fit to query_args, rather than results applied extra limitation conditions
		if do_rule_index_cache and is_capable_press_rule and #query_str_iden > 0 then
			local id_list = {}
			for _, v in ipairs(_t_query_set) do
				tinsert(id_list, v.id)
			end
			addIndexToManager(self, query_str_iden, id_list)
		end

		if partially_got then
			local id_list = {}
			-- retrieve needed objects' id
			for _, v in ipairs(query_set) do
				tinsert(id_list, v.id)
			end
			query_set = getFromRedisPipeline(self, id_list)
		end

		-- return results
		return query_set, total_length
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
		if isUsingRuleIndex(self) then
			updateIndexByRules(self, 'update')
		end

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
		if isUsingRuleIndex(self) then
			updateIndexByRules(self, 'update')
		end


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

		if isUsingRuleIndex() then
			updateIndexByRules(self, 'update')
		end

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
	rearrangeForeign = function (self, field, inlist)
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
	delForeign = function (self, field, obj)
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

		if isUsingRuleIndex() then
			updateIndexByRules(self, 'update')
		end

		-- update the lastmodified_time
		self.lastmodified_time = socket.gettime()
		db:hset(model_key, 'lastmodified_time', self.lastmodified_time)
		return self
	end;

	clearForeign = function (self, field)
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

		if isUsingRuleIndex() then
			updateIndexByRules(self, 'update')
		end

		-- update the lastmodified_time
		self.lastmodified_time = socket.gettime()
		db:hset(model_key, 'lastmodified_time', self.lastmodified_time)
		return self
	end;

	deepClearForeign = function (self, field)
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

		if isUsingRuleIndex() then
			updateIndexByRules(self, 'update')
		end

		-- update the lastmodified_time
		self.lastmodified_time = socket.gettime()
		db:hset(model_key, 'lastmodified_time', self.lastmodified_time)
		return self
	end;

	-- check whether some obj is already in foreign list
	-- instance:inForeign('some_field', obj)
	hasForeign = function (self, field, obj)
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
	--- deprecated
	classname = function (self)
		return getClassName(self)
	end;
	
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
Model.__indexfd = Model.__primarykey
Model.__tag = Model.__name
Model.getRankByIndex = Model.getRankByPrimaryKey
Model.getIdByIndex = Model.getIdByPrimaryKey
Model.getIndexById = Model.getPrimaryKeyById
Model.getByIndex = Model.getByPrimaryKey


return Model

