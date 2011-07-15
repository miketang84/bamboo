module(..., package.seeall)

local Upload = require 'bamboo.models.upload'

local Image = Upload:extend {
	__tag = 'Bamboo.Model.Upload.Image';
	__name = 'Image';
	__desc = 'Generitic Image definition';
	__fields = {
		['width'] = {},
		['height'] = {},
		
		['name'] = {},
		['path'] = {},
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




