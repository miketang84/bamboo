module(..., package.seeall)


local Model = require 'bamboo.model'

local Message = Model:extend {
    __tag = 'Object.Model.Message';
	__name = 'Message';
	__desc = 'General message definition.';
	__fields = {
		['from'] = { foreign='User', required=true },
		['to'] = { foreign='User' },
		['subject'] = { foreign='UNFIXED', st='ONE' },
		['type'] = {},
		-- ['uuid'] = {},
		['author'] = {},
		['content'] = {},
		['timestamp'] = {}
	};
    
	
	init = function (self, t)
		if not t then return self end
		
		self.type = t.type
		-- self.uuid = t.uuid
		self.author = t.author
		self.content = t.content
		self.timestamp = t.timestamp or os.time()
		
		return self
	end;
		
}

return Message
