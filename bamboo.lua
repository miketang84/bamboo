#!/usr/bin/env lua

require 'posix'
require 'signal'

SCRIPT_PIDS = {}

signal.signal("SIGINT", function (...)
    for script, pid in pairs(SCRIPT_PIDS) do
        posix.kill(pid)
    end
end)


function parse_args(arg)
    if #arg == 0 then return nil end

    local cmd = table.remove(arg, 1)
    local settings = {}
    local last_opt = nil

    for i, opt in ipairs(arg) do
        local token = opt:match("\-+([a-z\-]+)")

        if token then
            last_opt = token
        else
            settings[last_opt] = opt
        end
    end

    return cmd, settings
end


local function run_script(app_dir, script)
    pid = posix.fork()

    if pid == 0 then
        -- in pid, run the script
        --posix.execp("lua", script)
        -- 这里，这个script就是要执行的handler文件名
        posix.execp("bamboo_handler", app_dir, script)
    else
        print("Started " .. script .. " PID " .. pid)
        SCRIPT_PIDS[script] = pid
    end

    return pid
end


local function run_app(app_dir, targets)
    local pid
    local running = {}

    for script, pid in pairs(SCRIPT_PIDS) do
        running[script] = posix.kill(pid, 0) == 0
    end

    for _, script in ipairs(targets) do
        if not running[script] then
            run_script(app_dir, script)
        end
    end
end

local function run_tests(test_dir, full)
    print("\n---------------- TESTS -----------------")
    local tests = posix.glob(test_dir .. "/**/*_tests.lua")

    if tests then
        local cmd = "tsc "
        if full then cmd = cmd .. "-f " end

        os.execute(cmd .. table.concat(tests, ' '))
    else
        print("\n-------------- NO TESTS ----------------")
        print("  You must work at a startup.")
    end
end

local function wait_on_children()
    local dead_count = 0
    local child_count = 0
    local p, msg, ret

    repeat
        p, msg, ret = posix.wait(-1)
    until p

    for script, pid in pairs(SCRIPT_PIDS) do
        if p == pid then
            print("CHILD DIED " .. script .. " PID " .. p ..":", msg)
            SCRIPT_PIDS[pid] = nil
            return script, pid
        end
    end
end


COMMANDS = {
    test = function(settings)
        local target = settings.from or "tests"
        if not os.getenv('PROD') then
            run_tests(target, settings.full ~= nil)
        else
            print "Running in PROD mode, won't run tests."
        end
    end,

    start = function(settings)
        --for i,v in pairs(settings) do print(i,v) end
        -- 这里，这个app是一个搜索文件的一个模式匹配字符串，给glob用的
        -- 按我的理解，settings.app应该是应用的路径更好
        local app_dir = settings.app or './'
        local app = ('%s%s'):format((settings.app or "./"), 'app/handler_*.lua')
        local script_times = {}


        while true do
            local targets = assert(posix.glob(app))

            for _, script in ipairs(targets) do
                if not script_times[script] then
                    script_times[script] = os.time() 
                end
            end

            run_app(app_dir, targets)
            script, pid = wait_on_children()
            local tick = os.time()

            if tick - script_times[script] < 1 then
                print("SCRIPT " .. script .. " RESTARTING TOO FAST. Pausing while you fix stuff.")
                posix.sleep(10)
                tick = os.time()
            end

            script_times[script] = tick
        end
    end,

    help = function(settings)
        print("AVAILABLE COMMANDS:")
        for k,v in pairs(COMMANDS) do
            print(k)
        end
    end,
}


function run(cmd, settings)
    local cmd_to_run = COMMANDS[cmd]

    if cmd_to_run then
        cmd_to_run(settings)
    else
        print("ERROR: that's not a valid command")
        print("USAGE: tir <command> <options>")
    end
end


local cmd, settings = parse_args(arg)
run(cmd, settings)

