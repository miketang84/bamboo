module(..., package.seeall)

local json = require 'cjson'
local zmq = require 'zmq'
local cmsgpack = require 'cmsgpack'


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

-- data is string
-- extra is table
local function wrap(data, extra)
	local ret = {
		data = data,
		extra = extra
	}

	return cmsgpack.pack(ret)
end


--[[
    Receives a raw lgserver.request object that you can then work with.
    Upon error while parsing the data, returns nil and an error message.
]]
function Connection:recv()
	local reqstr, err = self.reqs:recv()
	local req = cmsgpack.unpack(reqstr)
	-- add some headers
	if req and type(req) == 'table' then
		req['sender_id'] = self.sender_id
		req['conn_id'] = conn_id or 0
		-- req.data = {}
	end

	return req
end

--[[
    Raw send to the given connection ID at the given uuid, mostly 
    used internally.
]]
function Connection:send(msg)
    return self.resp:send(msg)
end

function Connection:reply(req, data, code, status, headers)
    local msg = wrap(http_response(data, code, status, headers),
		{sender_id=req.sender_id, conn_id=req.conn_id})
    return self:send(msg)
end


--[[
    Same as reply, but tries to convert data to JSON first.
    data: table
]]
function Connection:reply_json(req, data)
    return self:reply(req, json.encode(data), 200, 'OK', 
		{['Content-Type'] = 'application/json'})
end

--[[
    Basic HTTP response mechanism which will take your body,
    any headers you've made, and encode them so that the 
    browser gets them.
]]
function Connection:reply_http(req, body, code, status, headers)
    return self:reply(req, body, code, status, headers)
end


--[=[
--[[
    This lets you send a single message to many currently
    connected clients.  There's a MAX_IDENTS that you should
    not exceed, so chunk your targets as needed.  Each target
    will receive the message once by lgserver, but you don't have
    to loop which cuts down on reply volume.
]]
function Connection:deliver(uuid, idents, data)
    return self:send(uuid, concat(idents, ' '), data)
end

--[[
    Same as deliver, but converts to JSON first.
]]
function Connection:deliver_json(uuid, idents, data)
    --return self:deliver(uuid, idents, json.encode(data))
	return self:deliver(uuid, idents, http_response(
		json.encode(data), 200, 'OK', {['content-type'] = 'application/json'}))

end

--[[
    Same as deliver, but builds a HTTP response.
]]
function Connection:deliver_http(uuid, idents, body, code, status, headers)
    code = code or 200
    status = status or 'OK'
    headers = headers or {}
    return self:deliver(uuid, idents, http_response(body, code, status, headers))
end

--]=]

--[[
-- Tells lgserver to explicitly close the HTTP connection.
--]]
function Connection:close(req)
    return self:reply(req, "")
end

--[=[
--[[
-- Sends and explicit close to multiple idents with a single message.
--]]
function Connection:deliver_close(uuid, idents)
    return self:deliver(uuid, idents, "")
end
--]=]

--[[
    Creates a new connection object.
    Internal use only, call ctx:new_context instead.
]]
local function new_connection(sender_id, sub_addr, pub_addr)
	local ctx, err = zmq.init(2)

	-- Create and connect to the PULL (request) socket.
	local channel_req, err = ctx:socket(zmq.PULL);
	if not channel_req then return nil, err end

	local good, err = channel_req:connect(sub_addr)
	if not good then return nil, err end

	-- Create and connect to the PUSH (response) socket.
	local channel_res, err = ctx:socket(zmq.PUSH)
	if not channel_res then return nil, err end

	good, err = channel_res:connect(pub_addr)
	if not good then return nil, err end

	-- good, err = resp:setopt(zmq.IDENTITY, sender_id)
	-- if not good then return nil, err end

	-- Build the object and give it a metatable.
	local obj = {
		ctx = ctx;
		sender_id = sender_id;

		sub_addr = sub_addr;
		pub_addr = pub_addr;

		reqs = reqs;
		resp = resp;
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
	local server = lgserver_config['server_name']
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
    print("CONNECTING", config.route, config.sender_id, sub_addr, pub_addr)
  
    local conn = new_connection(config.sender_id, sub_addr, pub_addr)

    assert(conn, "Failed to start lgserver connection.")

    return conn
end
