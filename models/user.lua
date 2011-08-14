module(..., package.seeall)


local Model = require 'bamboo.model'
local Session = require 'bamboo.session'
local md5 = require 'md5'


local User = Model:extend {
    __tag = 'Bamboo.Model.User';
	__name = 'User';
	__desc = 'Basic user definition.';
	__indexfd = "username";
	__fields = {
		['username'] = { required=true, unique=true },
		['password'] = { required=true },
		['email'] = { required=true },
		['nickname'] = {},
		['forwhat'] = {},
		['is_manager'] = {},
		['is_active'] = {},	
		['created_date'] = {},
		['lastlogin_date'] = {},
		['is_logined'] = {},
		
		['perms'] = { foreign="Permission", st="MANY" },
		['groups'] = { foreign="Group", st="MANY" },
	};
	

	init = function (self, t)
		if not t then return self end
		
		self.username = t.username
		self.password = md5.sumhexa(t.password)
		self.email = t.email
		self.nickname = t.nickname
		self.forwhat = t.forwhat
		self.is_manager = t.is_manager
		self.is_active = t.is_active
		self.created_date = os.time()
		self.perms = t.perms
		self.groups = t.groups
		
		return self
	end;
	
	
	authenticate = function (self, params)
		I_AM_CLASS(self)

		local user = self:getByIndex(params.username)
		if not user then return false end
		if md5.sumhexa(params.password) ~= user.password then
			return false
		end
		return true, user
	end;
	
	login = function (self, params)
		I_AM_CLASS(self)
		if not params['username'] or not params['password'] then return nil end
		local authed, user = self:authenticate(params)
		if not authed then return nil end

		Session:setKey('user_id', self:classname() + ':' + user.id)
		return user
	end;
	
	logout = function (self)
		I_AM_CLASS(self)
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

	-- deprecated api
	getFromReq = function (self)
		I_AM_CLASS(self)
		if not req.user then return nil end
		
		local id = req.user.id
		return self:getById(id)
	end;

	pick = function (self)
	    I_AM_CLASS(self)
	    if not req.user then return nil end

	    local id = req.user.id
		req.user = self:getById(id)
		return req.user
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
	
}

return User




