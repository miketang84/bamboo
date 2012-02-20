module(..., package.seeall)

function onSave(self)
	-- here, we need to add new instance's id to cache
	DEBUG('ready to add new member to cache.')
	self:addToCacheAndSortBy('aa_persons_list', 'name')
	
	return self
end
