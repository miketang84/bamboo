module(..., package.seeall)

local Model = require 'bamboo.model'

local Permission 
Permission = Model:extend {
    __tag = 'Bamboo.Model.Permission';
	__name = 'Permission';
	__desc = 'Permission is the basic tree like model';
	__indexfd = 'name';
	__fields = {
		['name'] 	= 	{newfield=true},
		['desc'] 	= 	{newfield=true},
	};
	
	init = function (self, t)
		if not t then return self end
		
		self.name = t.name
		self.desc = t.desc
		
		return self
	end;

	add = function (self, name, desc)
		I_AM_CLASS(self)
		checkType(name, 'string')
		local desc = desc or ''
		
		local perm = Permission:getByIndex(name)
		if not perm then
			local new_perm = Permission {
				name = name,
				desc = desc
			}
			new_perm:save()
		elseif perm.desc ~= desc then
			perm:update('desc', desc)
		end
		
	end;

	
}

return Permission


