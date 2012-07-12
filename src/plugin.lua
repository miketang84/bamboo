module(..., package.seeall)

local pluto = require 'pluto'

local PLUGIN_ARGS_DBKEY = "_plugin_args"

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
			res[k] = '__function__' .. string.dump(v)
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
			tbl[k] = loadstring(v:sub(13, -1))
		end
	end
	return tbl
end

function persist(plugin_name, args)
	assert(plugin_name, "[Error] @ plugin persist - missing plugin_name.")
	assert(type(args) == 'table', "[Error] @plugin persist - #2 args should be table.")
	assert(type(args._tag) == 'string', "[Error] @plugin persist - args._tag should be string.")

	-- use pluto to persist
	-- here, must use deepCopy to remove all the metatables in args
	-- pluto now can not process those metatables correctly, will report "[Error] Attempt to persist a C function."
	local buf = pluto.persist({}, deepCopyWithModelName(args))
	
	-- store to db
	local db = BAMBOO_DB
	db:hset(PLUGIN_ARGS_DBKEY, format("%s:%s", plugin_name, args._tag), buf)
	
end

function unpersist(plugin_name, _tag)
	assert(plugin_name, "[Error] @ plugin unpersist - missing plugin_name.")
	assert(type(_tag) == 'string', "[Error] @plugin unpersist - #2 _tag should be string.")

	local db = BAMBOO_DB
	local buf = db:hget(PLUGIN_ARGS_DBKEY, format("%s:%s", plugin_name, _tag))
	local tbl = pluto.unpersist({}, buf)
	assert(type(tbl) == 'table', "[Error] @plugin unpersist - unpersisted result should be table.")
	tbl = table2model(tbl)
	return tbl
end
