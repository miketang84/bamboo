module(..., package.seeall)

local http = require 'lglib.http'
local Node = require 'bamboo.node'

-- 记录当前最新的项
local ptr = 0

function makeMenuRecur (gmenus, menutable, rank, parent)
    
    for i, v in ipairs(menutable) do
        ptr = ptr + 1
        
        local item = { name = v.name, title = v.title, content = v.content, parent = parent, rank = rank }
        table.insert(gmenus, item)
        if parent ~= 0 then
            if not gmenus[parent]['children'] then gmenus[parent]['children'] = {} end
            table.insert(gmenus[parent]['children'], ptr)
        end

        if v.submenus then
            makeMenuRecur (gmenus, v.submenus, rank + 1, ptr)
        end
    end
    
    return gmenus
end

local Menu 
Menu = Node:extend {
    __tag = 'Bamboo.Model.Node.Menu';
	__name = 'Menu';
	__desc = 'Menu';
	__fields = {
		['name'] = {},						-- 菜单节点的内部名称
		['rank'] = {},						-- 菜单节点在整个菜单树中的级别，为数字
		['title'] = {},						-- 菜单节点标题
		['prompt'] = {},						-- 菜单节点提示（当鼠标放上去的时候，非必须）
		['content'] = {},				-- 菜单所链到的页面对象ID，或直接是URL地址，一个菜单节点只能链到一个页面ID上去

		['parent'] = {},						-- 菜单节点的父菜单节点id，如果为空，则表明本节点为顶级节点
		['children'] = {},					-- 此菜单节点的子菜单节点id列表字符串，默认每个菜单节点下面都可以接子节点
		
		['created_date'] 	= {},				-- 本节点创建的日期
		['lastmodified_date'] 	= {},		-- 最后一次修改的日期
		['creator'] 		= {},					-- 本节点的创建者
		['owner'] 			= {},					-- 本节点的拥有者
		['lastmodifier'] 	= {},				-- 最后一次本节点的修改者
				
	};
	
	init = function (self, t)
		if not t then return self end
		
		self.name = t.name or self.name
		-- 为表示层级的数字，从1开始
		self.rank = t.rank
		
		-- 在init函数中，不对children填充内容，因为在创建自身的时候，还不知道孩子在哪里
		-- 如果有children，则它是一个list
		if t.children then
			self.children = table.concat(t.children, ' ')
		end
		
		return self
	end;
	
	makeMenu  = function (self, menutable)
		local gmenus = {}
		ptr = 0
		-- 从第一层开始，第三个参数0，表示默认的根为0
		gmenus = makeMenuRecur (gmenus, menutable, 1, 0)
		-- 清除menu记录
		self:clearCounter()
		local menuobjs = {}
		for i, v in ipairs(gmenus) do
			local objitem = self(v)
			if not isEmpty(objitem) then
				table.insert(menuobjs, objitem)
			end
			-- 将以前的重复记录删掉
			self:delById (objitem.id)
			-- 保存到数据库
			objitem:save()
		end
		
		return menuobjs
	end;
	
	generateMenuView = function (menuobjs)
		local menu_htmls = '<ul class="menu">'
		
		if #menuobjs > 0 then
			menu_htmls = menu_htmls + ([[<li><a href="%s">%s</a>]]):format(menuobjs[1].content, menuobjs[1].title)
		end
		i = 2
		while i <= #menuobjs do
			if menuobjs[i].rank == menuobjs[i-1].rank then
				menu_htmls = menu_htmls + ([[</li><li><a href="%s">%s</a>]]):format(menuobjs[i].content, menuobjs[i].title)
			elseif menuobjs[i].rank > menuobjs[i-1].rank then
				menu_htmls = menu_htmls + ([[<ul><li><a href="%s">%s</a>]]):format(menuobjs[i].content, menuobjs[i].title)
			elseif menuobjs[i].rank < menuobjs[i-1].rank then
				menu_htmls = menu_htmls + '</li>'
				delta = menuobjs[i-1].rank - menuobjs[i].rank
				for n = 1, delta do
					menu_htmls = menu_htmls + '</ul></li>'
				end
				menu_htmls = menu_htmls + ([[<li><a href="%s">%s</a>]]):format(menuobjs[i].content, menuobjs[i].title)
				
			end
			
			i = i + 1
		end
		
		if menu_htmls then menu_htmls = menu_htmls + '</li>' end
		menu_htmls = menu_htmls + '</ul>'
		
		return menu_htmls
	end;
		
	
}

return Menu




