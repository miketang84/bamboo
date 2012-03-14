module(..., package.seeall)
local socket = require 'socket'
local Model = require 'bamboo.model'

local Group 
Group = Model:extend {
    __tag = 'Bamboo.Model.Group';
	__name = 'Group';
	__desc = 'Group is the basic tree like model';
	__indexfd = "name";
	__fields = {
		['name'] 	= 	{},
		['desc'] 	= 	{},
		['created_date'] = {},
		
		['perms'] 	= 	{ foreign="Permission", st="MANY" },
		['owner'] 	= 	{ foreign="User", st="ONE" },
		['managers'] 	= 	{ foreign="User", st="MANY" },
	};
	
	init = function (self, t)
		if not t then return self end
		
		self.name = t.name
		self.desc = self.desc
		self.created_date = socket.gettime()
		
		
		return self
	end;
	
}

return Group


