module(..., package.seeall)

local tinsert = table.insert

local db = BAMBOO_DB

local List = require 'lglib.list'
local rdstring = require 'bamboo.redis.string'
local rdlist = require 'bamboo.redis.list'
local rdset = require 'bamboo.redis.set'
local rdzset = require 'bamboo.redis.zset'
local rdfifo = require 'bamboo.redis.fifo'
local rdzfifo = require 'bamboo.redis.zfifo'
local rdhash = require 'bamboo.redis.hash'

local getModelByName  = bamboo.getModelByName 
local dcollector= 'DELETED:COLLECTOR'

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
rdactions['list'].add = rdlist.add
rdactions['list'].has = rdlist.has
rdactions['list'].num = rdlist.num

rdactions['set'].save = rdset.save
rdactions['set'].update = rdset.update
rdactions['set'].retrieve = rdset.retrieve
rdactions['set'].remove = rdset.remove
rdactions['set'].add = rdset.add
rdactions['set'].has = rdset.has
rdactions['set'].num = rdset.num

rdactions['zset'].save = rdzset.save
rdactions['zset'].update = rdzset.update
rdactions['zset'].retrieve = rdzset.retrieve
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



rdactions['MANY'] = rdactions['zset']

local getStoreModule = function (store_type)
	local store_module = rdactions[store_type]
	assert( store_module, "[Error] store type must be one of 'string', 'list', 'set', 'zset' or 'hash'.")
	return store_module
end


-----------------------------------------------------------------

local function getCounterName(self)
	return self.__name + ':__counter'
end 

local function getNameIdPattern(self)
	return self.__name + ':' + self.id
end

local function getNameIdPattern2(self, id)
	return self.__name + ':' + tostring(id)
end

local function getFieldPattern(self, field)
	return getNameIdPattern(self) + ':' + field
end 

local function getFieldPattern2(self, id, field)
	return getNameIdPattern2(self, id) + ':' + field
end 

-- return the key of some string like 'User'
--
local function getClassName(self)
	if type(self) ~= 'table' then return nil end
	return self.__tag:match('%.(%w+)$')
end

-- return the key of some string like 'User:__index'
--
local function getIndexKey(self)
	return getClassName(self) + ':__index'
end

local function getClassIdPattern(self)
	return getClassName(self) + self.id
end

local function getCustomKey(self, key)
	return getClassName(self) + ':custom:' + key
end

local function getCustomIdKey(self, key)
	return getClassName(self) + ':' + self.id + ':custom:'  + key
end

local function getCacheKey(self, key)
	return getClassName(self) + ':cache:' + key
end

local function getCachetypeKey(self, key)
	return 'CACHETYPE:' + getCacheKey(self, key)
end

local function getDynamicFieldKey(self, key)
	return getClassName(self) + ':dynamic_field:' + key
end

local function getDynamicFieldIndex(self)
	return getClassName(self) + ':dynamic_field:__index'
end

local function makeModelKeyList(self, ids)
	local key_list = List()
	for _, v in ipairs(ids) do
		key_list:append(getNameIdPattern2(self, v))
	end
	return key_list
end


-- can be called by instance and class
local isUsingFulltextIndex = function (self)
	local model = self
	if isInstance(self) then model = getModelByName(self:classname()) end
	if bamboo.config.fulltext_index_support and rawget(model, '__use_fulltext_index') then
		return true
	else
		return false
	end
end

local isUsingRuleIndex = function (self)
	if bamboo.config.index_support and rawget(self, '__use_rule_index') and rawget(self, '__name') then
		return true
	end
	return false
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


local makeObject = function (self, data)
	-- if data is invalid, return nil
	if not isValidInstance(data) then print("[Warning] Can't get object."); return nil end
	
	-- make id type is number
	data.id = tonumber(data.id) or data.id
	
	local fields = self.__fields
	for k, fld in pairs(fields) do
		-- ensure the correction of field description table
		checkType(fld, 'table')
		-- convert the number type field
		if fld.type == 'number' then
			data[k] = tonumber(data[k])
			
		elseif fld.foreign then
			local st = fld.st
			-- in redis, we don't save MANY foreign key in db, but we want to fill them when
			-- form lua object
			if st == 'MANY' then
				data[k] = 'FOREIGN MANY ' .. fld.foreign
			elseif st == 'FIFO' then
				data[k] = 'FOREIGN FIFO ' .. fld.foreign
			elseif st == 'ZFIFO' then
				data[k] = 'FOREIGN ZFIFO ' .. fld.foreign
			end
		end
	end

	-- generate an object
	-- XXX: maybe can put 'data' as parameter of self()
	local obj = self()
	table.update(obj, data)
	return obj

end


------------------------------------------------------------
-- this function can only be called by Model
-- @param model_key:
--
local getFromRedis = function (self, model_key)
	-- here, the data table contain ordinary field, ONE foreign key, but not MANY foreign key
	-- all fields are strings 
	local data = db:hgetall(model_key)
	return makeObject(self, data)

end 

-- 
local QuerySet

local getFromRedisPipeline = function (self, ids)
	local key_list = makeModelKeyList(self, ids)
	
	-- all fields are strings
	local data_list = db:pipeline(function (p) 
		for _, v in ipairs(key_list) do
			p:hgetall(v)
		end
	end)

	local objs = QuerySet()
	local obj
	for _, v in ipairs(data_list) do
		obj = makeObject(self, v)
		if obj then objs:append(obj) end
	end

	return objs
end 

-- 
local getPartialFromRedisPipeline = function (self, ids, fields)
	local key_list = makeModelKeyList(self, ids)
	
	-- all fields are strings
	local data_list = db:pipeline(function (p) 
		for _, v in ipairs(key_list) do
			p:hmget(v, unpack(fields))
		end
	end)

	local objs = {}
	local obj
	for _, v in ipairs(data_list) do
		obj = makeObject(self, v)
		if obj then tinsert(objs, obj) end
	end

	return objs
