module(..., package.seeall)

local Upload = require 'bamboo.models.upload'
local Session = require 'bamboo.session'

local Image = Upload:extend {
	__name = 'Image';
	__primarykey = 'path';
	__fields = {
		['width'] = {},
		['height'] = {},
		
		['name'] = {},
		['path'] = {widget_type="image"},
		['size'] = {},
		['timestamp'] = {},
		['desc'] = {},
	
	};
	
	init = function (self, t)
		if not t then return self end
		
		self.width = t.width
		self.height = t.height
				
		return self
	end;

}

return Image
