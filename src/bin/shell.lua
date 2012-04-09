#!/usr/bin/lua
require 'bamboo'

local redis = require 'bamboo.redis'
local util = require 'bamboo.util'

-- load configuration
local config = util.readSettings(bamboo.config)
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
