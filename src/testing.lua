-- execute the bootup file
dofile('/usr/local/bin/bamboo_handler')

module(..., package.seeall)

local Form = require 'bamboo.form'
local borrowed = bamboo.EXPORT_FOR_TESTING

local CONFIG_FILE = "settings.lua"
local TEMPLATES = "views/"

-- These globals are used to implement fake state for requests.
local SENDER_ID = "3ddfbc58-a249-45c9-9446-00b73de18f7c"
local SESSION_ID = "d257873dfdc254ff6ff930a1c44aa6a9"

local CONN_ID = 1

local RUNNERS = {}

local RESPONSES = {}

local DEFAULT_UAGENT = "curl/7.19.7 (i486-pc-linux-gnu) libcurl/7.19.7 OpenSSL/0.9.8k zlib/1.2.3.3 libidn/1.15" 

-- This constructs a fake mongrel2 connection that allows for running
-- a handler but yields to receive a request and stuffs all the responses
-- into RESPONSES for later inspection.
local function makeFakeConnect(config)
    local conn = {config = config}

    function conn:recv()
        local req = coroutine.yield()
        assert(req.headers.PATH:match(self.config.route), ("[ERROR] Invalid request %q sent to handler: %q"):format(req.headers.PATH, self.config.route))
        return req
    end

    function conn:send(uuid, conn_id, msg)
        RESPONSES[#RESPONSES + 1] = {
            type = "send",
            conn_id = conn_id,
            msg = msg
        }
    end

    function conn:reply(req, msg)
        RESPONSES[#RESPONSES + 1] = {
            type = "reply",
            req = req,
            msg = msg
        }
    end

    function conn:reply_json(req, data)
        RESPONSES[#RESPONSES + 1] = {
            type = "reply_json",
            req = req,
            data = data
        }
    end

    function conn:reply_http(req, body, code, status, headers)
        RESPONSES[#RESPONSES + 1] = {
            type = "reply_http",
            req = req,
            body = body,
            code = code or 200,
            status = status or 'OK',
            headers = headers or {}
        }
    end

    function conn:deliver(uuid, idents, data)
        RESPONSES[#RESPONSES + 1] = {
            type = "deliver",
            idents = idents,
            data = data
        }
    end

    function conn:deliver_json(uuid, idents, data)
        RESPONSES[#RESPONSES + 1] = {
            type = "deliver_json",
            idents = idents,
            data = data
        }
    end

    function conn:deliver_http(uuid, idents, body, code, status, headers)
        RESPONSES[#RESPONSES + 1] = {
            type = "deliver_http",
            idents = idents,
            body = body,
            code = code or 200,
            status = status or 'OK',
            headers = headers
        }
    end

    function conn:deliver_close(uuid, idents)
        RESPONSES[#RESPONSES + 1] = {
            type = "deliver_close",
            idents = idents
        }
    end

    function conn:close()
        CONN_ID = CONN_ID + 1
    end

    return conn
end

-- Replaces the base start with one that creates a fake m2 connection.
local start = function(config)
	local config = config or borrowed.updateConfig(config, CONFIG_FILE)

    config.methods = config.methods or borrowed.DEFAULT_ALLOWED_METHODS

    config.ident = config.ident or borrowed.default_ident

    local conn = makeFakeConnect(config)

    local runner = coroutine.wrap(borrowed.run)
    runner(conn, config)

    -- This runner is used later to feed fake requests to the run loop.
    RUNNERS[config.route] = runner
end

-- Makes fake requests with all the right stuff in them.
function makeFakeRequest(session, method, path, query, body, headers, data)
    local req = {
        conn_id = CONN_ID,
        sender = SENDER_ID,
        path = path,
        body = body or "",
        data = data or {},
    }

    if method == "JSON" then
        req.data.session_id = session.SESSION_ID
    end

    req.headers  = {
        PATTERN = path,
        METHOD = method,
        QUERY = query,
        VERSION = "HTTP/1.1",
        ['x-forwarded-for'] = '127.0.0.1',
        host = "localhost:6767",
        PATH = path,
        ['user-agent'] = DEFAULT_UAGENT,
        cookie = session.COOKIE,
        URI = query and (path .. '?' .. query) or path,
    }

    table.update(req.headers, headers or {})

    return req
