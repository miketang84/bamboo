module(..., package.seeall)

Prototype = Object:extend {
	-- widget_class = {},
	-- widget_attr = {},
	template = {
		label = [[<label for="$id">$caption</label>]],
		widget = '',
		help = [[<span class="help-inline">$help</span>]],
	},	
	template_uneditable = {
		label = [[<label>$caption:</label>]],
		widget = [[<span class="$class" $attr>$value</span>]],
		help = [[<span class="help-inline">$help</span>]],
	},
	init = function(self, t)
			   print('Prototype init')
			   -- for k, v in pairs(t) do
			   -- 	   self[k] = v
			   -- end
			   return self
		   end,
	toHtml = function(self, inst, field, format)
				 -- if self.editable == false then
				 -- 	 return ((self.template_uneditable.label or '') .. (self.template_uneditable.widget or '') .. (self.template_uneditable.help or ''))
				 -- else
				 -- print(field)
				 -- fptable(self)
				 -- print(self:toWidget(inst, field))
				 return (format or "$label$widget$help")
				 :gsub('$widget', self:toWidget(inst, field))
				 :gsub('$label', self:toLabel(inst, field))
				 :gsub('$help', self:toHelp(inst, field))
				 -- end
			 end,
	toLabel = function(self, inst, field)
				  if self.editable == false then
					  return self:strGSub((self.template_uneditable.label or ''), inst, field)
				  else
					  return self:strGSub((self.template.label or ''), inst, field)
				  end
			  end,
	toWidget = function(self, inst, field)
				   self.widget_class = self.widget_class or {}
				   self.widget_attr = self.widget_attr or {}
				   local str_class = ''
				   for _, c in ipairs(self.widget_class) do
					   str_class = str_class .. ' ' .. c
				   end
				   local str_attr = ''
				   for k, v in pairs(self.widget_attr) do
					   str_attr = str_attr .. ' ' .. k .. '="' .. tostring(v) ..'"'
				   end
				   if self.editable == false then
					   return self:strGSub((self.template_uneditable.widget or '')
										   :gsub('$class', str_class)
										   :gsub('$attr', str_attr)
										   , inst, field)
				   else
					   return self:strGSub((self.template.widget or '')
										   :gsub('$class', str_class)
										   :gsub('$attr', str_attr)
										   , inst, field)
				   end
			   end,
	toHelp = function(self, inst, field)
				 if self.editable == false then
					 return self:strGSub((self.template_uneditable.help or ''), inst, field)
				 else
					 return self:strGSub((self.template.help or ''), inst, field)
				 end
			  end,
	strGSub = function(self, string, inst, field)
				  -- print(field)
				  local ret = string
				  :gsub('$value', inst[field] or '')
				  :gsub('$caption', self.caption or field)
				  :gsub('$field', field)
				  :gsub('$help', self.help or '')
				  :gsub('$id', self.id or 'id_' .. field)
				  return ret
			  end,
}

Text = Prototype:extend {
	init = function(self)
			   self.template = table.copy(self.template)
			   self.template.widget = [[<input type="text" id="id_$field" class="$class" name="$field" $attr value="$value"/>]]
			   -- self.template = [[<input type="text" id="id_$field" class="$class" name="$field" $attr value="$value"/>]]
			   
			   -- print('____text init')
			   -- ptable(self)
			   -- print(self.template)
			   -- ptable(getmetatable(self))
			   return self
		   end,
	validate = function(self, inst) 
				   print('text validate')
			   end,
}

Email = Text:extend {
	validate = function(self, inst)  
				   self._parent.validate(self)
				   print('email')
			   end,
}

Url = Text:extend {
	
}

Textarea = Text:extend {
	init = function(self)
			   self.template = table.copy(self.template)
			   self.template.widget = [[<textarea id="id_$field" class="$class" name="$field" $attr>$value</textarea>]]
			   print('~~~textarea init')
		   end,
}

Date = Text:extend {

}

Enum = Prototype:extend {
	init = function(self) 
			   self.template = table.copy(self.template)
			   self.template.widget = [[<select id="id_$field" name="$field" class="$class" $attr>$enum</select>]]
			   return self
		   end,
	validate = function(self, inst, field)
				   for _, v in ipairs(self.enum) do
					   if v == inst[field] then
						   return true
					   end
				   end
				   return false
			   end,
	toWidget = function(self, inst, field)
				   print('<<<<<<<<<<<<<<')
				   local str_enum = ''
				   for _, v in ipairs(self.enum) do
				   	   if v == inst[field] then
				   		   str_enum = str_enum .. '<option selected>' .. v .. '</option>'
				   	   else
				   		   str_enum = str_enum .. '<option>' .. v .. '</option>'
				   	   end
				   end
				   self.template.widget = self.template.widget:gsub('$enum', str_enum)
				   return self._parent.toWidget(self, inst, field)
			   end,
}

