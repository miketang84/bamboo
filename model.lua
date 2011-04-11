module(..., package.seeall)

local db = BAMBOO_DB


local getkey = function (pattern)
	local keytable = db:keys(pattern)
	if #keytable == 0 then return nil end
	if #keytable > 1 then error('Instances suitable is more than one.') end
	-- 只有一个实例的key了，后面希望在redis里面添加一条指令，
	-- 通过匹配找到第一个key，就立即返回
	return keytable[1]
end




_G['I_AM_CLASS'] = function (self)
	assert(self:isClass(), 'This function is only allowed to be called by class singleton.')
end
------------------------------------------------------------------------
-- 数据库检索的限制函数集
-- 由于使用的时候希望不再做导入工作，所以在加载Model模块的时候直接导入到全局环境中
------------------------------------------------------------------------

_G['lt'] = function (limitation)
	return function (v)
		if v < limitation then
			return true
		else
			return false
		end
	end
end

_G['gt'] = function (limitation)
	return function (v)
		if v > limitation then
			return true
		else
			return false
		end
	end
end


_G['le'] = function (limitation)
	return function (v)
		if v <= limitation then
			return true
		else
			return false
		end
	end
end

_G['ge'] = function (limitation)
	return function (v)
		if v >= limitation then
			return true
		else
			return false
		end
	end
end

_G['bt'] = function (small, big)
	return function (v)
		if v > small and v < big then
			return true
		else
			return false
		end
	end
end

_G['be'] = function (small, big)
	return function (v)
		if v >= small and v < big then
			return true
		else
			return false
		end
	end
end

_G['outside'] = function (small, big)
	return function (v)
		if v < small and v > big then
			return true
		else
			return false
		end
	end
end

_G['contains'] = function (substr)
	return function (v)
		if v:contains(substr) then 
			return true
		else
			return false
		end
	end
end

_G['startsWith'] = function (substr)
	return function (v)
		if v:startsWith(substr) then 
			return true
		else
			return false
		end
	end
end

_G['endsWith'] = function (substr)
	return function (v)
		if v:endsWith(substr) then 
			return true
		else
			return false
		end
	end
end

