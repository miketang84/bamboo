module(..., package.seeall)

local cmsgpack = require 'cmsgpack'

local PLUGIN_ARGS_DBKEY = "_plugin_args:%s:%s"

local function collectUpvalues(func)
	local upvalues = {}
	for i=1, math.huge do
		local name, v = debug.getupvalue(func, i)
		if not name then break end
		local ctype = type(v)
		local table_has_metatable = false
		if ctype == 'table' then
			table_has_metatable = getmetatable(v) and true or false
		end
		-- because we could not collect the upvalues whose type is 'table', print warning here
		if type(v) == 'function' or table_has_metatable then
			print"[Warning] @collectUpvalues in plugin - bamboo has no ability to collect the function upvalue whose type is 'function' or 'table' with metatable."
			return false
		end

		if ctype == 'table' then
			upvalues[#upvalues + 1] = { name, serialize(v), type(v) }
		else
			upvalues[#upvalues + 1] = { name, tostring(v), type(v) }
		end
	end

	return upvalues
end

local function restoreFunction(func_str) 
	
	local dstart, dstop = func_str:find(' |^|^| ')
	local func_part = func_str:sub(13, dstart - 1)
	local up_part = func_str:sub(dstop+1, -1)
	-- now fpart is the function binary string
	local func = loadstring(func_part)
	-- now query_args is query function
	if func and not isFalse(up_part) then
		-- item 1 is key, item 2 is value, item 3 is value type, item 4 is key ....
		local flat_upvalues = up_part:split(' ^_^ ')
		for i=1, #flat_upvalues / 3 do
			local vtype = flat_upvalues[3*i]
			local key = flat_upvalues[3*i - 2]
			local value = flat_upvalues[3*i - 1]
			if vtype == 'table' then
				value = deserialize(value)
			elseif vtype == 'number' then
				value = tonumber(value)
			elseif vtype == 'boolean' then
				value = loadstring('return ' .. value)()
			elseif vtype == 'nil' then
				value = nil
			end
			-- set upvalues
			debug.setupvalue(func, i, value)
		end
	end
	
	return func
end

function deepCopyWithModelName(self, seen)
	local res = {}
	seen = seen or {}
	seen[self] = res
	
	if self.__spectype then
		res.__spectype = self.__spectype
	else
		if self.classname then
			res.__name = self:classname()
		else
			if self.__typename then
				res.__typename = self.__typename
			end		
		end
	end

	for k, v in pairs(self) do
		if "table" == type(v) then
			if seen[v] then
				res[k] = seen[v]
			else
				res[k] = deepCopyWithModelName(v, seen)
			end
		elseif "function" == type(v) then
			local upvalues = collectUpvalues(v)
			local tmp = {}
			for _, upvalue in ipairs(upvalues) do
				table.insert(tmp, table.concat(upvalue, ' ^_^ '))
			end
			local upvalue_str = table.concat(tmp, ' ^_^ ')
			res[k] = '__function__' .. string.dump(v) .. " |^|^| " .. upvalue_str
		else
			res[k] = v
		end
	end
	seen[self] = nil

	return res
end

function table2model(tbl)
	if tbl.__name then
		local model = bamboo.getModelByName(tbl.__name)
		--ptable(getmetatable(medel))
		tbl.__name = nil
		--tbl = model(tbl)
		setmetatable(tbl, {__index=model})
	end
	if tbl.__typename then
		tbl.__typename = nil
		tbl = List(tbl)
	end
	if tbl.__spectype then
		tbl.__spectype = nil
		tbl = QuerySet(tbl)
	end
	for k,v in pairs(tbl) do
		if type(v) == 'table' then
			tbl[k] = table2model(v)
		elseif type(v) == 'string' and v:startsWith('__function__') then
			tbl[k] = restoreFunction(v)
		end
	end
	return tbl
end

function persist(plugin_name, args)
	assert(plugin_name, "[Error] @ plugin persist - missing plugin_name.")
	assert(type(args) == 'table', "[Error] @plugin persist - #2 args should be table.")
	assert(type(args._tag) == 'string', "[Error] @plugin persist - args._tag should be string.")

	-- use cmsgpack to persist
	-- here, must use deepCopy to remove all the metatables in args
	-- cmsgpack now can not process those metatables correctly, will report "[Error] Attempt to persist a C function."
	-- local buf = cmsgpack.pack({}, deepCopyWithModelName(args))
	local ok, buf = pcall(cmsgpack.pack, {}, deepCopyWithModelName(args))
	if not ok then 
		return print(format('[Warning] plugin %s: arguments persisting failed.', plugin_name))
	end
	-- store to db
	local db = BAMBOO_DB
	local key = format(PLUGIN_ARGS_DBKEY, plugin_name, args._tag)
	db:set(key, buf)
	db:expire(key, bamboo.config.plugin_args_life or bamboo.PLUGIN_ARGS_LIFE)
	
end

function unpersist(plugin_name, _tag)
	assert(plugin_name, "[Error] @ plugin unpersist - missing plugin_name.")
	assert(type(_tag) == 'string', "[Error] @plugin unpersist - #2 _tag should be string.")

	local db = BAMBOO_DB
	local buf = db:get(format(PLUGIN_ARGS_DBKEY, plugin_name, _tag))
	-- local tbl = cmsgpack.unpersist({}, buf)
	if not buf then return {} end
	
	local ok, tbl = pcall(cmsgpack.unpack, {}, buf)
	if not ok then 
		return print(format('[Warning] plugin %s: arguments unpersisting failed.', plugin_name))
	end
	
	assert(type(tbl) == 'table', "[Error] @plugin unpersist - unpersisted result should be table.")
	tbl = table2model(tbl)
	return tbl
end
