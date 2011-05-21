module(..., package.seeall)

local db = BAMBOO_DB

local List = require 'lglib.list'
local rdzset = require 'bamboo.redis.rdzset'
local rdfifo = require 'bamboo.redis.rdfifo'
local rdzfifo = require 'bamboo.redis.rdzfifo'

local getModelByName  = bamboo.getModelByName 

local function getIndexName(self)
	return self.__name  + ':__index'
end

local function getClassName(self)
	if type(self) ~= 'table' then return nil end
	return self.__tag:match('%.(%w+)$')
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
	if isObjEmpty(data) then print("WARNING: Can't get object by", model_key); return nil end

	local fields = self.__fields
	for k, fld in pairs(fields) do
		-- 这里面这个k是从数据库取出来的，应该保证fields[k]存在的
		checkType(fld, 'table')
		if fld.foreign then
			local st = fld.st
			if st == 'MANY' then
				-- data[k] = rdlist.retrieveList(model_key + ':' + k)
				-- data[k] = rdzset.retrieveZset(model_key + ':' + k)
				data[k] = 'FOREIGN MANY'
			elseif st == 'FIFO' then
				data[k] = 'FOREIGN FIFO'
			elseif st == 'ZFIFO' then
				data[k] = 'FOREIGN ZFIFO'
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
	local model_key = self.__name +  ':' + self.id
	local index_name = getIndexName(self)
	
	local fields = self.__fields
	-- 在redis里面，将对象中关联的外键key-value对删除
	for k, v in pairs(self) do
		local fld = fields[k]
		if fld and fld.foreign then
			if fld.st == 'MANY' then
				local key = model_key + ':' + k 
				-- rdlist.delList(key)
				rdzset.delZset(key)
			elseif fld.st == 'FIFO' then
				local key = model_key + ':' + k 
				rdfifo.delFifo(key)
			elseif fld.st == 'ZFIFO' then
				local key = model_key + ':' + k 
				rdzfifo.delZfifo(key)
			end
		end
	end

	-- 删除这个key
	db:del(model_key)
	-- 删除本对象的一个全局模型索引
	db:zrem(index_name, self.name)
	-- 释放在lua中的对象
	self = nil
end

------------------------------------------------------------------------
-- 数据库检索的限制函数集
-- 由于使用的时候希望不再做导入工作，所以在加载Model模块的时候直接导入到全局环境中
------------------------------------------------------------------------

_G['eq'] = function ( cmp_obj )
	return function (v)
		if v == cmp_obj then
			return true
		else
			return false
		end
	end
end

_G['uneq'] = function ( cmp_obj )
	return function (v)
		if v ~= cmp_obj then
			return true
		else
			return false
		end
	end
end

_G['lt'] = function (limitation)
	return function (v)
		if tonumber(v) < limitation then
			return true
		else
			return false
		end
	end
end

_G['gt'] = function (limitation)
	return function (v)
		if tonumber(v) > limitation then
			return true
		else
			return false
		end
	end
end


_G['le'] = function (limitation)
	return function (v)
		if tonumber(v) <= limitation then
			return true
		else
			return false
		end
	end
end

_G['ge'] = function (limitation)
	return function (v)
		if tonumber(v) >= limitation then
			return true
		else
			return false
		end
	end
end

_G['bt'] = function (small, big)
	return function (v)
		if tonumber(v) > small and v < big then
			return true
		else
			return false
		end
	end
end

_G['be'] = function (small, big)
	return function (v)
		if tonumber(v) >= small and v <= big then
			return true
		else
			return false
		end
	end
end

_G['outside'] = function (small, big)
	return function (v)
		local v = tonumber(v)
		
		if v < small and v > big then
			return true
		else
			return false
		end
	end
end

_G['contains'] = function (substr)
	return function (v)
		v = tostring(v)
		if v:contains(substr) then 
			return true
		else
			return false
		end
	end
end

_G['startsWith'] = function (substr)
	return function (v)
		v = tostring(v)
		if v:startsWith(substr) then 
			return true
		else
			return false
		end
	end
end