end 

-- for use in "User:id" as each item key
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
	local obj
	for i, model in ipairs(model_list) do
		obj = makeObject(model, data_list[i])
		if obj then objs:append(obj) end
	end

	return objs
end 

--------------------------------------------------------------
-- this function can only be called by instance
--
local delFromRedis = function (self, id)
	local model_key = id and getNameIdPattern2(self, id) or getNameIdPattern(self)
	local index_key = getIndexKey(self)
	
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
	db:zremrangebyscore(index_key, self.id, self.id)
	
	-- clear fulltext index
	if isUsingFulltextIndex(self) then
		clearIndexesOnDeletion(self)
	end
	if isUsingRuleIndex(self) then
		updateIndexByRules(self, 'del')
	end
				
	-- release the lua object
	self = nil
end

--------------------------------------------------------------
-- Fake Deletion
--  called by instance
local fakedelFromRedis = function (self, id)
	local model_key = id and getNameIdPattern2(self, id) or getNameIdPattern(self)
	local index_key = getIndexKey(self)
	
	local fields = self.__fields
	-- in redis, delete the associated foreign key-value store
	for k, v in pairs(self) do
		local fld = fields[k]
		if fld and fld.foreign then
			local key = model_key + ':' + k
			db:rename(key, 'DELETED:' + key)
		end
	end 

	-- rename the key self
	db:rename(model_key, 'DELETED:' + model_key)
	-- delete the index in the global model index zset
	-- when deleted, the instance's index cache was cleaned.
	db:zremrangebyscore(index_key, self.id, self.id)
	-- add to deleted collector
	rdzset.add(dcollector,  model_key)
	
	-- clear fulltext index
	if isUsingFulltextIndex(self) then
		clearIndexesOnDeletion(self)
	end
	if isUsingRuleIndex(self) then
		updateIndexByRules(self, 'del')
	end

	-- release the lua object
	self = nil
end

--------------------------------------------------------------
-- Restore Fake Deletion
-- called by Some Model: self, not instance
local restoreFakeDeletedInstance = function (self, id)
	checkType(tonumber(id),  'number')
	local model_key = getNameIdPattern2(self)
	local index_key = getIndexKey(self)
	
	local instance = getFromRedis(self, model_key)
	if not instance then return nil end
	-- rename the key self
	db:rename('DELETED:' + model_key, model_key)
	local fields = self.__fields
	-- in redis, delete the associated foreign key-value store
	for k, v in pairs(instance) do
		local fld = fields[k]
		if fld and fld.foreign then
			local key = model_key + ':' + k
			db:rename('DELETED:' + key, key)
		end
	end

	-- when restore, the instance's index cache was restored.
	db:zadd(index_key, instance.id, instance.id)
	-- remove from deleted collector
	db:zrem(dcollector, model_key)
	
	return instance
end


local retrieveObjectsByForeignType = function (foreign, list)
	local obj_list
	
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


--------------------------------------------------------------------------------
if bamboo.config.fulltext_index_support then require 'mmseg' end
-- Full Text Search utilities
-- @param instance the object to be full text indexes
local makeFulltextIndexes = function (instance)
	
	local ftindex_fields = rawget(instance, '__fulltext_index_fields')
	if isFalse(ftindex_fields) then return false end

	local words
	for _, v in ipairs(ftindex_fields) do
		-- parse the fulltext field value
		words = mmseg.segment(instance[v])
		for _, word in ipairs(words) do
			-- only index word length larger than 1
			if string.utf8len(word) >= 2 then
				-- add this word to global word set
				db:sadd('_fulltext_words', word)
				-- add reverse fulltext index such as '_RFT:model:id', type is set, item is 'word'
				db:sadd('_RFT:' + getNameIdPattern(instance), word)
				-- add fulltext index such as '_FT:word', type is set, item is 'model:id'
				db:sadd('_FT:' + word, getNameIdPattern(instance))
			end
		end
	end
	
	return true	
end

local searchOnFulltextIndexes = function (ask_str, length)
	local search_tags = mmseg.segment(ask_str)
	local length = length or 10
	local contained_tags = List()
	for _, tag in ipairs(search_tags) do
		if string.utf8len(tag) >= 2 and db:sismember('_fulltext_words', tag) then
			contained_tags:append(tag)
		end
	end
	if #contained_tags == 0 then return List() end
	
	local rlist = List()
	local _tmp_key = "__tmp_ftkey"
	if #contained_tags == 1 then
		db:sinterstore(_tmp_key, '_FT:' + contained_tags[1])
	else
		local _args = {}
		for _, tag in ipairs(contained_tags) do
			table.insert(_args, '_FT:' + tag)
		end
		-- XXX, some afraid
		db:sinterstore(_tmp_key, unpack(_args))
	end
	
	-- sort and retrieve
	local model_keys =  db:sort(_tmp_key, {limit={0, length}, sort="desc"})
	-- return objects
	return getFromRedisPipeline2(model_keys)
end

local clearIndexesOnDeletion = function (instance)
	local model_key = getNameIdPattern(instance)
	local words = db:smembers('_RFT:' + model_key)
	db:pipeline(function (p)
		for _, word in ipairs(words) do
			p:srem('_FT:' + word, model_key)
		end
	end)
	-- clear the reverse fulltext key
	db:del('_RFT:' + model_key)
end


--------------------------------------------------------------------------------
-- The bellow four assertations, they are called only by class, instance or query set
--
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


_G['isQuerySet'] = function (self)
	if isList(self)
	and rawget(self, '__spectype') == nil and self.__spectype == 'QuerySet' 
	and self.__tag == 'Bamboo.Model'
	then return true
	else return false
	end
end

-------------------------------------------------------------
--
_G['I_AM_QUERY_SET'] = function (self)
	assert(isQuerySet(self), "[Error] This caller is not a QuerySet.")
end

_G['I_AM_CLASS'] = function (self)
	assert(self.isClass, '[Error] The caller is not a valid class.')
	assert(self:isClass(), '[Error] This function is only allowed to be called by class.') 
