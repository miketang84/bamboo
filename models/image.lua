module(..., package.seeall)

local Upload = require 'bamboo.models.upload'
local Session = require 'bamboo.session'

local Image = Upload:extend {
	__tag = 'Bamboo.Model.Upload.Image';
	__name = 'Image';
	__desc = 'Generitic Image definition';
	__keyfd = 'path';
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
				
		self.path = t.path or Session:getKey('_upload_file_') or 'media/uploads/default.png'
		Session:delKey('_upload_file_')

		self.size = posix.stat(self.path).size

		return self
	end;

}

return Image
