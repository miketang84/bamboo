module(..., package.seeall)

local Model = require 'bamboo.model'

local getModelByName = bamboo.getModelByName 

local Node 
Node = Model:extend {
    __tag = 'Bamboo.Model.Node';
	__name = 'Node';
	__desc = 'Node is the basic tree like model';
	__fields = {
		['name'] 	= 	{  newfield=true},
		['rank'] 	= 	{  newfield=true},
		['title'] 	= 	{  required=true, newfield=true},
		['content'] = 	{  required=true, newfield=true},
		['status'] 	= 	{  newfield=true},

		['is_category'] = {  newfield=true},
		['parent'] 		= { st='ONE', foreign='Node', newfield=true, order=1.1},
		['children'] 	= { st='MANY', foreign='Node', newfield=true},
		['groups'] 		= { st='MANY', foreign='Node', newfield=true},

		['comments'] 	= { st='MANY', foreign='Message', newfield=true},
		['attachments'] = { st='MANY', foreign='Upload', newfield=true},

		['created_date'] 	= {  newfield=true},
		['lastmodified_date'] 	= {  newfield=true},
		['creator'] 		= { st='ONE', foreign='User', newfield=true},
		['owner'] 			= { st='ONE', foreign='User', newfield=true},
		['lastmodifier'] 	= { st='ONE', foreign='User', newfield=true},
	
	};
	
	init = function (self, t)
		if not t then return self end
		
		self.name = t.name or self.name
		self.rank = t.rank
		self.title = t.title
		self.content = t.content

		self.is_category = t.is_category
		self.parent = t.parent
		self.children = t.children
		self.groups = t.groups
				
		self.comments = t.comments
		self.attachments = t.attachments

		self.created_date = os.time()
		self.lastmodified_date = self.created_date
		
		return self
	end;
	

	getComments = function (self)
		return self:getForeign ('comments')
	end;
	
	getPartialComments = function (self, start, stop)
		return self:getForeign ('comments', start, stop)
	end;
	

	getAttachments = function (self)
		return self:getForeign ('attachments')
	end;
	

	getChildren = function (self)
		if isFalse(self.children) then return {} end
		return self:getForeign ('children')
	end;
	

	getParent = function (self)
		if self.parent == '' then return nil end
		return self:getForeign('parent')
	end;

}

return Node




