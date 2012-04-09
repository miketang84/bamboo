
module(..., package.seeall)
require 'md5'
require 'posix'

local UUID_TYPE = 'random'
local SMALL_EXPIRE_TIME = 3600*24		    -- one day
local PID = tonumber(posix.getpid().pid)
local HOSTID = posix.hostid()
local RNG_BYTES = 8 						-- 64 bits of randomness should be good
local RNG_DEVICE = '/dev/urandom'

local rdlist = require 'bamboo.redis.list'
local rdset = require 'bamboo.redis.set'
local rdzset = require 'bamboo.redis.zset'
local rdfifo = require 'bamboo.redis.fifo'
local rdzfifo = require 'bamboo.redis.zfifo'
local rdhash = require 'bamboo.redis.hash'

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
    return os.date("%a, %d-%b-%Y %X GMT", os.time() + (seconds or SMALL_EXPIRE_TIME))
end


local makeSessionCookie = function (ident, seconds)
    return ('session=%s; version=1; path=/; expires=%s'):format(
        (ident or makeSessionId()), makeExpires(seconds))
end

local function parseSessionId (cookie)
    if not cookie then return nil end

    return cookie:match('session=(APP-[a-z0-9\-]+);?.*$')
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

        local session = Session:get(req.session_id)
        -- in session, we could not use User model to record something,
	-- because session is lower api, and shouldn't be limited as User model
        if session['user_id'] then
            local user_id = session['user_id']
            local model_name, id = user_id:match('^(%w+):(%d+)$')
            assert(model_name and id, "[ERROR] Session user_id format is not right.")
            local model = bamboo.getModelByName(model_name)
            assert(model, "[ERROR] This user model doesn't registerd.")
            -- get the real user instance, assign it to req.user
            req['user'] = model:getById(id)
        end

        db:expire(session_key, bamboo.config.expiration or SMALL_EXPIRE_TIME)
        req['session'] = session
        
        return true
    end;

    get = function (self, session_id)
        local session_key = PREFIX + (session_id or req.session_id)
        local session_t = db:hgetall(session_key)
        
        local ext_key
        for k, v in pairs(session_t) do
	    if v == "__list__" then
		ext_key = ("%s:%s:list"):format(session_key, k)
		session_t[k] = rdlist.retrieve(ext_key)
	    elseif v == "__set__" then
		ext_key = ("%s:%s:set"):format(session_key, k)
		session_t[k] = rdset.retrieve(ext_key)			
	    elseif v == "__zset__" then
		ext_key = ("%s:%s:zset"):format(session_key, k)			
		session_t[k] = rdzset.retrieve(ext_key)					
	    end
        end
        
        db:expire(session_key, bamboo.config.expiration or SMALL_EXPIRE_TIME)
        return session_t
    end;

    setKey = function (self, key, value, st, session_id)
        checkType(key, 'string')
        local session_key = PREFIX + (session_id or req.session_id)
        local st = st or 'string'
	local ext_key = ("%s:%s:%s"):format(session_key, key, st)
        
        --local session_t = db:hgetall(session_key)
        --session_t[key] = value
        --for k, v in pairs(session_t) do
        --end

	if st == 'string' then
	    assert( isStrOrNum(value),
	    	"[Error] @Session:setKey - Value should be string or number.")
            db:hset(session_key, key, value)
	else
	    -- checkType(val, 'table')
	    if st == 'list' then
		rdlist.save(ext_key, value)
		db:hset(session_key, key, "__list__")
	    elseif st == 'set' then
		rdset.save(ext_key, value)
		db:hset(session_key, key, "__set__")
	    elseif st == 'zset' then
		rdzset.save(ext_key, value)
		db:hset(session_key, key, "__zset__")
	    else
		error("[Error] @Session:setKey - st must be one of 'string', 'list', 'set' or 'zset'")
	    end
	end
        
        --req.session = session_t
        db:expire(session_key, bamboo.config.expiration or SMALL_EXPIRE_TIME)
        return true
    end;

    getKey = function (self, key, session_id)
        checkType(key, 'string')
        local session_key = PREFIX + (session_id or req.session_id)

	local ext_key
	local ovalue = db:hget(session_key, key)
	if ovalue == "__list__" then
	    ext_key = ("%s:%s:list"):format(session_key, k)
	    ovalue = rdlist.retrieve(ext_key)
	elseif ovalue == "__set__" then
	    ext_key = ("%s:%s:set"):format(session_key, k)
	    ovalue = rdset.retrieve(ext_key)			
	elseif ovalue == "__zset__" then
	    ext_key = ("%s:%s:zset"):format(session_key, k)			
	    ovalue = rdzset.retrieve(ext_key)					
	end

	db:expire(session_key, bamboo.config.expiration or SMALL_EXPIRE_TIME)
	return ovalue
    end;

    delKey = function (self, key, session_id)
        checkType(key, 'string')
        local session_key = PREFIX + (session_id or req.session_id)   
        req.session[key] = nil

        return db:hdel(session_key, key)
    end;

    del = function (self, session_id)
        checkType(session_id, 'string')
        local session_key = PREFIX+session_id
        -- req.session = nil

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
	
    setExpiration = function (self, seconds)
	checkType(seconds, 'number')
	bamboo.config.expiration = seconds
    end;
}


return Session

