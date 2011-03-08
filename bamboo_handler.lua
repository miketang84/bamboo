#!/usr/bin/env lua

package.path = '/usr/local/lib/lua/5.1/?.lua;/usr/local/lib/lua/5.1/?/init.lua;' .. package.path
require 'posix'
-- 获取当前进程所在目录
local PROCESS_DIR = posix.getcwd()

require 'lglib'
require 'bamboo'

-- 要传递给插件的渲染函数中去的全局变量
web = nil
req = nil

------------------------------------------------------------------------
-- 把应用路径放在这里，并且声明为全局变量，主要就是将其传递给bamboo的子模块使用
APP_DIR = arg[1]
-- 目标handler_xxx.lua文件
local handler_file = arg[2]

local errors = require 'bamboo.errors'
local redis = require 'bamboo.redis'

local CONFIG_FILE = APP_DIR + "conf/settings.lua"
-- 工程目录完整路径
local PROJECT_DIR = PROCESS_DIR + '/' + APP_DIR
-- 将工程目录也加入到搜索路径中去，以实现工程目录中的模块相互调用
package.path = package.path + (";%s/?.lua;%s/?/init.lua;"):format(PROJECT_DIR, PROJECT_DIR)
------------------------------------------------------------------------



local function updateConfig(config, config_file)
    local originals = table.copy(config)
    -- 将外部配置文件中的内容添加到config表中，
	-- 注：此处的config一定不能继承_G，不然会出很奇怪的错误
	setfenv(assert(loadfile(config_file)), config)()
    -- XXX: TODO
	table.update(config, originals)

    -- 返回合并参数后的配置表
	return config
end

local config = updateConfig({}, CONFIG_FILE)
local DB_HOST = config.DB_HOST or '127.0.0.1'
local DB_PORT = config.DB_PORT or 6379
local WHICH_DB = config.WHICH_DB or 0

-- 创建一个数据库连接，要注意不要与现有的数据库重合了，which一定要选正确
-- 全局对象。由于bamboo的同一个应用可能会有很多子进程。把这一句也在这里的话，
-- 我们会为每一个子进程生成一个数据库连接（从redis方面看，这也是无关紧要的）。
BAMBOO_DB = redis.connect {host=DB_HOST, port=DB_PORT, which = WHICH_DB}
--ptable(BAMBOO_DB)

local Web = require 'bamboo.web'
local Session = require 'bamboo.session'
local User = require 'bamboo.user'

------------------------------------------------------------------------
-- 定义一个新环境
local childenv = {}
-- 加载目标handler_xxx.lua文件，将其环境设为childenv，
-- 目的是将那个文件中定义的全局变量释放到childenv来
setfenv(assert(loadfile(handler_file)), setmetatable(childenv, {__index=_G}))()

print('------------ URL Settings --------------')
ptable(childenv.URLS)
print('----------------------------------------')
local URLS = childenv.URLS
------------------------------------------------------------------------

USERDEFINED_VIEWS = './views/'



-- 检查URLS的结构
local function checkURLS(urls)
	if isFalse(urls[1]) then
		error('URLS value is not right. URLS[1] must be string and NOT be blank.')
	end

	for i, v in pairs(urls) do
		if i ~= 1 then
			checkType(i, 'string')
			if type(v) == 'table' then
				checkType(v[1], v[2], 'function', 'boolean')
			else
				checkType(v, 'function')
			end
		end
	end

end
checkURLS(URLS)

local function trailingPath(path)
	local path = path:gsub('//+', '/')
	if path:sub(-1) ~= '/' then
		path = ('%s/'):format(path)
	end
	
	return path
end

local function makeUrlHandlerMapping(URLS)
	local mapping_table = {}
	
	local base = URLS[1]
	for k, v in pairs(URLS) do
		-- 这儿，如果能够把1这个元素分开就好了，少写一层判断
		if k ~= 1 then
			local url_t = base + k
			-- 去除多余的分隔符
			url_t = url_t:gsub('//+', '/')
			
			mapping_table[url_t:lower()] = v
		end
	end	
	
	return mapping_table
end

-- 对URLS中数据作简单处理，生成MappingTable，后面主要用MappingTable
local MappingTable = makeUrlHandlerMapping(URLS)

