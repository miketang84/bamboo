
module(..., package.seeall)

local View = require 'bamboo.view'

local Web = Object:extend {
	__name = 'Web';
	init = function (self, conn, main, req)
		self.conn = conn
		self.req = req
        self.main = main 
		-- for state programming
		self.controller = coroutine.create(main)
		return self
	end;


    setCookie = function (self, cookie)
        self.req.headers['set-cookie'] = cookie
    end;

    getCookie = function (self)
        return self.req.headers['cookie']
    end;

    close = function (self)
        self.conn:close(self.req)
    end;	

    json = function (self, data, conns)
        self:page(json.encode(data), 200, "OK", {['content-type'] = 'application/json'}, conns)
    end;

    jsonError = function (self, err_code, err_desc)
		self:json { success = false, err_code = err_code, err_desc = err_desc }	
    end;

    jsonSuccess = function (self, tbl)
		local tbl = tbl or {}
		tbl['success'] = true
		self:json(tbl)
    end;
	
    page = function (self, data, code, status, headers, conns)
        headers = headers or {}

        if self.req.headers['set-cookie'] then
            headers['set-cookie'] = self.req.headers['set-cookie']
        end

        headers['server'] = 'Bamboo on lgserver'
        local ctype = headers['content-type']

        if ctype == nil then
            headers['content-type'] = 'text/html'
        elseif ctype == false then
            headers['content-type'] = nil
        end

        self.conn:reply_http(data, code, status, headers, conns, self.req.meta)
		return false
    end;


    redirect = function (self, url)
        self:page("", 303, "See Other", {Location=url, ['content-type'] = false})
        return true
    end;

    error = function (self, data, code, status, headers)
		data = data or 'error'
        self:page(data, code, status, headers or {['content-type'] = false})
        self:close()
        return false
    end;

    ok = function (self, msg) self:page(msg or 'OK', 200, 'OK') end;
    notFound = function (self, msg) return self:error(msg or 'Not Found', 404, 'Not Found') end;
    unauthorized = function (self, msg) return self:error(msg or 'Unauthorized', 401, 'Unauthorized') end;
    forbidden = function (self, msg) return self:error(msg or 'Forbidden', 403, 'Forbidden') end;
    badRequest = function (self, msg) return self:error(msg or 'Bad Request', 400, 'Bad Request') end;

	
	-- deprecated
	html = function (self, html_tmpl, tbl)
		local tbl = tbl or {}
		self:page(View(html_tmpl)(tbl))
		return false
    end;

}


return Web

