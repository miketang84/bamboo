module(..., package.seeall)

local db = BAMBOO_DB

local rdlist = require 'bamboo.redis.rdlist'
local getModelByName  = bamboo.getModelByName 

local function getIndexName(self)
	--return self.__tag:match('%.(%w+)$')  + ':__index'
	return self.__name  + ':__index'
end

local function getClassName(self)
	return self.__tag:match('%.(%w+)$')
end

local function getStoreName(self)
	return self.__name
end

local function checkExistanceById(self, id)
	local index_name = getIndexName(self)
	local r = db:zrangebyscore(index_name, id, id)
	if #r == 0 then 
		return false, ''
	else
		return true, r[1]
	end
end


local function checkUnfixed(fld, item)
	local foreign = fld.foreign
	local link_model, linked_id
	if foreign == 'UNFIXED' then
		local link_model_str
		link_model_str, linked_id = item:match('^(%w+):(%d+)$')
		assert(link_model_str)
		assert(linked_id)
		link_model = getModelByName(link_model_str)
	else 
		link_model = getModelByName(foreign)
		assert(link_model, ("[ERROR] The foreign part (%s) of this field is not a valid model."):format(foreign))	
		-- 当没有写st属性，或st属性为ONE时，即为单外链时
		linked_id = item
	end

	return link_model, linked_id
end

-- 由模型调用
local getFromRedis = function (self, model_key)
	-- 先从数据库中取出来
	-- 这时，取出来的值，不包含一对多型外键的，但包括一对一外键
	local data = db:hgetall(model_key)
	if isEmpty(data) then print("WARNING: Can't get object by", model_key); return nil end

	local fields = self.__fields
	for k, fld in pairs(fields) do
		-- 这里面这个k是从数据库取出来的，应该保证fields[k]存在的
		checkType(fld, 'table')
		if fld.foreign then
			local st = fld.st
			if st == 'MANY' then
				data[k] = rdlist.retrieveList(model_key + ':' + k)
			end
		end
	end
	-- 产生一个对象
	local obj = self()
	table.update(obj, data)
	return obj
end 

