module(..., package.seeall)

local Upload = require 'bamboo.models.upload'

local Image = Upload:extend {
	__tag = 'Bamboo.Model.Upload.Image';
	__name = 'Image';
	__desc = 'Generitic Image definition';
	__fields = {
		['width'] = {},
		['height'] = {},
		
		['name'] = {},				-- 此文件的名字
		['path'] = {},			-- 此文件的可访问URI
		['size'] = {},				-- 此文件大小，以字节计算
		['timestamp'] = {}, 			-- 上传成功的时间戳
		['desc'] = {},			-- 此文件的描述
	
	};
	
	init = function (self, t)
		if not t then return self end
		
		self.width = t.width
		self.height = t.height
		
		return self
	end;

}

return Image
