module(..., package.seeall)


local db = BAMBOO_DB
local Model = require 'bamboo.model'
local Session = require 'bamboo.session'
local md5 = require 'md5'


local User = Model:extend {
    __tag = 'Bamboo.Model.User';
	__name = 'User';
	--username = ''; 	-- 必须（这个内容可以为email, 在某些场合下喜欢这样）
    --password = ''; 	-- 必须
    --email = ''; 	-- 必须
   
    --is_manager = false;	-- 指明用户是否具有网站的管理权限（可能是部分权限）
    --is_active = true; 		-- 是否是活动用户，代替删除
    --lastlogin_date = 0; 	-- 上次登录的时间日期
    --created_date = 0; 		-- 帐号创建的时间日期

    --perms = {};    	-- 权限集合
    --groups = {};    -- 用户所属组集合
	
	init = function (self, t)
		if not t then return self end
		
		self.username = t.username
		self.name = self.username
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
		-- 从数据库中取出按名字索引的字段，这个时候user实例还没有生成
		local user_nameindex = self:getNameIndex(params.username)
		if not user_nameindex then return false end
		-- 取出用户对象
		local user = self:get{id=user_nameindex}
		if not user then return false end
		if md5.sumhexa(params.password) ~= user.password then
			return false
		end
		return true, user
	end;
	
	-- 类函数，此处的self是User本身
	login = function (self, params, req)
		if not params['username'] or not params['password'] then return nil end
		local authed, user = self:authenticate(params)
		if not authed then return nil end
		-- 登录，即是在用户所在的session中添加一个user_id字段，值为用户的id号
		-- 登录的过期时间，即为session的过期时间
		Session:setKey(req, 'user_id', user.id)
		return user
	end;
	
	logout = function (self, req)
		return Session:delKey(req, 'user_id')
	end;
	
	-- 类函数，此处的self是User本身
	register = function (self, params, req)
		if not params['username'] or not params['password'] then return nil, 101, 'less parameters.' end
		-- 查看数据库中是否有同名用户
		local user_nameindex = self:getNameIndex(params.username)
		print('user_nameindex', user_nameindex)
		-- 如果有，就返回false
		if user_nameindex then return nil, 103, 'the same name user exists.' end
		
		-- 否则，创建一个用户
		local user = self(params)
		-- 保存到数据库
		user:save()
		-- 创建一个名字到id的反向索引到数据库
		user:saveName()
		
		return user
	end;
	
	-- 类函数，此处的self是User本身
	set = function (self, req)
		local user_id = req.session['user_id']
		if user_id then
			req.user = self:get{ id = user_id }
		else
			req.user = nil
		end
		return true
	end;
	

	
}

return User




