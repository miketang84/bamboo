------------------------------------------------------------------------
-- Bamboo is a Lua web framework
--
-- Bamboo is BSD licensed the same as Mongrel2.
------------------------------------------------------------------------

package.path = package.path .. './?.lua;./?/init.lua;../?.lua;../?/init.lua;'
require 'lglib'

module('bamboo', package.seeall)

URLS = {}

------------------------------------------------------------------------
PLUGIN_LIST = {}

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
------------------------------------------------------------------------

MODULE_LIST = {}
-- 
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
			
			local function actionTransform(web, req)
				if type(action) == 'function' then
					return action
				elseif type(action) == 'table' then
					local fun = action.handler
					checkType(fun, 'function')
					
					return function (web, req)
						local filter_flag, permission_flag = true, true
						if action.filters then
							checkType(action.filters, 'table')
							
							filter_flag = true
							-- execute all filters bound to this handler
							for _, filter_name in ipairs(action.filters) do
								local name_part, args_part = filter_name:trim():match("^(%w+):? *([%w ]*)")
								local args_list = {}
								if args_part then
									args_list = args_part:trim():split(' +')
								end
								local filter = getFilterByName(name_part)
								-- if filter is invalid, ignore it
								if filter then 
									local ret = filter(args_list)
									if not ret then 
										filter_flag = false 
										print(("[Warning] Filter list was broken at %s"):format(filter_name))
										break 
									end
								end
							end
							
						end
					
						if action.perms then
							checkType(action.perms, 'table')
							-- TODO
							--
						end
					
						if filter_flag == true and permission_flag == true then
							-- after execute filters and permissions check, pass here, then execute this handler
							return fun(web, req)
						else
							return false
						end
					end
				end
			end
			
			if mdl.init and type(mdl.init) == 'function' and not exclude_flag then
				nfun = function (web, req)
					local ret = mdl.init(extra_params)
					if ret then
						return actionTransform(web, req)(web, req)
					end
					
					-- make no sense
					return false
				end
			else
				nfun = actionTransform(web, req)
			end

			URLS[nurl] = nfun
		end
	end
end

------------------------------------------------------------------------
MODEL_LIST = {}

local function getClassName(model)
	return model.__tag:match('%.(%w+)$')
end

registerModel = function (model)
	checkType(model, 'table')
	assert( model.__tag, 'Registered model __tag must not be missing.' )
	
	MODEL_LIST[getClassName(model)] = model
end

getModelByName = function (name)
	checkType(name, 'string')
	assert(MODEL_LIST[name], ('[ERROR] This model %s is not registered!'):format(name))
	return MODEL_LIST[name]
end

------------------------------------------------------------------------
FILTER_LIST = {}

registerFilter = function ( filter_name, filter_func)
	checkType(filter_name, filter_func, 'string', 'function')
	
	FILTER_LIST[filter_name] = filter_func
end

getFilterByName = function ( filter_name )
	checkType(filter_name, 'string')
	
	local filter = FILTER_LIST[filter_name]
	if not filter then
		print(("[Warning] This filter %s is not registered!"):format(filter_name))
	end
	
	return filter
end



------------------------------------------------------------------------
-- MENUS is a list，rather than dict。every list item has a dict in it
--MENUS = {}

---- here, menu_item probaly is item，or item list
--registerMenu = function (menu_item)
	--checkType(menu_item, 'table')
	
    -- if it is a signle item
 	--if menu_item['name'] then
		---- 
		--table.append(MENUS, menu_item)
	--else
	---- 
		--for i, v in ipairs(menu_item) do
			--table.append(MENUS, v)
		--end
	--end
--end



