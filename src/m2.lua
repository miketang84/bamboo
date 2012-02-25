local monserver = require 'monserver'

module('bamboo.m2', package.seeall)

function findHandler(m2conf, route, host_name)
    local host_name = host_name or m2conf.servers[1].default_host

    for _, server in ipairs(m2conf.servers) do
        for _, host in ipairs(server.hosts) do
            if host.name == host_name then
                return host.routes[route]
            end
        end
    end

    return nil
end

--- load configuration from monserver's config.sqlite
-- 
------------------------------------------------------------------------
function loadConfig(config)
	local config_file = loadfile(config.config_file)
	-- release the global variables to config table
	setfenv(assert(config_file, "Failed to load monserver config file."), config)()
	ptable(config)

    local handler = findHandler(config, config.route, config.host)
    assert(handler, "Failed to find route: " .. config.route ..
            ". Make sure you set config.host to a host in your config.lua.")

    config.sub_addr = handler.send_spec
    config.pub_addr = handler.recv_spec

	return config
end



--- create a new connection between bamboo and mognrel2 (via zeromq)
-- @return conn: new created connection
------------------------------------------------------------------------
function connect(config)
    local sub_addr, pub_addr = config.sub_addr, config.pub_addr
    print("CONNECTING", config.route, config.sender_id, sub_addr, pub_addr)
  
    local ctx = monserver.new(config.io_threads)
    local conn = ctx:new_connection(config.sender_id, sub_addr, pub_addr)

    assert(conn, "Failed to start Monserver connection.")

    return conn
end


