module(..., package.seeall)

local User = require 'bamboo.models.user'

local cache_callbacks = require 'cachecall.callbacks'

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
	__decorators = {
		save = function(osave)
            return function(self, ...)
                self = osave(self, ...)
				if not self then return nil end
				
				self = cache_callbacks.onSave(self)
				
                return self
            end
        end;    
	
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




