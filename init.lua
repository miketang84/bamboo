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



