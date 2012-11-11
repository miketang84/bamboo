module(..., package.seeall)

local json = require 'cjson'
local zmq = require 'zmq'
local cmsgpack = require 'cmsgpack'
-- local luv = require('luv')

local insert, concat = table.insert, table.concat
local format = string.format

local Connection = {}
Connection.__index = Connection


--[[
    A Connection object manages the connection between your handler
    and a lgserver server (or servers).  It can receive raw requests
    or JSON encoded requests whether from HTTP or MSG request types,
    and it can send individual responses or batch responses either
    raw or as JSON.  It also has a way to encode HTTP responses
    for simplicity since that'll be fairly common.
]]

-- (code) (status)\r\n(headers)\r\n\r\n(body)
local HTTP_FORMAT = 'HTTP/1.1 %s %s\r\n%s\r\n\r\n%s'

local function http_response(body, code, status, headers)
    code = code or 200
    status = status or "OK"
    headers = headers or {}
    headers['Content-Type'] = headers['Content-Type'] or 'text/plain'
    body = tostring(body) or ''
    headers['Content-Length'] = #body
    
    local raw = {}
    for k, v in pairs(headers) do
        insert(raw, format('%s: %s', tostring(k), tostring(v)))
    end
    
    return format(HTTP_FORMAT, code, status, concat(raw, '\r\n'), body)
end

-- data structure return to lgserver
-- data is string
-- extra is table
-- conns: a list of connection keys
local function wrap(data, code, status, headers, conns, meta)
	local ret = {
		data = data,  			-- body string to reply
		code = code,			-- http code to reply
		status = status,		-- http status to reply
		headers = headers,		-- http headers to reply
		conns = conns,			-- http connections to receive this reply
		meta = meta				-- some other info to lgserver
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
	-- -- add some headers
	-- if req and type(req) == 'table' then
	-- 	req['sender_id'] = self.sender_id
	-- 	--req['conn_id'] = conn_id or 0
	-- 	-- req.data = {}
	-- end

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
function Connection:reply(req, data, code, status, headers, conns)
	local msg = wrap(
		data, 
		code, 
		status, 
		headers, 
		conns,
		{sender_id=req.meta.sender_id, conn_id=req.meta.conn_id} )
	
	return self:send(msg)
end


--[[
    Same as reply, but tries to convert data to JSON first.
    data: table
]]
function Connection:reply_json(req, data, conns)
    return self:reply(
		req, 
		json.encode(data), 
		200, 
		'OK', 
		{['content-type'] = 'application/json'},
		conns )
end

--[[
    Basic HTTP response mechanism which will take your body,
    any headers you've made, and encode them so that the 
    browser gets them.
]]
function Connection:reply_http(req, body, code, status, headers, conns)
    return self:reply(req, body, code, status, headers, conns)
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

	local ctx = zmq.init()

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
		sender_id = sender_id;

		sub_addr = sub_addr;
		pub_addr = pub_addr;
		cluster_addr = cluster_addr;

		channel_req = channel_req;
		channel_res = channel_res;
		cluster_channel_pub = cluster_channel_pub;
		cluster_channel_sub = cluster_channel_sub
	}

	return setmetatable(obj, Connection)
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

function findHandler(lgserver_config, server_name, host_name, route )
	local server = lgserver_config[server_name]
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
function loadConfig(config)
	config.lgserver_config = {}
	local config_file = loadfile(config.config_file)
	-- release the global variables to config table
	setfenv(assert(config_file, "Failed to load lgserver config file."), 
		config.lgserver_config)()
	
	local handler = findHandler(config.lgserver_config, config.server, config.host, config.route)
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
function connect(config)
    local sub_addr, pub_addr = config.sub_addr, config.pub_addr
	math.randomseed(os.time())
	local sender_id = config.sender_id or 'bamboo_handler_'..math.random(100000, 999999)
    print("CONNECTING", config.route, sender_id, sub_addr, pub_addr)
	
	local cluster_addr = config.cluster_addr or 'tcp://127.0.0.1:12315'

    local conn = newConnection(sender_id, sub_addr, pub_addr, cluster_addr)

    assert(conn, "Failed to start lgserver connection.")

    return conn
end
