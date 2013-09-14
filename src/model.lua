module(..., package.seeall)


local tinsert, tremove = table.insert, table.remove
local tupdate = table.update
local format = string.format
local socket = require 'socket'

local driver = require 'bamboo.db.driver'
require 'bamboo.queryset'


local now = function ()
  return socket.gettime()
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
  local objs = QuerySet()
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
	local fields = self.__fields

	-- if parameters exist, update it
	if params and type(params) == 'table' then
		for k, v in pairs(params) do
			if k ~= 'id' and fields[k] then
				self[k] = tostring(v)
			end
		end
	end

	return self
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
			local initcb = t[field] or fdt.default
			if type(initcb) == 'function' then
				self[field] = initcb()
			else
				self[field] = initcb
			end
		end

		self.created_time = now()
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

    local obj = driver.getById(self, id, fields)
    return makeObject(self, obj)
	end;

	getByIds = function (self, ids, fields)
		I_AM_CLASS(self)
		assert(type(ids) == 'table', '[Warning] invalid type of #2 param', tostring(ids))

    local objs = driver.getByIds(self, ids, fields)
    
		return makeObjects(self, objs)
	end;

	getByIndex = function (self, index, fields)
    return self:slice(fields, index, index)[1]
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
	slice = function (self, start, stop, is_rev, fields)
		-- !slice method won't be open to query set, because List has slice method too.
		I_AM_CLASS(self)
		
    local objs = driver.slice(self, start, stop, is_rev, fields)
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
	filter = function (self, query_args, fields, skip, ntr)
		I_AM_CLASS(self)
		
    local objs = driver.filter(self, query_args, fields, skip, ntr)
    
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
	
  
--  trueDelById = function (self, id)
--    I_AM_CLASS(self)
--    
--    return driver.trueDelById(self, id)
--  end;
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
    processBeforeSave(self, params)
    
    self.lastmodified_time = now()
		return driver.save(self)
	end;

	-- partially update function, once one field
	-- can only apply to none foreign field
	update = function (self, field, new_value)
		I_AM_INSTANCE(self)

    self.lastmodified_time = now()
		return driver.update(self, field, new_value)
	end;


	-- delete self instance object
	-- self can be instance or query set
--	trueDel = function (self)
--		return driver.trueDel(self)
--	end;


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
  -- obj must be an object, when in normal foreign mode
	-- return self
	addForeign = function (self, field, obj)
		I_AM_INSTANCE(self)

    local fdt = self.__fields[field]
    local ftype = fdt.foreign
		local nobj
    
		if ftype == 'ANYOBJ' or ftype == 'ANYSTRING' then
			nobj = obj
		else
			nobj = obj.id
		end

    self.lastmodified_time = now()
		driver.addForeign(self, field, nobj)
		return self
	end;

	--
	--
	--
	getForeign = function (self, ffield, start, stop, is_rev, fields)
		I_AM_INSTANCE(self)
		
    if start then
      assert(start and stop and start > 0 and stop > 0 and start < stop, '[Error] @model.lua getForeign - start and stop must be positive numbers.')
    end
    
    return driver.getForeign(self, ffield, start, stop, is_rev, fields)
    
	end;

	getForeignIds = function (self, ffield, start, stop, is_rev)
		I_AM_INSTANCE(self)
    
    if start then
      assert(start and stop and start > 0 and stop > 0 and start < stop, '[Error] @model.lua getForeignIds - start and stop must be positive numbers.')
    end
    
    
		return driver.getForeignIds(self, ffield, start, stop, is_rev)

	end;

	-- rearrange the foreign index by input list
	reorderForeignMembers = function (self, ffield, neworder_ids)
		I_AM_INSTANCE(self)
		
    self.lastmodified_time = now()
    return reorderForeignMembers(self, ffield, neworder_ids)
	end;

	-- delelte a foreign member
	-- obj can be instance object, also can be object's id, also can be anystring.
	removeForeignMember = function (self, field, obj)
		I_AM_INSTANCE(self)
		checkType(field, 'string')
    assert(obj, '[Error] @model.lua removeForeignMember - #3 obj missing.')
		local fdt = self.__fields[field]
		
    local ftype = fdt.foreign
		local nobj = ''
    
		if ftype == 'ANYSTRING' or type(obj) == 'string' then
			nobj = obj
		else
			assert(obj.id, '[Error] @model.lua removeForeignMember - #3 obj has no id.')
      nobj = obj.id
		end
    
    self.lastmodified_time = now()
		return driver.removeForeignMember(self, field, nobj)
	end;

	delForeign = function (self, field)
		I_AM_INSTANCE(self)
		checkType(field, 'string')
		local fld = self.__fields[field]
		
    self.lastmodified_time = now()
		return driver.delForeign(self, field)
	end;

	deepDelForeign = function (self, field)
		I_AM_INSTANCE(self)
		
    self.lastmodified_time = now()
    return driver.deepDelForeign(self, field)
	end;

	-- check whether some obj is already in foreign list
	-- instance:inForeign('some_field', obj)
	hasForeignMember = function (self, field, obj)
		I_AM_INSTANCE(self)
		
    local id
    if type(obj) == 'string' then
      id = obj
    else
      id = obj.id
      assert(id, '[Error] @model.lua hasForeignMember - #3 has no id.')
    end
    
		return driver.hasForeignMember(self, field, id)
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

	
	getClassName = function (self)
		return self.__name
	end;


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