end


function routeRequest(req)
    for pattern, runner in pairs(RUNNERS) do
        if req.headers.PATH:match(pattern) then
            return runner(req)
        end
    end

    assert(false, ("[ERROR] Request for %q path didn't match any loaded handlers."):format(req.headers.PATH))
end


-- Sets up a fake "browser" that is used in tests to pretend to send
-- and receive requests and then analyze the results.  It assumes a 
-- string request/response mode of operation and will throw errors if
-- that's not followed.
function browser(name, session_id, conn_id)
    CONN_ID = CONN_ID + 1

    local Browser = {
        RESPONSES = {},
        COOKIE = ('session="APP-%s"'):format(session_id or SESSION_ID),
        SESSION_ID = session_id or SESSION_ID,
        name = name,
    }

    function Browser:send(method, path, query, body, headers, data)
        routeRequest(makeFakeRequest(self, method, path, query, body, headers, data))

        local resp_count = #RESPONSES

        while #RESPONSES > 0 do
            local resp = table.remove(RESPONSES)
            if resp.req then
                self:extract_cookie(resp.req.headers)
            end
            self.RESPONSES[#self.RESPONSES] = resp
        end

        assert(resp_count > 0, ("[ERROR] Your application did not send a response to %q, that'll cause your browser to stall."):format(path))

        assert(resp_count == 1, ("[ERROR] A request for %q sent %d responses, that'll make the browser do really weird things."):format(path, resp_count))

    end

    function Browser:expect(needed)
        local last = self.RESPONSES[#self.RESPONSES]

        for k,v in pairs(last) do
            local pattern = needed[k]

            if pattern then
                if not tostring(v):match(tostring(pattern)) then
                    error(("[ERROR] [%s] Failed expect: %q did not match %q but was %q:%q"
                        ):format(self.name, k, pattern, v, last.body))
                end
            end
        end

        return last
    end


    function Browser:exited()
        return self.SESSION_ID  -- and not .get_state(self.SESSION_ID)
    end

    function Browser:extract_cookie(headers)
        local cookie = headers['set-cookie']

        if cookie and cookie ~= self.COOKIE then
            self.COOKIE = cookie
            self.SESSION_ID = borrowed.parseSessionId(cookie)
        end
    end

    function Browser:click(path, expect)
        self:send("GET", path)
        return self:expect(expect or { code = 200 })
    end
    
    -- alias
    Browser.get = Browser.click

    function Browser:submit(path, form, expect, headers)
		local form = form or {}
        local body = Form:encode(form)
        headers = headers or {}

        expect = expect or {code = 200}
        if not expect.code then expect.code = 200 end

        headers['content-type'] = "application/x-www-form-urlencoded"
        headers['content-length'] = #body

        self:send("POST", path, nil, body, headers)

        return self:expect(expect)
    end

    Browser.post = Browser.submit
    
    function Browser:xhr(path, form, expect)
        local headers = {['x-requested-with'] = "XMLHttpRequest"}
        self:submit(path, form, headers)
        return self:expect(expect or { code = 200 })
    end

    function Browser:query(path, params, expect, headers)
		local params = params or {}
        local query = Form:encode(params)
        self:send("GET", path, query, nil, headers)
        return self:expect(expect or { code = 200 })
    end

	function Browser:ajaxGet(path, params, expect, headers)
		local headers = {['x-requested-with'] = "XMLHttpRequest"}
        local resp = self:query(path, params, expect, headers)
		local res = json.decode(resp.body)
		checkType(res, 'table')
		return res
	end
		
	function Browser:ajaxPost(path, form, expect, headers)
		local headers = {['x-requested-with'] = "XMLHttpRequest"}
        local resp = self:submit(path, form, expect, headers)
		local res = json.decode(resp.body)
		checkType(res, 'table')
		return res
	end 
	

    return Browser
end

-------------------------------------------------------------------
-- here, boot the testing server
start(borrowed.config)
-------------------------------------------------------------------
