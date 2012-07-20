
local List = require 'lglib.list'
local rdstring = require 'bamboo.redis.string'
local rdlist = require 'bamboo.redis.list'
local rdset = require 'bamboo.redis.set'
local rdzset = require 'bamboo.redis.zset'
local rdfifo = require 'bamboo.redis.fifo'
local rdzfifo = require 'bamboo.redis.zfifo'
local rdhash = require 'bamboo.redis.hash'


-----------------------------------------------------------------
local rdactions = {
	['string'] = {},
	['list'] = {},
	['set'] = {},
	['zset'] = {},
	['hash'] = {},
	['MANY'] = {},
	['FIFO'] = {},
	['ZFIFO'] = {},
	['LIST'] = {},
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

rdactions['FIFO'].save = rdfifo.save
rdactions['FIFO'].update = rdfifo.update
rdactions['FIFO'].retrieve = rdfifo.retrieve
rdactions['FIFO'].remove = rdfifo.remove
rdactions['FIFO'].add = rdfifo.push
rdactions['FIFO'].has = rdfifo.has
rdactions['FIFO'].num = rdfifo.len

rdactions['ZFIFO'].save = rdzfifo.save
rdactions['ZFIFO'].update = rdzfifo.update
rdactions['ZFIFO'].retrieve = rdzfifo.retrieve
rdactions['ZFIFO'].remove = rdzfifo.remove
rdactions['ZFIFO'].add = rdzfifo.push
rdactions['ZFIFO'].has = rdzfifo.has
rdactions['ZFIFO'].num = rdzfifo.num

rdactions['LIST'] = rdactions['list']
rdactions['MANY'] = rdactions['zset']

local getStoreModule = function (store_type)
	local store_module = rdactions[store_type]
	assert( store_module, "[Error] store type must be one of 'string', 'list', 'set', 'zset' or 'hash'.")
	return store_module
end



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
incrCustom = function(self,key,step) 
	I_AM_CLASS_OR_INSTANCE(self)
	checkType(key, 'string')
	local custom_key = self:isClass() and getCustomKey(self, key) or getCustomIdKey(self, key)
	db:incrby(custom_key,step or 1) 
end;
decrCustom = function(self,key,step) 
	I_AM_CLASS_OR_INSTANCE(self)
	checkType(key, 'string')
	local custom_key = self:isClass() and getCustomKey(self, key) or getCustomIdKey(self, key)
	db:decrby(custom_key,step or 1);
end;

-- store customize key-value pair to db
-- now: it support string, list and so on
-- if fifo ,the scores is the length of the fifo
setCustom = function (self, key, val, st, scores)
	I_AM_CLASS_OR_INSTANCE(self)
	checkType(key, 'string')
	local custom_key = self:isClass() and getCustomKey(self, key) or getCustomIdKey(self, key)

	if not st or st == 'string' then
		assert( type(val) == 'string' or type(val) == 'number',
				"[Error] @setCustom - In the string mode of setCustom, val should be string or number.")
		rdstring.save(custom_key, val)
	else
		-- checkType(val, 'table')
		local store_module = getStoreModule(st)
		store_module.save(custom_key, val, scores)
	end
end;

-- 
getCustomKey = function (self, key)
	I_AM_CLASS_OR_INSTANCE(self)
	checkType(key, 'string')
	local custom_key = self:isClass() and getCustomKey(self, key) or getCustomIdKey(self, key)
	
	return custom_key, db:type(custom_key)
end;

-- 
getCustom = function (self, key, atype)
	I_AM_CLASS_OR_INSTANCE(self)
	checkType(key, 'string')
	local custom_key = self:isClass() and getCustomKey(self, key) or getCustomIdKey(self, key)
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
	return store_module.retrieve(custom_key), store_type
end;

delCustom = function (self, key)
	I_AM_CLASS_OR_INSTANCE(self)
	checkType(key, 'string')
	local custom_key = self:isClass() and getCustomKey(self, key) or getCustomIdKey(self, key)
	
	return db:del(custom_key)		
end;

-- check whether exist custom key
existCustom = function (self, key)
	I_AM_CLASS_OR_INSTANCE(self)
	checkType(key, 'string')
	local custom_key = self:isClass() and getCustomKey(self, key) or getCustomIdKey(self, key)
	
	if not db:exists(custom_key) then
		return false
	else 
		return true
	end
end;

updateCustom = function (self, key, val)
	I_AM_CLASS_OR_INSTANCE(self)
	checkType(key, 'string')
	local custom_key = self:isClass() and getCustomKey(self, key) or getCustomIdKey(self, key)

	if not db:exists(custom_key) then print('[Warning] @updateCustom - This custom key does not exist.'); return nil end
	local store_type = db:type(custom_key)
	local store_module = getStoreModule(store_type)
	return store_module.update(custom_key, val)
			 
end;

removeCustomMember = function (self, key, val)
	I_AM_CLASS_OR_INSTANCE(self)
	checkType(key, 'string')
	local custom_key = self:isClass() and getCustomKey(self, key) or getCustomIdKey(self, key)

	if not db:exists(custom_key) then print('[Warning] @removeCustomMember - This custom key does not exist.'); return nil end
	local store_type = db:type(custom_key)
	local store_module = getStoreModule(store_type)
	return store_module.remove(custom_key, val)
	
end;

addCustomMember = function (self, key, val, stype, score)
	I_AM_CLASS_OR_INSTANCE(self)
	checkType(key, 'string')
	local custom_key = self:isClass() and getCustomKey(self, key) or getCustomIdKey(self, key)
	
	if not db:exists(custom_key) then print('[Warning] @addCustomMember - This custom key does not exist.'); end
	local store_type = db:type(custom_key) ~= 'none' and db:type(custom_key) or stype
	local store_module = getStoreModule(store_type)
	return store_module.add(custom_key, val, score)
	
end;

hasCustomMember = function (self, key, mem)
	I_AM_CLASS_OR_INSTANCE(self)
	checkType(key, 'string')
	local custom_key = self:isClass() and getCustomKey(self, key) or getCustomIdKey(self, key)
	
	if not db:exists(custom_key) then print('[Warning] @hasCustomMember - This custom key does not exist.'); return nil end
	local store_type = db:type(custom_key)
	local store_module = getStoreModule(store_type)
	return store_module.has(custom_key, mem)

end;

numCustom = function (self, key)
	I_AM_CLASS_OR_INSTANCE(self)
	checkType(key, 'string')
	local custom_key = self:isClass() and getCustomKey(self, key) or getCustomIdKey(self, key)

	if not db:exists(custom_key) then return 0 end
	local store_type = db:type(custom_key)
	local store_module = getStoreModule(store_type)
	return store_module.num(custom_key)
end;


