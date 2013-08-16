

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
--_G['isValidInstance'] = function (obj)
--	if isFalse(obj) then return false end
--	checkType(obj, 'table')
--
--	for k, v in pairs(obj) do
--		if type(k) == 'string' then
--			if k ~= 'id' then
--				return true
--			end
--		end
--	end
--
--	return false
--end;


_G['isQuerySet'] = function (self)
	if isList(self)
	and rawget(self, '__spectype') == nil and self.__spectype == 'QuerySet'
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

_G['eq'] = function ( cmp )
	return cmp
end

_G['uneq'] = function ( cmp )
	return {
    ['$ne'] = cmp
  }
end

_G['lt'] = function (limitation)
	return {
    ['$lt'] = limitation
  }
end

_G['gt'] = function (limitation)
	return {
    ['$gt'] = limitation
  }
  
end

_G['lte'] = function (limitation)
	return {
    ['$lte'] = limitation
  }
end

_G['gte'] = function (limitation)
	return {
    ['$gte'] = limitation
  }
end

_G['bt'] = function (small, big)
	return {
    ['$gt'] = small,
    ['$lt'] = big
  }
end

_G['be'] = function (small, big)
	return {
    ['$gte'] = small,
    ['$lte'] = big
  }
end

_G['outside'] = function (small, big)
	return {
    ['$or'] = {
      ['$lt'] = small,
      ['$gt'] = big,
    }
  }
end

_G['contains'] = function (substr)
	return { 
    ['$regex'] = substr 
  }
end

_G['uncontains'] = function (substr)
	return {
    ['$not'] = {
      ['$regex'] = substr 
    }
  }
end

_G['startsWith'] = function (substr)
	return { 
    ['$regex'] = '^'..substr 
  }
end

_G['unstartsWith'] = function (substr)
	return {
    ['$not'] = {
      ['$regex'] = '^'..substr  
    }
  }
end


_G['endsWith'] = function (substr)
	return { 
    ['$regex'] = substr .. '$'
  }
end

_G['unendsWith'] = function (substr)
	return {
    ['$not'] = {
      ['$regex'] = substr .. '$'
    }
  }
end

_G['inset'] = function (set)
  return {
    ['$in'] = set
  }
end

_G['uninset'] = function (set)
	return {
    ['$nin'] = set
  }
end



--[[
local uglystr = '___hashindex^*_#@[]-+~~!$$$$'

_G['eq'] = function ( cmp_obj )
	return function (v)
		-- XXX: here we should not open the below line. v can be nil
		if v == uglystr then return nil, 'eq', cmp_obj; end--only return params

		if v == cmp_obj then
			return true
		else
			return false
		end
	end
end

_G['uneq'] = function ( cmp_obj )
	return function (v)
		-- XXX: here we should not open the below line. v can be nil
		if v == uglystr then return nil, 'uneq', cmp_obj; end

		if v ~= cmp_obj then
			return true
		else
			return false
		end
	end
end

_G['lt'] = function (limitation)
	return function (v)
		if v == uglystr then return nil, 'lt', limitation; end

		if v and v < limitation then
			return true
		else
			return false
		end
	end
end

_G['gt'] = function (limitation)
	return function (v)
		if v == uglystr then return nil, 'gt', limitation; end

		if v and v > limitation then
			return true
		else
			return false
		end
	end
end

_G['le'] = function (limitation)
	return function (v)
		if v == uglystr then return nil, 'le', limitation; end

		if v and v <= limitation then
			return true
		else
			return false
		end
	end
end

_G['ge'] = function (limitation)
	return function (v)
		if v == uglystr then return nil, 'ge', limitation; end

		if v and v >= limitation then
			return true
		else
			return false
		end
	end
end

_G['bt'] = function (small, big)
	return function (v)
		if v == uglystr then return nil, 'bt', {small, big}; end

		if v and v > small and v < big then
			return true
		else
			return false
		end
	end
end

_G['be'] = function (small, big)
	return function (v)
		if v == uglystr then return nil, 'be', {small,big}; end

		if v and v >= small and v <= big then
			return true
		else
			return false
		end
	end
end

_G['outside'] = function (small, big)
	return function (v)
		if v == uglystr then return nil, 'outside',{small,big}; end

		if v and (v < small or v > big) then
			return true
		else
			return false
		end
	end
end

_G['contains'] = function (substr)
	return function (v)
		if v == uglystr then return nil, 'contains', substr; end

		v = tostring(v)
		if v:contains(substr) then
			return true
		else
			return false
		end
	end
end

_G['uncontains'] = function (substr)
	return function (v)
		if v == uglystr then return nil, 'uncontains', substr; end

		v = tostring(v)
		if not v:contains(substr) then
			return true
		else
			return false
		end
	end
end

_G['startsWith'] = function (substr)
	return function (v)
		if v == uglystr then return nil, 'startsWith', substr; end

		v = tostring(v)
		if v:startsWith(substr) then
			return true
		else
			return false
		end
	end
end

_G['unstartsWith'] = function (substr)
	return function (v)
		if v == uglystr then return nil, 'unstartsWith', substr; end

		v = tostring(v)
		if not v:startsWith(substr) then
			return true
		else
			return false
		end
	end
end


_G['endsWith'] = function (substr)
	return function (v)
		if v == uglystr then return nil, 'endsWith', substr; end
		
		v = tostring(v)
		if v:endsWith(substr) then
			return true
		else
			return false
		end
	end
end

_G['unendsWith'] = function (substr)
	return function (v)
		if v == uglystr then return nil, 'unendsWith', substr; end
		v = tostring(v)
		if not v:endsWith(substr) then
			return true
		else
			return false
		end
	end
end

_G['inset'] = function (...)
	local args = {...}
	return function (v)
		if v == uglystr then return nil, 'inset', args; end
		
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
	local t = function (v)
		if v == uglystr then return nil, 'uninset', args; end
		
		v = tostring(v)
		for _, val in ipairs(args) do
			-- once meet one, false
			if tostring(val) == v then
				return false
			end
		end

		return true
	end
	return t
end
--]]