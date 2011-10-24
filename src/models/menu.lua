module(..., package.seeall)

local http = require 'lglib.http'
local Node = require 'bamboo.models.node'

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
		['name'] = {},
		['rank'] = {},
		['title'] = {},
		['prompt'] = { newfield=true },
		['content'] = {},

		['parent'] = {},
		['children'] = {},
		
		['created_date'] 	= {},
		['lastmodified_date'] 	= {},
		['creator'] 		= {},
		['owner'] 			= {},
		['lastmodifier'] 	= {},
				
	};
	
	init = function (self, t)
		if not t then return self end
		
		self.name = t.name or self.name
		self.rank = t.rank
		
		if t.children then
			self.children = table.concat(t.children, ' ')
		end
		
		return self
	end;
	
	makeMenu  = function (self, menutable)
		local gmenus = {}
		ptr = 0
		gmenus = makeMenuRecur (gmenus, menutable, 1, 0)
		self:clearAll ()
		local menuobjs = {}
		for i, v in ipairs(gmenus) do
			local objitem = self(v)
			if not isEmpty(objitem) then
				table.insert(menuobjs, objitem)
			end
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




