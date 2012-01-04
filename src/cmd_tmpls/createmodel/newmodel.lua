module(..., package.seeall)

local Model = require 'bamboo.model'

local $MODEL = Model:extend {
	__tag = 'Bamboo.Model.$MODEL';
	__name = '$MODEL';
	__desc = 'Generitic $MODEL definition';
	__indexfd = 'name',
	__fields = {
		['name'] = {},	
	
	};
	
	init = function (self, t)
		if not t then return self end
		
		self.name = t.name
		
		return self
	end;
	
	-- default methods
	newView = function (web, req)

	end;
	
	createInstance = function (web, req)

	end;
	
	editView = function (web, req)

	end;
	
	updateInstance = function (web, req)

	end;
	
	delView = function (web, req)

	end;
	
	delInstance = function (web, req)

	end;
	
	getInstance = function (web, req)

	end;
	
	getInstances = function (web, req)

	end;

}

return $MODEL