------------------------------------------------------------------------
-- Model定义
-- Model是Bambo中涉及到数据库及模型定义的通用接口
------------------------------------------------------------------------
local Model 
Model = Object:extend {
	__tag = 'Bamboo.Model';
	-- __name和__tag的最后一个单词不一定要保持一致
	__name = 'Model';
    -- 生成模型实例的id和name，这里这个self是Model本身
	init = function (self)
		self.id = self:getCounter() + 1
		-- 默认情况，name的值与id值相同
		self.name = self.id
		return self 
	end;
    

	--------------------------------------------------------------------
	-- 类函数。由类对象访问
	--------------------------------------------------------------------
    -- 根据名字返回相应的id
    getIdByName = function (self, name)
		I_AM_CLASS(self)
		local model_key = self.__name + ':[0-9]*:' + name
		local key = getkey(model_key)
		-- 如果不存在id index，就返回nil, 以示区别
		if not key then return nil	end
		
		-- 只找第一个，限制一个结果
		return index[1]:match('^%w+:(%d+):[%w%_%.%-]+$')
    end;
    -- 根据id返回相应的名字
    getNameById = function (self, id)
		I_AM_CLASS(self)
		local model_key = self.__name + ':' + tostring(id) + ':*'
		local key = getkey(model_key)
		-- 如果不存在id index，就返回nil, 以示区别
		if not key then return nil	end
		
		-- 只找第一个，限制一个结果
		return key:match('^%w+:%d+:([%w%_%.%-]+)$')
    end;
    -- 根据id返回对象
	getById = function (self, id)
		I_AM_CLASS(self)
		local model_key = self.__name + ':' + tostring(id) + ':*'
		local key = getkey(model_key)
		-- 如果没找到，就直接返回一个空表
		if not key then print('WARNING: Can\'t find any object by', model_key); return {} end
		local data = db:hgetall(key)
		if isEmpty(data) then print('WARNING: Can\'t get object by', key); return {} end
		local obj = self()
		table.update(obj, data)
		return obj
	end;
	-- 返回实例对象，此对象的数据由数据库中的数据更新
	getByName = function (self, name)
		I_AM_CLASS(self)
		local model_key = self.__name + ':[0-9]*:' + name
		local key = getkey(model_key)
		-- 如果没找到，就直接返回一个空表
		if not key then return {} end
		local data = db:hgetall(key)
		if isEmpty(data) then print('WARNING: Can\'t get object by', key); return {} end
		local obj = self()
		table.update(obj, data)
		return obj
	end;
	
	-- 返回此类中所有的成员
	all = function (self)
		I_AM_CLASS(self)
		local all_instaces = {}
		local all_keys = db:keys(self.__name + ':[0-9]*:*')
		local obj, data
		for _, key in ipairs(all_keys) do
			data = db:hgetall(key)
			if not isEmpty(data) then
				obj = self()
				table.update(obj, data)
				table.insert(all_instaces, obj)
			end
		end
		return all_instaces
	end;
	
	-- 返回此类中所有的key，返回一个列表
	allKeys = function (self)
		I_AM_CLASS(self)
		return db:keys(self.__name + ':[0-9]*:*')
	end;
	
	-- 返回此类中实例实际个数
	number = function (self)
		I_AM_CLASS(self)
		local all_keys = db:keys(self.__name + ':[0-9]*:*')
		return #all_keys
	end;
	
    -- 返回第一个查询对象，
    get = function (self, query)
		I_AM_CLASS(self)
		local query_args = table.copy(query)
		local id = query_args.id
		
		-- 如果查询要求中有id，就以id为主键查询。因为id是存放在总key中，所以要分开处理
		if id then
			local vv = nil
			query_args['id'] = nil
			local query_key = self.__name + ':' + tonumber(id)
			-- 判断数据库中有无此key存在
			local flag = db:exists(query_key)
			if not flag then return nil end
			-- 把这个key下的内容整个取出来
			vv = db:hgetall(query_key)
			
			for k, v in pairs(query_args) do
				if not vv[k] then return nil end
				-- 如果是函数，执行限定比较，返回布尔值
				if type(v) == 'function' then
					-- 进入函数v进行比较的，总是单个字段
					local flag = v(vv)
					-- 如果不在限制条件内，直接跳出循环
					if not flag then return nil end
				-- 处理查询条件为等于的情况
				else
					-- 一旦发现有不等的情况，立即返回否值
					if vv[k] ~= v then return nil end
				end
			end
			-- 如果执行到这一步，就说明已经找到了，返回对象
			return vv
		-- 如果查询要求中没有id
		else
			-- 取得所有关于这个模型的实例keys
			local all_keys = db:keys(self.__name + ':*')
			for _, kk in ipairs(all_keys) do
				-- 根据key获得一个实例的内容，返回一个表
				local vv = db:hgetall(kk)
				local flag = true
				for k, v in pairs(query_args) do
					if not vv[k] then flag=false; break end
					-- 目前为止，还只能处理条件式为等于的情况
					if type(v) == 'function' then
						-- 进入函数v进行比较的，总是单个字段
						flag = v(vv)
						-- 如果不在限制条件内，直接跳出循环
						if not flag then break end
					-- 处理条件式为等于的情况
					else
						if vv[k] ~= v then flag=false; break end
					end
				end
				-- 如果走到这一步，flag还为真，则说明已经找到第一个，直接返回
				if flag then
					return vv
				end
			end
		end
		
    end;

	-- filter的query表中，不应该出现id，这里也不打算支持它
	-- filter返回的是一个列表
	filter = function (self, query)
		I_AM_CLASS(self)
		local query_args = table.copy(query)
		if query_args['id'] then query_args['id'] = nil end
		-- ???行不行???
		-- 这里让query_set（一个表）也获得Model中定义的方法，到时可用于链式操作
		local query_set = setProto({}, Model)
	
		-- 取得所有关于这个模型的实例keys
		local all_keys = db:keys(self.__name + ':*')
		for _, kk in ipairs(all_keys) do
			-- 根据key获得一个实例的内容，返回一个表
			local vv = db:hgetall(kk)
			local flag = true	
			for k, v in pairs(query_args) do
				-- 对于多余的查询条件，一经发现，直接跳出
				if not vv[k] then flag=false; break end
				-- 处理条件式为外调函数的情况
				if type(v) == 'function' then
					-- 进入函数v进行比较的，总是单个字段
					flag = v(vv)
					-- 如果不在限制条件内，直接跳出循环
					if not flag then break end
				-- 处理条件式为等于的情况
				else
					if vv[k] ~= v then flag=false; break end
				end
			end
			-- 如果走到这一步，flag还为真，则说明已经找到，添加到查询结果表中去
			if flag then
				-- filter返回的表中由一个个值对构成
				table.insert(query_set, vv)
			end
		end
		return query_set
	end;

    -- 知道一个实例id的情况下，删除这个实例
    delById = function (self, id)
		I_AM_CLASS(self)
		assert( type(id) == 'number' or type(id) == 'string' )
		local model_key = self.__name + ':' + tostring(id) + ':*'
		local key = getkey(model_key)
		if key then	db:del(key)	end
		return true
    end;
    
    -- 知道一个实例name的情况下，删除这个实例
    delByName = function (self, name)
		I_AM_CLASS(self)
		checkType(name, 'string')
		local model_key = self.__name + ':[0-9]*:' + name
		local key = getkey(model_key)
		if key then	db:del(key)	end
		return true
    end;
    
	-- 获取模型的counter值
    getCounter = function (self)
		return tonumber(db:get(self.__name + ':__counter') or 0)
    end;
	
	-- 判断模型中的缓存（如果有的话），是否已经是脏的了，即已经不反映最新的状态了
	isDirty = function (self)
		I_AM_CLASS(self)
		local model_key = self.__name + ':__dirty'
		local r = db:get(model_key)
		if r and r == 'true' then
			return true
		else
			return false
		end
	end;
	
	-- 设置缓存标志为脏
	dirty = function (self)
		I_AM_CLASS(self)
		local dirty_key = self.__name + ':__dirty'
		db:set(dirty_key, 'true')
	end;
	
	-- 生成一个模型中所有对象的id列表的缓存
	cache = function (self)
		I_AM_CLASS(self)
		local model_key = self.__name + ':__cache'
		local dirty_key = self.__name + ':__dirty'
		local all_keys = self:allKeys()
		local idpart
		local id_list = {}
		for i, v in ipairs(all_keys) do
			idpart = tonumber(v:match(':(%d+):'))
			table.insert(id_list, idpart)
		end 
		table.sort(id_list)
		local constr = table.concat(id_list)
		db:set(model_key, constr)
		db:set(dirty_key, 'false')
	end;

	-- 向数据库中存入自定义键值对，灵活性比较高，也比较危险
	set = function (self, key, val)
		I_AM_CLASS(self)
		local one_key = self.__name + ':' + key
		return db:setnx(one_key, seri(val))
	end;

    --------------------------------------------------------------------
	-- 实例函数。由类的实例访问
	--------------------------------------------------------------------
    -- 在数据库中创建一个hash表项，保存模型实例
    save = function (self)
        local model_key = self.__name + ':' + tostring(self.id) + ':' + self.name
		-- 如果之前数据库中没有这个对象，即是新创建的情况
		if not db:exists(model_key) then
			-- 对象类别的总数计数器就加1
			db:incr(self.__name + ':__counter')
		end

		for k, v in pairs(self) do
			-- 保存的时候序列化一下。
			-- 跟Django一样，每一个save时，所有字段都全部保存，包括id
			-- 只保存正常数据，不保存函数和继承自父类的私有属性，以及自带的函数
			if not k:startsWith('_') and type(v) ~= 'function' then
				db:hset(model_key, k, seri(v))
			end
		end
		
        return true
    end;
    
    -- 删除数据库中的一个对象数据
    del = function (self)
		local model_name = self.__name
		-- 如果self是单个对象
		if self['id'] then
			-- 在数据库中删除这个对象的内容
			db:del(model_name + ':' + self.id + ':' + self.name)
			self = nil
		-- 如果self是一个对象列表
		else
			-- 一个一个挨着删除
			for _, v in ipairs(self) do
				db:del(model_name + ':' + v.id + ':' + v.name)
			end
		end
		return true
    end;

	--recordMany 实例调用
	-- 添加一个外链模型的实例的id到本对象的一个域中来
	-- 返回本对象
	appendToField = function (self, field, new_id)
		checkType(field, 'string')
		assert( type(new_id) == 'number' or type(new_id) == 'string' )
		self[field] = ('%s %s'):format((self[field] or ''), new_id)
		return self
	end;
	
	-- parseMany
	-- 释放本对象的一个域中所存储的外链模型的实例
	-- 返回那些实例的对象列表
	extractField = function (self, field, link_model)
		checkType(field, 'string')
		checkType(link_model, 'table')
		if isFalse(self[field]) then return nil end
		local list = self[field]:trim():split(' ')
		if isFalse(list) then return {} end
		local obj_list = {}
		for _, v in ipairs(list) do
			local obj = link_model:getById(v)
			-- 这里，要检查返回的obj是不是空对象，而不仅仅是不是空表
			if not isEmpty(obj) then
				table.insert(obj_list, obj)
			end
		end
		
		return obj_list
	end;    

	-- getPartial
	-- 释放本对象的一个域中所存储的外链模型的部分实例
	-- 返回那些实例的对象列表
	extractFieldSlice = function (self, field, link_model, start, ended)
		checkType(field, 'string')
		checkType(link_model, 'table')
		checkType(start, ended, 'number', 'number')
		if isFalse(self[field]) then return nil end
		local strpart = self[field]:findpart(start, ended)
		if isFalse(strpart) then return {} end
		local list = strpart:trim():split(' ')
		if isFalse(list) then return {} end
		
		local obj_list = {}
		for _, v in ipairs(list) do
			local obj = link_model:getById(v)
			if not isEmpty(obj) then
				table.insert(obj_list, obj)
			end
		end
		
		return obj_list
	end;


	

}

return Model