end

_G['I_AM_CLASS_OR_QUERY_SET'] = function (self)
	assert(self.isClass, '[Error] The caller is not a valid class.')
	assert(self:isClass() or isQuerySet(self), '[Error] This function is only allowed to be called by class or query set.')
end

_G['I_AM_INSTANCE'] = function (self)
	assert(self.isInstance, '[Error] The caller is not a valid instance.')
	assert(self:isInstance(), '[Error] This function is only allowed to be called by instance.')
end

_G['I_AM_INSTANCE_OR_QUERY_SET'] = function (self)
	assert(self.isInstance, '[Error] The caller is not a valid instance.')
	assert(self:isInstance() or isQuerySet(self), '[Error] This function is only allowed to be called by instance or query set.')
end

_G['I_AM_CLASS_OR_INSTANCE'] = function (self)
	assert(self.isClass or self.isInstance, '[Error] The caller is not a valid class or instance.')
	assert(self:isClass() or self:isInstance(), '[Error] This function is only allowed to be called by class or instance.')
end


------------------------------------------------------------------------
-- Query Function Set
-- for convienent, import them into _G directly
------------------------------------------------------------------------
local closure_collector = {}

_G['eq'] = function ( cmp_obj )
	local t = function (v)
		if v == cmp_obj then
			return true
		else
			return false
		end
	end
	closure_collector[t] = {'eq', cmp_obj}
	return t
end

_G['uneq'] = function ( cmp_obj )
	local t = function (v)
		if v ~= cmp_obj then
			return true
		else
			return false
		end
	end
	closure_collector[t] = {'uneq', cmp_obj}
	return t
end

_G['lt'] = function (limitation)
	local t = function (v)
		local nv = tonumber(v)
		if nv and nv < tonumber(limitation) then
			return true
		else
			return false
		end
	end
	closure_collector[t] = {'lt', limitation}
	return t
end

_G['gt'] = function (limitation)
	local t = function (v)
		local nv = tonumber(v)
		if nv and nv > tonumber(limitation) then
			return true
		else
			return false
		end
	end
	closure_collector[t] = {'gt', limitation}
	return t
end


_G['le'] = function (limitation)
	local t = function (v)
		local nv = tonumber(v)	
		if nv and nv <= tonumber(limitation) then
			return true
		else
			return false
		end
	end
	closure_collector[t] = {'le', limitation}
	return t
end

_G['ge'] = function (limitation)
	local t = function (v)
		local nv = tonumber(v)	
		if nv and nv >= tonumber(limitation) then
			return true
		else
			return false
		end
	end
	closure_collector[t] = {'ge', limitation}
	return t
end

_G['bt'] = function (small, big)
	local t = function (v)
		local nv = tonumber(v)
		if nv and nv > small and nv < big then
			return true
		else
			return false
		end
	end
	closure_collector[t] = {'bt', small, big}
	return t
end

_G['be'] = function (small, big)
	local t = function (v)
		local nv = tonumber(v)
		if nv and nv >= small and nv <= big then
			return true
		else
			return false
		end
	end
	closure_collector[t] = {'be', small, big}
	return t
end

_G['outside'] = function (small, big)
	local t = function (v)
		local nv = tonumber(v)
		if nv and nv < small and nv > big then
			return true
		else
			return false
		end
	end
	closure_collector[t] = {'outside', small, big}
	return t
end

_G['contains'] = function (substr)
	local t = function (v)
		v = tostring(v)
		if v:contains(substr) then 
			return true
		else
			return false
		end
	end
	closure_collector[t] = {'contains', substr}
	return t
end

_G['uncontains'] = function (substr)
	local t = function (v)
		v = tostring(v)
		if not v:contains(substr) then 
			return true
		else
			return false
		end
	end
	closure_collector[t] = {'uncontains', substr}
	return t
end


_G['startsWith'] = function (substr)
	local t = function (v)
		v = tostring(v)
		if v:startsWith(substr) then 
			return true
		else
			return false
		end
	end
	closure_collector[t] = {'startsWith', substr}
	return t
end

_G['unstartsWith'] = function (substr)
	local t = function (v)
		v = tostring(v)
		if not v:startsWith(substr) then 
			return true
		else
			return false
		end
	end
	closure_collector[t] = {'unstartsWith', substr}
	return t
end


_G['endsWith'] = function (substr)
	local t = function (v)
		v = tostring(v)
		if v:endsWith(substr) then 
			return true
		else
			return false
		end
	end
	closure_collector[t] = {'endsWith', substr}
	return t
end

_G['unendsWith'] = function (substr)
	local t = function (v)
		v = tostring(v)
		if not v:endsWith(substr) then 
			return true
		else
			return false
		end
	end
	closure_collector[t] = {'unendsWith', substr}
	return t
end

_G['inset'] = function (...)
	local args = {...}
	local t = function (v)
		v = tostring(v)
		for _, val in ipairs(args) do
			-- once meet one, ok
			if tostring(val) == v then
				return true
			end
		end
		
		return false
	end
	closure_collector[t] = {'inset', ...}
	return t
end

_G['uninset'] = function (...)
	local args = {...}
	local t = function (v)
		v = tostring(v)
		for _, val in ipairs(args) do
			-- once meet one, false
			if tostring(val) == v then
				return false
			end
		end
		
		return true
	end
	closure_collector[t] = {'uninset', ...}
	return t
end

-------------------------------------------------------------------
--


local compressQueryArgs = function (query_args)
	local out = {}
	local qtype = type(query_args)
	if qtype == 'table' then
	
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
			if type(v) == 'string' then
				tinsert(out, v)			
			else
				local queryt_iden = closure_collector[v]
				for _, item in ipairs(queryt_iden) do
					tinsert(out, item)		
				end
			end
			tinsert(out, '|')		
		end
	elseif qtype == 'function' then
		tinsert(out, 'function')
		tinsert(out, '|')	
		tinsert(out, string.dump(query_args))
		tinsert(out, '|')			
	end

	-- restore the first element, avoiding side effect
	query_args[1] = out[1]	

	-- clear the closure_collector
	closure_collector = {}
	-- use a delemeter to seperate obviously
	return table.concat(out, '   ')
