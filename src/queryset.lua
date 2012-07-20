


local QuerySetMeta = setProto({__spectype='QuerySet'}, Model)
QuerySet = function (list)
	local list = List(list)
	-- create a query set	
	-- add it to fit the check of isClass function
--	if not getmetatable(QuerySetMeta) then
--		QuerySetMeta = setProto(QuerySetMeta, Model)
--	end
	local query_set = setProto(list, QuerySetMeta)
	
	return query_set
end

_G['QuerySet'] = QuerySet



	--- fitler some instances belong to this model
	-- @param query_args: query arguments in a table
	-- @param start: specify which index to start slice, note: this is the position after filtering 
	-- @param stop: specify the end of slice
	-- @param is_rev: specify the direction of the search result, 'rev'
	-- @return: query_set, an object list (query set)
	-- @note: this function can be called by class object and query set
	filter = function (self, query_args, start, stop, is_rev, is_get)
		I_AM_CLASS_OR_QUERY_SET(self)
		assert(type(query_args) == 'table' or type(query_args) == 'function', '[Error] the query_args passed to filter must be table or function.')
		if start then assert(type(start) == 'number', '[Error] @filter - start must be number.') end
		if stop then assert(type(stop) == 'number', '[Error] @filter - stop must be number.') end
		if is_rev then assert(type(is_rev) == 'string', '[Error] @filter - is_rev must be string.') end
		
		local is_query_set = false
		if isQuerySet(self) then is_query_set = true end
		local is_args_table = (type(query_args) == 'table')
		local logic = 'and'
		
		local query_str_iden
		local is_using_rule_index = isUsingRuleIndex(self)
		if is_using_rule_index then
			if type(query_args) == 'function' then
				collectRuleFunctionUpvalues(query_args)
			                                   
			end
			-- make query identification string
			query_str_iden = compressQueryArgs(query_args)

			-- check index
			-- XXX: Only support class now, don't support query set, maybe query set doesn't need this feature
			local id_list = getIndexFromManager(self, query_str_iden)
			if type(id_list) == 'table' then
				if #id_list == 0 then
					return QuerySet()
				else
					-- #id_list > 0
					if is_get == 'get' then
						id_list = (is_rev == 'rev') and List{id_list[#id_list]} or List{id_list[1]}
					else	
						-- now id_list is a list containing all id of instances fit to this query_args rule, so need to slice
						id_list = id_list:slice(start, stop, is_rev)
					end
					
					-- if have this list, return objects directly
					if #id_list > 0 then
						return getFromRedisPipeline(self, id_list)
					end
				end
			end
			-- else go ahead
		end
		
		if is_args_table then

			if query_args and query_args['id'] then
				-- remove 'id' query argument
				print("[Warning] get and filter don't support search by id, please use getById.")
				-- print(debug.traceback())
				-- query_args['id'] = nil
				return nil
			end

			-- if query table is empty, return slice instances
			if isFalse(query_args) then 
				local start = start or 1
				local stop = stop or -1
				local nums = self:numbers()
				return self:slice(start, stop, is_rev)
			end

			-- normalize the 'and' and 'or' logic
			if query_args[1] then
				assert(query_args[1] == 'or' or query_args[1] == 'and', 
					"[Error] The logic should be 'and' or 'or', rather than: " .. tostring(query_args[1]))
				if query_args[1] == 'or' then
					logic = 'or'
				end
				query_args[1] = nil
			end
		end
		
		local all_ids = {}
		if is_query_set then
			-- if self is query set, we think of all_ids as object list, rather than id string list
			all_ids = self
			-- nothing in id list, return empty table
			if #all_ids == 0 then return QuerySet() end
		
		end
		
		-- create a query set
		local query_set = QuerySet()
		local logic_choice = (logic == 'and')
		local partially_got = false

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
		
		--DEBUG('all_ids', all_ids)
		if is_query_set then
			local objs = all_ids
			-- objs are already integrated instances
			walkcheck(objs)			
		else
            local hash_index_query_args = {};
            local hash_index_flag = false;
            local raw_filter_flag = false;

            if type(query_args) == 'function' then
                hash_index_flag = false;
                raw_filter_flag = true;
            elseif bamboo.config.index_hash then
                for field,value in pairs(query_args) do 
                    if self.__fields[field].index_type ~= nil then 
                        hash_index_query_args[field] = value;
                        query_args[field] = nil; 
                        hash_index_flag = true;
                    else
                        raw_filter_flag = true;
                    end
                end
            else
                raw_filter_flag = true;
                hash_index_flag = false;
            end


            if hash_index_flag then 
                all_ids = mih.filter(self,hash_index_query_args,logic);
            else
			    -- all_ids is id string list
    			all_ids = self:allIds()
            end

            if raw_filter_flag then 
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
            else
		        -- here, all_ids is the all instance id to query_args now
                --query_set = QuerySet(all_ids);
                for i,v in ipairs(all_ids) do 
                    tinsert(query_set,self:getById(tonumber(v)));
                end
            end
		end
		
		-- here, _t_query_set is the all instance fit to query_args now
		local _t_query_set = query_set
		
		if #query_set == 0 then
			if not is_query_set and is_using_rule_index then
				addIndexToManager(self, query_str_iden, {})
			end
		else
			if is_get == 'get' then
				query_set = (is_rev == 'rev') and List {_t_query_set[#_t_query_set]} or List {_t_query_set[1]}
			else	
				-- now id_list is a list containing all id of instances fit to this query_args rule, so need to slice
				query_set = _t_query_set:slice(start, stop, is_rev)
			end

			-- if self is query set, its' element is always integrated
			-- if call by class
			if not is_query_set then
				-- retrieve all objects' id
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
					id_list = {}
					-- retrieve needed objects' id
					for _, v in ipairs(query_set) do
						tinsert(id_list, v.id)
					end
					query_set = getFromRedisPipeline(self, id_list)
				end
			end
		end
		
		return query_set
	end;

	
	querySetIds = function (self)
		I_AM_QUERY_SET(self)
		local ids = List()
		for _, v in ipairs(self) do
			ids:append(v.id)
		end
		return ids
	end;

		-- do sort on query set by some field
	sortBy = function (self, field, direction, sort_func, ...)
		I_AM_QUERY_SET(self)
		-- checkType(field, 'string')
		
		local direction = direction or 'asc'
		
		local byfield = field
		local sort_func = sort_func or function (a, b)
			local af = a[byfield] 
			local bf = b[byfield]
			if af and bf then
				if direction == 'asc' then
					return af < bf
				elseif direction == 'desc' then
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
			direction = dir2 or 'asc'
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
