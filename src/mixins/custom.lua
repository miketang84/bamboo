local rdstring = require 'bamboo.db.redis.string'
local rdlist = require 'bamboo.db.redis.list'
local rdset = require 'bamboo.db.redis.set'
local rdzset = require 'bamboo.db.redis.zset'
local rdfifo = require 'bamboo.db.redis.fifo'
local rdzfifo = require 'bamboo.db.redis.zfifo'
local rdhash = require 'bamboo.db.redis.hash'

-----------------------------------------------------------------
local rdactions = {
	['string'] = {},
	['list'] = {},
	['set'] = {},
	['zset'] = {},
	['hash'] = {},
	['fifo'] = {},
	['zfifo'] = {},
  
}

rdactions['string'].save = rdstring.save
rdactions['string'].update = rdstring.update
rdactions['string'].retrieve = rdstring.retrieve
rdactions['string'].remove = rdstring.remove
rdactions['string'].add = rdstring.add
rdactions['string'].has = rdstring.has
rdactions['string'].num = rdstring.num

rdactions['list'].save = rdlist.save
rdactions['list'].update = rdlist.update
rdactions['list'].retrieve = rdlist.retrieve
rdactions['list'].remove = rdlist.remove
--rdactions['list'].add = rdlist.add
rdactions['list'].add = rdlist.append
rdactions['list'].has = rdlist.has
--rdactions['list'].num = rdlist.num
rdactions['list'].num = rdlist.len

rdactions['set'].save = rdset.save
rdactions['set'].update = rdset.update
rdactions['set'].retrieve = rdset.retrieve
rdactions['set'].remove = rdset.remove
rdactions['set'].add = rdset.add
rdactions['set'].has = rdset.has
rdactions['set'].num = rdset.num

rdactions['zset'].save = rdzset.save
rdactions['zset'].update = rdzset.update
--rdactions['zset'].retrieve = rdzset.retrieve
rdactions['zset'].retrieve = rdzset.retrieveWithScores
rdactions['zset'].remove = rdzset.remove
rdactions['zset'].add = rdzset.add
rdactions['zset'].has = rdzset.has
rdactions['zset'].num = rdzset.num

rdactions['hash'].save = rdhash.save
rdactions['hash'].update = rdhash.update
rdactions['hash'].retrieve = rdhash.retrieve
rdactions['hash'].remove = rdhash.remove
rdactions['hash'].add = rdhash.add
rdactions['hash'].has = rdhash.has
rdactions['hash'].num = rdhash.num

local getStoreModule = function (store_type)
	local store_module = rdactions[store_type]
	assert( store_module, "[Error] store type must be one of 'string', 'list', 'set', 'zset' or 'hash'.")
	return store_module
end

local getStoreModule = bamboo.internal.getStoreModule

local function getCustomKey(self, key)
	return format('%s:custom:%s', self.__name, key)
end

local function getCustomIdKey(self, key)
	return format('%s:%s:custom:%s', self.__name, self.id, key)
end

local makeCustomKey = function (self, key)
	return self:isClass() and getCustomKey(self, key) or getCustomIdKey(self, key)
end

local rdstring = require 'bamboo.db.redis.string'

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
			self.__db:incrby(custom_key,step or 1)
			
			return self
		end;
		
		decrCustom = function(self, key, step)
			I_AM_CLASS_OR_INSTANCE(self)
			checkType(key, 'string')
			local custom_key = makeCustomKey(self, key)
			self.__db:decrby(custom_key,step or 1);
			
			return self
		end;

		-- store customize key-value pair to db
		-- now: it support string, list and so on
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

		setCustomQuerySet = function (self, key, query_set, scores)
			I_AM_CLASS_OR_INSTANCE(self)
			I_AM_QUERY_SET(query_set)
			checkType(key, 'string')

			if type(scores) == 'table' then
				local ids = {}
				for i, v in ipairs(query_set) do
					tinsert(ids, v.id)
				end
				self:setCustom(key, ids, 'zset', scores)
			else
				local ids = {}
				for i, v in ipairs(query_set) do
					tinsert(ids, v.id)
				end
				self:setCustom(key, ids, 'list')
			end

			return self
		end;

		--
		getCustomKey = function (self, key)
			I_AM_CLASS_OR_INSTANCE(self)
			checkType(key, 'string')
			local custom_key = makeCustomKey(self, key)

			return custom_key, self.__db:type(custom_key)
		end;

		getCustom = function (self, key, start, stop, is_rev)
			I_AM_CLASS_OR_INSTANCE(self)
			checkType(key, 'string')
			
			local custom_key = makeCustomKey(self, key)
			if not self.__db:exists(custom_key) then
				local atype = start
				-- print(("[Warning] @getCustom - Key %s doesn't exist!"):format(custom_key))
				if not atype or atype == 'string' then return nil
				elseif atype == 'list' then
					return List()
				else
					-- TODO: need to seperate every type
					return {}
				end
			end

			-- get the store type in redis
			local store_type = self.__db:type(custom_key)
			local store_module = getStoreModule(store_type)
			local ids, scores = store_module.retrieve(custom_key)

      -- temporarily keep it now, is slow when list length is long
			if type(ids) == 'table' and (type(start)=='number' or stop) then
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
			local query_set_ids, scores = self:getCustom(key, start, stop, is_rev)
			if isFalse(query_set_ids) then
				return QuerySet(), nil
			else
				local query_set = self:getByIds(query_set_ids)
				return query_set, scores
			end
		end;

		delCustom = function (self, key)
			I_AM_CLASS_OR_INSTANCE(self)
			checkType(key, 'string')
			local custom_key = makeCustomKey(self, key)

			return self.__db:del(custom_key)
		end;

		-- check whether exist custom key
		existCustom = function (self, key)
			I_AM_CLASS_OR_INSTANCE(self)
			checkType(key, 'string')
			local custom_key = makeCustomKey(self, key)

			if self.__db:exists(custom_key) then
				return true
			else
				return false
			end
		end;

		removeCustomMember = function (self, key, val)
			I_AM_CLASS_OR_INSTANCE(self)
			checkType(key, 'string')
			local custom_key = makeCustomKey(self, key)		

			local store_type = self.__db:type(custom_key)
			local store_module = getStoreModule(store_type)
			return store_module.remove(custom_key, val)

		end;

		addCustomMember = function (self, key, val, st, score)
			I_AM_CLASS_OR_INSTANCE(self)
			checkType(key, 'string')
			local custom_key = makeCustomKey(self, key)		

			local store_type = self.__db:type(custom_key) ~= 'none' and self.__db:type(custom_key) or st
			local store_module = getStoreModule(store_type)
			return store_module.add(custom_key, val, score)

		end;

		hasCustomMember = function (self, key, mem)
			I_AM_CLASS_OR_INSTANCE(self)
			checkType(key, 'string')
			local custom_key = makeCustomKey(self, key)		

			if not self.__db:exists(custom_key) then print('[Warning] @hasCustomMember - This custom key does not exist.'); return nil end
			local store_type = self.__db:type(custom_key)
			local store_module = getStoreModule(store_type)
			return store_module.has(custom_key, mem)

		end;

		numCustom = function (self, key)
			I_AM_CLASS_OR_INSTANCE(self)
			checkType(key, 'string')
			local custom_key = makeCustomKey(self, key)		

			if not self.__db:exists(custom_key) then return 0 end
			local store_type = self.__db:type(custom_key)
			local store_module = getStoreModule(store_type)
			return store_module.num(custom_key)
		end;
	
	
	}
end