------------------------------------------------------------------------
-- 从URLS定义列表中找到匹配的handler，实际上这是个集合操作
-- @param mapt	URLS映射列表
-- @param path	来访path
-- @return  返回两个参数，第一个参数是handler函数，第二个参数是是否状态编程(true)，无状态编程(false)
------------------------------------------------------------------------
local function getHandlerByPath(mapt, path)
	local path = path:lower() 
	local parse = function (v)
		if type(v) == 'table' then
			checkType(v[1], v[2], 'function', 'boolean')
			return v[1], v[2]
		elseif type(v) == 'function' then
			-- 如果只写一个function，则默认为非状态编程。要状态编程，必须写成一个表，加上true标志
			return v, false
		end
	end
	
	local key, value = "", nil
	for k, v in pairs(mapt) do
		-- 此处，添加URL正则表达式匹配功能，要做到完整且尽可能长的匹配
		-- 而且，要求，如果两种模式都满足，则取表述清楚的那一种模式。如：
		-- "%w+/"与"login/"之间取"login/"
		--  如果都完全显式地等于它了，那么立即处理
		if k == path then
			return parse(v)
		-- 如果是一个模式匹配等于它的，则先悬挂，等到全部检查完，选择其中最长的模式
		-- 如果两个一样长，就取后面那一个
		elseif path:match('^' + k + '$') then
			if key == '' or #k >= #key then 
				key, value = k, v
			end
		end

	end	

	if key and value then
		-- 运行到这里，说明是通过模式匹配到的，执行最终的筛选结果
		return parse(value)
	end
	
	-- 执行到这里，说明没有符合的匹配模式
	return nil, nil
end




------------------------------------------------------------------------


-- 由于我们的URL直接正则表达式匹配了，所以这个函数没什么用了
-- 只对准确完整的URL有效
local function createStateRecorder(STATE, mapt)
	for k, _ in pairs(mapt) do
		STATE[k] = {}
	end
	return STATE
end


-- STATE是一个状态记录器，在其基础上实现一个FSM，有限状态机
-- STATE是一个二组数组。第一维是path，即URL PATH部分，第二维是conn_id
local STATE = createStateRecorder(setmetatable({}, {__mode="k"}), MappingTable)


-- 硬编码，临时
local DEFAULT_ALLOWED_METHODS = {GET = true, POST = true, PUT = true, JSON = true, XML = true}



------------------------------------------------------------------------
-- 状态编程。执行传入的函数
-- @param state  	记录状态的Web对象
-- @param req	请求来源对象
-- @param before	执行对象操作函数前的处理函数，由外部传入
-- @param after		执行对象操作函数后的处理函数，由外部传入
-- @param action_func	state对象操作函数，由外部传入
-- @return true|false 是否执行成功的标志及错误信息
------------------------------------------------------------------------
local function execState(state, req, before, after, action_func)
    local good, err

    -- 如果定义了前置处理函数的话，就保护模式调用，并检查其返回值
	if before then
        good, err = pcall(before, state, req)
        if not good then return good, err end
        if not err then return false end
    end
	
	-- 操作state对象
    good, err = action_func(state, req)
   
	-- 如果定义了后置处理函数的话，就保护模式调用，并检查其返回值
    if after then
        local after_good, after_err = pcall(after, state, req)
        if not after_good then return after_good, after_err end
        if not after_err then return false end
    end

    return good, err
end

------------------------------------------------------------------------
-- 状态编程。状态编程的控制函数。
-- @param main		由上层开发人员写的handler的主函数
-- @param conn  	连接对象
-- @param req	请求对象
-- @param conn_id	连接id（是cookie唯一编号吗？）
-- @param before	执行对象操作函数前的处理函数，由外部传入
-- @param after		执行对象操作函数后的处理函数，由外部传入
-- @return 无
------------------------------------------------------------------------
local function runCoro(conn, main, req, conn_id, path, before, after)
    -- 进入这个函数，意味着客户端发送了一个数据过来
	-- 从状态机中获得一个状态
    local state = STATE and STATE[path] and STATE[path][conn_id]
    local good, err

    -- 如果客户端是第一次发送数据过来，那么新创建一个状态（在这个状态中创建了一个协程）
    if not state then
		-- 创建一个Web对象实例，命名为state
        state = Web(conn, main, req, true)
		_G['web'] = state
        -- 在状态机中记录下这个对象实例，以连接编码为key
		STATE[path] = {}
		STATE[path][conn_id] = state
        good, err = execState(state, req, before, after,
            function (s, r)
                return coroutine.resume(state.controller, state, req) 
            end)
    -- 如果客户端不是第一次发送数据过来，就直接唤醒
	else
        state.req = req

        good, err = execState(state, req, before, after,
            function (s, r)
                return coroutine.resume(s.controller, r) 
            end)
    end

	-- 如果在执行的过程中出现了错误，就通过返回错误页面报错
    if not good and err then
        errors.reportError(conn, req, err, state)
    end

    -- 如果主函数已经完成或执行过程中出了错误，那么结束对客户端连接的跟踪
    if not good or coroutine.status(state.controller) == "dead" then
        -- 将客户端从状态集中清除即是
		STATE[path][conn_id] = nil
		STATE[path] = nil
    end
