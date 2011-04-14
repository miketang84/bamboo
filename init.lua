------------------------------------------------------------------------
-- Bamboo is a Lua web framework
--
-- Bamboo is BSD licensed the same as Mongrel2.
------------------------------------------------------------------------

package.path = package.path .. './?.lua;./?/init.lua;../?.lua;../?/init.lua;'
require 'lglib'

module('bamboo', package.seeall)

------------------------
-- 加载子模块
------------------------

--require 'bamboo.errors'
--require 'bamboo.redis'
------------------------
-- 加载类。由于是类，所以将其名称重命名为大写开头
------------------------
--Session = require 'bamboo.session'
--View = require 'bamboo.view'
--Web = require 'bamboo.web'
--Form = require 'bamboo.form'

------------------------
-- 一些辅助函数
------------------------

------------------------------------------------------------------------
-- 创建全局URLS
URLS = {}
-- 创建全局插件列表结构
PLUGIN_LIST = {}

registerPlugin = function (name, mdl)
	checkType(name, mdl, 'string', 'table')
	assert( name ~= '', 'Plugin name must not be blank.' )
	assert( mdl.main, 'Plugin must have a main function.' )
	checkType( mdl.main, 'function' )
	
	PLUGIN_LIST[name] = mdl.main
	print(name, PLUGIN_LIST[name])
	
	-- 将插件中的URL定义融合进来
	if mdl['URLS'] then
		table.update(URLS, mdl.URLS)
	end	
end
------------------------------------------------------------------------

------------------------------------------------------------------------
-- 创建全局模型注册列表结构
MODEL_MANAGEMENT = {}

registerModel = function (name, model)
	checkType(name, model, 'string', 'table')
	assert( name ~= '', 'Registed model name must not be blank.' )
	
	MODEL_MANAGEMENT[name] = model
	print(name, MODEL_MANAGEMENT[name])

end

getModelByName = function (name)
	assert(MODEL_MANAGEMENT[name], ('[ERROR] This model %s is not registered!'):format(name))
	return MODEL_MANAGEMENT[name]
end

------------------------------------------------------------------------

------------------------------------------------------------------------
-- 创建全局模型注册列表结构
-- MENUS是一个list，而不是一个dict。每一个list item下面则是dict
--MENUS = {}

---- 这里，menu_item有可能是一个item，也有可能是一个item列表
--registerMenu = function (menu_item)
	--checkType(menu_item, 'table')
	
	---- 如果是单个item
	--if menu_item['name'] then
		---- 这里，把新定义的menu item添加到总的menu列表中去
		--table.append(MENUS, menu_item)
	--else
	---- 如果是一个item列表
		--for i, v in ipairs(menu_item) do
			--table.append(MENUS, v)
		--end
	--end
--end

-- 菜单注册，应该有一个生成器，从lua表直接生成若干对象到数据库去
-- 放在bamboo的启动脚本里面去服务启动时自动生成
------------------------------------------------------------------------