Foreign = Prototype:extend {
	init = function(self)
			   self.template = table.copy(self.template)
			   if self.st == 'ONE' then
				   self.template.widget = [[<select name="$field" class="$class" $attr><option value="0"></option>$option</select>]]
			   elseif self.st == 'MANY' then
				   self.template.widget = [[
						   <div style="overflow:auto; width:200px; max-height:200px; border:1px solid black">
							   <input type="hidden" name="$field[]" value="0" />$option
						   </div>
					   ]]
				   
			   end
			   return self
		   end,
			
	toWidget = function(self, inst, field)
				   if self.st == 'ONE' then
					   local foreign_inst = inst:getForeign(field)
					   local model = bamboo.getModelByName(self.foreign)
					   local insts = model:all() or {}

					   local str_opt = ''
					   local indexfd = 'id'
					   if model.__indexfd and model.__indexfd ~= '' then indexfd = model.__indexfd end
					   for _, v in ipairs(insts) do
						   if foreign_inst and foreign_inst.id == v.id then
							   str_opt = str_opt .. '<option selected value="' .. v.id .. '">' .. tostring(v[indexfd]) .. '</option>'
						   else
							   str_opt = str_opt .. '<option value="' .. v.id .. '">' .. tostring(v[indexfd]) .. '</option>'
						   end
					   end
					   print(self.template.widget)
					   print(str_opt)
					   -- self.template.widget = self.template.widget:gsub('$option', str_opt)
					   self.template.widget = self.template.widget:gsub('$option', str_opt)
					   
					   return self._parent.toWidget(self, inst, field)
				   elseif self.st == 'MANY' then
					   local foreign_insts = inst:getForeign(field) or {}
					   local model = bamboo.getModelByName(self.foreign)
					   local insts = model:all() or {}
					   local str_opt = ''
					   local indexfd = 'id'
					   if model.__indexfd and model.__indexfd ~= '' then indexfd = model.__indexfd end
					   print(indexfd)
					   for _, v in ipairs(insts) do
						   local eq = false
						   for _, foreign_inst in ipairs(foreign_insts) do
							   if foreign_inst.id == v.id then
								   eq = true
							   end
						   end
						   if eq then 
							   str_opt = str_opt .. '<label><input type="checkbox" checked name="' .. field .. '[]" value="'.. v.id .. '"/>' ..tostring(v[indexfd]) .. '</label>'
						   else
							   str_opt = str_opt .. '<label><input type="checkbox" name="' .. field  .. '[]" value="'.. v.id .. '"/>' ..tostring(v[indexfd]) .. '</label>'
						   end
					   end
					   self.template.widget = self.template.widget:gsub('$option', str_opt)
					   return self._parent.toWidget(self, inst, field)
				   end
			   end,
}

ForeignImage = Prototype:extend {
	init = function(self) 
			   self.template = table.copy(self.template)
			   self.template_uneditable = table.copy(self.template_uneditable)
			   self.template.widget = [[<img id="id_$field" name="$field" class="$class" src="$src"/>]]
			   self.template_uneditable.widget = [[<img id="id_$field" name="$field" class="$class" src="/$src"/>]]
			   return self
		   end,
	toWidget = function(self, inst, field)
				   local foreign_inst = inst:getForeign(field)
				   self.template.widget = self.template.widget:gsub('$src', foreign_inst.path)
				   self.template_uneditable.widget = self.template.widget:gsub('$src', foreign_inst.path)
				   return self._parent.toWidget(self, inst, field)
			   end,
}

ForeignText = Prototype:extend {
	init = function(self) 
			   self.template = table.copy(self.template)
			   self.template_uneditable = table.copy(self.template_uneditable)
			   self.template.widget = [[<input type="text" id="id_$field" class="$class" name="$field" $attr value="$text"]]
			   self.template_uneditable.widget = [[<span class="$class" $attr>$text</span>]]
			   return self
		   end,
	toWidget = function(self, inst, field)
				   local foreign_inst = inst:getForeign(field)
				   local model = bamboo.getModelByName(self.foreign)
				   print(foreign_inst[model.__indexfd])
				   self.template.widget = self.template.widget:gsub('$text', foreign_inst[model.__indexfd])
				   self.template_uneditable.widget = self.template_uneditable.widget:gsub('$text', foreign_inst[model.__indexfd])
				   return self._parent.toWidget(self, inst, field)
			   end,
}

fieldType = {
	['text'] = Text,
	['email'] = Email,
	['enum'] = Enum,
	['url'] = Url,
	['textarea'] = Textarea,
	['date'] = Date,
	['image'] = Text,
	['foreign'] = Foreign,
	['foreign_img'] = ForeignImage,
	['foreign_text'] = ForeignText,
	-- ['foreign_one'] = ForeignOne,
}

return fieldType;
