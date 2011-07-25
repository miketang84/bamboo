------------------------------------------------------------------------
-- Bamboo is a Lua web framework
--
-- Bamboo is BSD licensed the same as Mongrel2.
------------------------------------------------------------------------

package.path = package.path .. './?.lua;./?/init.lua;../?.lua;../?/init.lua;'
require 'lglib'

module('bamboo', package.seeall)

------------------------------------------------------------------------
URLS = {}
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


-- 
-- 
-- 
registerModule = function (mdl, extra_params)
	checkType(mdl, 'table')
	
	if mdl.URLS then
		checkType(mdl.URLS, 'table')
		
		for url, fun in pairs(mdl.URLS) do
			local nurl = ''
			if url == '/' or not url:startsWith('/') then
				print(url)
				-- make the relative url pattern to absolute url pattern
				local module_name = mdl._NAME:match('%.([%w_]+)$')
				nurl = ('/%s/%s'):format(module_name, url)
				print(nurl)
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
					local ret = mdl.init(extra_params)
					if ret then
						return fun(web, req)
					end
					
					return false
				end
			else
				nfun = fun
			end

			URLS[nurl] = nfun
		end
	end
end

------------------------------------------------------------------------
MODEL_MANAGEMENT = {}

local function getClassName(model)
	return model.__tag:match('%.(%w+)$')
end

registerModel = function (model)
	checkType(model, 'table')
	assert( model.__tag, 'Registered model __tag must not be missing.' )
	
	MODEL_MANAGEMENT[getClassName(model)] = model
end

getModelByName = function (name)
	checkType(name, 'string')
	assert(MODEL_MANAGEMENT[name], ('[ERROR] This model %s is not registered!'):format(name))
	return MODEL_MANAGEMENT[name]
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



