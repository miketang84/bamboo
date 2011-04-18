module(..., package.seeall)


local Model = require 'bamboo.model'

local Message 
Message = Model:extend {
    __tag = 'Bamboo.Model.Message';
	__name = 'Message';
	__desc = 'General message definition.';
	__fields = {
		-- { 字段名称, 视图, 是否允许修改 }
		['from'] = {},				-- 消息的发送方，为用户id
		['to'] = {},				-- 消息的接收方，为用户id，可以不止一个，多个之间用空格分开
		['subject'] = { foreign='UNFIXED' st='ONE' },			-- 消息的主题，里面的内容是：Page:1, Upload:3, Message: 4等
		['type'] = {},				-- 消息的类型
		['uuid'] = {},				-- 消息的唯一标识符
		['author'] = {},			-- 消息的发送方的显示名称
		['content'] = {},			-- 消息的内容
		['timestamp'] = {}			-- 消息的时间戳
	};
    
	
	init = function (self, t)
		if not t then return self end
		
		self.name = os.time()
		self.from = t.from
		self.to = t.to
		self.subject = t.subject
		self.type = t.type
		self.uuid = t.uuid
		self.author = t.author
		self.content = t.content
		self.timestamp = t.timestamp
		
		return self
	end;
	

	
}

return Message
