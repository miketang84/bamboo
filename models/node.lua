module(..., package.seeall)

local Model = require 'bamboo.model'

local getModelByName = bamboo.getModelByName 

local Node 
Node = Model:extend {
    __tag = 'Bamboo.Model.Node';
	__name = 'Node';
	__desc = 'Node is the basic tree like model';
	__fields = {
		['name'] 	= 	{  newfield=true},						-- 节点的内部名称
		['rank'] 	= 	{  newfield=true},						-- 节点在整个节点树中的级别，为字符串
		['title'] 	= 	{  required=true, newfield=true},						-- 节点标题
		['content'] = 	{  required=true, newfield=true},				-- 节点内容
		['status'] 	= 	{  newfield=true},

		['is_category'] = {  newfield=true},			-- 标明此节点是否是一个类别节点，即是否可接子节点
		['parent'] 		= { st='ONE', foreign='Node', newfield=true},						-- 节点的父页面id，如果为空，则表明本节点为顶级节点
		['children'] 	= { st='MANY', foreign='Node', newfield=true},					-- 此节点的子节点id列表字符串，受is_category控制
		['groups'] 		= { st='MANY', foreign='Node', newfield=true},						-- 此节点可以所属的组，近似就是它们所说的tag

		['comments'] 	= { st='MANY', foreign='Message', newfield=true},					-- 对此节点的评论id列表字符串
		['attachments'] = { st='MANY', foreign='Upload', newfield=true},				-- 附着在此节点上的文件

		['created_date'] 	= {  newfield=true},				-- 本节点创建的日期
		['lastmodified_date'] 	= {  newfield=true},		-- 最后一次修改的日期
		['creator'] 		= { st='ONE', foreign='User', newfield=true},					-- 本节点的创建者
		['owner'] 			= { st='ONE', foreign='User', newfield=true},					-- 本节点的拥有者
		['lastmodifier'] 	= { st='ONE', foreign='User', newfield=true},				-- 最后一次本节点的修改者
	
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
				
		-- 对于这种是一个外链列表的情况，传入的值应该规定是一个list
		self.comments = t.comments
		self.attachments = t.attachments

		self.created_date = os.time()
		self.lastmodified_date = self.created_date
		self.creator = t.creator
		self.owner = t.owner
		self.lastmodifier = t.lastmodifier
		
		return self
	end;
	
	-- 实例函数。返回comments对象列表
	getComments = function (self)
		return self:getForeign ('comments')
	end;
	
	getPartialComments = function (self, start, stop)
		return self:getForeign ('comments', start, stop)
	end;
	
	-- 实例函数。返回attachments对象列表
	getAttachments = function (self)
		return self:getForeign ('attachments')
	end;
	
	-- 实例函数。返回孩子对象列表
	getChildren = function (self)
		if isFalse(self.children) then return {} end
		return self:getForeign ('children')
	end;
	
	-- 实例函数。返回父对象
	getParent = function (self)
		if self.parent == '' then return nil end
		return self:getForeign('parent')
	end;

}

return Node




