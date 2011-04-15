module(..., package.seeall)

local db = BAMBOO_DB

local rdlist = require 'bamboo.redis.rdlist'

-- 由实例调用
local saveFieldToRedis = function (self, model_key, field_key, field_val)
	local its_type = type(field_val)
	local def_type = self.__fields[field_key]
	-- 如果是数据或字符的话
	if its_type == 'string' or its_type == 'number' then
		db:hset(model_key, field_key, field_val)
	-- 如果是列表的话（这里，table只限定为列表list）
	elseif its_type == 'table' and def_type and def_type.st then
		-- 在这里设置一个ON，表明这个链接已经存在了
		db:hset(model_key, field_key, 'ON')
		
		local st = def_type.st
		if st == 'LIST' then
			rdlist.updateList(model_key + ':' + field_key, field_val)
		elseif st == 'SET' then

		elseif st == 'ZSET' then

		end
	end

end

-- 由模型调用
local getFromRedis = function (self, model_key)
	-- 先从数据库中取出来
	local data = db:hgetall(key)
	if isEmpty(data) then print("WARNING: Can't get object by", key); return nil end

	local fields = self.__fields
	for k, _ in pairs(data) do
		-- 这里面这个k是从数据库取出来的，肯定保证是满足fields[k]存在的
		if fields[k].st then
			local st = fields[k].st
			if st == 'LIST' then
				-- 对于类型是LIST的情况，就把lua中的表对象的这一项替换成取出的列表
				data[k] = rdlist.retrieveList(model_key + ':' + k)
				
			elseif st == 'SET' then

			elseif st == 'ZSET' then
			
			end
		end
	end
	
	local obj = self()
	table.update(obj, data)
	return obj
end 

