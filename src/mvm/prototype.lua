module(..., package.seeall)

local Validators = require 'bamboo.mvm.validate'

Prototype = Object:extend {
	-- widget_class = {},
	-- widget_attr = {},
	template = {
		label = [[<label for="$id">$caption</label>]],
		widget = '',
		help = [[<span class="$class">$help</span>]],
	},	
	template_uneditable = {
		label = [[<label>$caption:</label>]],
		widget = [[<span class="$class" $attr>$value</span>]],
		help = [[<span class="$class">$help</span>]],
	},
	init = function(self, t)
			   return self
		   end,
	toHtml = function(self, inst, field, format)
				 return (format or "$label$widget$help")
				 :gsub('$widget', self:toWidget(inst, field))
				 :gsub('$label', self:toLabel(inst, field))
				 :gsub('$help', self:toHelp(inst, field))
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
				   if self.rules then self.widget_attr.validate = json.encode(self.rules):gsub('"', "'") end
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
				 self.help_class = self.help_class or {}
				 self.help_attr = self.help_attr or {}
				 local str_class = ''
				 for _, c in ipairs(self.help_class) do
					 str_class = str_class .. ' ' .. c
				 end
				 local str_attr = ''
				 for k, v in pairs(self.help_attr) do
					 str_attr = str_attr .. ' ' .. k .. '="' .. tostring(v) ..'"'
				 end
				 if self.editable == false then
					 return self:strGSub((self.template_uneditable.help or '')
										 :gsub('$class', str_class)
										 :gsub('$attr', str_attr)
										 , inst, field)
				 else
					 return self:strGSub((self.template.help or '')
										 :gsub('$class', str_class)
										 :gsub('$attr', str_attr)
										 , inst, field)
				 end
			  end,
	strGSub = function(self, string, inst, field)
				  local ret = string
				  :gsub('$value', inst[field] or '')
				  :gsub('$caption', self.caption or field)
				  :gsub('$field', field)
				  :gsub('$help', self.help or '')
				  :gsub('$id', self.id or 'id_' .. field)
				  return ret
			  end,
	validate = function(self, val, field)
				   local is_valid = true
				   local err_msg = {}
				   for k, v in pairs(self.rules or {}) do
					   print(k, val, field, v)
					   local ret, msg = Validators[k](val, field, v)
					   if not ret then
						   table.insert(err_msg, msg)
						   is_valid = false
					   end
				   end
				   return is_valid, err_msg
			   end,
}

Text = Prototype:extend {
	init = function(self)
			   self.template = table.copy(self.template)
			   self.template.widget = [[<input type="text" id="$id" class="$class" name="$field" $attr value="$value"/>]]
			   return self
		   end,
}

Email = Text:extend {
	init = function(self)
			   self.rules = self.rules or {}
			   self.rules.email = true
			   return self._parent.init(self)
		   end,
}

Url = Text:extend {
	
}

Textarea = Text:extend {
	init = function(self)
			   self.template = table.copy(self.template)
			   self.template.widget = [[<textarea id="$id" class="$class" name="$field" $attr>$value</textarea>]]
			   return self
		   end,
}

Date = Text:extend {
	init = function(self)
			   self.rules = self.rules or {}
			   self.rules.dateISO = true
			   return self._parent.init(self)
		   end,
}

Enum = Prototype:extend {
	init = function(self) 
			   self.template = table.copy(self.template)
			   self.template.widget = [[<select id="$id" name="$field" class="$class" $attr>$enum</select>]]
			   return self
		   end,
	toWidget = function(self, inst, field)
				   local str_enum = ''
				   for _, v in ipairs(self.enum) do
				   	   if v == inst[field] then
				   		   str_enum = str_enum .. ('<option selected value="%s">%s</option>'):format(v[1], v[2])
				   	   else
				   		   str_enum = str_enum .. ('<option value="%s">%s</option>'):format(v[1], v[2])
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
			   	   -- self.template.widget = [[
			   	   -- 		   <div style="overflow:auto; width:200px; max-height:200px; border:1px solid black">]]
			   	   self.template.widget = [[
			   			   <div class="$class">
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
					   self.template.widget = [[<select name="$field" class="$class" $attr><option value="0"></option>]] .. str_opt .. [[</select>]]
					   
					   return self._parent.toWidget(self, inst, field)
				   elseif self.st == 'MANY' then
					   local foreign_insts = inst:getForeign(field) or {}
					   local model = bamboo.getModelByName(self.foreign)
					   local insts = model:all() or {}
					   local str_opt = ''
					   local indexfd = 'id'
					   if model.__indexfd and model.__indexfd ~= '' then indexfd = model.__indexfd end
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
					   self.template.widget = [[<div class="$class"><input type="hidden" name="$field[]" value="0" />]] .. str_opt .. [[</div>]]
					   return self._parent.toWidget(self, inst, field)
				   end
			   end,
}

ForeignImage = Prototype:extend {
	init = function(self) 
			   self.template = table.copy(self.template)
			   self.template_uneditable = table.copy(self.template_uneditable)
			   self.template.widget = [[<img id="$id" name="$field" class="$class" src="/$src"/>]]
			   self.template_uneditable.widget = [[<img id="$id" name="$field" class="$class" src="/$src"/>]]
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
			   self.template.widget = [[<input type="text" id="$id" class="$class" name="$field" $attr value="$text"]]
			   self.template_uneditable.widget = [[<span class="$class" $attr>$text</span>]]
			   return self
		   end,
	toWidget = function(self, inst, field)
				   local foreign_inst = inst:getForeign(field)
				   local model = bamboo.getModelByName(self.foreign)
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
