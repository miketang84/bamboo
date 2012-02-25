module(..., package.seeall)

local Model = require 'bamboo.model'

local Mymodel = Model:extend {
	__tag = 'Bamboo.Model.Mymodel';
	__name = 'Mymodel';
	__desc = 'Generitic Mymodel definition';
	__indexfd = 'name',
	__fields = {
		['name'] = {},	
	
	};
	
	init = function (self, t)
		if isFalse(t) then return self end
		
		-- auto fill non-foreign fields with params t
		local fields = self.__fields
		for k, v in pairs(t) do
			if fields[k] and not fields[k].foreign then
				self[k] = tostring(v)
			end
		end
		
		return self
	end;
	


}

return Mymodel


