module(..., package.seeall)

--local http = require 'lglib.http'

-- fdt2ht = {
-- 	['widget_type'] = {
-- 		['text'] = function(h, k, v, f) h.template = [[<label>$field:</label><input type="text" class="$class" $attr value="$value" >]], table.insert(h.class, 'textInput') end,
-- 		['textarea'] = function(h) h.template = [[<lable>$field:</label><textarea class="$class" $attr>$value</textarea>]] end,
-- 		['enum'] = function(h, k, val, f, value)
-- 					   h.template = [[<label>$field:</label><select>$enum</select>]]
-- 					   local str_enum = ''
-- 					   for _, v in ipairs(f.enum) do
-- 						   if v == value then
-- 							   str_enum = str_enum .. '<option selected>' .. v .. '</option>'
-- 						   else
-- 							   str_enum = str_enum .. '<option>' .. v .. '</option>'
-- 						   end
-- 					   end
-- 					   h.template = h.template:gsub('$enum', str_enum)
-- 				   end,
-- 		['date'] = function(h, k, v, f)
-- 					   table.insert(h.class, 'date')
-- 				   end,
-- 		['email'] = function(h, k, v, f)
-- 						table.insert(h.class, 'email')
-- 					end,
-- 		['image'] = function(h)
-- 						h.template = [[<label>$field:</label><img src="/$value" />]]
-- 					end,
-- 	},
-- 	['required'] = {
-- 		['true'] = function(h) table.insert(h.class, 'required') end
-- 	},
-- 	['max_length'] = {
-- 		default = function(h, k, v) h['maxlength'] = v end
-- 	},
-- 	['min_length'] = {
-- 		default = function(h, k, v) h['minlength'] = v end
-- 	},
-- 	['wrap'] = {
-- 		default = function() end,
-- 	},
-- 	['enum'] = {
-- 		default = function(h, k, v) 
					  
-- 				  end,
-- 	},
-- 	['editable'] = {
-- 		default = function() end
-- 	},
-- 	-- ['st'] = {},
-- 	['foreign'] = {
-- 		default = function(h, k, v)  end,
-- 	},
-- 	['st'] = {
-- 		default = function(h, k, v) end,
-- 	},
-- 	-- ['attr'] = function(h, k, v, f)
-- 	-- 			   h[k] = v
-- 	-- 		   end,
-- 	['default'] = function(h, k, v) h[k] = v end,
-- }

