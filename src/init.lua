------------------------------------------------------------------------
-- Bamboo is a Lua web framework
--
-- Bamboo is BSD licensed.
------------------------------------------------------------------------

--package.path = package.path .. './?.lua;./?/init.lua;../?.lua;../?/init.lua;'
require 'lglib'

module('bamboo', package.seeall)

local Set = require 'lglib.set'
local List = require 'lglib.list'
local FieldType = require 'bamboo.mvm.prototype'
require 'bamboo.globals'
local cmsgpack = require 'cmsgpack'

config = {}
-- for global rendering usage
context = {}
dbs = {}
userdata = {}
plugindata = {}
internal = {}
compiled_views_tmpls = {}
compiled_views = {}
compiled_views_locals = {}

WIDGETS = {}
require 'bamboo.widget'

-- for session life time
SESSION_LIFE = 3600 * 24
-- for cache life time
CACHE_LIFE = 1800
-- for rule index life time
RULE_LIFE = 1800
-- for plugin args life time
PLUGIN_ARGS_LIFE = 3600

-- global URLS definition
URLS = {}
PATTERN_URLS = {}
------------------------------------------------------------------------

--pubToCluster = function (msg_obj)
--	bamboo.cluster_channel_pub:send(cmsgpack.pack(msg_obj))
--end

------------------------------------------------------------------------
PLUGIN_LIST = {}
PLUGIN_CALLBACKS = {}

registerPlugin = function (name, mdl)
	checkType(name, mdl, 'string', 'table')
	assert( name ~= '', 'Plugin name must not be blank.' )
	assert( mdl.main, 'Plugin must have a main function.' )
	checkType( mdl.main, 'function' )
	
	PLUGIN_LIST[name] = mdl.main
	
	-- combine URLS in each module to the global URLS
	if mdl['URLS'] then
		table.update(URLS, mdl.URLS)
	end	
end


--registerPluginCallback = function (name, callback)
--	checkType(name, callback, 'string', 'function')
--	assert( name ~= '', 'Plugin callback name must not be blank.' )
--	
--	if PLUGIN_CALLBACKS[name] then
--		print('[Warning] This callback name:"'.. name ..'" has been used')
--	end
--	PLUGIN_CALLBACKS[name] = callback
--	
--end
--
--getPluginCallbackByName = function (name)
--	checkType(name, 'string')
--	return PLUGIN_CALLBACKS[name]
--end

------------------------------------------------------------------------

local function parseFilterName( filter_name )
	local name_part, args_part = filter_name:trim():match("^([%w_]+):? *([%w_ /%-%.]*)")
	local args_list = {}
	if args_part and args_part ~= '' then
		args_list = args_part:trim():split(' +')
	end
	
	filter = getFilterByName(name_part)
	return filter, args_list
end



MODULE_LIST = {}
-- 

