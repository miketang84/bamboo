module(..., package.seeall)

local pluto = require 'pluto'

local PLUGIN_ARGS_DBKEY = "_plugin_args"

function persist(plugin_name, args)
	assert(plugin_name, "[Error] @ plugin persist - missing plugin_name.")
	assert(type(args) == 'table', "[Error] @plugin persist - #2 args should be table.")
	assert(type(args._tag) == 'string', "[Error] @plugin persist - args._tag should be string.")

	-- use pluto to persist
	local buf = pluto.persist({}, args)
	
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
	
	return tbl
end