local function constructHtmlTable(instance, field, value, fdt)
	local h = {
		template =[[<label>$desc:</label><input type="text" class="$class" name="$field" $attr value="$value" >]],
		class={},
	}

	for desc, val in pairs(fdt) do
		print(desc, val)

		-- if desc == 'widget_type' then
		-- 	if val == 'text' then
		-- 		-- h.template = [[<label>$field:</label><input type="text" class="$class" $attr value="$value" >]]
		-- 		table.insert(h.class, 'textInput')
		-- 	elseif val == 'textarea' then
		-- 		h.template = [[<lable>$desc:</label><textarea class="$class" $attr>$value</textarea>]]
		-- 	elseif val == 'enum' then
		-- 		h.template = [[<label>$desc:</label><select>$enum</select>]]
		-- 		local str_enum = ''
		-- 		for _, v in ipairs(fdt.enum) do
		-- 			if v == value then
		-- 				str_enum = str_enum .. '<option selected>' .. v .. '</option>'
		-- 			else
		-- 				str_enum = str_enum .. '<option>' .. v .. '</option>'
		-- 			end
		-- 		end
		-- 		h.template = h.template:gsub('$enum', str_enum)
		-- 	elseif val == 'date' then
		-- 		table.insert(h.class, 'date')
		-- 	elseif val == 'email' then
		-- 		table.insert(h.class, 'email')
		-- 	elseif val == 'image' then
		-- 		h.template = [[<label>$desc:</label><img src="/$value" /><input type="text" value="$value />"]]
		-- 	end
		if desc == 'required' then
			if val == true then
				table.insert(h.class, 'required')
			end
		elseif desc == 'editable' then
			if val == false then
				local wtype = fdt.widget_type
				if wtype == 'url' then
					h.template = [[<label>$desc:</label><a href="http://$value" target='blank'>$value</a>]]
				else
					h.template = [[<label>$desc:</label><span>$value</span>]]
				end
			else
				local wtype = fdt.widget_type
				if wtype == 'text' then
					-- h.template = [[<label>$field:</label><input type="text" class="$class" $attr value="$value" >]]
					table.insert(h.class, 'textInput')
				elseif wtype == 'textarea' then
					h.template = [[<lable>$desc:</label><textarea class="$class" name="$field" $attr>$value</textarea>]]
				elseif wtype == 'enum' then
					h.template = [[<label>$desc:</label><select name="$field" class="$class">$enum</select>]]
					local str_enum = ''
					for _, v in ipairs(fdt.enum) do
						if v == value then
							str_enum = str_enum .. '<option selected>' .. v .. '</option>'
						else
							str_enum = str_enum .. '<option>' .. v .. '</option>'
						end
					end
					h.template = h.template:gsub('$enum', str_enum)
				elseif wtype == 'date' then
					table.insert(h.class, 'date')
					h.yearstart = '-100'
					h.yearend = '0'
				elseif wtype == 'email' then
					table.insert(h.class, 'email')
				elseif wtype == 'mobilephone' then
					table.insert(h.class, 'digits')
					h.minlength = 11
					h.maxlength = 11
				elseif wtype == 'image' then
					h.template = [[<label>$desc:</label><img src="/$value" /><input type="text" value="$value" name="$field"/>]]
				else
					h.template =[[<label>$desc:</label><input type="text" class="$class" $attr value="$value" name="$field"/>]]
				end
			end
		elseif desc == 'foreign' then
			if fdt.st == 'ONE' then
				-- local foreign_instance = instance:getForeign(field)
				-- local model = bamboo.getModelByName(fdt.foreign)
				-- if model.__keyfd then 
			end
		elseif desc == 'st' then
			--[[
			if val == 'ONE' then
				local foreign_instance = instance:getForeign(field)
				-- h.template = [==[<label>$field:</label><select>$option</select>]==]
				local model = bamboo.getModelByName(fdt.foreign)
				local instances = model:all()

				local str_opt = ''
				local indexfd = 'id'
				if model.__indexfd and model.__indexfd ~= '' then indexfd = model.__indexfd end
				-- print( indexfd)
				for _, v in ipairs(instances) do
					if foreign_instance.id == v.id then
						str_opt = str_opt .. '<option selected value="' .. v.id .. '">' .. tostring(v[indexfd]) .. '</option>'
					else
						str_opt = str_opt .. '<option value=' .. v.id .. '>' .. tostring(v[indexfd]) .. '</option>'
					end
				end
				-- str_opt = http.encodeURL(str_opt)
				-- print('>>>>>>>>>>>>>>', str_opt)
				-- h.template = h.template:gsub('$option', str_opt)
				h.template = '<label>$desc:</label><select style="width:200px">' .. str_opt .. '</select>'
			elseif val == 'MANY' then
				local foreign_instances = instance:getForeign(field)

				local model = bamboo.getModelByName(fdt.foreign)
				local instances = model:all()

				local str_opt = ''
				local indexfd = 'id'
				if model.__indexfd and model.__indexfd ~= '' then indexfd = model.__indexfd end
				
				print(indexfd)
				for _, v in ipairs(instances) do
					local eq = false
					for _, foreign_instance in ipairs(foreign_instances) do
						if foreign_instance.id == v.id then
							eq = true
						end
					end
					if eq then 
						str_opt = str_opt .. '<label><input type="checkbox" checked value="'.. v.id ..'"/>' ..tostring(v[indexfd]) .. '</label>'
					else
						str_opt = str_opt .. '<label><input type="checkbox" value="'.. v.id ..'"/>' .. tostring(v[indexfd]) .. '</label>'
					end
				end
				print('>>>>>>>>>>>>>>', str_opt)
				h.template = '<label>$field:</label><div style="overflow:auto; width:200px; height:200px">' .. str_opt .. '</div>'
			end
			--]]
		elseif desc == 'wrap' then
		elseif desc == 'enum' then
		elseif desc == 'desc' then
		elseif desc == 'widget_type' then
		elseif desc == 'vl' then
		elseif desc == 'class' then
		elseif desc == 'new_field' then
		elseif desc == 'max_length' then
			h['maxlength'] = val
		elseif desc == 'min_length' then
			h['minlength'] = val
		else
			h[desc] = val			
		end
	end

	return h
