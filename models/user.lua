module(..., package.seeall)


local db = BAMBOO_DB
local Model = require 'bamboo.model'
local Session = require 'bamboo.session'
local md5 = require 'md5'


local User = Model:extend {
    __tag = 'Bamboo.Model.User';
	__name = 'User';
	__desc = 'Basic user definition.';
	__fields = {
		['name'] = {},
		['username'] = { required=true },				-- 必须（这个内容可以为email, 在某些场合下喜欢这样）
		['password'] = { required=true },				-- 必须
		['email'] = { required=true },					-- 必须
		['is_manager'] = {},			-- 指明用户是否具有网站的管理权限（可能是部分权限）
		['is_active'] = {},			-- 是否是活动用户，代替删除
		['created_date'] = {},			-- 帐号创建的时间日期
		['lastlogin_date'] = {}, 		-- 上次登录的时间日期
		['is_logined'] = {},		-- 是否在线上
		['perms'] = {},				-- 权限集合
		['groups'] = {},				-- 用户所属组集合
	};

	init = function (self, t)
		if not t then return self end
		
		self.name = t.username or self.name		-- 每个模型必须有这个字段
		self.username = t.username
		self.password = md5.sumhexa(t.password)
		self.email = t.email
		self.is_manager = t.is_manager
		self.is_active = t.is_active
		self.created_date = os.time()
		self.perms = t.perms
		self.groups = t.groups
		
		return self
	end;
	
	
	-- 类函数，此处的self是User本身
	authenticate = function (self, params)
		I_AM_CLASS(self)
		-- 取出用户对象
		local user = self:getByName(params.username)
		if not user then return false end
		if md5.sumhexa(params.password) ~= user.password then
			return false
		end
		return true, user
	end;
	
	-- 类函数，此处的self是User本身
	login = function (self, params)
		I_AM_CLASS(self)
		if not params['username'] or not params['password'] then return nil end
		local authed, user = self:authenticate(params)
		if not authed then return nil end
		-- 登录，即是在用户所在的session中添加一个user_id字段，值为用户的id号
		-- 登录的过期时间，即为session的过期时间
		Session:setKey('user_id', user.id)
		return user
	end;
	
	logout = function (self)
		I_AM_CLASS(self)
		return Session:delKey('user_id')
	end;
	
	-- 类函数，此处的self是User本身，也可以是User的继承类型
	register = function (self, params)
		I_AM_CLASS(self)
		if not params['username'] or not params['password'] then return nil, 101, 'less parameters.' end
		-- 查看数据库中是否有同名用户
		local user_id = self:getIdByName (params.username)
		-- 如果有，就返回false
		if user_id then return nil, 103, 'the same name user exists.' end
		
		-- 否则，创建一个用户
		local user = self(params)
		-- 保存到数据库
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
	    return self:getById(id)
    end;
	
	
	-- 类函数，此处的self是User本身
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




