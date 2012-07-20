
local isUsingRuleIndex = function (self)
	if bamboo.config.rule_index_support and self.__use_rule_index and self.__name then
		return true
	end
	return false
end



-------------------------------------------------------------------
--
local collectRuleFunctionUpvalues = function (query_args)
	local upvalues = upvalue_collector
	for i=1, math.huge do
		local name, v = debug.getupvalue(query_args, i)
		if not name then break end
		-- because we could not collect the upvalues whose type is 'table', print warning here
		if type(v) == 'table' or type(v) == 'function' then 
			print"[Error] @collectRuleFunctionUpvalues of filter - bamboo has no ability to collect the function upvalue whose type is 'table' or 'function'."
			return nil
		end
			
		upvalues[#upvalues + 1] = { name, tostring(v), type(v) }
	end
end


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
		-- clear the closure_collector
		closure_collector = {}
		
		-- restore the first element, avoiding side effect
		query_args[1] = out[1]	

	elseif qtype == 'function' then
		tinsert(out, 'function')
		tinsert(out, '|')	
		tinsert(out, string.dump(query_args))
		tinsert(out, '|')			
		for _, pair in ipairs(upvalue_collector) do
			tinsert(out, pair[1])	-- key
			tinsert(out, pair[2])	-- value
			tinsert(out, pair[3])	-- value type			
		end

		-- clear the upvalue_collector
		upvalue_collector = {}
	end

	-- use a delemeter to seperate obviously
	return table.concat(out, ' ')
end

local extraQueryArgs = function (qstr)
	local query_args
	
	--DEBUG(string.len(qstr))		
	if qstr:startsWith('function') then
		local startpoint = qstr:find('|') or 1
		local endpoint = qstr:rfind('|') or -1
		--DEBUG(startpoint, endpoint)
		fpart = qstr:sub(startpoint + 2, endpoint - 2) -- :trim()
		apart = qstr:sub(endpoint + 2, -1) -- :trim()
		--DEBUG(string.len(fpart), string.len(apart))		
		-- now fpart is the function binary string
		query_args = loadstring(fpart)
		-- now query_args is query function
		--DEBUG(fpart, apart, query_args)
		if not isFalse(apart) then
			-- item 1 is key, item 2 is value, item 3 is value type, item 4 is key .... 
			local flat_upvalues = apart:split(' ')
			for i=1, #flat_upvalues / 3 do
				local vtype = flat_upvalues[3*i]
				local key = flat_upvalues[3*i - 2]
				local value = flat_upvalues[3*i - 1]
				if vtype == 'string' then
					-- nothing to do
				elseif vtype == 'number' then
					value = tonumber(value)
				elseif vtype == 'boolean' then
					value = loadstring('return ' .. value)()
				elseif vtype == 'nil' then
					value = nil
				end
				--DEBUG(vtype, key, value)
				-- set upvalues
				debug.setupvalue(query_args, i, value)
			end
		end
	else
	
		local endpoint = -1
		qstr = qstr:sub(1, endpoint - 1)
		local _qqstr = qstr:splittrim('|')
		--DEBUG(qstr, _qqstr)
		-- logic == 'and' or 'or'
		local logic = _qqstr[1]
		query_args = {logic}
		for i=2, #_qqstr do
			local str = _qqstr[i]
			local kt = str:splittrim(' ')
			--DEBUG(kt)
			-- kt[1] is 'key', [2] is 'closure', [3] .. are closure's parameters
			local key = kt[1]
			local closure = kt[2]
			if #kt > 2 then
				local _args = {}
				for j=3, #kt do
					tinsert(_args, kt[j])
				end
				--DEBUG('_args', _args)
				--DEBUG('_G[closure]', closure, _G[closure](unpack(_args)))				
				-- compute closure now
				query_args[key] = _G[closure](unpack(_args))
			else
				-- no args, means this 'closure' is a string
				query_args[key] = closure
			end
		end
		--DEBUG(query_args)
	end
	
	return query_args	
end




local canInstanceFitQueryRule = function (self, qstr)
	local query_args = extraQueryArgs(qstr)
	--DEBUG(query_args)
	local logic_choice = true
	if type(query_args) == 'table' then logic_choice = (query_args[1] == 'and'); query_args[1]=nil end
	return checkLogicRelation(self, query_args, logic_choice)
end

-- here, qstr rule exist surely
local addInstanceToIndexOnRule = function (self, qstr)
	local manager_key = rule_manager_prefix .. self.__name
	--DEBUG(self, qstr, manager_key)	
	local score = db:zscore(manager_key, qstr)
	local item_key = rule_result_pattern:format(self.__name, math.floor(score))

	local flag = canInstanceFitQueryRule(self, qstr)
	--DEBUG(flag)
	if flag then
		db:transaction(function(db)
			-- if previously added, remove it first, if no, just no effects
			-- but this may change the default object index orders
			--db:lrem(item_key, 0, self.id)
			--db:rpush(item_key, self.id)
			-- insert a new id after the old same id
			db:linsert(item_key, 'AFTER', self.id, self.id)
			-- delete the old one id
			db:lrem(item_key, 1, self.id)
			-- update the float score to integer
			db:zadd(manager_key, math.floor(score), qstr)
			db:expire(item_key, bamboo.config.rule_expiration or bamboo.RULE_LIFE)
		end)
	end
	return flag
end

local updateInstanceToIndexOnRule = function (self, qstr)
	local manager_key = rule_manager_prefix .. self.__name
	local score = db:zscore(manager_key, qstr)
	local item_key = rule_result_pattern:format(self.__name, math.floor(score))

	local flag = canInstanceFitQueryRule(self, qstr)
	db:transaction(function(db)
		if flag then
			db:linsert(item_key, 'AFTER', self.id, self.id)
		end
		-- delete the old one id
		db:lrem(item_key, 1, self.id)
			
		-- this may change the default object index orders
--		db:lrem(item_key, 0, self.id)
--		if flag then
--			db:rpush(item_key, self.id)	
--		end
		db:expire(item_key, bamboo.config.rule_expiration or bamboo.RULE_LIFE)
	end)
	return flag
end

local delInstanceToIndexOnRule = function (self, qstr)
	local manager_key = rule_manager_prefix .. self.__name
	local score = db:zscore(manager_key, qstr)
	local item_key = rule_result_pattern:format(self.__name, math.floor(score))

	local flag = canInstanceFitQueryRule(self, qstr)
	local options = { watch = item_key, cas = true, retry = 2 }
	db:transaction(options, function(db)
		db:lrem(item_key, 0, self.id)
		-- if delete to empty list, update the rule score to float
		if not db:exists(item_key) then   
			db:zadd(manager_key, score + 0.1, qstr)
		end
		db:expire(item_key, bamboo.config.rule_expiration or bamboo.RULE_LIFE)
	end)
	return flag
end

local INDEX_ACTIONS = {
	['save'] = addInstanceToIndexOnRule,
	['update'] = updateInstanceToIndexOnRule,
	['del'] = delInstanceToIndexOnRule
}

local updateIndexByRules = function (self, action)
	local manager_key = rule_manager_prefix .. self.__name
	local qstr_list = db:zrange(manager_key, 0, -1)
	local action_func = INDEX_ACTIONS[action]
	for _, qstr in ipairs(qstr_list) do
		action_func(self, qstr)
	end
end

-- can be reentry
local addIndexToManager = function (self, query_str_iden, obj_list)
	local manager_key = rule_manager_prefix .. self.__name
	-- add to index manager
	local score = db:zscore(manager_key, query_str_iden)
	-- if score then return end
	local new_score
	if not score then
		-- when it is a new rule 
		new_score = db:zcard(manager_key) + 1
		-- use float score represent empty rule result index
		if #obj_list == 0 then new_score = new_score + 0.1 end
		db:zadd(manager_key, new_score, query_str_iden)
	else
		-- when rule result is expired, re enter this function
		new_score = score
	end
	if #obj_list == 0 then return end
	
	local item_key = rule_result_pattern:format(self.__name, math.floor(new_score))
	local options = { watch = item_key, cas = true, retry = 2 }
	db:transaction(options, function(db)
		if not db:exists(item_key) then
			-- generate the index item, use list
			db:rpush(item_key, unpack(obj_list))
		end
		-- set expiration to each index item
		db:expire(item_key, bamboo.config.rule_expiration or bamboo.RULE_LIFE)
	end)
end

local getIndexFromManager = function (self, query_str_iden, getnum)
	local manager_key = rule_manager_prefix .. self.__name
	-- get this rule's socre
	local score = db:zscore(manager_key, query_str_iden)
	-- if has no score, means it is not rule indexed, 
	-- return nil directly
	if not score then 
		return nil
	end
	
	-- if score is float, means its rule result is empty, return empty query set
	if score % 1 ~= 0 then
		return (not getnum) and List() or 0
	end
	
	-- score is integer, not float, and rule result doesn't exist, means its rule result is expired now,
	-- need to retreive again, so return nil
	local item_key = rule_result_pattern:format(self.__name, score)
	if not db:exists(item_key) then 
		return nil
	end
	
	-- update expiration
	db:expire(item_key, bamboo.config.rule_expiration or bamboo.RULE_LIFE)
	-- rule result is not empty, and not expired, retrieve them
	if not getnum then
		-- return a list
		return List(db:lrange(item_key, 0, -1))
	else
		-- return the number of this list
		return db:llen(item_key)
	end
end