end

local extraQueryArgs = function (qstr)
	local query_args
	
	if qstr:startsWith('function') then
		local startpoint = qstr:find('|') or 1
		local endpoint = -1
		
		qstr = qstr:sub(startpoint + 1, endpoint - 1):trim()
		-- now qstr is the function binary string
		query_args = loadstring(qstr)
		-- set function environment, to solve the problem of upvalues can't find
		setfenv(assert(query_args, '[Error] @extraQueryArgs - function code error when extract.'), setmetatable(bamboo.userdata, {__index=_G}))

	else
	
		local endpoint = -1
		qstr = qstr:sub(1, endpoint - 1)
		local _qqstr = qstr:splittrim('|')
		-- logic == 'and' or 'or'
		local logic = _qqstr[1]
		query_args = {logic}
		for i=2, #_qqstr do
			local str = _qqstr[i]
			local kt = str:splittrim('    ')
			-- kt[1] is 'key', [2] is 'closure', [3] .. are closure's parameters
			local key = kt[1]
			local closure = kt[2]
			if #kt > 2 then
				local _args = {}
				for j=3, #kt do
					tinsert(_args, kt[j])
				end
				-- compute closure now
				query_args[key] = _G[closure](unpack(_args))
			else
				-- no args, means this 'closure' is a string
				query_args[key] = closure
			end
		end
	end
	
	return query_args	
end

local canInstanceFitQueryRule = function (self, qstr)
	local query_args = extraQueryArgs(qstr)
	if type(query_args) == 'function' then
		return query_args(self)
	else
		local logic_choice = (query_args[1] == 'and')
		query_args[1] = nil
		local flag = logic_choice
			
		local fields = self.__fields
		assert(not isFalse(fields), "[Error] instance's description table must not be blank.")
			
		for k, v in pairs(query_args) do
			if not fields[k] then return false end

			if type(v) == 'function' then
				flag = v(self[k])
			else
				flag = (self[k] == v)
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
	end

	return flag
end

local addInstanceToIndexOnRule = function (self, qstr)
	local manager_key = "_index_manager:" .. self.__name
	local flag = canInstanceFitQueryRule(self, qstr)
	if flag then
		local score = db:zscore(manager_key, qstr)
		local item_key = ('_RULE:%s:%s'):format(self.__name, score)
		db:rpush(item_key, self.id)	
		db:expire(item_key, bamboo.config.expiration or bamboo.CACHE_LIFE)
	end
end

local updateInstanceToIndexOnRule = function (self, qstr)
	local manager_key = "_index_manager:" .. self.__name
	local flag = canInstanceFitQueryRule(self, qstr)
	local score = db:zscore(manager_key, qstr)
	local item_key = ('_RULE:%s:%s'):format(self.__name, score)
	db:lrem(item_key, 0, self.id)
	if flag then
		db:rpush(item_key, self.id)	
	end
	db:expire(item_key, bamboo.config.expiration or bamboo.CACHE_LIFE)
end

local delInstanceToIndexOnRule = function (self, qstr)
	local manager_key = "_index_manager:" .. self.__name
	local flag = canInstanceFitQueryRule(self, qstr)
	local score = db:zscore(manager_key, qstr)
	local item_key = ('_RULE:%s:%s'):format(self.__name, score)
	db:lrem(item_key, 0, self.id)
	db:expire(item_key, bamboo.config.expiration or bamboo.CACHE_LIFE)
end

local INDEX_ACTIONS = {
	['save'] = addInstanceToIndexOnRule,
	['update'] = updateInstanceToIndexOnRule,
	['del'] = delInstanceToIndexOnRule
}

local updateIndexByRules = function (self, action)
	local manager_key = "_index_manager:" .. self.__name
	local qstr_list = db:zrange(manager_key, 0, -1)
	local action_func = INDEX_ACTIONS[action]
	for _, qstr in ipairs(qstr_list) do
		action_func(self, qstr)
	end
end

local addIndexToManager = function (self, query_str_iden, obj_list)
	local manager_key = "_index_manager:" .. self.__name
	-- add to index manager
	rdzset.add(manager_key, query_str_iden)
	local score = db:zscore(manager_key, query_str_iden)
	local item_key = ('_RULE:%s:%s'):format(self.__name, score)
	-- generate the index item, use list
	db:rpush(item_key, unpack(obj_list))
	-- set expiration to each index item
	db:expire(item_key, bamboo.config.expiration or bamboo.CACHE_LIFE)
	
end

local getIndexFromManager = function (self, query_str_iden)
	local manager_key = "_index_manager:" .. self.__name
	local score = db:zscore(manager_key, query_str_iden)
	if not score then return nil end
	-- add to index manager
	local item_key = ('_RULE:%s:%s'):format(self.__name, score)
	if not db:exists(item_key) then return nil end
	-- update expiration
	db:expire(item_key, bamboo.config.expiration or bamboo.CACHE_LIFE)
	-- return a list
	return db:lrange(item_key, 0, -1)
end


------------------------------------------------------------------------
-- 
------------------------------------------------------------------------
local QuerySetMeta = {__spectype='QuerySet'}
local Model

