
module(..., package.seeall)
require 'md5'
require 'posix'

local UUID_TYPE = 'random'
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

local setStructure = function (session_key, k, v, st)
	local ext_key = ("%s:%s:%s"):format(session_key, k, st)

	if st == 'list' then
		rdlist.save(ext_key, v)
		db:hset(session_key, k, "__list__")
	elseif st == 'set' then
		rdset.save(ext_key, v)
		db:hset(session_key, k, "__set__")
	elseif st == 'zset' then
		rdzset.save(ext_key, v)
		db:hset(session_key, k, "__zset__")
	else
		error("[Error] @Session:setKey - st must be one of 'string', 'list', 'set' or 'zset'")
	end

end

-- get the structure value according to string agent
local getStructure = function (session_key, k, v)
	local ext_key
	local ext_val = v
	if v == "__list__" then
		ext_key = ("%s:%s:list"):format(session_key, k)
		ext_val = rdlist.retrieve(ext_key)
	elseif v == "__set__" then
		ext_key = ("%s:%s:set"):format(session_key, k)
		ext_val = rdset.retrieve(ext_key)
	elseif v == "__zset__" then
		ext_key = ("%s:%s:zset"):format(session_key, k)
		ext_val = rdzset.retrieve(ext_key)
	end
	
	return ext_val
end


local Session 
Session = Object:extend {
	-- nothing to do
	init = function (self) return self end;

	set = function (self)
		local session_key = PREFIX + req.session_id
		if not db:hexists(session_key, 'session_id') then
		    db:hset(session_key, 'session_id', req.session_id)
		end

		local session = db:hgetall(session_key)
		for k, v in pairs(session) do
				session[k] = getStructure(session_key, k, v)
		end
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
			
			local expiration = session.expiration or bamboo.config.expiration or bamboo.SESSION_LIFE
		db:expire(session_key, expiration)
		req['session'] = session

		return true
	end;

	get = function (self, session_id)
		local session_key = PREFIX + (session_id or req.session_id)
		local session_t = db:hgetall(session_key)

		for k, v in pairs(session_t) do
				session_t[k] = getStructure(session_key, k, v)
		end

			if bamboo.config.relative_expiration then
				db:expire(session_key, session_t.expiration or bamboo.config.expiration or bamboo.SESSION_LIFE)
		end
		return session_t
	end;

	userHash = function (self, user, session_id)
		local user_id = format("%s:%s", user:classname(), user.id)
		-- if open user single login limitation
		if bamboo.config.user_single_login then
			local sid = db:hget('_users_sessions', user_id)
			-- if logined before, force to logout it 
			if sid and sid ~= session_id then
				Session:del(sid)
			end
		end
		
		db:hset('_users_sessions', user_id, session_id)
	end;
	
	getUserHash = function (self, user)
		local user = user or req.uesr
		assert(user, '[Error] @Session getUserHash - user is nil.')
		local user_id = format("%s:%s", user:classname(), user.id)
		return db:hget('_users_sessions', user_id)
	end;

	delUserHash= function (self, user)
		local user_id = format("%s:%s", user:classname(), user.id)
		db:hdel('_users_sessions', user_id)
	end;
	
    setKey = function (self, key, value, st, session_id)
        checkType(key, 'string')
        local session_key = PREFIX + (session_id or req.session_id)
        local st = st or 'string'

		if st == 'string' then
			assert( isNumOrStr(value),
				"[Error] @Session:setKey - Value should be string or number.")
			db:hset(session_key, key, value)
		else
			setStructure(session_key, key, value, st)
		end

		if bamboo.config.relative_expiration then
			local expiration = db:hget(session_key, 'expiration') or bamboo.config.expiration or bamboo.SESSION_LIFE
			db:expire(session_key, expiration)
        end

        return true
    end;

    getKey = function (self, key, session_id)
        checkType(key, 'string')
        local session_key = PREFIX + (session_id or req.session_id)

		local ovalue = db:hget(session_key, key)
		local nvalue = getStructure(session_key, key, ovalue)

		if bamboo.config.relative_expiration then
			local expiration = db:hget(session_key, 'expiration') or bamboo.config.expiration or bamboo.SESSION_LIFE
			db:expire(session_key, expiration)
        end
		
		return nvalue
    end;

    delKey = function (self, key, session_id)
        checkType(key, 'string')
        local session_key = PREFIX + (session_id or req.session_id)
        req.session[key] = nil

		if bamboo.config.relative_expiration then
			local expiration = db:hget(session_key, 'expiration') or bamboo.config.expiration or bamboo.SESSION_LIFE
			db:expire(session_key, expiration)
        end
        return db:hdel(session_key, key)
    end;

    del = function (self, session_id)
        checkType(session_id, 'string')
        local session_key = PREFIX + (session_id or req.session_id)

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
		local session_key = PREFIX + (session_id or req.session_id)
		
		db:hset(session_key, 'expiration', seconds)
		db:expire(session_key, seconds)
    end;
}


return Session

