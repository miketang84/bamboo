
if bamboo.config.fulltext_index_support then require 'mmseg' end
local db = BAMBOO_DB

local ft_words_manager = '_fulltext_words:%s:%s'	-- prefix:model:field		word set
local ft_rft_pattern = '_RFT:%s:%s:%s'		-- prefix:model:id:field	word set
local ft_ft_pattern = '_FT:%s:%s:%s'			-- prefix:model:field:word  	id set

local clearFtIndexesOnDeletion = function (instance)
	local model_key = format('%s:%s', instance.__name, instance.id)

	local ftindex_fields = instance['__fulltext_index_fields']
	if isFalse(ftindex_fields) then return false end

	local words
	for _, field in ipairs(ftindex_fields) do
		words = db:smembers(format(ft_rft_pattern, instance.__name, instance.id, field))
		db:pipeline(function (p)
			for _, word in ipairs(words) do
				p:srem(format(ft_ft_pattern, instance.__name, field, word), instance.id)
			end
		end)
		db:del(format(ft_rft_pattern, instance.__name, instance.id, field))
	end
end
bamboo.internals.clearFtIndexesOnDeletion = clearFtIndexesOnDeletion

-- Full Text Search utilities
-- @param instance the object to be full text indexes
local makeFulltextIndexes = function (instance)

	local ftindex_fields = instance['__fulltext_index_fields']
	if isFalse(ftindex_fields) then return false end

	local words
	for _, v in ipairs(ftindex_fields) do
		-- parse the fulltext field value
		words = mmseg.segment(instance[v])
		for _, word in ipairs(words) do
			-- only index word length larger than 1
			if string.utf8len(word) >= 2 then
				-- add this word to global word set
				db:sadd(format(ft_words_manager, instance.__name, v), word)
				-- add reverse fulltext index such as '_RFT:model:id', type is set, item is 'word'
				db:sadd(format(ft_rft_pattern, instance.__name, instance.id, v), word)
				-- add fulltext index such as '_FT:model:word', type is set, item is 'id'
				db:sadd(format(ft_ft_pattern, instance.__name, v, word), instance.id)
			end
		end
	end

	return true
end
bamboo.internals.makeFulltextIndexes = makeFulltextIndexes

local wordSegmentOnFieldFtIndex = function (self, field, ask_str)
	local search_tags = mmseg.segment(ask_str)
	
	local fdt = self:getFDT(field)
	if not fdt.fulltext_index then
		return List()
	end

	local tags = List()
	for _, tag in ipairs(search_tags) do
		if string.utf8len(tag) >= 2 and db:sismember(format(ft_words_manager, self.__name, field), tag) then
			tags:append(tag)
		end
	end
	return tags
end



local wordSegmentOnFtIndex = function (self, ask_str)
	local search_tags = mmseg.segment(ask_str)
	
	local ftindex_fields = self['__fulltext_index_fields']
	if isFalse(ftindex_fields) then return {} end
	
	local tags = {}
	for _, field in ipairs(ftindex_fields) do
		tags[field] = List()
	end

	for _, tag in ipairs(search_tags) do
		for _, field in ipairs(ftindex_fields) do
			if string.utf8len(tag) >= 2 and db:sismember(format(ft_words_manager, self.__name, field), tag) then
				tags[field]:append(tag)
			end
		end
	end
	return tags
end


-- here, tags is the field specified tags
local searchOnFieldFulltextIndexes = function (self, field, tags, n, onlyids)
	if not tags or #tags == 0 then return QuerySet() end

	local rlist = List()
	local _tmp_key = "__tmp_ftkey"
	if #tags == 1 then
		db:sinterstore(_tmp_key, format(ft_ft_pattern, self.__name, field, tags[1]))
	else
		local _args = {}
		for _, tag in ipairs(tags) do
			table.insert(_args, format(ft_ft_pattern, self.__name, field, tag))
		end
		-- XXX, some afraid
		db:sinterstore(_tmp_key, unpack(_args))
	end

	local ids = {}
	if n and type(n) == 'number' and n > 0 then
		ids = db:sort(_tmp_key, 'LIMIT', 0, n, 'DESC', 'ALPHA')
	else
		ids = db:sort(_tmp_key, 'DESC', 'ALPHA')
	end

	if onlyids == 'onlyids' then
		return QuerySet(ids)
	else
		local getFromRedisPipeline = bamboo.internals.getFromRedisPipeline
		-- return objects
		return getFromRedisPipeline(self, ids)
	end
