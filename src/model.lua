module(..., package.seeall)


local tinsert, tremove = table.insert, table.remove
local tupdate = table.update
local format = string.format
local socket = require 'socket'

local driver = require 'bamboo.db.driver'
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
  if not data then return nil end
  
	local fields = self.__fields
	for k, fld in pairs(fields) do
    if fld.type == 'number' then
      data[k] = tonumber(data[k])
    elseif fld.type == 'boolean' then
      data[k] = data[k] == 'true' and true or false
    end
  end
  
	-- generate an object
	local obj = self()
  tupdate(obj, data)
	return obj

end

local makeObjects = function (self, data_list)
  local objs = List()
  for i, data in ipairs(data_list) do
    tinsert(objs, makeObject(self, data))
  end
  
  return objs
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
--	    ['created_time'] = { type="number" },
--	    ['lastmodified_time'] = { type="number" },

	};

	-- make every object creatation from here: 
	-- every object has the 'id', 'created_time' and 'lastmodified_time' fields
	init = function (self, t)
		local t = t or {}
		local fields = self.__fields

		for field, fdt in pairs(fields) do
			-- assign to default value if exsits
			local initcb = t[field] or fdt.default
			if type(initcb) == 'function' then
				self[field] = initcb()
			else
				self[field] = initcb
			end
		end

--		self.created_time = socket.gettime()
--		self.lastmodified_time = self.created_time

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

    local obj = self, driver.getById(self, id, fields)
    return makeObject(self, obj)
	end;

	getByIds = function (self, ids, fields)
		I_AM_CLASS(self)
		assert(type(ids) == 'table', '[Warning] invalid type of #2 param', tostring(ids))

    local objs = driver.getByIds(self, ids, fields)
    
		return makeObjects(self, objs)
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
		
    local objs = driver.all(self, fields, is_rev)
    return makeObjects(self, objs)
	end;

	-- slice instance object list, support negative index (-1)
	--
	slice = function (self, fields, start, stop, is_rev)
		-- !slice method won't be open to query set, because List has slice method too.
		I_AM_CLASS(self)
		
    local objs = driver.slice(self, fields, start, stop, is_rev)
		return makeObjects(self, objs)
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
		
    local obj = driver.get(self, query_args, fields, skip)
    
		return makeObject(self, obj)
	end;

	--- fitler some instances belong to this model
	-- @param query_args: query arguments in a table
	-- @param 
	-- @return
	filter = function (self, query_args, fields, skip)
		I_AM_CLASS(self)
		
    local objs = driver.filter(self, query_args, fields, skip)
    
    return makeObjects(self, objs)
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

    local fld = self.__fields[field]
    local ftype = fld.foreign
		local nobj
    
		if ftype == 'ANYOBJ' or ftype == 'ANYSTRING' then
			nobj = obj
		else
			nobj = obj.id
		end

		driver.addForeign(self, field, nobj)
		return self
	end;

	--
	--
	--
	getForeign = function (self, ffield, start, stop, is_rev)
		I_AM_INSTANCE(self)
		
    return driver.getForeign(self, ffield, fields, start, stop, is_rev)
    
	end;

	getForeignIds = function (self, ffield, start, stop, is_rev)
		I_AM_INSTANCE(self)

		return driver.getForeignIds(self, ffield, start, stop, is_rev)

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
		
    
    
		return self
	end;

	delForeign = function (self, field)
		I_AM_INSTANCE(self)
		checkType(field, 'string')
		local fld = self.__fields[field]
		
    
		return driver.delForeign(self, field)
	end;

	deepDelForeign = function (self, field)
		I_AM_INSTANCE(self)
		
    return driver.deepDelForeign(self, field)
	end;

	-- check whether some obj is already in foreign list
	-- instance:inForeign('some_field', obj)
	hasForeignMember = function (self, field, obj)
		I_AM_INSTANCE(self)
		
		return driver.hasForeignMember(self, field, obj)
	end;

	-- return the number of elements in the foreign list
	-- @param field:  field of that foreign model
	numForeign = function (self, field)
		I_AM_INSTANCE(self)
		
    return driver.numForeign(self, field)
    
	end;

	-- check this class/object has a foreign key
	-- @param field:  field of that foreign model
	hasForeignKey = function (self, field)
		I_AM_INSTANCE(self)
		
    return driver.hasForeignKey(self, field)
	end;

	------------------------------------------------------------------------
	-- misc APIs
	------------------------------------------------------------------------

	
	getClassName = getClassName;


	getFDT = function (self, field)
		I_AM_CLASS_OR_INSTANCE(self)

		return self.__fields[field]

	end;

}
:include('bamboo.mixins.custom')
--:include('bamboo.mixins.fulltext')

Model.__tag = Model.__name
Model.classname = Model.getClassName

Model.clearForeign = Model.delForeign
Model.deepClearForeign = Model.deepDelForeign
Model.hasForeign = Model.hasForeignMember
Model.rearrangeForeign = Model.rearrangeForeignMembers



return Model

