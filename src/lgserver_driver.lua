--module(..., package.seeall)
local driver = {}

local json = require 'cjson'
local zmq = require 'zmq'
local cmsgpack = require 'cmsgpack'

local insert, concat = table.insert, table.concat
local format = string.format

local Connection = {}
local Connection_meta = {__index = Connection}

-- data structure return to lgserver
-- data is string
-- extra is table
-- conns: a list of connection keys
local function wrap(data, code, status, headers, conns, meta)
	local ret = {
		data = data or '',  			-- body string to reply
		code = code or 200,				-- http code to reply
		status = status or "OK",		-- http status to reply
		headers = headers or {},		-- http headers to reply
		conns = conns or {},			-- http connections to receive this reply
		meta = meta or {}				-- some other info to lgserver
	}

	return cmsgpack.pack(ret)
end


--[[
    Receives a raw lgserver.request object that you can then work with.
    Upon error while parsing the data, returns nil and an error message.
]]
function Connection:recv()
	local reqstr, err = self.channel_req:recv()
	local req = cmsgpack.unpack(reqstr)
	return req
end

--[[
    Raw send to the given connection ID at the given uuid, mostly 
    used internally.
]]
function Connection:send(msg)
    return self.channel_res:send(msg)
end

-- req.meta.conn_id and conns[i] are all connection id 
function Connection:reply(data, code, status, headers, conns, meta)
	local msg = wrap(
		data, 
		code, 
		status, 
		headers, 
		conns,
		meta)
	
	return self:send(msg)
end


--[[
    Same as reply, but tries to convert data to JSON first.
    data: table
]]
function Connection:reply_json(data, conns, meta)
    return self:reply( 
		json.encode(data), 
		200, 
		'OK', 
		{['content-type'] = 'application/json'},
		conns, meta )
end

--[[
    Basic HTTP response mechanism which will take your body,
    any headers you've made, and encode them so that the 
    browser gets them.
]]
function Connection:reply_http(body, code, status, headers, conns, meta)
    return self:reply(body, code, status, headers, conns, meta)
end


--[[
-- Tells lgserver to explicitly close the HTTP connection.
--]]
-- function Connection:close(req)
--     return self:reply(req, "")
-- end


--[[
    Creates a new connection object.
    Internal use only, call ctx:new_context instead.
]]
local function newConnection(sender_id, sub_addr, pub_addr, cluster_addr)

	local ctx = zmq.init(1)

	-- local channel_req = ctx:socket(zmq.PULL)
	-- channel_req:bind(sub_addr)

	-- local channel_res = ctx:socket(zmq.PUSH)
	-- channel_res:connect(pub_addr)

	local channel_req = ctx:socket(zmq.PULL)
	channel_req:connect(sub_addr)

	local channel_res = ctx:socket(zmq.PUSH)
	channel_res:connect(pub_addr)

	-- if set cluster channel
	if cluster_channel_addr then
		cluster_channel_pub = ctx:socket(zmq.PUB)
		cluster_channel_pub:bind(cluster_addr)

		local cluster_channel_sub = ctx:socket(zmq.SUB)
		cluster_channel_sub:setopt(zmq.SUBSCRIBE, "")
		cluster_channel_sub:connect(cluster_addr)
	end

	-- Build the object and give it a metatable.
	local obj = {
		ctx = ctx,
		sender_id = sender_id,

		sub_addr = sub_addr,
		pub_addr = pub_addr,
		cluster_addr = cluster_addr,

		channel_req = channel_req,
		channel_res = channel_res,
		cluster_channel_pub = cluster_channel_pub,
		cluster_channel_sub = cluster_channel_sub
	}

	return setmetatable(obj, Connection_meta)
end

--[[
local Request = {}
Request.__index = Request

-- Returns true if the request object is a disconnect event.
function Request:is_disconnect()
    return self.data.type == 'disconnect'
end

-- Checks if the request was for a connection close.
function Request:should_close()
    if self.headers['connection'] == 'close' then
        return true
    elseif self.headers['VERSION'] == 'HTTP/1.0' then
        return true
    else
        return false
    end
end

--]]

local function findHandler(lgserver_config, host_name, route )
	local server = lgserver_config.server
	local host_name = host_name or server.default_host

	for _, host in ipairs(server.hosts) do
	    if host.name == host_name then
		return host.routes[route]
	    end
	end

	return nil
end

--- load configuration from lgserver's config.sqlite
-- 
------------------------------------------------------------------------
function driver.loadConfig(config)
	config.lgserver_config = {}
	print('Ready to load config file: ', config.config_file)
	local config_file = loadfile(config.config_file)
	-- release the global variables to config table
	setfenv(assert(config_file, "Failed to load lgserver config file."), 
		config.lgserver_config)()
	
	local handler = findHandler(config.lgserver_config, config.host, config.route)
	assert(handler, "Failed to find route: " .. config.route ..
            ". Make sure you set config.host to a host in your config.lua.")

	config.sub_addr = handler.send_spec
	config.pub_addr = handler.recv_spec
	config.sender_id = handler.sender_id
	
	return config
end



--- create a new connection between bamboo and mognrel2 (via zeromq)
-- @return conn: new created connection
------------------------------------------------------------------------
function driver.connect(config)
    local sub_addr, pub_addr = config.sub_addr, config.pub_addr
	math.randomseed(os.time())
	local sender_id = config.sender_id or 'bamboo_handler_'..math.random(100000, 999999)
    print("CONNECTING", config.route, sender_id, sub_addr, pub_addr)
	
	local cluster_addr = config.cluster_addr or 'tcp://127.0.0.1:12315'

    local conn = newConnection(sender_id, sub_addr, pub_addr, cluster_addr)

    assert(conn, "Failed to start lgserver connection.")

    return conn
end

return driver
