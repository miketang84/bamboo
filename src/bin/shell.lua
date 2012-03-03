#!/usr/bin/lua
require 'bamboo'

local redis = require 'bamboo.redis'

-- load configuration
local config = {}

local function readSettings()
	-- only support boot in app directory
	local home = os.getenv("HOME")
	local global_configfile = loadfile(home + '/.bambooconfig')
	if global_configfile then
		setfenv(assert(global_configfile), config)()
	else
		print [[
[Error] You should make sure the existance of ~/.bambooconfig 

You can use:
	bamboo config -monserver_dir your_monserver_dir
	bamboo config -bamboo_dir your_bamboo_dir

to create this config file. Good Luck.
]]
		os.exit()
	end
	
	-- try to load settings.lua 
	local setting_file = loadfile('settings.lua') or loadfile('../settings.lua')
	if setting_file then
		setfenv(assert(setting_file), config)()
	end
	config.bamboo_dir = config.bamboo_dir or '/usr/local/share/lua/5.1/bamboo/'

	-- check whether have a global production setting
	local production = loadfile('/etc/bamboo_production')
	if production then
		config.PRODUCTION = true
	end

end

readSettings()
ptable(config)

local DB_HOST = config.DB_HOST or arg[1] or '127.0.0.1'
local DB_PORT = config.DB_PORT or arg[2] or '6379'
local WHICH_DB = config.WHICH_DB or arg[3] or 0
local AUTH = config.AUTH

db = redis.connect {host=DB_HOST, port=DB_PORT, which = WHICH_DB, auth=AUTH}
-- make model.lua work
BAMBOO_DB = db

-- add this project's initial register work to global evironment
setfenv(assert(loadfile('app/handler_entry.lua') or loadfile('../app/handler_entry.lua')), _G)()

print('Entering bamboo shell.... OK')
return true