-- 定义只能从实例调用
local delFromRedis = function (self)
	local model_name = self.__name
	local index_name = getIndexName(self)
	local id = self.id
	
	local fields = self.__fields
	-- 在redis里面，将对象中关联的外键key-value对删除
	for k, v in pairs(self) do
		local fld = fields[k]
		if fld and fld.foreign then
			local key = model_name + ':' + self.id + ':' + k 
			if fld.st == 'MANY' then
				rdlist.delList(key)
			end
		end
	end

	-- 删除这个key
	db:del(model_name + ':' + id)
	-- 删除本对象的一个全局模型索引
	db:zrem(index_name, self.name)
	-- 释放在lua中的对象
	self = nil
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
		if v >= small and v <= big then
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
		
		local index_name = getIndexName(self)
		local idstr = db:zscore(index_name, name)
		return tonumber(idstr)
    end;
    
    -- 根据id返回相应的名字
    getNameById = function (self, id)
		I_AM_CLASS(self)
		checkType(tonumber(id), 'number')
		
		-- range本身返回一个列表，这里限定只返回一个元素的列表
		local flag, name = checkExistanceById(self, id)
		if isFalse(flag) or isFalse(name) then return nil end

		return name
    end;
    -- 根据id返回对象
	getById = function (self, id)
		I_AM_CLASS(self)
		checkType(tonumber(id), 'number')
		
		-- 先检查索引器里面有没
		if not checkExistanceById(self, id) then return nil end
		-- 再检查有没model_key
		local key = self.__name + ':' + tostring(id)
		if not db:exists(key) then return nil end
		return getFromRedis(self, key)
	end;
	
	-- 返回实例对象，此对象的数据由数据库中的数据更新
	getByName = function (self, name)
		I_AM_CLASS(self)
		local id = self:getIdByName(name)
		if not id then return nil end
		return self:getById (id)
	end;
	
	-- 返回此类的所有id组成的一个列表
	allIds = function (self)
		local index_name = getIndexName(self)
		local all_ids = db:zrange(index_name, 0, -1, 'withscores')
		local r = {}
		for _, v in ipairs(all_ids) do
			-- v[2] is the id
			table.insert(r, v[2])
		end
		
		return r
	end;	
	
	-- 返回此类中所有的成员
	all = function (self)
		I_AM_CLASS(self)
		local all_instaces = {}
		local _name = self.__name + ':'
		
		local index_name = getIndexName(self)
		local all_ids = self:allIds()
		local getById = self.getById 
		
		local obj, data
		for _, id in ipairs(all_ids) do
			local obj = getById(self, id)
			if obj then
				table.insert(all_instaces, obj)
			end
		end
		return all_instaces
	end;
	
	-- 返回此类的所有的key（有可能不限于此类，
	-- 还包含父类的key以及继承于同一父类的所有子类，如果它们的__name都是父类的名字的话）
	-- 所以这是一个很奇妙的函数
	-- 返回一个字符串列表
	allKeys = function (self)
		I_AM_CLASS(self)
		return db:keys(self.__name + ':[0-9]*')
	end;
	
	-- 返回此类中实例实际个数
	numbers = function (self)
		I_AM_CLASS(self)
		return db:zcard(getIndexName(self))
	end;
	
    -- 返回第一个查询对象，
    get = function (self, query)
		I_AM_CLASS(self)
		local query_args = table.copy(query)
		local id = query_args.id
		
		-- 如果查询要求中有id，就以id为主键查询。因为id是存放在总key中，所以要分开处理
		if id then

			query_args['id'] = nil

			-- 把这个id的整个取出来
			local vv = self:getById( id )
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
			local all_ids = self:allIds()
			local getById = self.getById 
			for _, kk in ipairs(all_ids) do
				-- 根据key获得一个实例的内容，返回一个表
				local vv = getById(self, kk)
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
	
		-- 取得所有关于这个模型的例id
		local all_ids = self:allIds()
		local getById = self.getById 
		for _, kk in ipairs(all_ids) do
			-- 根据key获得一个实例的内容，返回一个表
			local vv = getById (self, kk)
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
    
    -- 将模型的counter值归零
    clearCounter = function (self)
		I_AM_CLASS(self)
		db:set(self.__name + ':__counter', 0)
		
		return self
    end;
	
	clearAll = function (self)
		I_AM_CLASS(self)
		local all_objs = self:all()
		for i, v in ipairs(all_objs) do
			v:del()
		end
		self:clearCounter ()
		
		return self
	end;
	
	---- 判断模型中的缓存（如果有的话），是否已经是脏的了，即已经不反映最新的状态了
	--isDirty = function (self)
		--I_AM_CLASS(self)
		--local model_key = self.__name + ':__dirty'
		--local r = db:get(model_key)
		--if r and r == 'true' then
			--return true
		--else
			--return false
		--end
	--end;
	
	---- 设置缓存标志为脏
	--dirty = function (self)
		--I_AM_CLASS(self)
		--local dirty_key = self.__name + ':__dirty'
		--db:set(dirty_key, 'true')
		
		--return self
	--end;
	
	---- 生成一个模型中所有对象的id列表的缓存
	--cache = function (self)
		--I_AM_CLASS(self)
		--local model_key = self.__name + ':__cache'
		--local dirty_key = self.__name + ':__dirty'
		--local all_keys = self:allKeys()
		--local idpart
		--local id_list = {}
		--for i, v in ipairs(all_keys) do
			--idpart = tonumber(v:match(':(%d+):'))
			--table.insert(id_list, idpart)
		--end 
		--table.sort(id_list)
		--local constr = table.concat(id_list, ' ')
		--db:set(model_key, constr)
		--db:set(dirty_key, 'false')
		---- 返回所有id的list
		--local keystr = db:get(model_key)
		--if not keystr then return {} end
		--return keystr:split(' ')
	--end;

	--getCache = function (self)
		--I_AM_CLASS(self)
		--local model_key = self.__name + ':__cache'
		--local keystr = db:get(model_key)
		--if not keystr then return {} end
		---- 返回所有id的list
		--return keystr:split(' ')
	--end;

	-- 向数据库中存入自定义键值对，灵活性比较高，也比较危险
	setCustom = function (self, key, val)
		I_AM_CLASS(self)
		checkType(key, val, 'string', 'string')
		local one_key = getClassName(self) + ':' + key
		return db:set(one_key, seri(val))
	end;

	-- 向数据库中取出自定义键值对
	getCustom = function (self, key)
		I_AM_CLASS(self)
		checkType(key, 'string')
		
		local one_key = getClassName(self) + ':' + key
		if not db:exists(one_key) then print(("[WARNING] Key %s doesn't exist!"):format(one_key)); return nil end
		return db:get(one_key)
	end;

    --------------------------------------------------------------------
	-- 实例函数。由类的实例访问
	--------------------------------------------------------------------
    -- 在数据库中创建一个hash表项，保存模型实例
    save = function (self)
        assert(self.name, "[ERROR] The name field doesn't exist!")
        local model_key = self.__name + ':' + tostring(self.id)
		local isExisted = db:exists(model_key)
		-- 如果之前数据库中没有这个对象，即是新创建的情况
		if not isExisted then
			-- 对象类别的总数计数器就加1
			db:incr(self.__name + ':__counter')
			-- 将记录添加到Model:__index中去
			-- 在保存索引的时候，使用__tag中的最后一个单词作为名字，
			-- 这是因为__name有可能会命名成与父辈同名的名字
			local index_key = getIndexName(self)
			-- local index_key = self.__name + ':__index'
			--assert(db:exists(index_key), ("[ERROR] %s doesn't exist!"):format(index_key))
			db:zadd(index_key, tonumber(self.id), self.name)
		end

		-- 这两项必存
		db:hset(model_key, 'id', self.id)
		db:hset(model_key, 'name', self.name)

		for k, v in pairs(self) do
			-- 保存的时候序列化一下。
			-- 跟Django一样，每一个save时，所有字段都全部保存，包括id
			-- 只保存正常数据，不保存函数和继承自父类的私有属性，以及自带的函数
			-- 对于在程序中任意写的字段名也不予保存，要进行类定义时字段的检查
			-- 对于有外链的字段，也不在save中保存，只能用外键相关函数处理
			local field = self.__fields[k]
			if v and (not k:startsWith('_')) and type(v) ~= 'function' and field and (not field['foreign']) then
				-- 由于不保存有外键的字段，故可以在这里对各种类型直接以字符串存储
				db:hset(model_key, k, seri(v))
			end
		end
		
		return self
    end;
    
    -- 这是当实例取出来后，进行部分更新的函数
    update = function (self, field, new_value)
		checkType(field, new_value, 'string', 'string')
		local fld = self.__fields[field]
		assert(fld, ("[ERROR] Field %s doesn't be defined!"):format(field))
		assert( not fld['foreign'], ("[ERROR] %s is a foreign field, shouldn't use update function!"):format(field))
		local model_key = self.__name + ':' + tostring(self.id)
		assert(db:exists(model_key), ("[ERROR] Key %s does't exist! Can't apply update."):format(model_key))
		db:hset(model_key, field, new_value)
		
		return self
    end;
    
    fillNewField = function (self, t)
		if not t then return self end
		return self:init(t)
    end;
    
    -- 获取模型的counter值
    getCounter = function (self)
		return tonumber(db:get(self.__name + ':__counter') or 0)
    end;
    
    -- 删除数据库中的一个对象数据
    del = function (self)
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
	addForeign = function (self, field, new_obj)
		checkType(field, new_obj, 'string', 'table')
		checkType(tonumber(new_obj.id), 'number')

		local fld = self.__fields[field]
		assert(fld, ("[ERROR] Field %s doesn't be defined!"):format(field))
		assert( fld.foreign, ("[ERROR] This field %s is not a foreign field."):format(field))
		assert( new_obj.id, "[ERROR] This object doesn't contain id, it's not a valid object!")
		
		local new_id
		if fld.foreign == 'UNFIXED' then
			new_id = new_obj.__name + ':' + new_obj.id
		else 
			new_id = new_obj.id
		end
		
		local model_key = self.__name + ':' + tostring(self.id)
		if (not fld.st) or fld.st == 'ONE' then
			-- 当没有写st属性，或st属性为ONE时，即为单外链时
			db:hset(model_key, field, new_id)
			self[field] = new_id
		elseif fld.st == 'MANY' then
			-- 当为多外键时
			local key = model_key + ':' + field
			-- 将新值更新到数据库中去，因此，后面不用用户再写self:save()了
			rdlist.appendToList(key, new_id)
			if not self[field] then self[field] = {} end
			-- 给本对象添加更新值
			table.insert(self[field], new_id)
		end
		
		return self
	end;
	
	-- liststr的处理算法
	-- 释放本对象的一个域中所存储的外链模型的实例
	-- 返回那些实例的对象列表
	getForeign = function (self, field, start, stop)
		checkType(field, 'string')
		local fld = self.__fields[field]
		assert(fld, ("[ERROR] Field %s doesn't be defined!"):format(field))
		assert( fld.foreign, ("[ERROR] This field %s is not a foreign field."):format(field))
		if isFalse(self[field]) then return nil end
		
		local model_key = self.__name + ':' + self.id
		local link_model, linked_id
		if (not fld.st) or fld.st == 'ONE' then
			link_model, linked_id = checkUnfixed(fld, self[field])
			-- 返回单个外键对象
			local obj = link_model:getById (linked_id)
			if isFalse(obj) then
				
				-- 如果没有获取到，就把这个外键去掉
				db:hset(model_key, field, '')
				self[field] = ''
				return nil
			else
				return obj
			end
		elseif fld.st == 'MANY' then
			local list = self[field]
			if isFalse(list) then return {} end
			
			local start = start or 1
			local stop = stop or #list
			
			list = table.slice(list, start, stop)
			if isFalse(list) then return {} end
			
			local obj_list = {}
			for _, v in ipairs(list) do
				link_model, linked_id = checkUnfixed(fld, v)

				local obj = link_model:getById(linked_id)
				-- 这里，要检查返回的obj是不是空对象，而不仅仅是不是空表
				if isFalse(obj) then
					-- 如果没有获取到，就把这个外键去掉
					rdlist.removeFromList(model_key + ':' + field, v)
					table.iremVal(self[field], v)
				else
					table.insert(obj_list, obj)
				end
			end
			
			if #obj_list == 1 then
				return obj_list[1]
			else
				return obj_list
			end
		end
		
	end;    


	
	delForeign = function (self, field, frobj)
		checkType(field, frobj, 'string', 'table')
		local fld = self.__fields[field]
		assert(fld, ("[ERROR] Field %s doesn't be defined!"):format(field))
		assert( fld.foreign, ("[ERROR] This field %s is not a foreign field."):format(field))
		assert( frobj.id, "[ERROR] This object doesn't contain id, it's not a valid object!")
		if isFalse(self[field]) then return end
		
		local frid
		if fld.foreign == 'UNFIXED' then
			frid = frobj.__name + ':' + frobj.id
		else 
			frid = tostring(frobj.id)
		end
		
		local link_model = frobj.__name
		assert(link_model and link_model == fld.foreign,
			("[ERROR] The foreign model (%s) of this field %s doesn't equal the object's model %s."):format(fld.foreign, field, link_model))
		
		local model_key = self.__name + ':' + tostring(self.id)
		if (not fld.st) or fld.st == 'ONE' then
			-- 当没有写st属性，或st属性为ONE时，即为单外链时
			-- 将单字符串外键置空，要在指定的对象与记录的外键id是同一个时才执行删除操作
			if self[field] == frid then
				db:hset(model_key, field, '')
				self[field] = ''
			end
			
		elseif fld.st == 'MANY' then
			
			rdlist.removeFromList(model_key + ':' + field, frid)
			table.iremVal(self[field], frid)
		end
	
		return self
	end;




}

return Model
