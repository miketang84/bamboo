
module(..., package.seeall)

local Session = require 'bamboo.session'
local Form  = require 'bamboo.form'
local View = require 'bamboo.view'

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
			-- state programming
			controller = coroutine.create(main)
		else
			controller = main
		end
		self.controller = controller
		return self
	end;

	path = function (self)
		return self.req.headers.PATH
	end;

    method = function (self)
        return self.req.headers.METHOD
    end;

    isRequestJson = function (self)
        return self.req.headers.METHOD == "JSON" or
            self.req.headers['content-type'] == 'application/json'
    end;

    isAjax = function (self)
        return self.req.headers['x-requested-with'] == "XMLHttpRequest"
    end;

    zapSession = function (self)
        -- to zap the session we just set a new random cookie instead
        self:setCookie(Session.makeSessionCookie())
    end;

    setCookie = function (self, cookie)
        self.req.headers['set-cookie'] = cookie
    end;

    getCookie = function (self)
        return self.req.headers['cookie']
    end;

    session = function (self)
        return self.req.session_id
    end;

    close = function (self)
        self.conn:close(self.req)
    end;	

    send = function (self, data)
        return self.conn:reply_json(self.req, data)
    end;

    json = function (self, data, ctype)
        self:page(json.encode(data), 200, "OK", {['content-type'] = ctype or 'application/json'})
    end;

	jsonError = function (self, err_code, err_desc)
		self:json { success = false, err_code = err_code, err_desc = err_desc }	
	end;

	jsonSuccess = function (self, tbl)
		tbl['success'] = true
		self:json(tbl)
	end;
	
    redirect = function (self, url)
        self:page("", 303, "See Other", {Location=url, ['content-type'] = false})
        return true
    end;

    error = function (self, data, code, status, headers)
        self:page(data, code, status, headers or {['content-type'] = false})
        self:close()
        return false
    end;

	loginRequired = function (self, reurl)
		local reurl = reurl or '/index/'
		if isFalse(req.user) then web:redirect(reurl); return false end
		return true
	end;
	

    pageNotFound = function (self, msg) return self:error(msg or 'Page Not Found', 404, 'Not Found') end;
    unauthorized = function (self, msg) return self:error(msg or 'Unauthorized', 401, 'Unauthorized') end;
    forbidden = function (self, msg) return self:error(msg or 'Forbidden', 403, 'Forbidden') end;
    badRequest = function (self, msg) return self:error(msg or 'Bad Request', 400, 'Bad Request') end;


    page = function (self, data, code, status, headers)
        headers = headers or {}

        if self.req.headers['set-cookie'] then
            headers['set-cookie'] = self.req.headers['set-cookie']
        end

        headers['server'] = 'Bamboo on Monserver'
        local ctype = headers['content-type']

        if ctype == nil then
            headers['content-type'] = 'text/html'
        elseif ctype == false then
            headers['content-type'] = nil
        end

        self.conn:reply_http(self.req, data, code, status, headers)
		return false
    end;
	
	html = function (self, html_tmpl, tbl)
		local tbl = tbl or {}
		self:page(View(html_tmpl)(tbl))
		return false
	end;
	
    ok = function (self, msg) self:page(msg or 'OK', 200, 'OK') end;
	
	--------------------------------------------------------------------
	-- State Programming
	--------------------------------------------------------------------

    recv = function (self) 
		if not self.stateful then error("This is a stateless handler, can't call recv.") end
		self.req = coroutine.yield()
		return self.req
	end;

	click = function (self)
		if not self.stateful then error("This is a stateless handler, can't call click.") end
		local req = self:recv()
		return req.headers.PATH
	end;

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

	prompt = function (self, data, code, status, headers)
		if not self.stateful then error("This is a stateless handler, can't call prompt.") end
		self:page(data, code, status, headers)
		return self:input()
	end;

	input = function (self) 
		if not self.stateful then error("This is a stateless handler, can't call input.") end
		local req = self:recv()
		return Form:parse(req), req
	end;

}


return Web

