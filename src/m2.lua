local mongrel2 = require 'mongrel2'
local mconfig = require 'mongrel2.config'

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

--- load configuration from mongrel2's config.sqlite
-- 
------------------------------------------------------------------------
function loadConfig(config)
    local m2conf = assert(mconfig.read(config.config_db),
        "Failed to load the mongrel2 config: " .. config.config_db)

    local handler = findHandler(m2conf, config.route, config.host)
    assert(handler, "Failed to find route: " .. config.route ..
            ". Make sure you set config.host to a host in your mongrel2.conf.")

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
  
    local ctx = mongrel2.new(config.io_threads)
    local conn = ctx:new_connection(config.sender_id, sub_addr, pub_addr)

    assert(conn, "Failed to start Mongrel2 connection.")

    return conn
end