end

-- here, tags is the field specified tags
local searchOnFieldFulltextIndexesByOr = function (self, field, tags, n, onlyids)
	local tag_dict = {}
	for _, tag in ipairs(tags) do
		tag_dict[tag] = searchOnFieldFulltextIndexes(self, field, {tag}, nil, 'onlyids')
	end

	local id_set = Set()
	for tag, ids in pairs(tag_dict) do
		id_set = id_set:union(Set(ids))
	end
	
	local results
	if onlyids == 'onlyids' then
		results = QuerySet(id_set:members():slice(1, n))
	else
		local getFromRedisPipeline = bamboo.internals.getFromRedisPipeline
		results = getFromRedisPipeline(self, id_set:members():slice(1, n))
	end
	
	return results, tag_dict
end

-- here, tags is the whole tags dict
local searchOnFulltextIndexes = function (self, tags, n, is_or, standalone, onlyids)
	
	local ftindex_fields = self['__fulltext_index_fields']
	if isFalse(ftindex_fields) then return QuerySet() end
	
	local field_dict = {}
	if is_or ~= 'or' then
		for _, field in ipairs(ftindex_fields) do
			field_dict[field] = searchOnFieldFulltextIndexes(self, field, tags[field], nil, 'onlyids')
		end
	else
		for _, field in ipairs(ftindex_fields) do
			field_dict[field] = searchOnFieldFulltextIndexesByOr(self, field, tags[field], nil, 'onlyids')
		end
	end
	
	if onlyids == 'onlyids' then
		if standalone == 'standalone' then
			return field_dict
		else
			local id_set = Set()
			for k, ids in pairs(field_dict) do
				id_set = id_set:union(Set(ids))
			end
			return id_set:members():slice(1, n)
		end
	end
	
	local results
	local getFromRedisPipeline = bamboo.internals.getFromRedisPipeline
	if standalone == 'standalone' then
		for k, ids in pairs(field_dict) do
			results[k] = getFromRedisPipeline(self, ids)
		end
	else
		local id_set = Set()
		for k, ids in pairs(field_dict) do
			id_set = id_set:union(Set(ids))
		end
		results = getFromRedisPipeline(self, id_set:members():slice(1, n))
	end
	
	return results, id_dict
	
--[[
	if #tags == 0 then return List() end

	local rlist = List()
	local _tmp_key = "__tmp_ftkey"
	if #tags == 1 then
		db:sinterstore(_tmp_key, format(ft_ft_pattern, self.__name, tags[1]))
	else
		local _args = {}
		for _, tag in ipairs(tags) do
			table.insert(_args, format(ft_ft_pattern, self.__name, tag))
		end
		-- XXX, some afraid
		db:sinterstore(_tmp_key, unpack(_args))
	end

	local ids
	if n and type(n) == 'number' and n > 0 then
		ids = db:sort(_tmp_key, 'LIMIT', 0, n, 'DESC', 'ALPHA')
	else
		ids = db:sort(_tmp_key, 'DESC', 'ALPHA')
	end

	-- return objects
	return getFromRedisPipeline(self, ids)
--]]

end



local ft_longwords_manager = '_fulltext_longwords:%s'   -- _fulltext_longwords:model
local ft_longword_pattern = '_FT_LONGWORD:%s:%s'	-- _FT_LONGWORD:model:lword_part

-- self is model name
local function makeLongWordIndexes (self, longwords)
	local words
	for _, longword in ipairs(longwords) do
		words = mmseg.segment(longword)
		for _, word in ipairs(words) do
			db:sadd(format(ft_longwords_manager, self.__name), word)
			db:sadd(format(ft_longword_pattern, self.__name, word), longword)
		end
	end
	
	return self
