require 'mongrel2'
require 'mongrel2.config'

module('bamboo.m2', package.seeall)

function findHandler(m2conf, route, host_name)
    local host_name = host_name or m2conf[1].default_host

    for _, server in ipairs(m2conf) do
        for _, host in ipairs(server.hosts) do
            if host.name == host_name then
                return host.routes[route]
            end
        end
    end

    return nil
end

------------------------------------------------------------------------
-- 从Mongrel2的配置文件中加载handler（处理子）的配置
-- @return 返回cookie id，也即session id值
------------------------------------------------------------------------
function loadConfig(config)
    local m2conf = assert(mongrel2.config.read(config.config_db),
        "Failed to load the mongrel2 config: " .. config.config_db)

    local handler = findHandler(m2conf, config.route, config.host)
    assert(handler, "Failed to find route: " .. config.route ..
            ". Make sure you set config.host to a host in your mongrel2.conf.")

    config.sub_addr = handler.send_spec
    config.pub_addr = handler.recv_spec
end


------------------------------------------------------------------------
-- 创建一个新的连接，连接到zmq管道上。这是mongrel2-lua之上的又一层封装（mongrel2-lua对lua-zmq
-- 又做了一次封装），是bamboo Web开发框架与底层沟通的接口
-- @return 新创建的连接
------------------------------------------------------------------------
function connect(config)
    -- 如果存在非默认目录的全局应用路径，则对之前定义的zmp信息通道的路径做相应修改
    local sub_addr, pub_addr = config.sub_addr, config.pub_addr
    if config.monserver_dir then
        sub_addr = sub_addr:sub(1,6) + config.monserver_dir + sub_addr:sub(7)
        pub_addr = pub_addr:sub(1,6) + config.monserver_dir + pub_addr:sub(7)
    end
    print("CONNECTING", config.route, config.sender_id, sub_addr, pub_addr)
  
    local ctx = mongrel2.new(config.io_threads)
    local conn = ctx:new_connection(config.sender_id, sub_addr, pub_addr)

    assert(conn, "Failed to start Mongrel2 connection.")

    return conn
end