_G['endsWith'] = function (substr)
	return function (v)
		v = tostring(v)
		if v:endsWith(substr) then 
			return true
		else
			return false
		end
	end
end

_G['inset'] = function (...)
	local args = {...}
	return function (v)
		v = tostring(v)
		for _, val in ipairs(args) do
			-- 只要有一个满足，就表明在这个集合里
			if tostring(val) == v then
				return true
			end
		end
		
		return false
	end

end

_G['uninset'] = function (...)
	local args = {...}
	return function (v)
		v = tostring(v)
		for _, val in ipairs(args) do
			-- 需要所有的都不等，才表明不在这个集合里
			-- 只要有一个等，就说明在这个集合里
			if tostring(val) == v then
				return false
			end
		end
		
		return true
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
	allIds = function (self, is_rev)
		I_AM_CLASS(self)
		local index_name = getIndexName(self)
		local all_ids 
		if is_rev ~= 'rev' then
			all_ids = db:zrange(index_name, 0, -1, 'withscores')
		else
			all_ids = db:zrevrange(index_name, 0, -1, 'withscores')
		end
		local r = List()
		for _, v in ipairs(all_ids) do
			-- v[2] is the id
			r:append(v[2])
		end
		
		return r
	end;
	
	-- 支持以负数为索引
	sliceIds = function (self, start, stop, is_rev)
		I_AM_CLASS(self)
		checkType(start, stop, 'number', 'number')
		local index_name = getIndexName(self)
		if start > 0 then start = start - 1 end
		if stop > 0 then stop = stop - 1 end
		local all_ids
		if not is_rev then
			all_ids = db:zrange(index_name, start, stop, 'withscores')
		else
			all_ids = db:zrevrange(index_name, start, stop, 'withscores')
		end
		local r = List()
		for _, v in ipairs(all_ids) do
			-- v[2] is the id
			r:append(v[2])
		end
		
		return r
	end;	
	
	-- 返回此类中所有的成员
	all = function (self, is_rev)
		I_AM_CLASS(self)
		local all_instaces = List()
		local _name = self.__name + ':'
		
		local index_name = getIndexName(self)
		local all_ids = self:allIds(is_rev)
		local getById = self.getById 
		
		local obj, data
		for _, id in ipairs(all_ids) do
			local obj = getById(self, id)
			if obj then
				all_instaces:append(obj)
			end
		end
		return all_instaces
	end;

	-- 支持以负数为索引
	slice = function (self, start, stop, is_rev)
		I_AM_CLASS(self)
		local all_ids = self:sliceIds(start, stop, is_rev)
		local objs = List()
		local getById = self.getById 

		for _, id in ipairs(all_ids) do
			local obj = getById(self, id)
			if obj then
				objs:append(obj)
			end
		end
		
		return objs
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
    get = function (self, query_args, is_rev)
		I_AM_CLASS(self)
		local id = query_args.id
		
		-- 如果查询要求中有id，就以id为主键查询。因为id是存放在总key中，所以要分开处理
		if id then
			query_args['id'] = nil

			-- 把这个id的整个对象取出来
			local obj = self:getById( id )
			if isObjEmpty(obj) then return nil end
			
			local fields = obj.__fields
			for k, v in pairs(query_args) do
				if not fields[k] then return nil end
				-- 如果是函数，执行限定比较，返回布尔值
				if type(v) == 'function' then
					-- 进入函数v进行比较的，总是单个字段
					local flag = v(obj[k])
					-- 如果不在限制条件内，直接跳出循环
					if not flag then return nil end
				-- 处理查询条件为等于的情况
				else
					-- 一旦发现有不等的情况，立即返回否值
					if obj[k] ~= v then return nil end
				end
			end
			-- 如果执行到这一步，就说明已经找到了，返回对象
			return obj
		-- 如果查询要求中没有id
		else
			-- 取得所有关于这个模型的实例keys
			local all_ids = self:allIds(is_rev)
			local getById = self.getById 
			for _, kk in ipairs(all_ids) do
				-- 根据key获得一个实例的内容，返回一个表
				local obj = getById(self, kk)
				local flag = true
				local fields = obj.__fields
				for k, v in pairs(query_args) do
					if not obj or not fields[k] then flag=false; break end
					
					if type(v) == 'function' then
						-- 进入函数v进行比较的，总是单个字段
						flag = v(obj[k])
						-- 如果不在限制条件内，直接跳出循环，检查下一个
						if not flag then break end
					else
						-- 处理条件式为等于的情况
						if obj[k] ~= v then flag=false; break end
					end
				end
				-- 如果走到这一步，flag还为真，则说明已经找到第一个，直接返回
				if flag then
					return obj
				end
			end
		end
		
		return nil		
    end;

	-- filter的query表中，不应该出现id，这里也不打算支持它
	-- filter返回的是一个列表
	-- starti 是指明从哪一个序号开始搜索, length指明要找几个元素
	-- dir指明要查找的方向，1表示正向，-1表示反向
	filter = function (self, query_args, is_rev, starti, length, dir)
		I_AM_CLASS_OR_QUERY_SET(self)
		
		local is_query_set = false
		if isList(self) then is_query_set = true end
		
		local dir = dir or 1
		assert( dir == 1 or dir == -1, '[Error] dir must be 1 or -1.')
		
		if query_args and query_args['id'] then
			-- 去除以id为键的搜索
			print("[WARNING] Filter doesn't support search by id.")
			query_args['id'] = nil 
			
		end
		
		-- 当为空时，就返回所有
		if isEmpty(query_args) then return self:all() end
		
		local logic = 'and'
		if query_args[1] then
			if query_args[1] == 'or' then
				logic = 'or'
			end
			query_args[1] = nil
		end
		-- ???行不行???
		-- 这里让query_set（一个表）也获得Model中定义的方法，到时可用于链式操作
		-- 这里就创建了一个query_set，类似于Django中的
		local query_set = setProto(List(), Model)
		-- add it to fit the check of isClass function
		query_set.__spectype = 'QuerySet'
		
			
		local all_ids
		if is_query_set then
		-- 如果是query_set，则把all_ids就看成对象的列表，而不是对象id的列表
			all_ids = self
		else
		-- 取得所有关于这个模型的实例id
			all_ids = self:allIds(is_rev)
		end
		
		if starti then
			checkType(starti, 'number')
			assert( starti >= 1, '[Error] starti must be greater than 1.')
			-- 取得从指定开始位置到末尾的列表
			if dir == 1 then
				all_ids = all_ids:slice(starti, -1)
			else
				all_ids = all_ids:slice(1, starti)
			end
		end
		if #all_ids == 0 then return {} end
		
		local s, e
		local exiti = 0
		local getById = self.getById 
		if dir > 0 then
			s = 1
			e = #all_ids
			dir = 1
		else
			s = #all_ids
			e = 1
			dir = -1
		end
			
		for i = s, e, dir do
			local flag = true	
			local flag_all = false
			local obj
			if is_query_set then
				obj = all_ids[i]
			else
				local kk = all_ids[i]
				-- 根据key获得一个实例的内容，返回一个表
				obj = getById (self, kk)
			end
			local fields = obj.__fields
			
			for k, v in pairs(query_args) do
				-- 对于多余的查询条件，一经发现，直接跳出
				if not obj or not fields[k] then flag=false; break end
				-- 处理条件式为外调函数的情况
				if type(v) == 'function' then
					-- 进入函数v进行比较的，总是单个字段
					flag = v(obj[k])
					-- 如果不在限制条件内，直接跳出循环
					if logic == 'and' then
					-- 逻辑为and的情况下，只要有一个条件不满足，就跳过
						if not flag then break end
					else
					-- 逻辑为or的情况下，只要有一个条件满足，就添加
						if flag then break end
					end
	
				else
				-- 处理条件式为等于的情况
					if logic == 'and' then
					-- 逻辑为and的情况下，只要有一个条件不满足，就跳过
						if obj[k] ~= v then flag=false; break end
					else
					-- 逻辑为or的情况下，只要有一个条件满足，就添加
						if obj[k] == v then flag=true; break end
					end
				end
			end
			-- 如果走到这一步，flag还为真，则说明已经找到，添加到查询结果表中去
			if flag then
				-- filter返回的表中由一个个值对构成
				query_set:append(obj)
				
				if length then 
					checkType(length, 'number')
					if length > 0 and #query_set >= length then
					-- 如果找到的元素个数已经达到要求
						exiti = i
						break
					end
				end
			end
		end
			
		-- 返回的时候，不仅返回取得的结果，还返回搜索到的最终位置
		local endpoint
		if starti then
			if exiti > 0 then
				endpoint = (dir == 1) and starti + exiti - 1 or exiti
			else
				endpoint = (dir == 1) and starti + #all_ids - 1 or 1
			end
		else
			endpoint = #all_ids
		end
		
		-- 当是反向查找的时候，还要把结果再反过来
		if dir == -1 then
			query_set:reverse()
		end
		
		return query_set, endpoint
		
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
	
	-- 向数据库中存入自定义键值对，灵活性比较高，也比较危险
	-- 目前可以存储字符串和list
	setCustom = function (self, key, val, st)
		I_AM_CLASS(self)
		checkType(key, 'string')
		local one_key = getClassName(self) + ':' + key
		if st == 'LIST' then
			checkType(val, 'table')
			-- 先删除以前的value，要重填value
			db:del(one_key)
			for _, v in ipairs(val) do
				db:rpush(one_key, v)
			end
		else
			assert( type(val) == 'string' or type(val) == 'number', "[ERROR] In the string mode of setCustom, val should be string or number.")
			db:set(one_key, val)
		end
	end;

	-- 向数据库中取出自定义键值对
	getCustom = function (self, key, st)
		I_AM_CLASS(self)
		checkType(key, 'string')
		local one_key = getClassName(self) + ':' + key
		if not db:exists(one_key) then print(("[WARNING] Key %s doesn't exist!"):format(one_key)); return nil end

		local store_type = db:type(one_key)
		if store_type == 'list' then
			if not st or st ~= 'LIST' then print(("[WARNING] Key %s is list!"):format(one_key)) end
			return db:lrange(one_key, 0, -1)
		elseif store_type == 'string' then
			return db:get(one_key)
		end
	end;

	delCustom = function (self, key)
		I_AM_CLASS(self)
		checkType(key, 'string')
		local one_key = getClassName(self) + ':' + key
		
		return db:del(one_key)		
	end;
	
	-- 简单的使用模型验证上传表单参数的功能
	validate = function (self, params)
		I_AM_CLASS(self)
		checkType(params, 'table')
		local fields = self.__fields
		for k, v in pairs(fields) do
			local t = params[k]
			-- 规则1，如果域有required=true，那么
			if v.required then
				-- 在required的情况下，如果上传参数不存在，或参数长度为空
				if not t or #t == 0 then return false, ('Required parameter "%s" is missing.'):format(k) end
			end
			-- 如果有此域的内容，那么就检测
			if t and t ~= '' then
				-- 规则2，如果域有min, max，则说明传输的是数字，限定一个范围
				if v.min then
					local num = tonumber(t)
					if not num or num < tonumber(v.min) then
						return false, ('Parameter "%s" should be equal or larger than %s.'):format(k, v.min) 
					end
				end
				if v.max then
					local num = tonumber(t)
					if not num or num > tonumber(v.max) then
						return false, ('Parameter "%s" should be equal or smaller than %s.'):format(k, v.max) 
					end
				end
				-- 规则3，如果域有min_length, max_length，则说明传输的是字符串，要限定在一个范围
				if v.min_length then
					if #t < v.min_length then
						return false, ('Parameter "%s" should be equal or larger than %s.'):format(k, v.min_length) 
					end
				end
				if v.max_length then
					if #t > v.max_length then
						return false, ('Parameter "%s" should be equal or smaller than %s.'):format(k, v.max_length) 
					end
				end
				-- 规则4，如果域有pattern，则说明传输的是字符串，要限定在一个正则表达式匹配范围内
				if v.pattern then
					local ret = t:match(v.pattern)
					if not ret or #t ~= #ret then
						return false, ('Parameter "%s" should be suited to the internal pattern.'):format(k) 
					end
				end
			end
		end
		
		return true
	end;
	
	fieldInfo = function (self, field)
		I_AM_CLASS(self)
		checkType(field, 'string')
		
		-- 如果有，就返回描述表；如果没有，就返回nil
		return self.__fields[field]
	end;
	
	
    --------------------------------------------------------------------
	-- 实例函数。由类的实例访问
	--------------------------------------------------------------------
    -- 在数据库中创建一个hash表项，保存模型实例
    save = function (self)
		I_AM_INSTANCE(self)
        assert(self.name, "[ERROR] The name field doesn't exist!")
        local model_key = self.__name + ':' + tostring(self.id)
		local isExisted = db:exists(model_key)
		-- 如果之前数据库中没有这个对象，即是新创建的情况
		local index_key = getIndexName(self)
		if not isExisted then
			-- 对象类别的总数计数器就加1
			db:incr(self.__name + ':__counter')
			-- 将记录添加到Model:__index中去
			-- 在保存索引的时候，使用__tag中的最后一个单词作为名字，
			-- 这是因为__name有可能会命名成与父辈同名的名字
			
			-- local index_key = self.__name + ':__index'
			--assert(db:exists(index_key), ("[ERROR] %s doesn't exist!"):format(index_key))
			db:zadd(index_key, tonumber(self.id), self.name)
		else
			-- 如果对象存在, 更新索引信息
			-- 先把之前的删除掉
			db:zremrangebyscore(index_key, self.id, self.id)
			-- 再把新的name添加进去
			db:zadd(index_key, self.id, self.name)
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
			-- 如果v为nil，则pairs将不会遍历它及它对应的key
			if (not k:startsWith('_')) and type(v) ~= 'function' and field and (not field['foreign']) then
				-- 由于不保存有外键的字段，故可以在这里对各种类型直接以字符串存储
				db:hset(model_key, k, v)
			end
		end
		
		return self
    end;
    
    -- 这是当实例取出来后，进行部分更新的函数
    update = function (self, field, new_value)
		I_AM_INSTANCE(self)
		checkType(field, new_value, 'string', 'string')
		local fld = self.__fields[field]
		assert(fld, ("[ERROR] Field %s doesn't be defined!"):format(field))
		assert( not fld['foreign'], ("[ERROR] %s is a foreign field, shouldn't use update function!"):format(field))
		local model_key = self.__name + ':' + tostring(self.id)
		assert(db:exists(model_key), ("[ERROR] Key %s does't exist! Can't apply update."):format(model_key))
		db:hset(model_key, field, new_value)
		
		return self
    end;
    
    --fillFreshFields = function (self, t)
		--I_AM_INSTANCE(self)
		--if not t then return self end
		--return self:init(t)
    --end;
    
    -- 获取模型的counter值
    getCounter = function (self)
		I_AM_INSTANCE(self)
		return tonumber(db:get(self.__name + ':__counter') or 0)
    end;
    
    -- 删除数据库中的一个对象数据
    -- 可以是单个对象，也可以是query_set，即对象列表
    del = function (self)
		I_AM_INSTANCE_OR_QUERY_SET(self)
		-- 如果self是单个对象
		if self['id'] then
			-- 在数据库中删除这个对象的内容
			delFromRedis(self)
		
		else
		-- 如果self是一个对象列表，即query_set
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
		I_AM_INSTANCE(self)
		checkType(field, 'string')
		assert(type(new_obj) == 'table' or type(new_obj) == 'string', '[ERROR] "new_obj" should be table or string.')
		if type(new_obj) == 'table' then checkType(tonumber(new_obj.id), 'number') end
		
		local fld = self.__fields[field]
		assert(fld, ("[ERROR] Field %s doesn't be defined!"):format(field))
		assert( fld.foreign, ("[ERROR] This field %s is not a foreign field."):format(field))
		assert( fld.foreign == 'ANYSTRING' or new_obj.id , "[ERROR] This object doesn't contain id, it's not a valid object!")
		assert( fld.foreign == 'ANYSTRING' or fld.foreign == 'UNFIXED' or fld.foreign == getClassName(new_obj), ("[ERROR] This foreign field '%s' can't accept the instance of model '%s'."):format(field, getClassName(new_obj) or new_obj))
		
		local new_id
		if fld.foreign == 'ANYSTRING' then
			checkType(new_obj, 'string')
			new_id = new_obj
		elseif fld.foreign == 'UNFIXED' then
			new_id = getClassName(new_obj) + ':' + new_obj.id
		else
			new_id = new_obj.id
		end
		
		local model_key = self.__name + ':' + tostring(self.id)
		if (not fld.st) or fld.st == 'ONE' then
			-- 当没有写st属性，或st属性为ONE时，即为单外链时
			db:hset(model_key, field, new_id)
			-- 单外键是可以被get系函数获取出来的
			self[field] = new_id

		elseif fld.st == 'MANY' then
			-- 当为多外键时
			local key = model_key + ':' + field
			-- 将新值更新到数据库中去，因此，后面不用用户再写self:save()了
			rdzset.addToZset(key, new_id)

		elseif fld.st == 'FIFO' then
			-- 当指定的为FIFO管道时
			local length = fld.fifolen
			assert(length and type(length) == 'number' and length > 0, 
				"[ERROR] In Fifo foreign, the 'fifolen' must be number greater than 0!")
			local key = model_key + ':' + field
			rdfifo.pushToFifo(key, length, new_id)

		elseif fld.st == 'ZFIFO' then
			-- 当指定的为ZFIFO管道时
			local length = fld.fifolen
			assert(length and type(length) == 'number' and length > 0, 
				"[ERROR] In Fifo foreign, the 'fifolen' must be number greater than 0!")
			local key = model_key + ':' + field
			
			local new_score = db:incr(key+':virctr')
			rdzfifo.pushToZfifo(key, length, new_score, new_id)
		end
		
		return self
	end;
	
	-- liststr的处理算法
	-- 释放本对象的一个域中所存储的外链模型的实例
	-- 返回那些实例的对象列表
	getForeign = function (self, field, start, stop, is_rev)
		I_AM_INSTANCE(self)
		checkType(field, 'string')
		local fld = self.__fields[field]
		assert(fld, ("[ERROR] Field %s doesn't be defined!"):format(field))
		assert( fld.foreign, ("[ERROR] This field %s is not a foreign field."):format(field))
		
		
		local model_key = self.__name + ':' + self.id
		local link_model, linked_id
		if (not fld.st) or fld.st == 'ONE' then
			if isFalse(self[field]) then return nil end
			
			if fld.foreign == 'ANYSTRING' then
				-- 直接返回字符串
				return self[field]
			else
				-- 其它真正的外键情况
				link_model, linked_id = checkUnfixed(fld, self[field])
				-- 返回单个外键对象
				local obj = link_model:getById (linked_id)
				if isObjEmpty(obj) then
					
					-- 如果没有获取到，就把这个外键去掉
					db:hset(model_key, field, '')
					self[field] = ''
					return nil
				else
					return obj
				end
			end
		elseif fld.st == 'MANY' then
			if isFalse(self[field]) then return {} end
			
			local key = model_key + ':' + field
			local list = rdzset.retrieveZset(key)
			if isEmpty(list) then return {} end
			
			list = list:slice(start, stop, is_rev)
			if isEmpty(list) then return {} end
			
			if fld.foreign == 'ANYSTRING' then
				-- 直接返回字符串列表
				return list
			else
				local obj_list = List()
				for _, v in ipairs(list) do
					link_model, linked_id = checkUnfixed(fld, v)

					local obj = link_model:getById(linked_id)
					-- 这里，要检查返回的obj是不是空对象，而不仅仅是不是空表
					if isObjEmpty(obj) then
						-- 如果没有获取到，就把这个外键去掉
						rdzset.removeFromZset(key, v)
					else
						obj_list:append(obj)
					end
				end
				
				return obj_list
			end
			
		elseif fld.st == 'FIFO' then
			if isFalse(self[field]) then return {} end
		
			local key = model_key + ':' + field
			local list = rdfifo.retrieveFifo(key)
			
			list = list:slice(start, stop, is_rev)
			if isFalse(list) then return {} end
	
			if fld.foreign == 'ANYSTRING' then
				-- 直接返回字符串列表
				return list
			else
				local obj_list = List()
				for _, v in ipairs(list) do
					link_model, linked_id = checkUnfixed(fld, v)

					local obj = link_model:getById(linked_id)
					-- 这里，要检查返回的obj是不是空对象，而不仅仅是不是空表
					if isObjEmpty(obj) then
						-- 如果没有获取到，就把这个外键元素去掉
						rdfifo.removeFromFifo(key, v)
					else
						obj_list:append(obj)
					end
				end
				
				return obj_list
			end
			
		elseif fld.st == 'ZFIFO' then
			if isFalse(self[field]) then return {} end
		
			local key = model_key + ':' + field
			-- 由于FIFO的特性，取出来的列表，新鲜的是在左边
			local list = rdzfifo.retrieveZfifo(key)
			
			list = list:slice(start, stop, is_rev)
			if isFalse(list) then return {} end
	
			if fld.foreign == 'ANYSTRING' then
				-- 直接返回嵌套列表
				return list
			else
				local obj_list = List()
				-- 把下面用得到的内容部分抽取出来
				local tlist = List()
				for _, v in ipairs(list) do
					tlist:append(v[1])
				end
				list = tlist
				
				for _, v in ipairs(list) do
					link_model, linked_id = checkUnfixed(fld, v)

					local obj = link_model:getById(linked_id)
					-- 这里，要检查返回的obj是不是空对象，而不仅仅是不是空表
					if isObjEmpty(obj) then
						-- 如果没有获取到，就把这个外键元素去掉
						rdzfifo.removeFromZfifo(key, 0, v)
					else
						obj_list:append(obj)
					end
				end
				
				return obj_list
			end
		end

	end;    
	
	delForeign = function (self, field, frobj)
		I_AM_INSTANCE(self)
		checkType(field, frobj, 'string', 'table')
		local fld = self.__fields[field]
		assert(fld, ("[ERROR] Field %s doesn't be defined!"):format(field))
		assert( fld.foreign, ("[ERROR] This field %s is not a foreign field."):format(field))
		assert( fld.foreign == 'ANYSTRING' or frobj.id, "[ERROR] This object doesn't contain id, it's not a valid object!")
		if isFalse(self[field]) then return end
		
		local frid
		if fld.foreign == 'ANYSTRING' then
			checkType(frobj, 'string')
			frid = frobj
		elseif fld.foreign == 'UNFIXED' then
			frid = getClassName(frobj) + ':' + frobj.id
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
			rdzset.removeFromZset(model_key + ':' + field, frid)
		
		elseif fld.st == 'FIFO' then
			rdfifo.removeFromFifo(model_key + ':' + field, frid)
			
		elseif fld.st == 'ZFIFO' then
			-- 此处，frid为要删除的项的score
			rdzfifo.removeFromZfifo(model_key + ':' + field, frid)
			
		end
	
		return self
	end;

	numForeign = function (self, field)
		I_AM_INSTANCE(self)
		checkType(field, 'string')
		local fld = self.__fields[field]
		assert(fld, ("[ERROR] Field %s doesn't be defined!"):format(field))
		assert( fld.foreign, ("[ERROR] This field %s is not a foreign field."):format(field))
		-- 还没有外链的
		if isFalse(self[field]) then return 0 end
		
		local model_key = self.__name + ':' + tostring(self.id)
		if (not fld.st) or fld.st == 'ONE' then
			-- 单外链就是一个噻
			return 1
		elseif fld.st == 'MANY' then
			return rdzset.lenZset(model_key + ':' + field)
		
		elseif fld.st == 'FIFO' then
			return rdfifo.lenFifo(model_key + ':' + field)
	
		elseif fld.st == 'ZFIFO' then
			return rdzfifo.lenZfifo(model_key + ':' + field)
	
		end
	
	end;


}

return Model