end

------------------------------------------------------------------------
-- 无状态编程。无状态编程的控制函数。
-- @param conn  	连接对象
-- @param main		由上层开发人员写的handler的主函数
-- @param req	请求对象
-- @param before	执行对象操作函数前的处理函数，由外部传入
-- @param after		执行对象操作函数后的处理函数，由外部传入
-- @return 无
------------------------------------------------------------------------
local function runStateless(conn, main, req, before, after)
    local state = Web(conn, main, req, false)
	_G['web'] = state
	
    local good, err = execState(state, req, before, after, function(s,r)
        return pcall(s.controller, s, r)
    end)

    if not good and err then
        errors.reportError(conn, req, err, state)
    end
end


------------------------------------------------------------------------
-- Bamboo框架的主循环。在Bamboo中，每一个handler都是独立的进程。所以都有一个主循环存在
-- @param conn  	连接对象
-- @param config	从start函数传过来
-- @return 无
------------------------------------------------------------------------
function run(conn, config)
    local main, ident, disconnect = config.main, config.ident, config.disconnect
    local before, after = config.before, config.after
    local good, err
    local req, msg_type, controller
    local conn_id, path
	local PREV_PATH = {}
	
    -- 主循环
	while true do
        -- Get a message from the Mongrel2 server
		-- 从Mongrel2 server那获得一条消息，没有的话就阻塞等待
        req, err = conn:recv()
		_G['req'] = req

        if req and not err then
			-- 如果HTTP指令不在限制范围内，直接报错
            if not config.methods[req.headers.METHOD] then
                basicError(conn, req, "Method Not Allowed",
                    405, "Method Not Allowed", {Allow = config.allowed_methods_header})
            else
                msg_type = req.data.type
				
				-- 客户端已经断掉连接
                if msg_type == 'disconnect' then
                    if disconnect then disconnect(req) end
                    print("DISCONNECT", req.conn_id)
                else
					-- 这里产生conn_id，这个id就是cookie码，也是session码
                    conn_id = ident(req)
					-- 注意path的格式，这里确保path最后一个字符是'/'
					path = trailingPath(req.path)
					req.path = path
                    print(("req %s: %s"):format(config.route, req.conn_id), os.date(), req.headers.PATH, req.headers.METHOD, req.session_id)
					
					--ptable(req)
					--ptable(req.headers)
					--ptable(req.data)
					-------------------------------------------------
					-- 我们在这里临时在请求中增加一些我们自定义的键值
					-- session 
					-- req.session = {}
					-- METHOD
					req.METHOD = req.headers.METHOD
					if req.headers['x-requested-with'] == 'XMLHttpRequest' then
						req['ajax'] = true
					end
					-- 经过这里定义后，req中能直接获得的属性有：
					-- conn_id		连接唯一编码，如：5
					-- path			访问路径，如：/arc
					-- session_id	session_id编码，如：APP-f4a619a2f181ccccd4812e9f664e9029
					-- data			一个表，里面放置一些数据
					-- body			当请求为POST时，这个里面放置上传数据
					-- METHOD		请求方法，如：GET
					-- sender		zmq的通道靠近客户的那一端的唯一编码，如：e884a439-31be-4f74-8050-a93565795b25
					-- session		表。放置会话相关数据
					-- headers		消息头。里面有更多数据，要用的话，可以继续参考里面的
					-------------------------------------------------
					-- 数据库的session记录
					-- 这句使进来的请求的req.session表的内容，总是与数据库中的数据同步的
					-- 经过这一步后，req中会获得如下属性
					-- session 当前session表					
					Session:set(req)
					-- 这一句执行后，req中会带一个user属性，如果Session中有user_id这个键值的话
					User:set(req)
					
					-- 状态保护，如果在一个系列状态中途执行其它操作，则清空这个状态，重新开始
					local session_id = req.session_id
					local prev_path = PREV_PATH[session_id]
					if prev_path and prev_path ~= req.path and STATE[prev_path] and STATE[prev_path][session_id] then
						if not STATE[prev_path] then STATE[prev_path] = {} end
						STATE[prev_path][session_id] = nil
					else
						PREV_PATH[session_id] = req.path
					end
					--ptable(BAMBOO_DB:hgetall('session:'+req.session_id))	-- for test
					-------------------------------------------------
					-- 根据来的PATH，找到对应的handler，如果没有找到，就报错（目前来讲是这样，但后面应该返回一个404页面）。
					local main_t, state_flag = getHandlerByPath(MappingTable, path)
					if not main_t then
						error(('No handler to process this path: %s'):format(path))
					end
					main = main_t
					
					-- 状态编程
					if state_flag then
						runCoro(conn, main, req, conn_id, path, before, after)
					-- 无状态编程
					else
						runStateless(conn, main, req, before, after)
					end

                end
            end
        -- 请求错误，打印一条信息，并不处理，然后继续下一条请求处理
		else
            print("FATAL ERROR", good, req, err)
        end
    end
