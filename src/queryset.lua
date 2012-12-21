
local QuerySetMeta = {__spectype='QuerySet'}

-- require neccessary methods
local checkLogicRelation = bamboo.internals.checkLogicRelation


QuerySetMeta.get = function (self, query_args, find_rev)
	I_AM_QUERY_SET(self)

	local checkRelation = function (obj)
		-- logic check
local checkLogicRelation = bamboo.internals.checkLogicRelation
        
		flag = checkLogicRelation(obj, query_args, logic == 'and')
		if flag then return obj end

		return nil
	end
	
	local obj
	if find_rev == 'rev' then
		for i=#self, 1, -1 do
			return checkRelation(self[i])
		end
	else
		for i=1, #self do
			return checkRelation(self[i])
		end
		
	end


	
end

QuerySetMeta.filter = function (self, query_args, ...)
	I_AM_QUERY_SET(self)
	local objs = self
	if #objs == 0 then return QuerySet() end

	assert(type(query_args) == 'table' or type(query_args) == 'function', 
		'[Error] the query_args passed to filter must be table or function.')
	local no_sort_rule
	-- regular the args
	local sort_field, sort_dir, sort_func, start, stop, is_rev
	local first_arg = select(1, ...)
	if type(first_arg) == 'function' then
		sort_func = first_arg
		start = select(2, ...)
		stop = select(3, ...)
		is_rev = select(4, ...)
		no_sort_rule = false
	elseif type(first_arg) == 'string' then
		sort_field = first_arg
		sort_dir = select(2, ...)
		start = select(3, ...)
		stop = select(4, ...)
		is_rev = select(5, ...)
		no_sort_rule = false
	elseif type(first_arg) == 'number' then
		start = first_arg
		stop = select(2, ...)
		is_rev = select(3, ...)
		no_sort_rule = true
	end

	if start then assert(type(start) == 'number', '[Error] @filter - start must be number.') end
	if stop then assert(type(stop) == 'number', '[Error] @filter - stop must be number.') end
	if is_rev then assert(type(is_rev) == 'string', '[Error] @filter - is_rev must be string.') end

	local is_args_table = (type(query_args) == 'table')
	local logic = 'and'

	-- create a query set
	local query_set = QuerySet()

	if is_args_table then
		assert( not query_args['id'], 
			"[Error] query set doesn't support searching by id, please use getById.")

		-- if query table is empty, treate it as all action, or slice action
		if isFalse(query_args) and no_sort_rule then
			return self:slice(start, stop, is_rev)
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
	-- walkcheck can process full object and partial object
	local walkcheck = function (objs)
		for i, obj in ipairs(objs) do
			-- check the object's legalery, only act on valid object
local checkLogicRelation = bamboo.internals.checkLogicRelation
			local flag = checkLogicRelation(obj, query_args, logic_choice)

			-- if walk to this line, means find one
			if flag then
				table.insert(query_set, obj)
			end
		end
	end

	walkcheck(objs)
	-- sort
	if not no_sort_rule then
		query_set = query_set:sortBy(sort_field or sort_func, sort_dir)
	end
	-- slice
	if start or stop then
		query_set = query_set:slice(start, stop, is_rev)
	end

	return query_set
end


QuerySetMeta.sortBy = function (self, ...)
	I_AM_QUERY_SET(self)
	local field, dir, sort_func, field2, dir2, sort_func2
	-- regular the args, 6 cases
	local first_arg = select(1, ...)
	if type(first_arg) == 'function' then
		sort_func = first_arg
		local second_arg = select(2, ...)
		if type(second_arg) == 'function' then
			sort_func2 = first_arg
		elseif type(second_arg) == 'string' then
			field2 = second_arg
			dir2 = select(3, ...)
		end
	elseif type(first_arg) == 'string' then
		field = first_arg
		dir = select(2, ...)
		local third_arg = select(3, ...)
		if type(third_arg) == 'function' then
			sort_func2 = third_arg
		elseif type(third_arg) == 'string' then
			filed2 = third_arg
			dir2 = select(4, ...)
		end
	end
	

	local dir = dir or 'asc'
	local byfield = field
	local sort_func = sort_func or function (a, b)
		local af = a[byfield]
		local bf = b[byfield]
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

	table.sort(self, sort_func)

	-- secondary sort
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
		dir = dir2 or 'asc'
		sort_func = sort_func2 or sort_func
		for i, val in ipairs(work_t) do
			table.sort(val, sort_func)
			table.insert(result, val)
		end

		-- flatten to one rank table
		local flat = QuerySet()
		for i, val in ipairs(result) do
			for j, v in ipairs(val) do
				table.insert(flat, v)
			end
		end

		self = flat
	end

	return self
end


QuerySetMeta.querySetIds = function (self)
	I_AM_QUERY_SET(self)
	local ids = List()
	for _, v in ipairs(self) do
		ids:append(v.id)
	end
	return ids
end
	
QuerySetMeta.combineQuerySets = function (self, another)
	I_AM_QUERY_SET(self)
	I_AM_QUERY_SET(another)		
	local ids = List()
	for _, v in ipairs(self) do
		ids:append(v.id)
	end
	local self_set = Set(ids)
	
	for _, v in ipairs(another) do
		-- if not duplicated, append it
		if not self_set[v.id] then
			self:append(v)
		end
	end
	
	return self
end;
	
QuerySetMeta.fakeDel = function (self)
	I_AM_QUERY_SET(self)
	local fakeDelFromRedis = bamboo.internals.fakeDelFromRedis
	
	for _, v in ipairs(self) do
		fakeDelFromRedis(v)
		v = nil
	end

	self = nil
end;

QuerySetMeta.trueDel = function (self)
	I_AM_QUERY_SET(self)
	local delFromRedis = bamboo.internals.delFromRedis
	
	for _, v in ipairs(self) do
		delFromRedis(v)
		v = nil
	end

	self = nil
end;

QuerySetMeta.del = function (self)
	I_AM_QUERY_SET(self)
	if bamboo.config.use_fake_deletion == true then
		return self:fakeDel()
	else
		return self:trueDel()
	end
end;
	
QuerySet = function (list)
	local list = List(list)
	local query_set = setProto(list, QuerySetMeta)

	return query_set
end

_G['QuerySet'] = QuerySet
