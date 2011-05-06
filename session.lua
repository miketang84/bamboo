
module(..., package.seeall)
require 'md5'
require 'posix'

local UUID_TYPE = 'random'
local BIG_EXPIRE_TIME = 20					-- years
local SMALL_EXPIRE_TIME = 3600*24*14		-- two weeks
local PID = tonumber(posix.getpid().pid)
local HOSTID = posix.hostid()
local RNG_BYTES = 8 						-- 64 bits of randomness should be good
local RNG_DEVICE = '/dev/urandom'


local db = BAMBOO_DB
-- 这里，我们把Session也看作一个模型
local PREFIX = 'Session:'

------------------------------------------------------------------------
-- 一些内部使用的函数
------------------------------------------------------------------------
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

local makeBigExpires = function ()
    local tmp = os.date("*t", os.time())
    tmp.year = tmp.year + BIG_EXPIRE_TIME
    return os.date("%Y-%m-%d %H:%M:%S", os.time(tmp))
end

local makeSessionCookie = function (ident)
    return ('session="%s"; version=1; path=/; expires=%s'):format(
        (ident or makeSessionId()), makeExpires())
end

local parseSessionId = function (cookie)
    if not cookie then return nil end

    return cookie:match('session="(APP-[a-z0-9\-]+)";?')
end

------------------------------------------------------------------------
-- 对json形式来临的req作加工处理，确保req.data和req中都有session_id这个成员值
-- @return 返回cookie id，也即session id值
------------------------------------------------------------------------
local manuSessionIdJson = function (req)   -- json_ident()
    local ident = req.data.session_id

    if not ident then
        ident = makeSessionId()
        req.data.session_id = ident
    end

    req.session_id = ident
    return ident
end

------------------------------------------------------------------------
-- 对http形式来临的req作加工处理，确保req.data和req中都有session_id这个成员值
-- @return 返回cookie id，也即session id值
------------------------------------------------------------------------
local manuSessionIdHttp = function (req)
    local ident = parseSessionId(req.headers['cookie'])

    if not ident then
        ident = makeSessionId()
        local cookie = makeSessionCookie(ident)

        req.headers['set-cookie'] = cookie
        req.headers['cookie'] = cookie
        req.session_id = ident
    end

    req.session_id = ident
    return ident
end



local Session = Object:extend {
	__tag = 'Bamboo.Session';
    __name = 'Session';
    -- nothing to do
	init = function (self) return self end;
    
    -- 虽然Session继承自Model，但由于Session操作的特殊性，它基本上还是起到一个模块的作用
    -- 即并不产生具体的实例对象。因此，这里面会重新实现一些函数，并且，实现的这些函数的参
    -- 数里面，都没有self作为第一个参数。那为什么不把它直接实现为一个模块呢？因为它要涉及
    -- 操作数据库，感觉弄成一个类，会好一点。以后说不定可以供别人继承呢。
    -- 现在看来，把session做成一个模块更好一点(110505)。
    -- 在数据库中创建一个hash表项
    set = function (self, req)
        local session_key = PREFIX+req.session_id
        if not db:hexists(session_key, 'session_id') then
            db:hset(session_key, 'session_id', req.session_id)
        end
        -- 同步req中的session表
        local session = db:hgetall(session_key)
        -- 下面这段代码的工作在后面的User:set()函数中已经做了
        -- session是比User低一级的模块，在这里面不能引用User，只能用底层redis的API
        if session['user_id'] then
            -- 根据session中记录的用户id号，获取到真正的用户对象
            local id = session['user_id']
            -- 所以，req.user不是一个真正的User对象，而只是一个包含user信息的一个表
            req['user'] = db:hgetall('User:' + id)
        end
        -- 让所有的session记录都在最后一次访问的一周后自动过期，这里这个数后面要换
        db:expire(session_key, SMALL_EXPIRE_TIME)
        req['session'] = session
        
        return true
    end;

    -- 返回一个table
    get = function (self)
        local session_key = PREFIX+req.session_id
        db:expire(session_key, SMALL_EXPIRE_TIME)
        return db:hgetall(session_key)
    end;

    setKey = function (self, key, value)
        checkType(key, value, 'string', 'string')
        -- 这里，req直接用的全局变量
        local session_key = PREFIX+req.session_id
        
        -- 这里还必须这样，先把之前的数据取出来，把新数据加到lua表中，
        -- 再一次性写到数据库hash项中去，这样存的数据才正确。直接写新hash子项
        -- 到数据库的话，会把之前的信息清除掉。很奇怪，为什么？怀疑是系统环境
        -- 是不是因为对key加了expire的原因？
        local session_t = db:hgetall(session_key)
        session_t[key] = value
        for k, v in pairs(session_t) do
            db:hset(session_key, k, v)
        end
        
        -- 同步req中的session表
        req.session = session_t
        db:expire(session_key, SMALL_EXPIRE_TIME)
        return true
    end;

    -- 返回
    getKey = function (self, key)
        checkType(key, 'string')
        local session_key = PREFIX+req.session_id
        db:expire(session_key, SMALL_EXPIRE_TIME)
        
        -- 这里，我们返回的数据，不做反序列化操作，主要是为了效率考虑
        return db:hget(session_key, key)
    end;

    -- 返回是否删除成功标志
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

    ------------------------------------------------------------------------
    -- 对外接口
    -- @return 返回cookie id，也即session id值，不管是来自客户端的还是新产生的
    ------------------------------------------------------------------------
    identRequest = function (req)		-- default_ident
        if req.headers.METHOD == "JSON" then
            return manuSessionIdJson(req)
        else
            return manuSessionIdHttp(req)
        end
    end;

}


return Session

