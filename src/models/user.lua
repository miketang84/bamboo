module(..., package.seeall)


local Model = require 'bamboo.model'
local Session = require 'bamboo.session'
local md5 = require 'md5'
local socket = require 'socket'
local Perm = require 'bamboo.models.permission'

local User = Model:extend {
    __tag = 'Bamboo.Model.User';
	__name = 'User';
	__desc = 'Basic user definition.';
	__indexfd = "username";
	__fields = {
		['username'] = { required=true, unique=true },
		['password'] = { required=true },
		['salt'] = {},
		['email'] = { required=true },
		['nickname'] = {},
		['created_date'] = {type="number"},

		['perms'] = { foreign="Permission", st="MANY" },
		['groups'] = { foreign="Group", st="MANY" },
	};
	

	init = function (self, t)
		if not t then return self end
		
		self.username = t.username
		self.email = t.email
		self.nickname = t.nickname
		self.created_date = socket.gettime()

		math.randomseed(os.time())
		self.salt = tostring(math.random(1, 1000000))
		
		if self.encrypt and type(self.encrypt) == 'function' then
			self.password = self:encrypt(t.password)
		end

		return self
	end;

	encrypt = function(self, password)
		return md5.sumhexa(password .. (self.salt or '')):lower()
	end;

	authenticate = function (self, params)
		I_AM_CLASS(self)

		local user = self:getByIndex(params.username)
		if not user then return false end

		if self.encrypt and type(self.encrypt) == 'function' then
			if user:encrypt(params.password) ~= user.password then
				return false
			end
		else
			if (params.password):lower() ~= user.password then
				return false
			end
		end
		return true, user
	end;

	login = function (self, params)
		I_AM_CLASS_OR_INSTANCE(self)
		-- make instance can use this login
		if isInstance(self) then params = self end
		if not params['username'] or not params['password'] then return nil end
		local authed, user = self:authenticate(params)
		if not authed then return nil end

		Session:setKey('user_id', self:classname() + ':' + user.id)
		Session:hashReversely(user, req.session_id)
		
		return user
	end;

	logout = function (self)
		-- I_AM_CLASS(self)
		-- Class and instance can both call this function
		Session:delHashReversely(user)
		return Session:delKey('user_id')
	end;

	register = function (self, params)
		I_AM_CLASS(self)
		if not params['username'] or not params['password'] then return nil, 101, 'less parameters.' end

		local user_id = self:getIdByIndex(params.username)
		if user_id then return nil, 103, 'the same name user exists.' end

		local user = self(params)
		user:save()

		return user
	end;

	set = function (self, req)
		I_AM_CLASS(self)
		local user_id = req.session['user_id']
		if user_id then
			req.user = self:getById(user_id)
		else
			req.user = nil
		end
		return self
	end;
	
	addPerm = function(self, ...)
		local perms = {...}
		for _, perm in ipairs(perms) do
			local ps = Perm:filter(function(u) return u.name:startsWith(perm) end)
			for _, p in ipairs(ps) do
				self:addForeign('perms', p)
			end
		end
	end;

	hasPerm = function(self, ...)
		local perms = {...}
		for _, perm in ipairs(perms) do
			local ps = Perm:filter(function(u) return u.name:startsWith(perm) end)
			for _, p in ipairs(ps) do
				if not self:hasForeign('perms', p) then
					return false
				end
			end
		end
		return true
	end;
	
	loginRequired = function (self, url)
	    local url = url or '/'
	    if isFalse(req.user) then web:redirect(url); return false end
	    return true
	end;
	
}

return User




