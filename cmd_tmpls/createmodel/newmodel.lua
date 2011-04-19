module(..., package.seeall)

local Model = require 'bamboo.model'

local $MODEL = Model:extend {
	__tag = 'Bamboo.Model.$MODEL';
	__name = '$MODEL';
	__desc = 'Generitic $MODEL definition';
	__fields = {
		['name'] = {},	
	
	};
	
	init = function (self, t)
		if not t then return self end
		self.name = t.name or self.name
		
		return self
	end;

}

return $MODEL