local function permissionCheck(action_perms, perms)
	if #perms > 0 then
		local perm_list = {}
		for _, perm in ipairs(perms) do
			perm_list[#perm_list + 1] = perm.name
		end
		
		local perms_setA = Set(perm_list)
		local perms_setB = Set(action_perms)
		local flag, diff_elem = perms_setB:isSub(perms_setA)
		
		if flag then
			-- if action permissions are contained by given permissions
			-- execute success function
			-- TODO
			local ret = nil
			for _, perm_name in ipairs(action_perms) do
				local perm_do = getPermissionByName(perm_name)
				if not perm_do then
					print(('[Warning] This permission %s is not registered.'):format(perm_name))
				elseif perm_do and perm_do.success_func then
					ret = perm_do.success_func()
					-- once one permission success function return false
					-- jump out
					if not ret then
						print(('[Prompt] permission check chains was broken at %s'):format(perm_name))
						return false
					end
				end
			end
			
			return true
		else
			-- execute failure function
			local perm_not_fit = getPermissionByName(diff_elem)
			if perm_not_fit and perm_not_fit.failure_func then
				print(('[Prompt] enter failure function %s.'):format(diff_elem))
				perm_not_fit.failure_func()
			end

			return false
		end
	else
		print('[Prompt] No permissions in the given list.')
		local perm_not_fit = getPermissionByName(action_perms[1])
		if perm_not_fit and perm_not_fit.failure_func then
			print(('[Prompt] enter failure function %s.'):format(action_perms[1]))
			perm_not_fit.failure_func()
		end

		return false				
	end
end

local function actionTransform(web, req, action)
	if type(action) == 'function' then
		return action
	elseif type(action) == 'table' then
		local fun = table.remove(action)
		checkType(fun, 'function')
		
		return function (web, req, inited_params)
			local propagated_params = inited_params or {}
			local ret
			-- check filters
			local action_filters = action
			if action_filters and #action_filters > 0 then
				-- execute all filters bound to this handler
				for i, filter_func in ipairs(action_filters) do
          ret, propagated_params = filter_func(web, req, propagated_params)
          if not ret then 
            print(("[Warning] MiddleWare chains was broken at %s."):format(i))
            return nil
          end
				end
			end
			
			-- execute handler
			-- after execute filters and permissions check, pass here, then execute this handler
			local ret, propagated_params = fun(web, req, propagated_params)
						
			-- return from lua function
			return ret, propagated_params
		end
	else
		error("Handler must be function or middleware chains.", 2)
	end
end


registerModule = function (mdl, extra_params)
	checkType(mdl, 'table')
	
	if mdl.URLS then
		checkType(mdl.URLS, 'table')
		
		for url, action in pairs(mdl.URLS) do
			local nurl = ''
			if (url == '/' or not url:startsWith('/')) and mdl._NAME then
				-- print(url)
				-- make the relative url pattern to absolute url pattern
				local module_name = mdl._NAME:match('%.([%w_]+)$')
				nurl = ('/%s/%s'):format(module_name, url)
				-- print(nurl)
			else
				nurl = url
			end
			
			local nfun
			local exclude_flag = false
			if extra_params then
				checkType(extra_params, 'table')
				if extra_params['excludes'] then
				-- add exceptions to module's init function
					for _, exclude in ipairs(extra_params['excludes']) do
						if exclude == url then
							exclude_flag = true
						end
					end
				end
			end
			
			if mdl.init and type(mdl.init) == 'function' and not exclude_flag then
				nfun = function (web, req)
					local ret, inited_params = mdl.init(web, req, extra_params or {})
					if not ret then
            print(format("[Warning] chains aborted after module %s's init.", mdl._NAME or ''))
          end
					local finished_params
					local last_params
					if ret then
						ret, finished_params = actionTransform(web, req, action)(web, req, inited_params)
					end
					if not ret and mdl.finish then
            print("[Warning] chains aborted after handler: ", url)
          end

					
					if ret and mdl.finish and type(mdl.finish) == 'function' then
						ret, last_params = mdl.finish(web, req, finished_params)
					end
					
					-- make no sense
					return ret, last_params or finished_params or inited_params
				end
      
      -- no init function, but have finish function
			elseif mdl.finish and type(mdl.finish) == 'function' and not exclude_flag then
				nfun = function (web, req)
					local ret, finished_params = actionTransform(web, req, action)(web, req, extra_params)

					local last_params
					if ret then
						ret, last_params = mdl.finish(web, req, finished_params)
					end
					
					-- make no sense
					return ret, last_params or finished_params
				end
			else
				nfun = actionTransform(web, req, action)
			end

			URLS[nurl] = nfun
		end
	end
end

------------------------------------------------------------------------
MODEL_LIST = {}

registerModel = function (model)
	checkType(model, 'table')
	assert( model.__name, 'Registered model __name must not be missing.' )
	local model_name = model.__name

	if MODEL_LIST[model_name] then
		print('[Warning] The same __name model had been registered.')
		return
	else
		MODEL_LIST[model_name] = model

		-- set metatable for each field
		for field, fdt in pairs(model.__fields) do
			setmetatable(fdt, {__index = FieldType[fdt.widget_type or 'text']})
			fdt:init()
		end
		
		-- check if ask fulltext index
		model['__fulltext_index_fields'] = {}
		for key, field_dt in pairs(model.__fields) do
			if field_dt.fulltext_index == true then
				model['__use_fulltext_index'] = true
				table.insert(model.__fulltext_index_fields, key)
			end			
		end
		

		-- decorators
		if not isFalse(model.__decorators) then
			if not rawget(model, '__decorators') then
				model.__decorators={}
			end
			model.__decorators.__foontprint={}
			-- Counter to avoid endless recursion
			local function footprintfunc(func, k)
				return
				function(self, ...)
					local fp = model.__decorators.__foontprint
					local key = tostring(self.id or select(1, ...)) .. tostring(k) --tostring(func)
					local ret
					if not fp[key] then
						fp[key] = true
						ret = func(self, ...)
					end
					fp[key] = nil
					return ret
				end
			end
			
			local decoratorSet = Set{'update', 'save', 'del', 'addForeign', 'delForeign', 'getById'}
			
			local p = model
			repeat
				p = p._parent
				if p.__name ~= 'Model' then
					registerModel(p)
				end
			until p.__name == 'Model' or not p

			for k, v in pairs(rawget(model, '__decorators') or {}) do
				if decoratorSet:has(k) then
					-- add decorator wrapper function to model self
					model[k] = footprintfunc(v(model[k]), k)
				end
			end
			
		end
	
	end
end

getModelByName = function (name)
	checkType(name, 'string')
	assert(MODEL_LIST[name], ('[ERROR] This model %s is not registered!'):format(name))
	return MODEL_LIST[name]
end

bamboo.MAIN_USER = nil
registerMainUser = function (mdl, extra_params)
	registerModel (mdl, extra_params)
	bamboo.MAIN_USER = mdl
end;

------------------------------------------------------------------------
--FILTER_LIST = {}
--
--registerFilter = function ( filter_name, filter_func)
--	checkType(filter_name, filter_func, 'string', 'function')
--	
--	assert(not FILTER_LIST[filter_name], "[Error] This filter name has been registerd.")
--	
--	FILTER_LIST[filter_name] = filter_func
--end
--
--getFilterByName = function ( filter_name )
--	checkType(filter_name, 'string')
--	
--	local filter = FILTER_LIST[filter_name]
--	if not filter then
--		print(("[Warning] This filter %s is not registered!"):format(filter_name))
--	end
--	
--	return filter
--end
--
--
-- used mainly in entry file and each module's initial function
-- @filters   
--executeFilters = function ( filters, params )
--	checkType(filters, 'table')
--	params = params or {}
--	for _, filter_name in ipairs(filters) do
--		local filter, args_list = parseFilterName(filter_name)
--		if filter then
--			-- now filter has no extra parameters
--			local ret, params = filter(args_list, params)
--			if not ret then
--				print(("[Warning] Filter chains was broken at %s."):format(filter_name))				
--				return false
--			end
--		end
--	end
--	return true, params
--end
--
--registerFilters = function (filter_table)
--	checkType(filter_table, 'table')
--	for _, filter_define in ipairs(filter_table) do
--		-- 1. name, 2. func
--		registerFilter(filter_define[1], filter_define[2])
--	end
--end

------------------------------------------------------------------------
PERMISSION_LIST = {}

function executePermissionCheck(perms)
	local permission_flag = true
	local user = req.user
	if user then
		-- check the user's permissions
		if user.perms then
			local user_perms = user:getForeign('perms')
			permission_flag = permissionCheck(perms, user_perms)	
			
		end
		
		-- check groups' permissions
		if user.groups then
			local groups = user:getForeign('groups')
			for _, group in ipairs(groups) do
				if group then
					if group.perms then
						local group_perms = group:getForeign('perms')
						local ret = permissionCheck(perms, group_perms)
						-- once a group's permissions fit action_perms, return true
						if ret then permission_flag = true; break end
					end
				end
			end
		end
		
		return permission_flag
	end
end


registerPermission = function (name, desc, failure_func, success_func)
	local Permission = require 'bamboo.models.permission'
	checkType(name, 'string')
	local desc = desc or ''
	if failure_func then
		checkType(failure_func, 'function')
	end
	
	if success_func then
		checkType(success_func, 'function')
	end

	Permission:add(name, desc)
	PERMISSION_LIST[name] = {
		name = name,
		desc = desc,
		failure_func = failure_func,
		success_func = success_func
	}

end

registerPermissions = function (perm_t)
	checkType(perm_t, 'table')
	for _, perm_params in ipairs(perm_t) do
		registerPermission(perm_params[1], perm_params[2], 
			perm_params[3], perm_params[4])
	end

end

getPermissionByName = function (name)
	checkType(name, 'string')
	
	return PERMISSION_LIST[name]
end

