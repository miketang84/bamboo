

-- can be called by instance and class
local isUsingFulltextIndex = function (self)
	local model = self
	if isInstance(self) then model = getModelByName(self:classname()) end
	if bamboo.config.fulltext_index_support and rawget(model, '__use_fulltext_index') then
		return true
	else
		return false
	end
end


--------------------------------------------------------------------------------
if bamboo.config.fulltext_index_support then require 'mmseg' end
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
				db:sadd(format('_fulltext_words:%s', instance.__name), word)
				-- add reverse fulltext index such as '_RFT:model:id', type is set, item is 'word'
				db:sadd(format('_RFT:%s', getNameIdPattern(instance)), word)
				-- add fulltext index such as '_FT:word', type is set, item is 'model:id'
				db:sadd(format('_FT:%s:%s', instance.__name, word), instance.id)
			end
		end
	end
	
	return true	
end

local wordSegmentOnFtIndex = function (self, ask_str)
	local search_tags = mmseg.segment(ask_str)
	local tags = List()
	for _, tag in ipairs(search_tags) do
		if string.utf8len(tag) >= 2 and db:sismember(format('_fulltext_words:%s', self.__name), tag) then
			tags:append(tag)
		end
	end
	return tags
end


local searchOnFulltextIndexes = function (self, tags, n)
	if #tags == 0 then return List() end
	
	local rlist = List()
	local _tmp_key = "__tmp_ftkey"
	if #tags == 1 then
		db:sinterstore(_tmp_key, format('_FT:%s:%s', self.__name, tags[1]))
	else
		local _args = {}
		for _, tag in ipairs(tags) do
			table.insert(_args, format('_FT:%s:%s', self.__name, tag))
		end
		-- XXX, some afraid
		db:sinterstore(_tmp_key, unpack(_args))
	end
	
	local limits
	if n and type(n) == 'number' and n > 0 then
		limits = {0, n}
	else
		limits = nil
	end
	-- sort and retrieve
	local ids =  db:sort(_tmp_key, {limit=limits, sort="desc"})
	-- return objects
	return getFromRedisPipeline(self, ids)
end
















	
	-- for fulltext index API
	fulltextSearch = function (self, ask_str, n)
		I_AM_CLASS(self)
		local tags = wordSegmentOnFtIndex(self, ask_str)
		return searchOnFulltextIndexes(self, tags, n)
	end;

	-- for fulltext index API
	fulltextSearchByWord = function (self, word, n)
		I_AM_CLASS(self)
		return searchOnFulltextIndexes(self, {word}, n)
	end;
