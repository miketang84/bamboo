--
-- in this version, we use luamongo as our low level
-- 
module(..., package.seeall)


local mongo = require "mongo"

local QueryOption_SlaveOk = 4





local function cursor_all(cursor)
    local results = {}
    for r in cursor:results() do
        table.insert(results, r)
    end
    
    return results
end

-- XXX: can this work?
local addAttachMethod2Cursor = function (cursor)
    local cursor_mt = getmetatable(cursor)
    local up_mt = cursor_mt.__index
    
    -- add function all
    up_mt.all = cursor_all
    
end
    
    


local find = function (self, ns, query, fieldsToReturn, nToSkip, nToReturn, queryOptions, batchSize)
    assert(type(ns) == 'string')
    
    if self.secondary then
        local bit = require("bit")
        if queryOptions then
            queryOptions = bit.bor(queryOptions, QueryOption_SlaveOk)
        else
            queryOptions = QueryOption_SlaveOk
        end
    end

    local cursor, err = self.conn:query(self.db..'.'..ns, query, nToReturn, nToSkip, fieldsToReturn, queryOptions, batchSize)
    if err then print(err) end

    addAttachMethod2Cursor(cursor)

    return cursor

end

local findOne = function (self, ns, query, fieldsToReturn, nToSkip, queryOptions, batchSize)
    
    local cursor = find(self, ns, query, fieldsToReturn, nToSkip, queryOptions, batchSize)
    local result = cursor:next()

    -- XXX: need to notice whether it is nil when none found
    return result

end


local insert = function (self, ns, doc)
    local ns = self.db..'.'..ns
    local ok, err = self.conn:insert(ns, doc)
    
    -- XXX: need disturb or continue??
    if err then print(err) end

    return ok

end


local insert_batch = function (self, ns, docs)
    local ns = self.db..'.'..ns
    local ok, err = self.conn:insert_batch(ns, docs)
    
    -- XXX: need disturb or continue??
    if err then print(err) end

    return ok

end


local update = function (self, ns, query, modifier, upsert, multi)
    local ns = self.db..'.'..ns
    local ok, err = self.conn:update(ns, query, modifier, upsert, multi)

    -- XXX: need disturb or continue??
    if err then print(err) end

    return ok
end

local remove = function (self, ns, query, justOne)
    local ns = self.db..'.'..ns
    local ok, err = self.conn:remove(ns, query, justOne)

    -- XXX: need disturb or continue??
    if err then print(err) end

    return ok
end


local count = function (self, ns, query)
    local ns = self.db..'.'..ns
    local count, err = self.conn:count(ns, query)
    
    -- XXX: need disturb or continue??
    if err then print(err) end

    return count
end



-- useage:
-- local mongo = require 'bamboo.db.mongo'
-- local conn = mongo.connect(mongo_config)
-- local db = conn:use('one_db_name')
-- 
function _connect(config)
    assert(type(config) == 'table', 'missing config in mongo.connect')
    local host = config.host
    local port = config.port
    local dbname = config.db
    local conn_str = host..':'..port

    -- Create a Connection object
    local conn = mongo.Connection.New({auto_reconnect = true})
    assert( conn ~= nil, 'unable to create mongo.Connection' )
    assert( conn:connect(conn_str), 'unable to forcefully connect to mongo instance' )

    if config.user and config.user ~= '' then
        --assert( conn:auth { dbname = 'admin', username = config.user, password = config.password } == true, "unable to auth to db" )
        assert( conn:auth { dbname = dbname, username = config.user, password = config.password } == true, "unable to auth to db" )
    end

    return conn
end

function _connect_replica_set(config)
    assert(type(config) == 'table', 'missing config in mongo.connect')
    local set = config.set
    assert(set, 'missing set in replica set connect.')
    local dbname = config.db
    -- ensure replicaset is a host:port array
    local replicaset = config.replicaset

    -- Create a Connection object
    local conn = mongo.ReplicaSet.New(set, replicaset)
    assert( conn ~= nil, 'unable to create mongo.ReplicaSetConnection' )
    assert( conn:connect(), 'unable to forcefully connect to mongo instance' )
   
	print(conn)

    if config.user and config.user ~= '' then
        --assert( conn:auth { dbname = 'admin', username = config.user, password = config.password } == true, "unable to auth to db" )
        assert( conn:auth { dbname = dbname, username = config.user, password = config.password } == true, "unable to auth to db" )
    end
	print('db ', dbname, config.user, config.password, 'authored success.')

    return conn
end


-- mongodb methods metatable
local _mt_db = {
    find = find,
    findOne = findOne,
    insert = insert,
    insert_batch = insert_batch,
    update = update,
    remove = remove,
    count = count
}



function connect (config)
    assert(type(config) == 'table', 'missing config in mongo.connect')
    config.db = config.db or 'test'
    local replicaset = config.replicaset
    
    local db = {}
    -- attach all methods to db
    setmetatable(db, { __index = _mt_db })
    local conn
    if replicaset then
        conn = _connect_replica_set(config)
    else
		config.host = config.host or '127.0.0.1'
		config.port = config.port or '27017'
        conn = _connect(config)
    end
    
    for k, v in pairs(config) do
        db[k] = v
    end
    -- add db instance to db
    db.conn = conn
    
    return db
end

function connectReplSet(config, username, password, secondary)
	assert(config, "connectReplSet config null");
	assert(config.primary, "connectReplSet config.primary");

	local primary_str = config.primary.host..':'..config.primary.port
	local second_strs = {}
	if config.secondaries then
		for i, s in ipairs(config.secondaries) do
			second_strs[i] = s.host..':'..s.port
		end
	end

	local replicaset = {primary_str}	
	for i=1, #second_strs do
		table.insert(replicaset, second_strs[i])
	end

	local newconfig = {
        set = config.set,
		db = config.dbname,
		user = username,
		password = password,
		replicaset = replicaset,
        secondary = secondary
	}

	return connect(newconfig)
end


function connectPrimary(config, username, password)
	assert(config, "connectReplSet config null");
	assert(config.primary, "connectReplSet config.primary");


	local newconfig = {
		host = config.primary.host,
		port = config.primary.port,
		db = config.dbname,
		user = username,
		password = password
	}

	return connect(newconfig)
end


function connectSecondary(config, username, password)
	assert(config, "connectReplSet config null");
	assert(config.primary, "connectReplSet config.primary");

    return connectReplSet(config, username, password, true);
end


