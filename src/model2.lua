module(..., package.seeall)


local tinsert, tremove = table.insert, table.remove
local format = string.format
local socket = require 'socket'

local driver = require 'bamboo.db.drver'
require 'bamboo.queryset'



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
local Model = Object:extend {
	__name = 'Model';
	__fields = {
	    -- here, we don't put 'id' as a field
	    ['created_time'] = { type="number" },
	    ['lastmodified_time'] = { type="number" },

	};

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
	
	getById = function (self, id, fields)
		I_AM_CLASS(self)
		local idtype = type(id)
    if idtype ~= 'string' and idtype ~= 'number' then
      print('[Warning] invalid type of #2 param', id)
      return nil
    end

    return driver.getById(self, id, fields)
	end;

	getByIds = function (self, ids, fields)
		I_AM_CLASS(self)
		assert(type(ids) == 'table', '[Warning] invalid type of #2 param', tostring(ids))

		return getFromRedisPipeline(self, ids)
	end;

	
	-- return a list containing all ids of all instances of this Model
	--
	allIds = function (self, is_rev)
		I_AM_CLASS(self)
		
    return driver.allIds(self, is_rev)
	end;

	
	-- slice the ids list, start from 1, support negative index (-1)
	--
	sliceIds = function (self, start, stop, is_rev)
		I_AM_CLASS(self)
    
		
    return driver.sliceIds(self, start, stop, is_rev)

	end;

	-- return all instance objects belong to this Model
	--
	all = function (self, fields, is_rev)
		I_AM_CLASS(self)
		
    return driver.all(self, fields, is_rev)
	end;

	-- slice instance object list, support negative index (-1)
	--
	slice = function (self, fields, start, stop, is_rev)
		-- !slice method won't be open to query set, because List has slice method too.
		I_AM_CLASS(self)
		
		return driver.slice(self, fields, start, stop, is_rev)
	end;

	-- return the actual number of the instances
	--
	numbers = function (self)
		I_AM_CLASS(self)
		return driver.numbers(self)
	end;

	-- return the first instance found by query set
	--
	get = function (self, query_args, fields, skip)
		I_AM_CLASS(self)
		
		return driver.get(self, query_args, fields, skip)
	end;

	--- fitler some instances belong to this model
	-- @param query_args: query arguments in a table
	-- @param 
	-- @return
	filter = function (self, query_args, fields, skip)
		I_AM_CLASS(self)
		
    return driver.filter(self, query_args, fields, skip)
	end;


    	-- deprecated
	-- count the number of instance fit to some rule
	count = function (self, query_args)
		I_AM_CLASS(self)
		return driver.count(self, query_args)
	end;

	
	
	-- delete self instance object
	-- self can be instance or query set
	delById = function (self, id)
		I_AM_CLASS(self)
		
    return driver.delById(self, id)
	end;
	
  
  trueDelById = function (self, id)
    I_AM_CLASS(self)
    
    return driver.trueDelById(self, id)
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

		return driver.save(self, params)
	end;

	-- partially update function, once one field
	-- can only apply to none foreign field
	update = function (self, field, new_value)
		I_AM_INSTANCE(self)

		return driver.update(self, field, new_value)
	end;


	-- delete self instance object
	-- self can be instance or query set
	trueDel = function (self)
		return driver.trueDel(self)
	end;


	-- delete self instance object
	-- self can be instance or query set
	del = function (self)
		return driver.del(self)
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
		else
			new_id = obj.id
		end

		driver.addForeign(self, field, new_id)
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

	getForeignIds = function (self, field, force)
		I_AM_INSTANCE(self)
		checkType(field, 'string')
		local fld = self.__fields[field]
		assert(fld, ("[Error] Field %s doesn't be defined!"):format(field))
		assert(fld.foreign, ("[Error] This field %s is not a foreign field."):format(field))
		assert(fld.st, ("[Error] No store type setting for this foreign field %s."):format(field))

		return driver.getForeignIds(self, ffield, force)

	end;

	-- rearrange the foreign index by input list
	reorderForeignMembers = function (self, ffield, neworder_ids)
		I_AM_INSTANCE(self)
		
    return reorderForeignMembers(self, ffield, neworder_ids)
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

