
local db = BAMBOO_DB

local function getCustomKey(self, key)
	return getClassName(self) + ':custom:' + key
end

local function getCustomIdKey(self, key)
	return getClassName(self) + ':' + self.id + ':custom:'  + key
end


local makeCustomKey = function (self, key)
	local custom_key = self:isClass() and getCustomKey(self, key) or getCustomIdKey(self, key)
end


return function ()
	
	return {
		-------------------------------------------------------------------
		-- CUSTOM API
		--- seven APIs
		-- 1. setCustom
		-- 2. getCustom
		-- 3. delCustom
		-- 4. existCustom
		-- 5. updateCustom
		-- 6. addCustomMember
		-- 7. removeCustomMember
		-- 8. hasCustomMember
		-- 9. numCustom

		-- 10. incrCustom   only number
		-- 11. decrCustom   only number
		--
		--- five store type
		-- 1. string
		-- 2. list
		-- 3. set
		-- 4. zset
		-- 5. hash
		-- 6. fifo   , scores is the length of fifo
		-------------------------------------------------------------------

		-- store customize key-value pair to db
		-- now: st is string, and value is number
		-- if no this key, the value is 0 before performing the operation
		incrCustom = function(self, key, step)
			I_AM_CLASS_OR_INSTANCE(self)
			checkType(key, 'string')
			local custom_key = makeCustomKey(self, key)
			db:incrby(custom_key,step or 1)
		end;
		
		decrCustom = function(self, key, step)
			I_AM_CLASS_OR_INSTANCE(self)
			checkType(key, 'string')
			local custom_key = makeCustomKey(self, key)
			db:decrby(custom_key,step or 1);
		end;

		-- store customize key-value pair to db
		-- now: it support string, list and so on
		-- if fifo ,the scores is the length of the fifo
		setCustom = function (self, key, val, st, scores)
			I_AM_CLASS_OR_INSTANCE(self)
			checkType(key, 'string')
			
			local custom_key = makeCustomKey(self, key)		

			if not st or st == 'string' then
				assert( type(val) == 'string' or type(val) == 'number',
						"[Error] @setCustom - In the string mode of setCustom, val should be string or number.")
				rdstring.save(custom_key, val)
			else
				local store_module = getStoreModule(st)
				store_module.save(custom_key, val, scores)
			end

			return self
		end;

		setCustomQuerySet = function (self, key, query_set, scores, is_cache, cache_life)
			I_AM_CLASS_OR_INSTANCE(self)
			I_AM_QUERY_SET(query_set)
			checkType(key, 'string')

			if type(scores) == 'table' then
				local ids = {}
				for i, v in ipairs(query_set) do
					tinsert(ids, v.id)
				end
				self:setCustom(key, ids, 'zset', scores, is_cache, cache_life)
			else
				local ids = {}
				for i, v in ipairs(query_set) do
					tinsert(ids, v.id)
				end
				self:setCustom(key, ids, 'list', is_cache, cache_life)
			end

			return self
		end;

		--
		getCustomKey = function (self, key)
			I_AM_CLASS_OR_INSTANCE(self)
			checkType(key, 'string')
			local custom_key = makeCustomKey(self, key)

			return custom_key, db:type(custom_key)
		end;

		--
		getCustom = function (self, key, start, stop, is_rev)
			I_AM_CLASS_OR_INSTANCE(self)
			checkType(key, 'string')
			local custom_key = makeCustomKey(self, key)
			if not db:exists(custom_key) then
				print(("[Warning] @getCustom - Key %s doesn't exist!"):format(custom_key))
				if not atype or atype == 'string' then return nil
				elseif atype == 'list' then
					return List()
				else
					-- TODO: need to seperate every type
					return {}
				end
			end

			-- get the store type in redis
			local store_type = db:type(custom_key)
			if atype then assert(store_type == atype, '[Error] @getCustom - The specified type is not equal the type stored in db.') end
			local store_module = getStoreModule(store_type)
			local ids, scores = store_module.retrieve(custom_key)

			if type(ids) == 'table' and (start or stop) then
				ids = ids:slice(start, stop, is_rev)
				if type(scores) == 'table' then
					scores = scores:slice(start, stop, is_rev)
				end
			end

			return ids, scores
		end;

		getCustomQuerySet = function (self, key, start, stop, is_rev)
			I_AM_CLASS_OR_INSTANCE(self)
			checkType(key, 'string')
			local query_set_ids, scores = self:getCustom(key, nil, start, stop, is_rev)
			if isFalse(query_set_ids) then
				return QuerySet(), nil
			else
				local query_set, nils = getFromRedisPipeline(self, query_set_ids)

				if bamboo.config.auto_clear_index_when_get_failed then
					if not isFalse(nils) then
						for _, v in ipairs(nils) do
							self:removeCustomMember(key, v)
						end
					end
				end

				return query_set, scores
			end
		end;

		delCustom = function (self, key)
			I_AM_CLASS_OR_INSTANCE(self)
			checkType(key, 'string')
			local custom_key = makeCustomKey(self, key)

			return db:del(custom_key)
		end;

		-- check whether exist custom key
		existCustom = function (self, key)
			I_AM_CLASS_OR_INSTANCE(self)
			checkType(key, 'string')
			local custom_key = makeCustomKey(self, key)

			if not db:exists(custom_key) then
				return false
			else
				return true
			end
		end;

		-- XXX: this is a odd api, useless
		-- TODO: add score argument appending
		updateCustom = function (self, key, val)
			I_AM_CLASS_OR_INSTANCE(self)
			checkType(key, 'string')
			local custom_key = makeCustomKey(self, key)		

			if not db:exists(custom_key) then print('[Warning] @updateCustom - This custom key does not exist.'); return nil end
			local store_type = db:type(custom_key)
			local store_module = getStoreModule(store_type)
			return store_module.update(custom_key, val)

		end;

		removeCustomMember = function (self, key, val)
			I_AM_CLASS_OR_INSTANCE(self)
			checkType(key, 'string')
			local custom_key = makeCustomKey(self, key)		

			if not db:exists(custom_key) then print('[Warning] @removeCustomMember - This custom key does not exist.'); return nil end
			local store_type = db:type(custom_key)
			local store_module = getStoreModule(store_type)
			return store_module.remove(custom_key, val)

		end;

		addCustomMember = function (self, key, val, st, score)
			I_AM_CLASS_OR_INSTANCE(self)
			checkType(key, 'string')
			local custom_key = makeCustomKey(self, key)		

			if not db:exists(custom_key) then print('[Warning] @addCustomMember - This custom key does not exist.'); end
			local store_type = db:type(custom_key) ~= 'none' and db:type(custom_key) or st
			local store_module = getStoreModule(store_type)
			return store_module.add(custom_key, val, score)

		end;

		hasCustomMember = function (self, key, mem)
			I_AM_CLASS_OR_INSTANCE(self)
			checkType(key, 'string')
			local custom_key = makeCustomKey(self, key)		

			if not db:exists(custom_key) then print('[Warning] @hasCustomMember - This custom key does not exist.'); return nil end
			local store_type = db:type(custom_key)
			local store_module = getStoreModule(store_type)
			return store_module.has(custom_key, mem)

		end;

		numCustom = function (self, key)
			I_AM_CLASS_OR_INSTANCE(self)
			checkType(key, 'string')
			local custom_key = makeCustomKey(self, key)		

			if not db:exists(custom_key) then return 0 end
			local store_type = db:type(custom_key)
			local store_module = getStoreModule(store_type)
			return store_module.num(custom_key)
		end;
	
	}
end
