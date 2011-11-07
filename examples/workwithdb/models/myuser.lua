module(..., package.seeall)

local User = require 'bamboo.models.user'

local MYUser = User:extend {
	__tag = 'Bamboo.Model.User.MYUser';
	__name = 'MYUser';
	__desc = 'Generitic MYUser definition';
	__indexfd = 'name';
	__fields = {
		['name'] = {},
		['age'] = {},
		['gender'] = {},

	};
	
	init = function (self, t)
		if not t then return self end
		
		self.name = t.name
		self.age = t.age
		self.gender = t.gender
		
		return self
	end;

}

return MYUser




