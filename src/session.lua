
module(..., package.seeall)

require 'md5'
require 'posix'

local UUID_TYPE = 'random'
local PID = tonumber(posix.getpid().pid)
local HOSTID = posix.hostid()
local RNG_BYTES = 8 						-- 64 bits of randomness should be good
local RNG_DEVICE = '/dev/urandom'


-- Thouge Session is not a model, but we use model way to process it
local PREFIX = 'Session:'

------------------------------------------------------------------------
--
local makeRNG = function ()
    if posix.access(RNG_DEVICE) then
        local urandom = assert(io.open(RNG_DEVICE))

        return function()
            return md5.sumhexa(('%s%s%s%s'):format(urandom:read(RNG_BYTES), os.time(), PID, HOSTID))
        end
    else
        print(("WARNING! YOU DO NOT HAVE %s.\n Your session keys aren't very secure."):format(RNG_DEVICE))
        math.randomseed(os.time() + PID + HOSTID)

        return function()
            return md5.sumhexa(('%s%s%s%s'):format(tostring(math.random()), os.time(), PID, HOSTID))
        end
    end
end

local RNG = makeRNG()

local makeSessionId = function ()
    return ('%s%s'):format('APP-', RNG())
end


local makeExpires = function (seconds)
    return os.date("%a, %d-%b-%Y %X GMT", os.time() + seconds)
end


local makeSessionCookie = function (ident, seconds)
    return ('session=%s; version=1; path=/; expires=%s'):format(
        (ident or makeSessionId()), seconds and makeExpires(seconds) or '')  --makeExpires(seconds)
end

local function parseSessionId (cookie)
    if not cookie then return nil end

    return cookie:match('session=(APP%-[a-z0-9%-]+);?.*$')
end


--- to json format request
-- @return: session identifier
------------------------------------------------------------------------
local manuSessionIdJson = function (req)
    local ident = req.data.session_id

    if not ident then
        ident = makeSessionId()
        req.data.session_id = ident
    end

    req.session_id = ident
    return ident
end


--- to http format request
-- @return: session identifier
------------------------------------------------------------------------
local manuSessionIdHttp = function (req)
    local ident = parseSessionId(req.headers['cookie'])

    if not ident then
        ident = makeSessionId()
        local cookie = makeSessionCookie(ident, bamboo.config.expiration)

        req.headers['set-cookie'] = cookie
        req.headers['cookie'] = cookie

  else
    if bamboo.config.expiration then
      local session_key = PREFIX + ident
      local custom_expiration = nil
      if bamboo.config.open_custom_expiration then
        custom_expiration = db:hget(session_key, 'expiration')
      end
      
      if bamboo.config.relative_expiration then
        -- for relative expiration, we need keep the expiration field in session, if have
        -- update the same cookie and session for every visit
        local cookie = makeSessionCookie(ident, custom_expiration or bamboo.config.expiration)
        req.headers['set-cookie'] = cookie
        req.headers['cookie'] = cookie
    
      else
        -- for absolute expiration
        if custom_expiration then
          local cookie = makeSessionCookie(ident, custom_expiration)
          req.headers['set-cookie'] = cookie
          req.headers['cookie'] = cookie
          -- clear the custom expiration flag, for absolute expiration, we only need it once
          db:hdel(session_key, 'expiration')
        end
      end
    end
  end
  
    req.session_id = ident
    return ident
end


local expireit = function (self, session_key)
  local expiration = self.db:hget(session_key, 'expiration') or bamboo.config.expiration or bamboo.SESSION_LIFE
  self.db:expire(session_key, expiration)
end


-- to add session support, we add 
--     Session(redis_db, web, req) 
-- in handler_entry.lua' init function
-- later, can use web.session:setKey(...), web.session:getKey(...)
-- and use req.user, req.session to access session content

local Session 
Session = Object:extend {
  init = function (self, db, web, req) 
    -- contains a db connector for each instance
    self.db = db
    self.req = req
    
    self:identRequest()
    self:set()

    web.session = self
    return self 
  end;

  set = function (self)
    local session_key = PREFIX + self.req.session_id
    if not self.db:hexists(session_key, 'session_id') then
        self.db:hset(session_key, 'session_id', self.req.session_id)
    end

    local session = self.db:hgetall(session_key)
    
    -- attach user object 
    -- in session, we could not use User model to record something,
    -- because session is lower api, and shouldn't be limited as User model
    if session['user_id'] then
        local user_id = session['user_id']
        local model_name, id = user_id:match('^(%w+):(%d+)$')
        assert(model_name and id, "[ERROR] Session user_id format is not right.")
        local model = bamboo.getModelByName(model_name)
        assert(model, "[ERROR] This user model doesn't registerd.")
        -- get the real user instance, assign it to self.req.user
        self.req['user'] = model:getById(id)
        
    end
      
    expireit(session_key)
    self.req['session'] = session

    return true
  end;

  get = function (self, session_id)
    local session_key = PREFIX + (session_id or self.req.session_id)
    local session_t = self.db:hgetall(session_key)

    expireit(session_key)
    return session_t
  end;
  
  setKey = function (self, key, value)
    checkType(key, 'string')
    local session_key = PREFIX + (session_id or self.req.session_id)

    self.db:hset(session_key, key, tostring(value))

    expireit(session_key)
    -- update the in memory value
    self.req.session[key] = value

    return true
  end;

  getKey = function (self, key, session_id)
    checkType(key, 'string')
    local session_key = PREFIX + (session_id or self.req.session_id)

    local value = self.db:hget(session_key, key)
    expireit(session_key)
    
    return value
  end;

  delKey = function (self, key, session_id)
    checkType(key, 'string')
    self.req.session[key] = nil
    
    local session_key = PREFIX + (session_id or self.req.session_id)
    expireit(session_key)
    
    return self.db:hdel(session_key, key)
  end;

  del = function (self, session_id)
    checkType(session_id, 'string')
    local session_key = PREFIX + (session_id or self.req.session_id)

    return self.db:del(session_key)
  end;

  --- calculate the session id of a coming request
  -- @return: session id
  identRequest = function (self)
    return manuSessionIdHttp(self.req)
  end;

  parseSessionId = parseSessionId;
  makeSessionCookie = makeSessionCookie;

  -- redefine global expiration parameter
  setGlobalExpiration = function (self, seconds)
    checkType(seconds, 'number')
    bamboo.config.expiration = seconds
  end;

  -- set expiration for each session
  setExpiration = function (self, seconds, session_id)
    assert(bamboo.config.open_custom_expiration, 
      "[Error] @ setExpiration - for using this function, you must set 'open_custom_expiration=true' in settings.lua firstly!")
    assert(seconds, "[Error] missing params seconds.")
    local session_key = PREFIX + (session_id or self.req.session_id)
    
    self.db:hset(session_key, 'expiration', seconds)
    self.db:expire(session_key, seconds)
  end;
}

return Session