end

local function didLongWordIndexed (self)
	local ret = #db:smembers(format(ft_longwords_manager, self.__name))
	
	return ret > 0
end


local function searchOnLongWords (self, sentence)
	local longwords_chosen = List()
	local i, p, e = 1, 1, 1

	local dataset = Set()
	local old_dataset = Set()
	while i <= sentence:utf8len() do
		-- i = i + 1
		p = i
		while true  do
			local word = sentence:utf8index(i)
			if word then
				i = i + 1
				local is_this_in = db:sismember(format(ft_longwords_manager, self.__name), word)
				if is_this_in then
					local thisset = db:smembers(format(ft_longword_pattern, self.__name, word))
					--db:interstore('__tmp_longkey', format(ft_longword_pattern, self.__name, word))
					old_dataset = Set(table.copy(dataset))
					if dataset:size() > 0 then
						dataset = dataset * Set(thisset)
					else
						dataset = Set(thisset)
					end
					
					if dataset:size() == 0 then
						dataset = old_dataset
						e = i - 2
						break
					end
					

				else
					e = i - 2
					break
				end
		
			else
				e = i - 1
				break
			end
		end	
		local words_length = e - p + 1
		if words_length > 0 then
			if dataset:size() == 1 then
				local longword = dataset:members()[1]
				local thisword = sentence:utf8slice(p, e)
				if thisword == longword then
					longwords_chosen:append(longword)
				end
			else
				local longwords = dataset:members()
				local thisword = sentence:utf8slice(p, e)
				for _, v in ipairs(longwords) do
					if thisword == v then
						longwords_chosen:append(thisword)
						break
					end
				end
			end
			dataset = Set()
		end
		
	end
	
	return chosen
end


return function (...)
	
	if bamboo.config.fulltext_index_support then 
		require 'mmseg'
		return {

			makeFulltextIndexes = function (self)
				I_AM_CLASS(self)
				self:all():each(function (instance) makeFulltextIndexes(instance) end)
				return true
			end;
			
			-- for fulltext index API
			fulltextSearch = function (self, ask_str, n)
				I_AM_CLASS(self)
				local tags = wordSegmentOnFtIndex(self, ask_str)
				return searchOnFulltextIndexes(self, tags, n)
			end;

			-- for fulltext index API
			fulltextSearchByOr = function (self, ask_str, n)
				I_AM_CLASS(self)
				local tags = wordSegmentOnFtIndex(self, ask_str)
				return searchOnFulltextIndexes(self, tags, n, 'or')
			end;

			-- for fulltext index API
			fulltextSearchByFieldByOr = function (self, field, ask_str, n)
				I_AM_CLASS(self)
				local tags = wordSegmentOnFieldFtIndex(self, field, ask_str)
				return searchOnFieldFulltextIndexesByOr(self, field, tags, n)
			end;

			-- for fulltext index API
			fulltextSearchByField = function (self, field, ask_str, n)
				I_AM_CLASS(self)
				local tags = wordSegmentOnFieldFtIndex(self, field, ask_str)
				return searchOnFieldFulltextIndexes(self, field, tags, n)
			end;

			-- for fulltext index API
			fulltextSearchByWord = function (self, word, n)
				I_AM_CLASS(self)
				local ftindex_fields = self['__fulltext_index_fields']
				if isFalse(ftindex_fields) then return QuerySet() end
			
				local tags = {}
				for _, field in ipairs(ftindex_fields) do
					tags[field] = {word}
				end
				return searchOnFulltextIndexes(self, tags, n)
			end;

			-- for fulltext index API
			fulltextSearchByFieldByWord = function (self, field, word, n)
				I_AM_CLASS(self)
				return searchOnFieldFulltextIndexes(self, field, {word}, n)
			end;

			---------------------------------------------------------------------
			-- long word APIs
			makeLongWordIndexes = makeLongWordIndexes;
			searchOnLongWords = searchOnLongWords;
			didLongWordIndexed = didLongWordIndexed;
		}
	else
		return {}
	end
	
end

