

-- 由于此模块是一个无继承类的定义，注意模块名应该全小写（一个类对应一个文件，和模块统一起来，牛）
-- 使用方法： local Web = require 'bamboo.web'
-- Web就是一个类了
module(..., package.seeall)

local session = require 'bamboo.session'
local Form  = require 'bamboo.form'

local Web = Object:extend {
	__tag = 'Bamboo.Web';
	__name = 'Web';
	init = function (self, conn, main, req, stateful)
		local controller
		self.conn = conn
		self.req = req
        self.main = main 
        self.stateful = stateful
		if stateful then
			-- 如果是有状态的编程，则创建协程块
			controller = coroutine.create(main)
		else
			controller = main
		end
		self.controller = controller
		return self
	end;
	-- 获取请求的URL，这个值存储在请求的headers的PATH里面
	path = function (self)
		return self.req.headers.PATH
	end;
	-- 获取请求的方法。有GET, POST, JSON 等
    method = function (self)
        return self.req.headers.METHOD
    end;
	-- 检查请求方法是不是JSON
    isRequestJson = function (self)
        return self.req.headers.METHOD == "JSON" or
            self.req.headers['content-type'] == 'application/json'
    end;
	-- 检查请求方法是不是XMLHttpRequest
    isRequestXHR = function (self)
        return self.req.headers['x-requested-with'] == "XMLHttpRequest"
    end;
	-- 给请求生成一个cookie值，放到请求头里面
    zapSession = function (self)
        -- to zap the session we just set a new random cookie instead
        self:setCookie(session.makeSessionCookie())
    end;
	-- 给请求生成一个cookie值，放到请求头里面
    setCookie = function (self, cookie)
        self.req.headers['set-cookie'] = cookie
    end;
	-- 获取当前请求的cookie值
    getCookie = function (self)
        return self.req.headers['cookie']
    end;
	-- 获取当前请求的会话id，实际也就是cookie值
    session = function (self)
        return self.req.session_id
    end;
	-- 关闭连接
    close = function (self)
		-- 这里为何要一个req参数？
        self.conn:close(self.req)
    end;	
	-- 发送响应数据，json格式
    send = function (self, data)
        return self.conn:reply_json(self.req, data)
    end;
	-- 返回json编码的页面
    json = function (self, data, ctype)
        self:page(json.encode(data), 200, "OK", {['content-type'] = ctype or 'application/json'})
    end;
	-- 返回一个报告错误的json信息
	jsonError = function (self, err_code, err_desc)
		self:json { success = false, err_code = err_code, err_desc = err_desc }	
	end;
	-- 页面重定向
    redirect = function (self, url)
        self:page("", 303, "See Other", {Location=url, ['content-type'] = false})
        return true
    end;
    -- 报告一个错误，然后关闭连接
    error = function (self, data, code, status, headers)
        self:page(data, code, status, headers or {['content-type'] = false})
        self:close()
        return false
    end;
	-- 需要用户登录
	loginRequired = function (self, reurl)
		local reurl = reurl or '/index/'
		if isFalse(req.user) then web:redirect(reurl); self:close(); return false end
		return true
	end;
	
    -- 一些关于错误类型的函数
    notFound = function (self, msg) self:error(msg or 'Not Found', 404, 'Not Found') end;
    unauthorized = function (self, msg) self:error(msg or 'Unauthorized', 401, 'Unauthorized') end;
    forbidden = function (self, msg) self:error(msg or 'Forbidden', 403, 'Forbidden') end;
    badRequest = function (self, msg) self:error(msg or 'Bad Request', 400, 'Bad Request') end;

    -- 用于返回常规的Web页面响应
	-- 如果headers中不包含content-type，则会返回'text/html'作为默认类型
	-- 而如果设定了content-type为false，则返回的数据头中不会包含content-type。
    page = function (self, data, code, status, headers)
        headers = headers or {}

        if self.req.headers['set-cookie'] then
            headers['set-cookie'] = self.req.headers['set-cookie']
        end

        headers['server'] = 'Bamboo on Mongrel2'
        local ctype = headers['content-type']

        if ctype == nil then
            headers['content-type'] = 'text/html'
        elseif ctype == false then
            headers['content-type'] = nil
        end

        return self.conn:reply_http(self.req, data, code, status, headers)
    end;
    -- 成功返回的快捷方式
    ok = function (self, msg) self:page(msg or 'OK', 200, 'OK') end;
	
	--------------------------------------------------------------------
	-- 下面的，都是状态编程的函数
	--------------------------------------------------------------------
	-- 接收请求
	-- @return 返回请求对象
    recv = function (self) 
		if not self.stateful then error("This is a stateless handler, can't call recv.") end
		self.req = coroutine.yield()
		return self.req
	end;
	-- 状态编程。接收请求，返回请求的URL
	-- @return 返回请求的URL	
	click = function (self)
		if not self.stateful then error("This is a stateless handler, can't call click.") end
		local req = self:recv()
		return req.headers.PATH
	end;
	-- 状态编程。接收请求，检查请求的URL是不是pattern所限定的内容
	-- @return url, nil | nil, 'Not Found' 如果是，则返回url，否则返回nil和一个描述信息
	expect = function (self, pattern, data, code, status, headers)
		if not self.stateful then error("This is a stateless handler, can't call expect.") end
		self:page(data, code, status, headers)
		local path = self:click()

		if path:match(pattern) then
			return path, nil
		else
			self:error("Not found", 404, "Not Found")
			return nil, "Not Found"
		end
	end;
	-- 先响应一个表单页面，然后接收用户的输入，提交，返回表单解析后的lua对象值
	-- @return 回表单解析后的lua对象值
	prompt = function (self, data, code, status, headers)
		if not self.stateful then error("This is a stateless handler, can't call prompt.") end
		self:page(data, code, status, headers)
		return self:input()
	end;
	-- 状态编程。接收请求。这个请求是一个表单提交的数据，也即输入请求。
	-- @return 返回解析后的form内容，也是一个lua对象
	input = function (self) 
		if not self.stateful then error("This is a stateless handler, can't call input.") end
		local req = self:recv()
		return Form:parse(req), req
	end;

}


return Web

