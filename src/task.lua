module(..., package.seeall)

local IO_THREADS = 1
local zmq = require 'zmq'

-- for task process main loop
function start(config)
    assert(config.spec, "You need to at least set spec = to your 0MQ socket spec.")
    assert(config.main, "You must set a main function.")

    local ctx = assert(zmq.init(config.io_threads or IO_THREADS))
    local conn = assert(ctx:socket(config.socket_type or zmq.SUB))
    local main = config.main
    conn:setopt(zmq.SUBSCRIBE, config.subscribe or '')
    conn:bind(config.spec)

    if config.recv_ident then
        conn:setopt(zmq.IDENTITY, config.recv_ident)
    end

    print("BACKGROUND TASK " .. config.spec .. " STARTED.")

    if not config.custom_mainloop then
		while true do
			-- receive data from client
			local data = assert(conn:recv())
			main(conn, data)
		end
    else
		main(conn) 
    end

    print('Task main loop terminated!')
end

-- used by client to connect the task server
function connect(config)
    assert(config.spec, "You need to at least set spec = to your 0MQ socket spec.")

    local ctx = assert(zmq.init(config.io_threads or IO_THREADS))
    local conn = assert(ctx:socket(config.socket_type or zmq.PUB))
    conn:connect(config.spec)

    if config.send_ident then
        conn:setopt(zmq.IDENTITY, config.send_ident)
    end

    local TaskConn = {
        ctx = ctx,
        conn = conn,
        config = config
    }

    function TaskConn:send(data)
        self.conn:send(data, zmq.NOBLOCK)
    end

    -- conn_dispatcher is the default bamboo connecion dispatcher
    function TaskConn:wait()
		bamboo.poller:add(conn, zmq.POLLIN, bamboo.internals.connDispatcher)
		-- yield return data from task process
		return coroutine.yield()
    end

    -- callback(conn, revents)
    function TaskConn:send_and_wait(data, callback)
        self.conn:send(data, zmq.NOBLOCK)
		bamboo.poller:add(conn, zmq.POLLIN, callback)
    end


    function TaskConn:term()
		bamboo.SUSPENDED_TASKS[conn] = nil
		bamboo.poller:remove(conn)

		self.conn:close()
        self.ctx:term()
    end

    -- here, use global variable web
    bamboo.SUSPENDED_TASKS[conn] = web
    return TaskConn
end

