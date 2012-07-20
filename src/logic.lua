

------------------------------------------------------------------------
-- Query Function Set
-- for convienent, import them into _G directly
------------------------------------------------------------------------
local closure_collector = {}
local upvalue_collector = {}
local uglystr = '___hashindex^*_#@[]-+~~!$$$$'

_G['eq'] = function ( cmp_obj )
	local t = function (v)
	-- XXX: here we should not open the below line. v can be nil
		if v == uglystr then return nil, 'eq', cmp_obj; end--only return params
		
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
	-- XXX: here we should not open the below line. v can be nil
		if v == uglystr then return nil, 'uneq', cmp_obj; end

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
	limitation = tonumber(limitation) or limitation
	local t = function (v)
        if v == uglystr then return nil, 'lt', limitation; end

		local nv = tonumber(v) or v
		if nv and nv < limitation then
			return true
		else
			return false
		end
	end
	closure_collector[t] = {'lt', limitation}
	return t
end

_G['gt'] = function (limitation)
	limitation = tonumber(limitation) or limitation
	local t = function (v)
        if v == uglystr then return nil, 'gt', limitation; end

		local nv = tonumber(v) or v
		if nv and nv > limitation then
			return true
		else
			return false
		end
	end
	closure_collector[t] = {'gt', limitation}
	return t
end


_G['le'] = function (limitation)
	limitation = tonumber(limitation) or limitation
	local t = function (v)
        if v == uglystr then return nil, 'le', limitation; end

		local nv = tonumber(v) or v
		if nv and nv <= limitation then
			return true
		else
			return false
		end
	end
	closure_collector[t] = {'le', limitation}
	return t
end

_G['ge'] = function (limitation)
	limitation = tonumber(limitation) or limitation
	local t = function (v)
        if v == uglystr then return nil, 'ge', limitation; end

		local nv = tonumber(v) or v
		if nv and nv >= limitation then
			return true
		else
			return false
		end
	end
	closure_collector[t] = {'ge', limitation}
	return t
end

_G['bt'] = function (small, big)
	small = tonumber(small) or small
	big = tonumber(big) or big	
	local t = function (v)
        if v == uglystr then return nil, 'bt', {small, big}; end

		local nv = tonumber(v) or v
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
	small = tonumber(small) or small
	big = tonumber(big) or big	
	local t = function (v)
        if v == uglystr then return nil, 'be', {small,big}; end

		local nv = tonumber(v) or v
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
	small = tonumber(small) or small
	big = tonumber(big) or big	
	local t = function (v)
        if v == uglystr then return nil, 'outside',{small,big}; end

		local nv = tonumber(v) or v
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
        if v == uglystr then return nil, 'contains', substr; end

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
        if v == uglystr then return nil, 'uncontains', substr; end

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
        if v == uglystr then return nil, 'startsWith', substr; end

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
        if v == uglystr then return nil, 'unstartsWith', substr; end

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
        if v == uglystr then return nil, 'endsWith', substr; end
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
        if v == uglystr then return nil, 'unendsWith', substr; end
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
	closure_collector[t] = {'inset', ...}
	return t
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
	closure_collector[t] = {'uninset', ...}
	return t
end