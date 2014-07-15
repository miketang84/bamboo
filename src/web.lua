
module(..., package.seeall)

local View = require 'bamboo.view'
local json = require 'cjson'
local cmsgpack = require 'cmsgpack'

local function rawwrap(data, meta)
  local ret = {
    data = data or '',  		-- body string to reply
    meta = meta or {}				-- some other info to webserver
  }

  return cmsgpack.pack(ret)
end


local function wrap(data, code, status, headers, meta)
  local ret = {
    data = data or '',  			-- body string to reply
    code = code or 200,				-- http code to reply
    status = status or "OK",		-- http status to reply
    headers = headers or {},		-- http headers to reply
--    conns = conns or {},			-- http connections to receive this reply
    meta = meta or {}				-- some other info to webserver
  }

  return cmsgpack.pack(ret)
end


local Web = Object:extend {
  __name = 'Web';
  init = function (self, main, req)
    self.req = req
    -- self.main = main 
    -- for state programming
    self.controller = coroutine.create(main)
    self.dbs = {}
    
    return self
  end;


  setCookie = function (self, cookie)
      self.req.headers['set-cookie'] = cookie
  end;

  getCookie = function (self)
      return self.req.headers['cookie']
  end;



  json = function (self, data, conns)
      self:page(json.encode(data), 200, "OK", {['content-type'] = 'application/json'}, conns)
  end;

  jsonError = function (self, tbl)
    tbl = tbl or {}
    tbl['success'] = false
    self:json(tbl)	
  end;

  jsonSuccess = function (self, tbl)
    tbl = tbl or {}
    tbl['success'] = true
    self:json(tbl)
  end;

  page = function (self, data, code, status, headers, conns)
    headers = headers or {}

    if self.req.headers and self.req.headers['set-cookie'] then
        headers['set-cookie'] = self.req.headers['set-cookie']
    end

    headers['server'] = 'Bamboo on lgserver'
    local ctype = headers['content-type']

    if ctype == nil then
        headers['content-type'] = 'text/html'
    elseif ctype == false then
        headers['content-type'] = nil
    end

    if bamboo.is_testing then
      -- for bamboo automatic test
      local msg = {
        body = data,
        code = code or 200,
        status = status or 'OK',
        headers = headers or {}
      }
      bamboo.conn:send(self.req, msg)
    else
      local meta = self.req.meta
      meta.conns = conns
      bamboo.ch_send:send(wrap(data, code, status, headers, meta))
    end
    
    return false
  end;


  redirect = function (self, url)
      return self:page("", 303, "See Other", {Location=url, ['content-type'] = false})
  end;

  error = function (self, data, code, status, headers)
      self:page(data or 'error', 500, 'Internal Error', headers or {['content-type'] = false})
      return self:close()
  end;

  ok = function (self, msg) self:page(msg or 'OK', 200, 'OK') end;
  notFound = function (self, msg) return self:error(msg or 'Not Found', 404, 'Not Found') end;
  unauthorized = function (self, msg) return self:error(msg or 'Unauthorized', 401, 'Unauthorized') end;
  forbidden = function (self, msg) return self:error(msg or 'Forbidden', 403, 'Forbidden') end;
  badRequest = function (self, msg) return self:error(msg or 'Bad Request', 400, 'Bad Request') end;

  send = function (self, data, meta)
    if bamboo.is_testing then
      -- for bamboo automatic test
      local msg = {
        data = data,
        meta = meta
      }
      bamboo.conn:send(self.req, msg)
    else
      bamboo.ch_send:send(rawwrap(data, meta))
    end
  end,
  
  close = function (self)
    self:send('', { cmd = 'close' })
    return false
  end,
  
}


return Web

