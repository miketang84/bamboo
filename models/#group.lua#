module(..., package.seeall)

local Model = require 'bamboo.model'

local Group 
Group = Model:extend {
    __tag = 'Bamboo.Model.Group';
	__name = 'Group';
	__desc = 'Group is the basic tree like model';
	__indexfd = "name";
	__fields = {
		['name'] 	= 	{ newfield=true },
		['desc'] 	= 	{ newfield=true },
		['created_date'] = { newfield=true },
		
		['perms'] 	= 	{ foreign="Permissions", st="MANY", newfield=true },
		['owner'] 	= 	{ foreign="User", st="ONE", newfield=true },
		['managers'] 	= 	{ foreign="User", st="MANY", newfield=true },
	};
	
	init = function (self, t)
		if not t then return self end
		
		self.name = t.name
		self.desc = self.desc
		self.created_date = os.time()
		
		
		return self
	end;
	
}

return Group


