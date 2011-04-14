module(..., package.seeall)

local Model = require 'bamboo.model'

local getModelByName = bamboo.getModelByName 

local Node 
Node = Model:extend {
    __tag = 'Bamboo.Model.Node';
	__name = 'Node';
	__desc = 'Node is the basic tree like model';
	__fields = {
		{ 'name', 'text', false },						-- 节点的内部名称
		{ 'rank', 'text', true },						-- 节点在整个节点树中的级别，为字符串
		{ 'title', 'text', true },						-- 节点标题
		{ 'content', 'textarea', true },				-- 节点内容

		{ 'is_category', 'checkbox', true },			-- 标明此节点是否是一个类别节点，即是否可接子节点
		{ 'parent', 'text', true },						-- 节点的父页面id，如果为空，则表明本节点为顶级节点
		{ 'children', 'text', true },					-- 此节点的子节点id列表字符串，受is_category控制
		{ 'groups',	'text', true }						-- 此节点可以所属的组，近似就是它们所说的tag

		{ 'comments', 'text', true },					-- 对此节点的评论id列表字符串
		{ 'attachments', 'text', true },				-- 附着在此节点上的文件

		{ 'created_date', 'date', false },				-- 本节点创建的日期
		{ 'lastmodified_date', 'date', false },		-- 最后一次修改的日期
		{ 'creator', 'text', false },					-- 本节点的创建者
		{ 'owner', 'text', false },					-- 本节点的拥有者
		{ 'lastmodifier', 'text', false },				-- 最后一次本节点的修改者
	
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
		local Message = require 'legecms.models.message'
		return self:extractField(self.comments, Message)
	end;
	
	getPartialComments = function (self, start, ended)
		local Message = require 'legecms.models.message'
		return self:extractFieldSlice (self.comments, Message, start, ended)
	end;
	
	-- 实例函数。返回attachments对象列表
	getAttachments = function (self)
		local Upload = require 'bamboo.upload'
		return self:extractField(self.attachments, Upload)
	end;
	
	-- 实例函数。返回孩子对象列表
	getChildren = function (self)
		if isFalse(self.children) then return {} end
		local model = getModelByName(self.__name)
		return self:extractField(self.children, model)
	end;
	
	-- 实例函数。返回父对象
	getParent = function (self)
		if self.parent == '' then return nil end
		local model = getModelByName(self.__name)
		return model:getById(self.parent)
	end;

}

return Node




