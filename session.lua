
module(..., package.seeall)
require 'md5'
require 'posix'

local UUID_TYPE = 'random'
local BIG_EXPIRE_TIME = 3600*24*14			-- years
local SMALL_EXPIRE_TIME = 3600*24		    -- one day
local PID = tonumber(posix.getpid().pid)
local HOSTID = posix.hostid()
local RNG_BYTES = 8 						-- 64 bits of randomness should be good
local RNG_DEVICE = '/dev/urandom'


local db = BAMBOO_DB
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
    return os.date("%Y-%m-%d %H:%M:%S", os.time() + (seconds or SMALL_EXPIRE_TIME))
end

local makeBigExpires = function (seconds)
    return os.date("%Y-%m-%d %H:%M:%S", os.time() + (seconds or BIG_EXPIRE_TIME))
end

local makeSessionCookie = function (ident)
    return ('session="%s"; version=1; path=/; expires=%s'):format(
        (ident or makeSessionId()), makeExpires())
end

local function parseSessionId (cookie)
    if not cookie then return nil end

    return cookie:match('session="(APP-[a-z0-9\-]+)";?')
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
        local cookie = makeSessionCookie(ident)

        req.headers['set-cookie'] = cookie
        req.headers['cookie'] = cookie
    end

    req.session_id = ident
    return ident
end



local Session = Object:extend {
	__tag = 'Bamboo.Session';
    __name = 'Session';
    -- nothing to do
	init = function (self) return self end;
    
    set = function (self, req)
        local session_key = PREFIX + req.session_id
        if not db:hexists(session_key, 'session_id') then
            db:hset(session_key, 'session_id', req.session_id)
        end

        local session = db:hgetall(session_key)
        -- in session, we could not use User model to record something,
		-- because session is lower api, and shouldn't be limited as User model
        if session['user_id'] then
            local user_id = session['user_id']
            local model_name, id = user_id:match('^(%w+):(%d+)$')
            local model = bamboo.getModelByName(model_name)
            -- get the real user instance, assign it to req.user
            req['user'] = model:getById(id)
        end

        db:expire(session_key, SMALL_EXPIRE_TIME)
        req['session'] = session
        
        return true
    end;

    get = function (self)
        local session_key = PREFIX+req.session_id
        db:expire(session_key, SMALL_EXPIRE_TIME)
        return db:hgetall(session_key)
    end;

    setKey = function (self, key, value)
        checkType(key, value, 'string', 'string')
        local session_key = PREFIX+req.session_id
        
        local session_t = db:hgetall(session_key)
        session_t[key] = value
        for k, v in pairs(session_t) do
            db:hset(session_key, k, v)
        end
        
        req.session = session_t
        db:expire(session_key, SMALL_EXPIRE_TIME)
        return true
    end;

    getKey = function (self, key)
        checkType(key, 'string')
        local session_key = PREFIX+req.session_id
        db:expire(session_key, SMALL_EXPIRE_TIME)
        
        return db:hget(session_key, key)
    end;

    delKey = function (self, key)
        checkType(key, 'string')
        local session_key = PREFIX+req.session_id   
        req.session[key] = nil

        return db:hdel(session_key, key)
    end;

    del = function (self, session_key)
        checkType(session_key, 'string')
        local session_key = PREFIX+session_key
        req.session = nil

        return db:del(session_key)
    end;

    --- calculate the session id of a coming request
    -- @return: session id
    identRequest = function (req)
        if req.headers.METHOD == "JSON" then
            return manuSessionIdJson(req)
        else
            return manuSessionIdHttp(req)
        end
    end;

	parseSessionId = parseSessionId;
}


return Session

