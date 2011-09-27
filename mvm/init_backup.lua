module(..., package.seeall)

fdt2ht = {
	['widget_type'] = {
		['text'] = function(h, k, v, f) h.template = [[<label>$field:</label><input type="text" class="$class" $attr value="$value" >]], table.insert(h.class, 'textInput') end,
		['textarea'] = function(h) h.template = [[<lable>$field:</label><textarea class="$class" $attr>$value</textarea>]] end,
		['enum'] = function(h, k, val, f, value)
					   h.template = [[<label>$field:</label><select>$enum</select>]]
					   local str_enum = ''
					   for _, v in ipairs(f.enum) do
						   if v == value then
							   str_enum = str_enum .. '<option selected>' .. v .. '</option>'
						   else
							   str_enum = str_enum .. '<option>' .. v .. '</option>'
						   end
					   end
					   h.template = h.template:gsub('$enum', str_enum)
				   end,
		['date'] = function(h, k, v, f)
					   table.insert(h.class, 'date')
				   end,
		['email'] = function(h, k, v, f)
						table.insert(h.class, 'email')
					end,
		['image'] = function(h)
						h.template = [[<label>$field:</label><img src="/$value" />]]
					end,
	},
	['required'] = {
		['true'] = function(h) table.insert(h.class, 'required') end
	},
	['max_length'] = {
		default = function(h, k, v) h['maxlength'] = v end
	},
	['min_length'] = {
		default = function(h, k, v) h['minlength'] = v end
	},
	['wrap'] = {
		default = function() end,
	},
	['enum'] = {
		default = function(h, k, v) 
					 
				  end,
	},
	['editable'] = {
		default = function() end
	},
	-- ['st'] = {},
	['foreign'] = {
		default = function(h, k, v)  end,
	},
	['st'] = {
		default = function(h, k, v) end,
	},
	-- ['attr'] = function(h, k, v, f)
	-- 			   h[k] = v
	-- 		   end,
	['default'] = function(h, k, v) h[k] = v end,
}




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

function fieldToViewMapping(field, value, fdt, filters, attached)
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

		for describer, val in pairs(f) do
			-- print(describer, val)
			-- switch(describer, tostring(val))(fdt2ht)(html_table, describer, val, fdt, value)
			
		end

		fptable(html_table)

		local str_class, str_attr = '', ''
		for k, v in pairs(html_table) do
			if k ~= 'template' then
				if k == 'class' then
					for _, c in ipairs(v) do
						str_class = str_class .. ' ' .. c
					end
				else
					str_attr = str_attr ..' ' .. k .. '="' .. v ..'"'
				end
			end
		end
		
		output = html_table.template:gsub('$class', str_class):gsub('$attr', str_attr):gsub('$value', value):gsub('$field', field)
		if attached.wrap then
			output = attached.wrap:format(output)
		end
	end
	
	return output
end

function modelToViewMapping(instance, filters, attached)
	local output = '<form action="/admin/validate" class="required-validate pageForm" onsubmit="return validateCallback(this)">'
	
	local value_type = type(instance)
	if value_type == 'string' or value_type == 'number' then
		output = output + ('<span>%s</span>'):format(instance)

	elseif value_type == 'table' and isValidInstance(instance) then
		local fields = instance.__fields
		for field, fdt in pairs(fields) do

			output = output + fieldToViewMapping(field, instance[field] or '', fdt, filters, attached)

		end
	else
		output = output + ''
	end

	output = output + '<input type="submit" value="submit" /></form>'
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
	assert(type(filters) == 'nil' or type(attached) == 'table')

    -- print(instance, restcode)

    return modelToViewMapping(instance, filters, attached)

end
