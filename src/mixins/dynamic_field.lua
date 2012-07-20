

	
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