end



------------------------------------------------------------------------
-- Bamboo框架启动接口
-- @param config	从外部上层应用的handler的调用中传入的配置文件
-- @return 无		一直保持循环等待，不会退出这个函数
------------------------------------------------------------------------
-- Starts a Tir engine, wiring up all the stuff we need for this process
-- using the given config.  The config is expected to have at least
-- {route='/path', main=handler_func}.  In addition to that you can put
-- other settings that are common to all handlers in CONFIG_FILE.
-- Options you can override are: templates, ident, sender_id, sub_addr, pub_addr, io_threads
function start(config)
	local m2 = require 'bamboo.m2'
	-- 配置可以有4处地方：
	-- 一是在启动进程的时候，作为函数参数传入；
	-- 二是在参数中自己定义一个配置文件的路径；
	-- 三是使用默认配置文件；
	-- 四是mongrel2使用的sqlite3数据库中的配置；
	
	-- 等式右侧的URLS是前面定义的局部变量，从handler文件中传来
	config = config or {}
	config.APP_DIR = APP_DIR
	-- 需要这个变量来从sqlite3数据库中找到传输通道
	config.route = URLS[1]
	config.MappingTable = MappingTable
	
    config = updateConfig(config, config.config_file or CONFIG_FILE)
    -- 模板路径（用户定义，或默认）
	config.templates = config.templates or (APP_DIR + "views/")
    -- 标识码产生器，为一函数（用户定义，或默认）
	config.ident = config.ident or Session.identRequest

    -- HTTP指令白名单，可用户自定义
    config.methods = config.methods or DEFAULT_ALLOWED_METHODS
	-- allowed表中存储的是允许的HTTP指令
    local allowed = {}
    for m, yes in pairs(config.methods) do
        if yes then allowed[#allowed + 1] = m end
    end

    -- allowed_methods_header字段是一个字符串
	config.allowed_methods_header = table.concat(allowed, ' ')
	
	if config.monserver_dir then
		config.config_db = config.monserver_dir + config.config_db
	end
	
	if not isFalse(config.views) then
		config.views = APP_DIR + config.views
		_G['USERDEFINED_VIEWS'] = config.views
	end
	
	
	
	-- 加载sqlite3中的配置
    m2.loadConfig(config)
	-- 产生一个连接，作为handler进程与mongrel2的交流通道
    local conn = assert(m2.connect(config), "Failed to connect to Mongrel2.")

    -- 启动引擎，开始运行。这里实际是个尾调用。
	-- 这里调用后，此处的start函数已经找不到了，即run如果返回，不会再回到start函数了
    run(conn, config)
end


--------------
-- 启动handler
--------------
start()