QuerySet = function (list)
	local list = list or List()
	-- create a query set	
	-- add it to fit the check of isClass function
	if not getmetatable(QuerySetMeta) then
		QuerySetMeta = setProto(QuerySetMeta, Model)
	end
	local query_set = setProto(list, QuerySetMeta)
	
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
		-- id type is number
		self.id = self:getCounter() + 1

		return self 
	end;
    

	toHtml = function (self, params)
		 I_AM_INSTANCE(self)
		 params = params or {}
		 
		 if params.field and type(params.field) == 'string' then
			 for k, v in pairs(params.attached) do
				 if v == 'html_class' then
					 self.__fields[params.field][k] = self.__fields[params.field][k] .. ' ' .. v
				 else
					 self.__fields[params.field][k] = v
				 end
			 end
			 
			 return (self.__fields[params.field]):toHtml(self, params.field, params.format)
		 end
		 
		 params.attached = params.attached or {}
		 
		 local output = ''
		 for field, fdt_old in pairs(self.__fields) do
			 local fdt = table.copy(fdt_old)
			 setmetatable(fdt, getmetatable(fdt_old))
			 for k, v in pairs(params.attached) do
				 if type(v) == 'table' then
					 for key, val in pairs(v) do
						 fdt[k] = fdt[k] or {}
						 fdt[k][key] = val
					 end
				 else
					 fdt[k] = v
				 end
			 end

			 local flag = true
			 params.filters = params.filters or {}
			 for k, v in pairs(params.filters) do
				 -- to redundant query condition, once meet, jump immediately
				 if not fdt[k] then
					 -- if k == 'vl' then self.__fields[field][k] = 0 end
					 if k == 'vl' then fdt[k] = 0 end
				 end

				 if type(v) == 'function' then
					 flag = v(fdt[k] or '')
					 if not flag then break end
				 else
					 if fdt[k] ~= v then flag=false; break end
				 end
			 end

			 if flag then
				 output = output .. fdt:toHtml(self, field, params.format or nil)
			 end

		 end

		 return output
	 end,


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
		local key = getNameIdPattern2(self, id)
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
		local obj = self:filter(query_args, is_rev)[1]
		return obj
	end;

	--- fitler some instances belong to this model
	-- @param query_args: query arguments in a table
	-- @param is_rev: 'rev' or other value, means start to search from begining or from end
	-- @param starti: specify which index to start search, note: this is the position after filtering 
	-- @param length: specify how many elements to find
	-- @param dir: specify the direction of the search action, 1 means positive, -1 means negative
	-- @return: query_set, an object list (query set)
	-- @note: this function can be called by class object and query set
	filter = function (self, query_args, is_rev, starti, length, dir)
		I_AM_CLASS_OR_QUERY_SET(self)
		assert(type(query_args) == 'table' or type(query_args) == 'function', '[Error] the query_args passed to filter must be table or function.')
		if starti then assert(type(starti) == 'number', '[Error] @filter - starti must be number.')
		if length then assert(type(length) == 'number', '[Error] @filter - length must be number.')
		if dir then assert(type(dir) == 'number', '[Error] @filter - dir must be number.')				
		
		local is_query_table = (type(query_args) == 'table')
		local is_query_set = false
		if isQuerySet(self) then is_query_set = true end
		local logic = 'and'
		
		-- normalize the direction value
		local dir = dir or 1
		assert( dir == 1 or dir == -1, '[Error] dir must be 1 or -1.')
		local query_str_iden
		local is_using_rule_index = isUsingRuleIndex(self)
		if is_using_rule_index then
			if type(query_args) == 'function' then
				for i=1, math.huge do
			    	local name, v = debug.getupvalue(query_args, i)
			    	if not name then break end
					-- record upvalue to bamboo.userdata, for later use when extract
			        bamboo.userdata[name] = v
			        -- print(name, v)
				end
			                                   
			end
			-- make query identification string
			query_str_iden = compressQueryArgs(query_args)
		end
		
		if is_query_table then
			-- check index
			-- XXX: Only support class now, don't support query set, maybe query set doesn't need this feature
			local id_list
			if is_using_rule_index then
				id_list = getIndexFromManager(self, query_args)
				-- now id_list is a list containing all id of instances fit to this query_args rule, so need to slice
				if starti then
					if dir == 1 then
						id_list = id_list:slice(starti, length and (starti + length - 1) or -1) 
					else
						id_list = id_list:slice(length and (starti - length + 1) or 1, starti) 
					end
				end

				-- if have this list, return objects directly
				if id_list then
					return getFromRedisPipeline(self, id_list)
				end
				-- else go ahead
			end		

			if query_args and query_args['id'] then
				-- remove 'id' query argument
				print("[Warning] Filter doesn't support search by id.")
				query_args['id'] = nil 
			end

			-- if query table is empty, return slice instances
			if isFalse(query_args) then 
				local stop = starti + length - 1
				local nums = self:numbers()
				return self:slice(starti, stop, is_rev)
			end

			-- normalize the 'and' and 'or' logic
			if query_args[1] then
				if query_args[1] == 'or' then
					logic = 'or'
				end
				query_args[1] = nil
			end
		end
		
		local all_ids
		if is_query_set then
			-- if self is query set, we think of all_ids as object list, rather than id string list
			all_ids = (is_rev == 'rev') and self:reverse() or self
		else
			-- all_ids is id string list
			all_ids = self:allIds(is_rev)
		end
		-- nothing in id list, return empty table
		if #all_ids == 0 then return List() end

		
		-- create a query set
		local query_set = QuerySet()
		local logic_choice = (logic == 'and')
		local partially_got = false

		local walkcheck = function (objs)
			for i = 1, #all_ids do
				local flag = logic_choice
				local obj = objs[i]
				
				if is_query_table then
					for k, v in pairs(query_args) do
						-- to redundant query condition, once meet, jump immediately
						if not obj[k] then flag=false; break end

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
				
				-- if walk to this line, means find one 
				if flag then
					tinsert(query_set, obj)
				end
			end
		end
		
		if is_query_set then
			local objs = all_ids
			-- objs are already integrated instances
			walkcheck(objs)			
		else
			local qfs = {'id'}
			if is_query_table then
				for k, _ in pairs(query_args) do
					tinsert(qfs, k)
				end
			else
				-- use precollected fields
				-- if model has set '__use_rule_index' manually, collect all fields to index
				-- if not set '__use_rule_index' manually, collect fields with 'index=true' in their field description table
				-- if not set '__use_rule_index' manually, and not set 'index=true' in any field, collect NOTHING
				for _, k in ipairs(self.__rule_index_fields) do
					tinsert(qfs, k)
				end
			end
			table.sort(qfs)
			local objs
			-- == 1, means only have 'id', collect nothing on fields 
			if #qfs == 1 then
				-- collect nothing, use 'hgetall' to retrieve, partially_got is false
				objs = getFromRedisPipeline(self, all_ids)
			else
				-- use hmget to retrieve
				objs = getPartialFromRedisPipeline(self, all_ids, qfs)
				partially_got = true
			end
			walkcheck(objs)			
		end
		
		-- here, _t_query_set is the all instance fit to query_args now
		local _t_query_set = query_set
		if starti then
			if dir == 1 then
				query_set = _t_query_set:slice(starti, length and (starti + length - 1) or -1) 
			else
				query_set = _t_query_set:slice(length and (starti - length + 1) or 1, starti) 
			end
		end

		-- if self is query set, its' element is always integrated
		-- if call by class
		if not is_query_set and #_t_query_set > 0 then
			-- retrieve ids
			local id_list = {}
			for _, v in ipairs(_t_query_set) do
				tinsert(id_list, v.id)
			end
			-- add to index, here, we index all instances fit to query_args, rather than results applied extra limitation conditions
			if is_using_rule_index then
				addIndexToManager(self, query_str_iden, id_list)
			end
			
			-- if partially got previously, need to get the integrated objects now
			if partially_got then
				query_set = getFromRedisPipeline(self, id_list)
			end
		end

		
		return query_set
		
	end;
    
	
	-------------------------------------------------------------------
	-- CUSTOM API
	--- seven APIs
	-- 1. setCustom
	-- 2. getCustom
	-- 3. delCustom
	-- 4. existCustom
	-- 5. updateCustom
	-- 6. addCustomMember
	-- 7. removeCustomMember
	-- 8. hasCustomMember
	-- 9. numCustom
	--
	--- five store type
	-- 1. string
	-- 2. list
	-- 3. set
	-- 4. zset
	-- 5. hash
	-------------------------------------------------------------------
	
	-- store customize key-value pair to db
	-- now: it support string, list and so on
	setCustom = function (self, key, val, st, scores)
		I_AM_CLASS_OR_INSTANCE(self)
		checkType(key, 'string')
		local custom_key = self:isClass() and getCustomKey(self, key) or getCustomIdKey(self, key)

		if not st or st == 'string' then
			assert( type(val) == 'string' or type(val) == 'number',
					"[Error] @setCustom - In the string mode of setCustom, val should be string or number.")
			rdstring.save(custom_key, val)
		else
			-- checkType(val, 'table')
			local store_module = getStoreModule(st)
			store_module.save(custom_key, val, scores)
		end
	end;


	-- 
	getCustom = function (self, key, atype)
		I_AM_CLASS_OR_INSTANCE(self)
		checkType(key, 'string')
		local custom_key = self:isClass() and getCustomKey(self, key) or getCustomIdKey(self, key)
		if not db:exists(custom_key) then
			print(("[Warning] @getCustom - Key %s doesn't exist!"):format(custom_key))
			if not atype or atype == 'string' then return nil
			else
				return {}
			end
		end
		
		-- get the store type in redis
		local store_type = db:type(custom_key)
		if atype then assert(store_type == atype, '[Error] @getCustom - The specified type is not equal the type stored in db.') end
		local store_module = getStoreModule(store_type)
		return store_module.retrieve(custom_key), store_type
	end;

	delCustom = function (self, key)
		I_AM_CLASS_OR_INSTANCE(self)
		checkType(key, 'string')
		local custom_key = self:isClass() and getCustomKey(self, key) or getCustomIdKey(self, key)
		
		return db:del(custom_key)		
	end;
	
	-- check whether exist custom key
	existCustom = function (self, key)
		I_AM_CLASS_OR_INSTANCE(self)
		checkType(key, 'string')
		local custom_key = self:isClass() and getCustomKey(self, key) or getCustomIdKey(self, key)
		
		if not db:exists(custom_key) then
			return false
		else 
			return true
		end
	end;
	
	updateCustom = function (self, key, val)
		I_AM_CLASS_OR_INSTANCE(self)
		checkType(key, 'string')
		local custom_key = self:isClass() and getCustomKey(self, key) or getCustomIdKey(self, key)

		assert(db:exists(custom_key), '[Error] @updateCustom - This custom key does not exist.')
		local store_type = db:type(custom_key)
		local store_module = getStoreModule(store_type)
		return store_module.update(custom_key, val)
				 
	end;

	removeCustomMember = function (self, key, val)
		I_AM_CLASS_OR_INSTANCE(self)
		checkType(key, 'string')
		local custom_key = self:isClass() and getCustomKey(self, key) or getCustomIdKey(self, key)

		assert(db:exists(custom_key), '[Error] @removeCustomMember - This custom key does not exist.')
		local store_type = db:type(custom_key)
		local store_module = getStoreModule(store_type)
		return store_module.remove(custom_key, val)
		
	end;
	
	addCustomMember = function (self, key, val, score)
		I_AM_CLASS_OR_INSTANCE(self)
		checkType(key, 'string')
		local custom_key = self:isClass() and getCustomKey(self, key) or getCustomIdKey(self, key)

		assert(db:exists(custom_key), '[Error] @addCustomMember - This custom key does not exist.')
		local store_type = db:type(custom_key)
		local store_module = getStoreModule(store_type)
		return store_module.append(custom_key, val)
		
	end;
	
	hasCustomMember = function (self, key, mem)
		I_AM_CLASS_OR_INSTANCE(self)
		checkType(key, 'string')
		local custom_key = self:isClass() and getCustomKey(self, key) or getCustomIdKey(self, key)
		
		assert(db:exists(custom_key), '[Error] @hasCustomMember - This custom key does not exist.')
		local store_type = db:type(custom_key)
		local store_module = getStoreModule(store_type)
		return store_module.has(custom_key, mem)

	end;

	numCustom = function (self, key)
		I_AM_CLASS_OR_INSTANCE(self)
		checkType(key, 'string')
		local custom_key = self:isClass() and getCustomKey(self, key) or getCustomIdKey(self, key)

		if not db:exists(custom_key) then return 0 end
		local store_type = db:type(custom_key)
		local store_module = getStoreModule(store_type)
		return store_module.num(custom_key)
	end;
	
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
	-- 
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
    save = function (self, params)
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
		if isFalse(indexfd) then
			db:zadd(index_key, self.id, self.id)
		elseif isFalse(self[indexfd]) then
			print("[Warning] index field value must not be empty, will not save it, please check your model defination.")
			return nil
		else
			local score = db:zscore(index_key, self[indexfd])
			-- is exist, return directely, else redis will update the score of val
			if score then 
				print("[Warning] save duplicate to an unique limited field, aborted!")
				return nil 
			end
			db:zadd(index_key, self.id, self[indexfd])				
		end

		local store_kv = {}
		--- save an hash object
		-- 'id' are essential in an object instance
		table.insert(store_kv, 'id')
		table.insert(store_kv, tostring(self.id))		

		-- if parameters exist, update it
		if params and type(params) == 'table' then
			for k, v in pairs(params) do
				if k ~= 'id' and self[k] then
					self[k] = v
				end
			end
		end

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
					table.insert(store_kv, k)
					table.insert(store_kv, tostring(v))		
				end
			end
		end
		-- save to database
		db:hmset(model_key, unpack(store_kv))
		
		-- make fulltext indexes
		if isUsingFulltextIndex(self) then
			makeFulltextIndexes(self)
		end
		if isUsingRuleIndex(self) then
			updateIndexByRules(self, 'save')
		end

		
		return self
    end;
    
    -- partially update function, once one field
	-- can only apply to none foreign field
    update = function (self, field, new_value)
		I_AM_INSTANCE(self)
		checkType(field, 'string')
		assert(type(new_value) == 'string' or type(new_value) == 'number')
		local fld = self.__fields[field]
		if not fld then print(("[Warning] Field %s doesn't be defined!"):format(field)); return nil end
		assert( not fld.foreign, ("[Error] %s is a foreign field, shouldn't use update function!"):format(field))
		local model_key = getNameIdPattern(self)
		assert(db:exists(model_key), ("[Error] Key %s does't exist! Can't apply update."):format(model_key))
		-- apply to db
		db:hset(model_key, field, new_value)
		-- apply to lua object
		self[field] = new_value
		
		-- if fulltext index
		if fld.fulltext_index and isUsingFulltextIndex(self) then
			makeFulltextIndexes(self)
		end
		if isUsingRuleIndex(self) then
			updateIndexByRules(self, 'update')
		end
		
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
    fakeDel = function (self)
		-- if self is query set
		if isQuerySet(self) then
			for _, v in ipairs(self) do
				fakedelFromRedis(v)
				-- clear fulltext indexes
				if isUsingFulltextIndex(v) then
					clearIndexesOnDeletion(v)
				end
				v = nil
			end
		else
			fakedelFromRedis(self)
			-- clear fulltext indexes
			if isUsingFulltextIndex(self) then
				clearIndexesOnDeletion(self)
			end
		end
		
		self = nil
    end;
	
	-- delete self instance object
    -- self can be instance or query set
    trueDel = function (self)
		-- if self is query set
		if isQuerySet(self) then
			for _, v in ipairs(self) do
				delFromRedis(v)
				-- clear fulltext indexes
				if isUsingFulltextIndex(v) then
					clearIndexesOnDeletion(v)
				end
				v = nil
			end
		else
			delFromRedis(self)
			-- clear fulltext indexes
			if isUsingFulltextIndex(self) then
				clearIndexesOnDeletion(self)
			end
		end
		
		self = nil
    end;
	
	
	-- delete self instance object
    -- self can be instance or query set
    del = function (self)
		I_AM_INSTANCE_OR_QUERY_SET(self)
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

		else
			local key = getFieldPattern(self, field)
			local store_module = getStoreModule(fld.st)
			store_module.add(key, new_id, fld.fifolen or 100)			
			-- in zset, the newest member has the higher score
			-- but use getForeign, we retrieve them from high to low, so newest is at left of result
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
					print('[Warning] invalid ONE foreign id or object.')
					return nil
				else
					return obj
				end
			end
		else
			if isFalse(self[field]) then return QuerySet() end
			
			local key = getFieldPattern(self, field)
		
			local store_module = getStoreModule(fld.st)
			local list = store_module.retrieve(key)

			if list:isEmpty() then return QuerySet() end
			list = list:slice(start, stop, is_rev)
			if list:isEmpty() then return QuerySet() end
		
			return retrieveObjectsByForeignType(fld.foreign, list)
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
			local list = store_module.retrieve(key)
			if list:isEmpty() then return List() end
			
			list = list:slice(start, stop, is_rev)
			if list:isEmpty() then return List() end
			
			return list
		end

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
		assert(fld.foreign == 'ANYSTRING' or fld.foreign == 'UNFIXED' or (type(obj) == 'table' and fld.foreign == getClassName(obj)), ("[Error] This foreign field '%s' can't accept the instance of model '%s'."):format(field, getClassName(obj) or tostring(obj)))

		-- if self[field] is nil, it must be wrong somewhere
		if isFalse(self[field]) then return nil end
		
		local new_id
		if isStrOrNum(obj) then
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
		
		
		if fld.st == 'ONE' then
			-- we must check the equality of self[filed] and new_id before perform delete action
			local key = getNameIdPattern(self)
			if self[field] == new_id then
				-- maybe here is rude
				db:hdel(key, field)
				self[field] = nil
			end
		else
			local key = getFieldPattern(self, field)
			local store_module = getStoreModule(fld.st)
			store_module.remove(key, new_id)
		end
	
		return self
	end;
	
	clearForeign = function (self, field)
		I_AM_INSTANCE(self)
		checkType(field, 'string')
		local fld = self.__fields[field]
		assert(fld, ("[Error] Field %s doesn't be defined!"):format(field))
		assert(fld.foreign, ("[Error] This field %s is not a foreign field."):format(field))
		assert(fld.st, ("[Error] No store type setting for this foreign field %s."):format(field))

		local key = getFieldPattern(self, field)		
		-- delete the foreign key
		db:del(key)
		
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
		if isStrOrNum(obj) then
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
			store_module.has(key, new_id)
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
			store_module.num(key)
		end
	end;

	--- return the class name of an instance
	classname = function (self)
		return getClassName(self)
	end;

	-- do sort on query set by some field
	sortBy = function (self, field, direction, sort_func, ...)
		I_AM_QUERY_SET(self)
		checkType(field, 'string')
		
		local direction = direction or 'asc'
		
		local byfield = field
		local sort_func = sort_func or function (a, b)
			local af = a[byfield] 
			local bf = b[byfield]
			if af and bf then
				if direction == 'asc' then
					return af < bf
				elseif direction == 'des' then
					return af > bf
				else
					return nil
				end
			end
		end
		
		table.sort(self, sort_func)
		
		-- secondary sort
		local field2, dir2, sort_func2 = ...
		if field2 then
			checkType(field2, 'string')

			-- divide to parts
			local work_t = {{self[1]}, }
			for i = 2, #self do
				if self[i-1][field] == self[i][field] then
					-- insert to the last table element of the list
					table.insert(work_t[#work_t], self[i])
				else
					work_t[#work_t + 1] = {self[i]}
				end
			end

			-- sort each part
			local result = {}
			byfield = field2
			sort_func = sort_func2 or sort_func
			for i, val in ipairs(work_t) do
				table.sort(val, sort_func)
				table.insert(result, val)
			end

			-- flatten to one rank table
			local flat = {}
			for i, val in ipairs(result) do
				for j, v in ipairs(val) do
					table.insert(flat, v)
				end
			end

			self = flat
		end
	
		return self		
	end;
	
	addToCacheAndSortBy = function (self, cache_key, field, sort_func)
		I_AM_INSTANCE(self)
		checkType(cache_key, field, 'string', 'string')
		
		DEBUG(cache_key)
		DEBUG('entering addToCacheAndSortBy')
		local cache_saved_key = getCacheKey(self, cache_key)
		if not db:exists(cache_saved_key) then 
			print('[WARNING] The cache is missing or expired.')
			return nil
		end
		
		local cached_ids = db:zrange(cache_saved_key, 0, -1)
		local head = db:hget(getNameIdPattern2(self, cached_ids[1]), field)
		local tail = db:hget(getNameIdPattern2(self, cached_ids[#cached_ids]), field)
		assert(head and tail, "[Error] @addToCacheAndSortBy. the object referring to head or tail of cache list may be deleted, please check.")
		DEBUG(head, tail)
		local order_type = 'asc'
		local field_value, stop_id
		local insert_position = 0
		
		if head > tail then order_type = 'des' end
		-- should always keep `a` and `b` have the same type
		local sort_func = sort_func or function (a, b)
			if order_type == 'asc' then
				return a > b
			elseif order_type == 'des' then
				return a < b
			end
		end
		
		DEBUG(order_type)
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
		DEBUG(insert_position)

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
		
		DEBUG(new_score)
		-- add new element to cache
		db:zadd(cache_saved_key, new_score, self.id)
			
		
		return self
	end;

	
	--------------------------------------------------------------------------
	-- Dynamic Field API
	--------------------------------------------------------------------------
	
	-- called by model
	addDynamicField = function (self, field_name, field_dt)
		I_AM_CLASS(self)
		checkType(field_name, field_dt, 'string', 'table')
		
		
		local fields = self.__fields
		if not fields then print('[Warning] This model has no __fields.'); return nil end
		-- if already exist, can not override it
		-- ensure the added is new field
		if not fields[field_name] then
			fields[field_name] = field_dt
			-- record to db
			local key = getDynamicFieldKey(self, field_name)
			for k, v in pairs(field_dt) do
				db:hset(key, k, serialize(v))
			end
			-- add to dynamic field index list
			db:rpush(getDynamicFieldIndex(self), field_name)
		end
		
	end;
	
	hasDynamicField = function (self)
		I_AM_CLASS(self)
		local dfindex = getDynamicFieldIndex(self)
		if db:exists(dfindex) and db:llen(dfindex) > 0 then
			return true
		else
			return false
		end
	end;
	
	delDynamicField = function (self, field_name)
		I_AM_CLASS(self)
		checkType(field_name, 'string')
		local dfindex = getDynamicFieldIndex(self)
		local dfield = getDynamicFieldKey(self, field_name)
		-- get field description table
		db:del(dfield)
		db:lrem(dfindex, 0, field_name)
		self.__fields[field_name] = nil
		
		return self
	end;

	importDynamicFields = function (self)
		I_AM_CLASS(self)
		local dfindex = getDynamicFieldIndex(self)
		local dfields_list = db:lrange(dfindex, 0, -1)
		
		for _, field_name in ipairs(dfields_list) do
			local dfield = getDynamicFieldKey(self, field_name)
			-- get field description table
			local data = db:hgetall(dfield)
			-- add new field to __fields
			self.__fields[field_name] = data
		end
		
		return self
	end;

	querySetIds = function (self)
		I_AM_QUERY_SET(self)
		local ids = List()
		for _, v in ipairs(self) do
			ids:append(v.id)
		end
		return ids
	end;
	
	-- for fulltext index API
	fulltextSearch = function (self, ask_str)
		assert(self.__name == 'Model')
				
		
	end;

}



return Model
