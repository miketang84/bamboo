

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
_G.eq = function (cmp_obj)
	return {'eq', cmp_obj}
end

_G.uneq = function ( cmp_obj )
	return {'uneq', cmp_obj}
end

_G.lt = function (limitation)
	return {'lt', limitation}
end

_G.gt = function (limitation)
	return {'gt', limitation}
end

_G.le = function (limitation)
	return {'le', limitation}
end

_G.ge = function (limitation)
	return {'ge', limitation}
end

_G.bt = function (small, big)
	return {'bt', small, big}
end

_G.be = function (small, big)
	return {'be', small, big}
end

_G.outside = function (small, big)
	return {'outside', small, big}
end

_G.contains = function (substr)
	return {'contains', substr}
end

_G.uncontains = function (substr)
	return {'uncontains', substr}
end

_G.startsWith = function (substr)
	return {'startsWith', substr}
end

_G.unstartsWith = function (substr)
	return {'unstartsWith', substr}
end

_G.endsWith = function (substr)
	return {'endsWith', substr}
end

_G.unendsWith = function (substr)
	return {'unendsWith', substr}
end

_G.inset = function (args)
	return {'inset', args}
end

_G.uninset = function (args)
	return {'uninset', args}
end