end




function switch(case1, case2)
	return 
	function(codetable)
		local f = codetable.default
		-- f = codetable[case1][case2] or codetable.default
		if codetable[case1] then
			-- f = codetable[case1]
			if codetable[case1][case2] then
				f = codetable[case1][case2]
			end
			if codetable[case1].default then
				f = codetable[case1].default
			end
		end
		if f then
			if type(f)=="function" then
				return f
			else
				error("case "..tostring(case1).." not a function")
			end
		end
	end
end

function fieldToViewMapping(instance, field, value, fdt, filters, attached)
	local output = ''
	if field ~= 'id' then

		local html_table = {
			template =[[<label>$field:</label><input type="text" class="$class" $attr value="$value" >]],
			class={},
		}
		
		local f = fdt

		for k, v in pairs(attached) do
			if v == 'class' then
				f[k] = f[k] .. ' ' .. v
			else
				f[k] = v
			end
		end

		-- for describer, val in pairs(f) do
		-- 	-- print(describer, val)
		-- 	-- switch(describer, tostring(val))(fdt2ht)(html_table, describer, val, fdt, value)
			
		-- end

		local html_table = constructHtmlTable(instance, field, value, f)

		fptable(html_table)

		local str_class, str_attr = f.class or '', ''
		for k, v in pairs(html_table) do
			if k ~= 'template' then
				if k == 'class' then
					for _, c in ipairs(v) do
						str_class = str_class .. ' ' .. c
					end
				else
					str_attr = str_attr ..' ' .. k .. '="' .. tostring(v) ..'"'
				end
			end
		end
		
		local desc = f.desc
		
		output = html_table.template:gsub('$class', str_class)
		:gsub('$attr', str_attr)
		:gsub('$value', value or '')
		:gsub('$field', field)
		:gsub('$desc', desc or field)

	else
		-- output = ([[<label>id:</label><span name="id">$id</span>]]):gusb('$id', instance.id)
	end

	if attached.wrap then
		output = attached.wrap:format(output)
	end
	
	return output
end

function modelToViewMapping(instance, filters, attached)
	local output = ''
	
	local value_type = type(instance)
	if value_type == 'string' or value_type == 'number' then
		output = output + ('<span>%s</span>'):format(instance)

	elseif value_type == 'table' and isValidInstance(instance) then
		local fields = instance.__fields
		for field, fdt in pairs(fields) do

			local flag = true
			for k, v in pairs(filters) do
				-- to redundant query condition, once meet, jump immediately
				if not fdt[k] then 
					-- flag=false;
					-- break
					if k == 'vl' then fdt[k] = 0 end
				end

				if type(v) == 'function' then
					flag = v(fdt[k] or '')
					if not flag then break end
				else
					if fdt[k] ~= v then flag=false; break end
				end
			end

			if flag then
				output = output + fieldToViewMapping(instance, field, instance[field] or '', fdt, filters, attached)
			end
		end
	else
		output = output + ''
	end

	print(output)
	return output
end

function process( instance, restcode )
	-- print(instance, restcode)
	-- restcode = restcode:gsub('[\n\r]+', ' ')
    assert(loadstring('_t = {' + restcode + ' }'), '[Error] wrong syntax in view tag {**}.')()
	assert(type(_t) == 'table')

	local filters = _t.filters
	assert(type(filters) == 'nil' or type(filters) == 'table')
	local attached = _t.attached
	assert(type(attached) == 'nil' or type(attached) == 'table')
	attached = attached or {}

    -- print(instance, restcode)

    return modelToViewMapping(instance, filters, attached)

end