-- 可以从实例调用，也可以从模型调用
-- 从实例调用时，不要写第二个参数id
-- 从模型调用时，要写第二个参数id
local delFromRedis = function (self, id)
	local model_name = self.__name
	local index_name = model_name + ':__index'
	local id = id or self.id
	
	db:del(model_name + ':' + id)
	
	-- 模型没有这个属性
	if self.name then
		db:zrem(index_name, self.name)
	else
		local t = db:zrangebyscore(index_name, id, id)
		if #t > 0 then
			db:zrem(index_name, t[1])
		end
	end
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
	__desc = 'Model is the base of all models.';
	__fields = {};
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
		checkType(name, 'string')
		
		local idstr = db:zscore(self.__name + ':__index', name)
		return tonumber(idstr)
    end;
    -- 根据id返回相应的名字
    getNameById = function (self, id)
		I_AM_CLASS(self)
		checkType(tonumber(id), 'number')
		
		-- range本身返回一个列表，这里限定只返回一个元素的列表
		local name = db:zrangebyscore(self.__name + ':__index', id, id)[1]
		
		if isFalse(name) then return nil end
		return name
    end;
    -- 根据id返回对象
	getById = function (self, id)
		I_AM_CLASS(self)
		checkType(tonumber(id), 'number')
		
		local key = self.__name + ':' + tostring(id)
		if not db:exists(key) then return nil end
		
		return getFromRedis(key)
	end;
	-- 返回实例对象，此对象的数据由数据库中的数据更新
	getByName = function (self, name)
		I_AM_CLASS(self)
		local id = self:getIdByName(name)
		if not id then return nil end
		return self:getById (id)
	end;
	
	-- 返回此类中所有的成员
	all = function (self)
		I_AM_CLASS(self)
		local all_instaces = {}
		local all_keys = db:keys(self.__name + ':[0-9]*')
		local obj, data
		for _, key in ipairs(all_keys) do
			local obj = getFromRedis(key)
			if not obj then
				table.insert(all_instaces, obj)
			end
		end
		return all_instaces
	end;
	
	-- 返回此类中所有的key，返回一个列表
	allKeys = function (self)
		I_AM_CLASS(self)
		return db:keys(self.__name + ':[0-9]*')
	end;
	
	-- 返回此类中实例实际个数
	number = function (self)
		I_AM_CLASS(self)
		--local all_keys = db:keys(self.__name + ':[0-9]*')
		--return #all_keys
		return db:zcard(self.__name + ':__index')
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
			local query_key = self.__name + ':' + tostring(id)
			-- 判断数据库中有无此key存在
			local flag = db:exists(query_key)
			if not flag then return nil end
			-- 把这个key下的内容整个取出来
			vv = getFromRedis(query_key)
			if not vv then return nil end
			
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
			local all_keys = db:keys(self.__name + ':[0-9]*')
			for _, kk in ipairs(all_keys) do
				-- 根据key获得一个实例的内容，返回一个表
				local vv = getFromRedis(kk)
				local flag = true
				for k, v in pairs(query_args) do
					if not vv or not vv[k] then flag=false; break end
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
		local all_keys = db:keys(self.__name + ':[0-9]*')
		for _, kk in ipairs(all_keys) do
			-- 根据key获得一个实例的内容，返回一个表
			local vv = getFromRedis(kk)
			local flag = true	
			for k, v in pairs(query_args) do
				-- 对于多余的查询条件，一经发现，直接跳出
				if not vv or not vv[k] then flag=false; break end
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
		checkType(tonumber(id), 'number')
		
		if not db:exists(self.__name + ':' + id) then 
			print(("[WARNING] Key %s doesn't exist!"):format(key)) 
			return nil 
		end
		
		delFromRedis(self, id)
		return true
    end;
    
    -- 知道一个实例name的情况下，删除这个实例
    delByName = function (self, name)
		I_AM_CLASS(self)
		checkType(name, 'string')
		local id = self:getIdByName (name)
		return self:delById (id)
    end;
    
    -- 将模型的counter值归零
    clearCounter = function (self)
		I_AM_CLASS(self)
		db:set(self.__name + ':__counter', 0)
    end;
	
	clearAll = function (self)
		I_AM_CLASS(self)
		local all_objs = self:all()
		for i, v in ipairs(all_objs) do
			v:del()
		end
		self:clearCounter ()
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
		local constr = table.concat(id_list, ' ')
		db:set(model_key, constr)
		db:set(dirty_key, 'false')
		-- 返回所有id的list
		local keystr = db:get(model_key)
		if not keystr then return {} end
		return keystr:split(' ')
	end;

	getCache = function (self)
		I_AM_CLASS(self)
		local model_key = self.__name + ':__cache'
		local keystr = db:get(model_key)
		if not keystr then return {} end
		-- 返回所有id的list
		return keystr:split(' ')
	end;

	-- 向数据库中存入自定义键值对，灵活性比较高，也比较危险
	setCustom = function (self, key, val)
		I_AM_CLASS(self)
		checkType(key, val, 'string', 'string')
		local one_key = self.__name + ':' + key
		return db:set(one_key, seri(val))
	end;

	-- 向数据库中取出自定义键值对
	getCustom = function (self, key)
		I_AM_CLASS(self)
		checkType(key, 'string')
		
		local one_key = self.__name + ':' + key
		if not db:exists(one_key) then print(("[WARNING] Key %s doesn't exist!"):format(one_key)); return nil end
		return db:get(one_key)
	end;

	-- 直接从模型入手，在获知id的情况下，更新此对象的某一个域
	updateById = function (self, id, field, new_value)
		I_AM_CLASS(self)
		checkType(field, new_value, 'string', 'string')
		
		local key = self.__name + ':' + tostring(id)
		assert(db:exists(key), ("[ERROR] Key %s does't exist! Can't apply update."):format(key))
		
		db:hset(key, field, new_value)
	end;
	
	-- 直接从模型入手，在获知name的情况下，更新此对象的某一个域
	updateByName = function (self, name, field, new_value)
		I_AM_CLASS(self)
		checkType(name, field, new_value, 'string', 'string', 'string')
		
		local id = self:getIdByName (name)
		assert(id, ("[ERROR] Name %s does't exist!"):format(name))
		self:updateById (id, field, new_value)
	end;
	

    --------------------------------------------------------------------
	-- 实例函数。由类的实例访问
	--------------------------------------------------------------------
    -- 在数据库中创建一个hash表项，保存模型实例
    save = function (self)
        assert(self.name, "[ERROR] The name field doesn't exist!"))
        local model_key = self.__name + ':' + tostring(self.id)
		-- 如果之前数据库中没有这个对象，即是新创建的情况
		if not db:exists(model_key) then
			-- 对象类别的总数计数器就加1
			db:incr(self.__name + ':__counter')
		end

		for k, v in pairs(self) do
			-- 保存的时候序列化一下。
			-- 跟Django一样，每一个save时，所有字段都全部保存，包括id
			-- 只保存正常数据，不保存函数和继承自父类的私有属性，以及自带的函数
			-- 对于在程序中任意写的字段名也不予保存，要进行类定义时字段的检查
			if (not k:startsWith('_')) and type(v) ~= 'function' and self.__fields[k] then
				--db:hset(model_key, k, seri(v))
				saveFieldToRedis(self, model_key, k, v)
			end
		end
		
		-- 将记录添加到Model:__index中去
		local index_key = self.__name + ':__index'
		assert(db:exists(index_key), ("[ERROR] %s doesn't exist!"):format(index_key))
		db:zadd(index_key, tonumber(self.id), self.name)
		
    end;
    
    -- 这是当实例取出来后，进行部分更新的函数
    update = function (self, field, new_value)
		checkType(field, new_value, 'string', 'string')
		assert(self.__fields[field], ("[ERROR] Field %s doesn't be defined!"):format(field))
		local model_key = self.__name + ':' + tostring(self.id)
		assert(db:exists(model_key), ("[ERROR] Key %s does't exist! Can't apply update."):format(model_key))
		-- db:hset(model_key, field, new_value)
		saveFieldToRedis(self, model_key, field, new_value)
    end;
    
    
    -- 获取模型的counter值
    getCounter = function (self)
		return tonumber(db:get(self.__name + ':__counter') or 0)
    end;
    
    -- 删除数据库中的一个对象数据
    del = function (self)
		local model_name = self.__name
		-- 如果self是单个对象
		if self['id'] then
			-- 在数据库中删除这个对象的内容
			delFromRedis(self)
		-- 如果self是一个对象列表
		else
			-- 一个一个挨着删除
			for _, v in ipairs(self) do
				delFromRedis(v)
				v = nil
			end
		end
		
		self = nil
    end;

	-- 实例调用
	-- 添加一个外链模型的实例的id到本对象的一个域中来
	-- 返回本对象
	appendToField = function (self, field, new_obj)
		checkType(field, 'string')
		checkType(tonumber(new_id), 'number')
		local def_type = self.__fields[field]
		assert( def_type == 'LIST', ("[ERROR] This field %s doesn't accept appending."):format(field))
		assert( new_obj.id, "[ERROR] This object doesn't contain id!")

		local new_id = new_obj.id
		local key = self.__name + ':' + self.id + ':' + field
		-- 将新值更新到数据库中去，因此，后面不用用户再写self:save()了
		rdlist.appendToList(key, new_id)
		if not self[field] then self[field] == {} end
		-- 给本对象添加更新值
		table.insert(self[field], new_id)
		
		--self[field] = ('%s %s'):format((self[field] or ''), new_id)
		return self
	end;
	
	-- liststr的处理算法
	-- 释放本对象的一个域中所存储的外链模型的实例
	-- 返回那些实例的对象列表
	extractField = function (self, field, link_model)
		checkType(field, link_model, 'string', 'table')
		if not self[field] then return nil end

		local list = self[field]
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

	-- 释放本对象的一个域中所存储的外链模型的部分实例
	-- 返回那些实例的对象列表
	extractFieldSlice = function (self, field, link_model, start, ended)
		checkType(field, link_model, start, ended, 'string', 'table', 'number', 'number')
		if not self[field] then return nil end

		local list = table.slice(self[field], start, ended)
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
